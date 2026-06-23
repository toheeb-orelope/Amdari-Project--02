"""Wallet credit and debit operations."""

import hashlib
import json
from decimal import Decimal, InvalidOperation

from flask import Blueprint, current_app, jsonify, request
from psycopg2.errors import UniqueViolation

from app.auth import require_auth
from app.db import get_connection
from app.extensions import limiter

wallets_bp = Blueprint("wallets", __name__)

MAX_AMOUNT = Decimal("9999999999999999.99")
MAX_DESCRIPTION_LENGTH = 500
MAX_COUNTERPARTY_LENGTH = 255
MIN_IDEMPOTENCY_KEY_LENGTH = 8
MAX_IDEMPOTENCY_KEY_LENGTH = 128

CREDIT_FIELDS = {"amount", "description"}
DEBIT_FIELDS = {"amount", "counterparty", "description"}


def authenticated_user_key():
    """Use the user ID set by require_auth as the rate-limit key."""
    return f"user:{request.current_user_id}"


def close_database_resources(cur, conn):
    """Close partially initialized database resources safely."""
    if cur is not None:
        try:
            cur.close()
        except Exception:
            current_app.logger.exception("Failed to close wallet database cursor")
    if conn is not None:
        try:
            conn.close()
        except Exception:
            current_app.logger.exception("Failed to close wallet database connection")


def validate_request_body(allowed_fields):
    """Validate the JSON object and reject mass-assignment fields."""
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return None, (jsonify({
            "error": "request body must be a JSON object"
        }), 400)

    unknown_fields = sorted(set(data) - allowed_fields)
    if unknown_fields:
        return None, (jsonify({
            "error": "unsupported fields",
            "fields": unknown_fields,
        }), 400)
    return data, None


def validate_amount(value):
    """Return a positive two-decimal amount within NUMERIC(18,2)."""
    if isinstance(value, bool) or value is None:
        return None
    try:
        amount = Decimal(str(value))
    except (InvalidOperation, TypeError, ValueError):
        return None

    if not amount.is_finite() or amount <= 0 or amount > MAX_AMOUNT:
        return None
    if amount.as_tuple().exponent < -2:
        return None
    return amount.quantize(Decimal("0.01"))


def validate_optional_text(value, default, maximum_length):
    """Validate and normalize bounded optional text."""
    if value is None:
        value = default
    if not isinstance(value, str):
        return None
    value = value.strip()
    if len(value) > maximum_length:
        return None
    return value


def transaction_reference(account_id, direction):
    """Derive a stable unique reference from a caller-supplied idempotency key."""
    idempotency_key = request.headers.get("Idempotency-Key", "")
    if not (
        MIN_IDEMPOTENCY_KEY_LENGTH
        <= len(idempotency_key)
        <= MAX_IDEMPOTENCY_KEY_LENGTH
    ):
        return None

    digest = hashlib.sha256(
        f"{account_id}:{direction}:{idempotency_key}".encode("utf-8")
    ).hexdigest().upper()
    return f"TXN-{digest[:60]}"


def find_existing_transaction(
    cur,
    reference,
    account_id,
    direction,
    require_owner=True,
):
    """Find an idempotent replay within the caller's permitted scope."""
    ownership_filter = ""
    parameters = [reference, account_id, direction]
    if require_owner:
        ownership_filter = " AND a.user_id = %s"
        parameters.append(request.current_user_id)
    cur.execute(
        "SELECT t.reference FROM transactions AS t "
        "INNER JOIN accounts AS a ON a.id = t.account_id "
        "WHERE t.reference = %s AND t.account_id = %s "
        "AND t.direction = %s"
        f"{ownership_filter}",
        tuple(parameters),
    )
    return cur.fetchone()


def is_credit_operator(cur):
    """Allow only active finance or admin users to credit wallets."""
    cur.execute(
        "SELECT 1 FROM users "
        "WHERE id = %s AND role IN ('finance', 'admin') AND is_active = TRUE",
        (request.current_user_id,),
    )
    return cur.fetchone() is not None


def account_error_response(cur, account_id, amount=None, require_owner=True):
    """Return a safe reason when an atomic balance update changes no row."""
    ownership_filter = ""
    parameters = [account_id]
    if require_owner:
        ownership_filter = " AND user_id = %s"
        parameters.append(request.current_user_id)
    cur.execute(
        "SELECT balance, status FROM accounts "
        "WHERE id = %s"
        f"{ownership_filter}",
        tuple(parameters),
    )
    account = cur.fetchone()
    if not account:
        return jsonify({"error": "account not found"}), 404
    if account["status"] != "active":
        return jsonify({"error": "account is not active"}), 409
    if amount is not None and Decimal(str(account["balance"])) < amount:
        return jsonify({"error": "insufficient funds"}), 400
    return jsonify({"error": "wallet operation could not be completed"}), 409


def log_wallet_audit(direction, account_id, amount, reference):
    """Emit a structured audit event without logging secrets or request bodies."""
    try:
        current_app.logger.info(
            json.dumps({
                "event": "wallet_balance_changed",
                "actor_user_id": request.current_user_id,
                "account_id": account_id,
                "direction": direction,
                "amount": str(amount),
                "reference": reference,
                "source_ip": request.remote_addr,
            })
        )
    except Exception:
        # A logging backend failure must not misreport a committed transfer.
        current_app.logger.exception("Failed to emit wallet audit event")


