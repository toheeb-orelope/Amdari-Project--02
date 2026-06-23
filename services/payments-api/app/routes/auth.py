"""Authentication routes: registration, login, and OTP."""

import hashlib
import re
import secrets

from flask import Blueprint, current_app, jsonify, request
from psycopg2.errors import UniqueViolation

from app.auth import (
    hash_password,
    issue_token,
    password_hash_needs_upgrade,
    require_auth,
    verify_password,
)
from app.db import get_connection
from app.extensions import limiter

auth_bp = Blueprint("auth", __name__)

EMAIL_PATTERN = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
PHONE_PATTERN = re.compile(r"^\+[1-9]\d{7,14}$")
MIN_PASSWORD_LENGTH = 12
MAX_PASSWORD_LENGTH = 128
MAX_EMAIL_LENGTH = 255
MAX_FULL_NAME_LENGTH = 255

REGISTRATION_FIELDS = {"email", "password", "full_name"}
LOGIN_FIELDS = {"email", "password"}
OTP_FIELDS = {"phone"}

# Perform a full password verification even when an email does not exist.
DUMMY_PASSWORD_HASH = hash_password(secrets.token_urlsafe(32))


def normalized_email_from_request():
    """Return a normalized email without raising during limiter evaluation."""
    data = request.get_json(silent=True)
    if not isinstance(data, dict) or not isinstance(data.get("email"), str):
        return ""
    return data["email"].strip().lower()


def email_rate_limit_key():
    """Rate limit an account target without storing raw email PII in Redis."""
    email = normalized_email_from_request()
    digest = hashlib.sha256(email.encode("utf-8")).hexdigest()
    return f"email:{digest}"


def authenticated_user_key():
    """Use the user ID set by require_auth as the rate-limit key."""
    return f"user:{request.current_user_id}"


def close_database_resources(cursor, connection):
    """Close partially initialized database resources safely."""
    if cursor is not None:
        try:
            cursor.close()
        except Exception:
            current_app.logger.exception("Failed to close auth database cursor")
    if connection is not None:
        try:
            connection.close()
        except Exception:
            current_app.logger.exception("Failed to close auth database connection")


def validate_json_object(allowed_fields):
    """Return a JSON object after rejecting malformed or unexpected fields."""
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return None, (jsonify({"error": "request body must be a JSON object"}), 400)

    unknown_fields = sorted(set(data) - allowed_fields)
    if unknown_fields:
        return None, (
            jsonify(
                {
                    "error": "unsupported fields",
                    "fields": unknown_fields,
                }
            ),
            400,
        )

    return data, None


def validate_email(email):
    """Normalize and validate an email address for storage and lookup."""
    if not isinstance(email, str):
        return None

    normalized_email = email.strip().lower()
    if (
        not normalized_email
        or len(normalized_email) > MAX_EMAIL_LENGTH
        or not EMAIL_PATTERN.fullmatch(normalized_email)
    ):
        return None
    return normalized_email


def validate_password(password):
    """Enforce bounded password input suitable for the configured KDF."""
    return (
        isinstance(password, str)
        and MIN_PASSWORD_LENGTH <= len(password) <= MAX_PASSWORD_LENGTH
    )


