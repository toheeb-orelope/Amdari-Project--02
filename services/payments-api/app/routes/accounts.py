"""Account lookup, listing, and profile endpoints."""

from flask import Blueprint, current_app, jsonify, request

from app.auth import require_auth
from app.db import get_connection
from app.extensions import limiter

accounts_bp = Blueprint("accounts", __name__)

# Only fields backed by the current schema and safe for account owners belong here.
PROFILE_FIELDS = {"full_name"}
MAX_FULL_NAME_LENGTH = 255


def authenticated_user_key():
    """Use the user ID set by require_auth as the rate-limit key."""
    return f"user:{request.current_user_id}"


def close_database_resources(cur, conn):
    """Close partially initialized database resources safely."""
    if cur is not None:
        try:
            cur.close()
        except Exception:
            current_app.logger.exception("Failed to close database cursor")
    if conn is not None:
        try:
            conn.close()
        except Exception:
            current_app.logger.exception("Failed to close database connection")


@accounts_bp.route("/<int:account_id>", methods=["GET"])
# Apply a broad IP limit before authentication.
@limiter.limit("120/minute")
@require_auth
# Apply a tighter limit after require_auth has set current_user_id.
@limiter.limit("60/minute", key_func=authenticated_user_key)
def get_account(account_id):
    """Look up an account owned by the authenticated user."""
    conn = None
    cur = None
    try:
        conn = get_connection()
        cur = conn.cursor()
        cur.execute(
            "SELECT id, user_id, account_number, currency, balance, status, created_at "
            # Restrict the requested ID to the authenticated owner.
            "FROM accounts WHERE id = %s AND user_id = %s",
            # Bind both values rather than interpolating user-controlled data.
            (account_id, request.current_user_id),
        )
        account = cur.fetchone()
        if not account:
            # Do not reveal whether a non-owned account exists.
            return jsonify({"error": "account not found"}), 404

        return jsonify(dict(account))
    except Exception:
        # Log diagnostic details server-side without exposing them to clients.
        current_app.logger.exception("Failed to retrieve account")
        return jsonify({"error": "internal server error"}), 500
    finally:
        close_database_resources(cur, conn)


@accounts_bp.route("/", methods=["GET"])
# Apply a broad IP limit before authentication.
@limiter.limit("120/minute")
@require_auth
# Apply a tighter limit after require_auth has set current_user_id.
@limiter.limit("60/minute", key_func=authenticated_user_key)
def list_accounts():
    """List accounts owned by the authenticated user."""
    conn = None
    cur = None
    try:
        conn = get_connection()
        cur = conn.cursor()
        cur.execute(
            "SELECT id, account_number, currency, balance, status "
            "FROM accounts WHERE user_id = %s ORDER BY id",
            # A one-value SQL parameter must be passed as a tuple.
            (request.current_user_id,),
        )
        rows = cur.fetchall()
        return jsonify([dict(row) for row in rows])
    except Exception:
        # Log diagnostic details server-side without exposing them to clients.
        current_app.logger.exception("Failed to list accounts")
        return jsonify({"error": "internal server error"}), 500
    finally:
        close_database_resources(cur, conn)


@accounts_bp.route("/<int:account_id>/profile", methods=["PUT"])
# Apply a broad IP limit before authentication.
@limiter.limit("60/minute")
@require_auth
# Apply stricter per-user limits to the state-changing endpoint.
@limiter.limit("10/minute;50/day", key_func=authenticated_user_key)
def update_profile(account_id):
    """Update schema-backed profile fields for an owned account."""
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify({"error": "request body must be a JSON object"}), 400
    if not data:
        return jsonify({"error": "no fields supplied"}), 400

    # Reject unknown fields instead of silently accepting a partial request.
    unknown_fields = sorted(set(data) - PROFILE_FIELDS)
    if unknown_fields:
        return (
            jsonify(
                {
                    "error": "unsupported profile fields",
                    "fields": unknown_fields,
                }
            ),
            400,
        )

    full_name = data.get("full_name")
    if not isinstance(full_name, str):
        return jsonify({"error": "full_name must be a string"}), 400

    # Normalize harmless surrounding whitespace before validation and storage.
    full_name = full_name.strip()
    if not full_name:
        return jsonify({"error": "full_name must not be empty"}), 400
    if len(full_name) > MAX_FULL_NAME_LENGTH:
        return (
            jsonify(
                {
                    "error": f"full_name must not exceed {MAX_FULL_NAME_LENGTH} characters"
                }
            ),
            400,
        )

    conn = None
    cur = None
    try:
        conn = get_connection()
        cur = conn.cursor()
        cur.execute(
            "UPDATE users AS u SET full_name = %s " "FROM accounts AS a "
            # Require both the referenced account and authenticated user to match.
            "WHERE a.id = %s AND a.user_id = %s AND u.id = a.user_id "
            # Return only fields intentionally exposed by this endpoint.
            "RETURNING u.full_name",
            (full_name, account_id, request.current_user_id),
        )
        updated_profile = cur.fetchone()
        if not updated_profile:
            # Use the same response for absent and non-owned accounts.
            return jsonify({"error": "account not found"}), 404

        conn.commit()
        return jsonify(
            {
                "account_id": account_id,
                "full_name": updated_profile["full_name"],
            }
        )
    except Exception:
        if conn is not None:
            # Clear a failed transaction before returning the connection.
            conn.rollback()
        # Log diagnostic details server-side without exposing them to clients.
        current_app.logger.exception("Failed to update account profile")
        return jsonify({"error": "internal server error"}), 500
    finally:
        close_database_resources(cur, conn)