@wallets_bp.route("/<int:account_id>/credit", methods=["POST"])
@limiter.limit("30/minute")
@require_auth
@limiter.limit("10/minute;100/day", key_func=authenticated_user_key)
def credit_wallet(account_id):
    """Atomically credit a wallet as an active finance or admin user."""
    data, error_response = validate_request_body(CREDIT_FIELDS)
    if error_response:
        return error_response

    amount = validate_amount(data.get("amount"))
    description = validate_optional_text(
        data.get("description"),
        "credit",
        MAX_DESCRIPTION_LENGTH,
    )
    reference = transaction_reference(account_id, "credit")
    if amount is None:
        return jsonify({"error": "amount must be a positive value with at most 2 decimals"}), 400
    if description is None:
        return jsonify({"error": "description is invalid or too long"}), 400
    if reference is None:
        return jsonify({"error": "valid Idempotency-Key header required"}), 400

    conn = None
    cur = None
    try:
        conn = get_connection()
        cur = conn.cursor()
        # Credits mint funds and therefore require an elevated database role.
        if not is_credit_operator(cur):
            return jsonify({"error": "finance or admin role required"}), 403
        if find_existing_transaction(
            cur,
            reference,
            account_id,
            "credit",
            require_owner=False,
        ):
            return jsonify({"reference": reference, "idempotent_replay": True}), 200

        # The database performs the arithmetic atomically under its row lock.
        cur.execute(
            "UPDATE accounts SET balance = balance + %s "
            "WHERE id = %s AND status = 'active' "
            "RETURNING balance, currency",
            (amount, account_id),
        )
        account = cur.fetchone()
        if not account:
            return account_error_response(
                cur,
                account_id,
                require_owner=False,
            )

        cur.execute(
            "INSERT INTO transactions "
            "(account_id, reference, amount, currency, direction, description, status) "
            "VALUES (%s, %s, %s, %s, 'credit', %s, 'completed')",
            (account_id, reference, amount, account["currency"], description),
        )
        conn.commit()
        log_wallet_audit("credit", account_id, amount, reference)
        return jsonify({
            "reference": reference,
            "new_balance": str(account["balance"]),
        })
    except UniqueViolation:
        if conn is not None:
            conn.rollback()
        if cur is not None and find_existing_transaction(
            cur,
            reference,
            account_id,
            "credit",
            require_owner=False,
        ):
            return jsonify({"reference": reference, "idempotent_replay": True}), 200
        current_app.logger.exception("Unexpected wallet credit reference conflict")
        return jsonify({"error": "wallet credit conflict"}), 409
    except Exception:
        if conn is not None:
            conn.rollback()
        current_app.logger.exception("Wallet credit failed")
        return jsonify({"error": "wallet credit failed"}), 500
    finally:
        close_database_resources(cur, conn)


@wallets_bp.route("/<int:account_id>/debit", methods=["POST"])
@limiter.limit("30/minute")
@require_auth
@limiter.limit("10/minute;100/day", key_func=authenticated_user_key)
def debit_wallet(account_id):
    """Atomically debit an owned active wallet without a negative balance."""
    data, error_response = validate_request_body(DEBIT_FIELDS)
    if error_response:
        return error_response

    amount = validate_amount(data.get("amount"))
    counterparty = validate_optional_text(
        data.get("counterparty"),
        "",
        MAX_COUNTERPARTY_LENGTH,
    )
    description = validate_optional_text(
        data.get("description"),
        "debit",
        MAX_DESCRIPTION_LENGTH,
    )
    reference = transaction_reference(account_id, "debit")
    if amount is None:
        return jsonify({"error": "amount must be a positive value with at most 2 decimals"}), 400
    if counterparty is None:
        return jsonify({"error": "counterparty is invalid or too long"}), 400
    if description is None:
        return jsonify({"error": "description is invalid or too long"}), 400
    if reference is None:
        return jsonify({"error": "valid Idempotency-Key header required"}), 400

    conn = None
    cur = None
    try:
        conn = get_connection()
        cur = conn.cursor()
        if find_existing_transaction(cur, reference, account_id, "debit"):
            return jsonify({"reference": reference, "idempotent_replay": True}), 200

        # The balance check and subtraction occur in one atomic statement.
        cur.execute(
            "UPDATE accounts SET balance = balance - %s "
            "WHERE id = %s AND user_id = %s AND status = 'active' "
            "AND balance >= %s "
            "RETURNING balance, currency",
            (amount, account_id, request.current_user_id, amount),
        )
        account = cur.fetchone()
        if not account:
            return account_error_response(cur, account_id, amount)

        cur.execute(
            "INSERT INTO transactions "
            "(account_id, reference, amount, currency, direction, "
            "counterparty, description, status) "
            "VALUES (%s, %s, %s, %s, 'debit', %s, %s, 'completed')",
            (
                account_id,
                reference,
                amount,
                account["currency"],
                counterparty,
                description,
            ),
        )
        conn.commit()
        log_wallet_audit("debit", account_id, amount, reference)
        return jsonify({
            "reference": reference,
            "new_balance": str(account["balance"]),
        })
    except UniqueViolation:
        if conn is not None:
            conn.rollback()
        if cur is not None and find_existing_transaction(
            cur,
            reference,
            account_id,
            "debit",
        ):
            return jsonify({"reference": reference, "idempotent_replay": True}), 200
        current_app.logger.exception("Unexpected wallet debit reference conflict")
        return jsonify({"error": "wallet debit conflict"}), 409
    except Exception:
        if conn is not None:
            conn.rollback()
        current_app.logger.exception("Wallet debit failed")
        return jsonify({"error": "wallet debit failed"}), 500
    finally:
        close_database_resources(cur, conn)
