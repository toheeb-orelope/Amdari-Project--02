"""Transaction search and lookup endpoints."""

from flask import Blueprint, current_app, jsonify, request

from app.auth import require_auth
from app.db import get_connection
from app.extensions import limiter

transactions_bp = Blueprint("transactions", __name__)

MAX_SEARCH_LENGTH = 100
MAX_REFERENCE_LENGTH = 64
SEARCH_RESULT_LIMIT = 50


def authenticated_user_key():
    """Use the user ID set by require_auth as the rate-limit key."""
    return f"user:{request.current_user_id}"


def close_database_resources(cur, conn):
    """Close partially initialized database resources safely."""
    if cur is not None:
        try:
            cur.close()
        except Exception:
            current_app.logger.exception("Failed to close transaction database cursor")
    if conn is not None:
        try:
            conn.close()
        except Exception:
            current_app.logger.exception(
                "Failed to close transaction database connection"
            )


@transactions_bp.route("/search", methods=["GET"])
# Apply a broad source-IP limit before authentication.
@limiter.limit("120/minute")
@require_auth
# Apply a tighter limit after require_auth has set current_user_id.
@limiter.limit("60/minute", key_func=authenticated_user_key)
def search_transactions():
    """Search transactions belonging to the authenticated user's accounts."""
    query_text = request.args.get("q", "")
    account_id_text = request.args.get("account_id")

    if not isinstance(query_text, str):
        return jsonify({"error": "q must be a string"}), 400
    query_text = query_text.strip()
    if len(query_text) > MAX_SEARCH_LENGTH:
        return (
            jsonify({"error": f"q must not exceed {MAX_SEARCH_LENGTH} characters"}),
            400,
        )

    account_id = None
    if account_id_text not in (None, ""):
        try:
            account_id = int(account_id_text)
        except (TypeError, ValueError):
            return jsonify({"error": "account_id must be a positive integer"}), 400
        if account_id <= 0:
            return jsonify({"error": "account_id must be a positive integer"}), 400

    # Values remain separate from SQL so search text cannot alter the query.
    search_pattern = f"%{query_text}%"
    parameters = [
        request.current_user_id,
        search_pattern,
        search_pattern,
        search_pattern,
    ]

    conn = None
    cur = None
    try:
        conn = get_connection()
        cur = conn.cursor()
        if account_id is None:
            cur.execute(
                "SELECT t.id, t.account_id, t.reference, t.amount, t.currency, "
                "t.direction, t.counterparty, t.description, t.status, t.created_at "
                "FROM transactions AS t "
                # Join ownership into the query so other users' rows cannot match.
                "INNER JOIN accounts AS a ON a.id = t.account_id "
                "WHERE a.user_id = %s "
                "AND (t.reference ILIKE %s "
                "OR t.counterparty ILIKE %s "
                "OR t.description ILIKE %s) "
                "ORDER BY t.created_at DESC, t.id DESC "
                "LIMIT %s",
                tuple(parameters + [SEARCH_RESULT_LIMIT]),
            )
        else:
            cur.execute(
                "SELECT t.id, t.account_id, t.reference, t.amount, t.currency, "
                "t.direction, t.counterparty, t.description, t.status, t.created_at "
                "FROM transactions AS t "
                # Join ownership into the query so other users' rows cannot match.
                "INNER JOIN accounts AS a ON a.id = t.account_id "
                "WHERE a.user_id = %s "
                "AND (t.reference ILIKE %s "
                "OR t.counterparty ILIKE %s "
                "OR t.description ILIKE %s) "
                "AND t.account_id = %s "
                "ORDER BY t.created_at DESC, t.id DESC "
                "LIMIT %s",
                tuple(parameters + [account_id, SEARCH_RESULT_LIMIT]),
            )
        rows = cur.fetchall()
        return jsonify([dict(row) for row in rows])
    except Exception:
        current_app.logger.exception("Failed to search transactions")
        return jsonify({"error": "failed to search transactions"}), 500
    finally:
        close_database_resources(cur, conn)


@transactions_bp.route("/<reference>", methods=["GET"])
# Apply a broad source-IP limit before authentication.
@limiter.limit("120/minute")
@require_auth
# Apply a tighter limit after require_auth has set current_user_id.
@limiter.limit("60/minute", key_func=authenticated_user_key)
def get_transaction(reference):
    """Fetch a transaction belonging to the authenticated user's account."""
    reference = reference.strip()
    if not reference or len(reference) > MAX_REFERENCE_LENGTH:
        return jsonify({"error": "invalid transaction reference"}), 400

    conn = None
    cur = None
    try:
        conn = get_connection()
        cur = conn.cursor()
        cur.execute(
            "SELECT t.id, t.account_id, t.reference, t.amount, t.currency, "
            "t.direction, t.counterparty, t.description, t.status, t.created_at "
            "FROM transactions AS t "
            # Scope the reference lookup to accounts owned by this user.
            "INNER JOIN accounts AS a ON a.id = t.account_id "
            "WHERE t.reference = %s AND a.user_id = %s",
            (reference, request.current_user_id),
        )
        transaction = cur.fetchone()
        if not transaction:
            # Do not reveal whether another user owns the reference.
            return jsonify({"error": "transaction not found"}), 404
        return jsonify(dict(transaction))
    except Exception:
        current_app.logger.exception("Failed to retrieve transaction")
        return jsonify({"error": "failed to retrieve transaction"}), 500
    finally:
        close_database_resources(cur, conn)
