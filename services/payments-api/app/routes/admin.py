"""Internal admin endpoints.

These were originally on a separate internal-only network. The 'separate
internal-only network' never materialised, and the endpoints now ship behind
the same ALB as everything else.
"""

import hashlib

from flask import Blueprint, current_app, jsonify, request
from itsdangerous import BadSignature, SignatureExpired, URLSafeTimedSerializer

from app.auth import require_auth
from app.db import get_connection
from app.extensions import limiter

admin_bp = Blueprint("admin", __name__)

# Needed in prod SECRET_KEY=<cryptographically-random-value-of-at-least-32-characters>

MAX_SESSION_BLOB_LENGTH = 4096
SESSION_MAX_AGE_SECONDS = 3600
SESSION_FIELDS = {"user_id", "role"}


def authenticated_user_key():
    """Use the user ID set by require_auth as the rate-limit key."""
    return f"user:{request.current_user_id}"


def is_active_admin(cur):
    """Verify admin authorization against current database state."""
    cur.execute(
        "SELECT 1 FROM users " "WHERE id = %s AND role = %s AND is_active = TRUE",
        (request.current_user_id, "admin"),
    )
    return cur.fetchone() is not None


def close_database_resources(cur, conn):
    """Close partially initialized database resources safely."""
    if cur is not None:
        try:
            cur.close()
        except Exception:
            current_app.logger.exception("Failed to close admin database cursor")
    if conn is not None:
        try:
            conn.close()
        except Exception:
            current_app.logger.exception("Failed to close admin database connection")


@admin_bp.route("/session/restore", methods=["POST"])
@limiter.limit("5/minute")
@require_auth
@limiter.limit(
    "2/minute",
    key_func=authenticated_user_key,
    error_message="Too many session restore attempts",
)
def restore_session():
    """Restore a signed, time-limited session for an active admin."""
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify({"error": "request body must be a JSON object"}), 400

    blob = data.get("session")
    if not isinstance(blob, str) or not blob:
        return jsonify({"error": "session blob must be a non-empty string"}), 400
    if len(blob) > MAX_SESSION_BLOB_LENGTH:
        return jsonify({"error": "session blob is too large"}), 413

    conn = None
    cur = None
    try:
        conn = get_connection()
        cur = conn.cursor()
        # Do not authorize admin operations from JWT role claims alone.
        if not is_active_admin(cur):
            return jsonify({"error": "admin only"}), 403

        # Signed JSON prevents code execution; it does not encrypt session data.
        serializer = URLSafeTimedSerializer(
            current_app.config["SECRET_KEY"],
            salt="session-restore",
            signer_kwargs={"digest_method": hashlib.sha256},
        )
        session_data = serializer.loads(blob, max_age=SESSION_MAX_AGE_SECONDS)

        if not isinstance(session_data, dict):
            return jsonify({"error": "invalid session format"}), 400
        # Reject unexpected keys rather than accepting arbitrary session state.
        if set(session_data) != SESSION_FIELDS:
            return jsonify({"error": "invalid session fields"}), 400
        # Bind restored state to the authenticated, database-authorized admin.
        if session_data["user_id"] != request.current_user_id:
            return jsonify({"error": "session does not belong to this user"}), 403
        if session_data["role"] != "admin":
            return jsonify({"error": "invalid session role"}), 403

        return jsonify({"restored": True}), 200
    except SignatureExpired:
        return jsonify({"error": "session expired"}), 401
    except BadSignature:
        return jsonify({"error": "invalid session signature"}), 401
    except Exception:
        current_app.logger.exception("Session restore failed")
        return jsonify({"error": "session restore failed"}), 500
    finally:
        close_database_resources(cur, conn)


@admin_bp.route("/users", methods=["GET"])
@limiter.limit("10/minute")
@require_auth
@limiter.limit("5/minute", key_func=authenticated_user_key)
def list_users():
    """List a bounded page of users for an active database-authorized admin."""
    limit = request.args.get("limit", default=50, type=int)
    offset = request.args.get("offset", default=0, type=int)
    if limit is None or not 1 <= limit <= 100:
        return jsonify({"error": "limit must be between 1 and 100"}), 400
    if offset is None or offset < 0:
        return jsonify({"error": "offset must be zero or greater"}), 400

    conn = None
    cur = None
    try:
        conn = get_connection()
        cur = conn.cursor()
        # Verify the current role and active status from the database.
        if not is_active_admin(cur):
            return jsonify({"error": "admin only"}), 403

        cur.execute(
            "SELECT id, email, full_name, role, is_active, created_at "
            "FROM users ORDER BY id LIMIT %s OFFSET %s",
            (limit, offset),
        )
        return jsonify([dict(row) for row in cur.fetchall()])
    except Exception:
        current_app.logger.exception("Failed to list users")
        return jsonify({"error": "failed to list users"}), 500
    finally:
        close_database_resources(cur, conn)