@auth_bp.route("/register", methods=["POST"])
# Limit aggregate registration traffic by source IP.
@limiter.limit("5/10 minutes;20/day")
# Limit repeated registration attempts against the same normalized email.
@limiter.limit("3/hour", key_func=email_rate_limit_key)
def register():
    """Register a merchant without allowing role assignment or enumeration."""
    data, error_response = validate_json_object(REGISTRATION_FIELDS)
    if error_response:
        return error_response

    email = validate_email(data.get("email"))
    password = data.get("password")
    full_name = data.get("full_name", "")

    if email is None:
        return jsonify({"error": "valid email required"}), 400
    if not validate_password(password):
        return (
            jsonify(
                {
                    "error": (
                        f"password must be between {MIN_PASSWORD_LENGTH} "
                        f"and {MAX_PASSWORD_LENGTH} characters"
                    )
                }
            ),
            400,
        )
    if not isinstance(full_name, str):
        return jsonify({"error": "full_name must be a string"}), 400

    full_name = full_name.strip()
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
            "INSERT INTO users "
            "(email, password_hash, full_name, role) "
            "VALUES (%s, %s, %s, %s)",
            # The client cannot assign an administrative role.
            (email, hash_password(password), full_name, "merchant"),
        )
        conn.commit()
    except UniqueViolation:
        if conn is not None:
            conn.rollback()
        # Return the same response as successful registration.
    except Exception:
        if conn is not None:
            conn.rollback()
        current_app.logger.exception("Registration failed")
        return jsonify({"error": "registration unavailable"}), 500
    finally:
        close_database_resources(cur, conn)

    # The same status and body prevent existing-email enumeration.
    return jsonify({"message": "registration request received"}), 202


@auth_bp.route("/login", methods=["POST"])
# Limit aggregate login traffic by source IP.
@limiter.limit("5/minute;20/hour")
# Also limit distributed attacks against one normalized email.
@limiter.limit("5/minute;20/hour", key_func=email_rate_limit_key)
def login():
    """Authenticate a user, migrate legacy hashes, and issue a short-lived JWT."""
    data, error_response = validate_json_object(LOGIN_FIELDS)
    if error_response:
        return error_response

    email = validate_email(data.get("email"))
    password = data.get("password")
    if email is None or not isinstance(password, str):
        return jsonify({"error": "invalid credentials"}), 401

    conn = None
    cur = None
    try:
        conn = get_connection()
        cur = conn.cursor()
        cur.execute(
            "SELECT id, password_hash, role, is_active " "FROM users WHERE email = %s",
            (email,),
        )
        user = cur.fetchone()

        # Verify a dummy hash when the account is absent to reduce timing leakage.
        stored_hash = user["password_hash"] if user else DUMMY_PASSWORD_HASH
        password_valid = verify_password(password, stored_hash)
        if user and password_hash_needs_upgrade(stored_hash):
            # Match the cost of current hashes while legacy MD5 migration exists.
            verify_password(password, DUMMY_PASSWORD_HASH)
        if not user or not password_valid or not user["is_active"]:
            return jsonify({"error": "invalid credentials"}), 401

        if password_hash_needs_upgrade(user["password_hash"]):
            # Upgrade a verified legacy MD5 hash inside the login transaction.
            cur.execute(
                "UPDATE users SET password_hash = %s WHERE id = %s",
                (hash_password(password), user["id"]),
            )
            conn.commit()

        token = issue_token(user["id"], user["role"])
        if isinstance(token, bytes):
            token = token.decode("utf-8")
        return jsonify(
            {
                "token": token,
                "user_id": user["id"],
                "role": user["role"],
            }
        )
    except Exception:
        if conn is not None:
            conn.rollback()
        current_app.logger.exception("Login failed")
        return jsonify({"error": "authentication unavailable"}), 500
    finally:
        close_database_resources(cur, conn)


@auth_bp.route("/otp", methods=["POST"])
# Limit unauthenticated traffic before token verification.
@limiter.limit("10/hour")
@require_auth
# Apply a stricter limit to the authenticated user.
@limiter.limit("3/5 minutes;10/hour", key_func=authenticated_user_key)
def request_otp():
    """Generate a secure OTP for the authenticated user's delivery workflow."""
    data, error_response = validate_json_object(OTP_FIELDS)
    if error_response:
        return error_response

    phone = data.get("phone")
    if not isinstance(phone, str) or not PHONE_PATTERN.fullmatch(phone.strip()):
        return jsonify({"error": "phone must use E.164 format"}), 400

    # Generate a cryptographically secure six-digit code.
    otp = f"{secrets.randbelow(1_000_000):06d}"

    # Never log or return the OTP. A production SMS provider must consume it here.
    del otp
    return jsonify({"status": "sent"}), 202
