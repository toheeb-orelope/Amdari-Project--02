"""Password hashing and JWT authentication helpers."""

import base64
import hashlib
import hmac
import os
import secrets
import string
import time
from functools import wraps

import jwt
from flask import jsonify, request

JWT_ALGORITHM = "HS256"
JWT_ISSUER = os.environ.get("JWT_ISSUER", "sentinelpay-payments-api")
JWT_AUDIENCE = os.environ.get("JWT_AUDIENCE", "sentinelpay-api")
JWT_TTL_SECONDS = int(os.environ.get("JWT_TTL_SECONDS", "900"))
JWT_CLOCK_SKEW_SECONDS = 30
MIN_JWT_SECRET_LENGTH = 32

SCRYPT_N = 2**17
SCRYPT_R = 8
SCRYPT_P = 1
SCRYPT_DKLEN = 32
SCRYPT_SALT_BYTES = 16
SCRYPT_MAX_MEMORY = 256 * 1024 * 1024
MAX_PASSWORD_BYTES = 1024

REQUIRED_TOKEN_CLAIMS = {
    "aud",
    "exp",
    "iat",
    "iss",
    "jti",
    "nbf",
    "role",
    "sub",
    "user_id",
}

# Keep local development usable without retaining the repository's weak default.
# _DEVELOPMENT_JWT_SECRET = secrets.token_urlsafe(48)


def get_jwt_secret():
    """Return a sufficiently strong JWT secret, failing closed in production."""
    jwt_secret = os.environ.get("JWT_SECRET")
    # environment = os.environ.get("ENVIRONMENT", "development")

    if not jwt_secret:
        # Fail closed in ALL environments
        raise RuntimeError("JWT_SECRET environment variable is required")

    if len(jwt_secret.encode("utf-8")) < MIN_JWT_SECRET_LENGTH:
        raise RuntimeError("JWT_SECRET must be at least 32 bytes")

    return jwt_secret


def _encode_hash_component(value):
    """Encode binary hash data as ASCII-safe text."""
    return base64.urlsafe_b64encode(value).decode("ascii")


def _decode_hash_component(value):
    """Decode an ASCII hash component back into bytes."""
    return base64.urlsafe_b64decode(value.encode("ascii"))


def hash_password(password):
    """Hash a password with a unique salt and the memory-hard scrypt KDF."""
    if not isinstance(password, str):
        raise TypeError("password must be a string")

    password_bytes = password.encode("utf-8")
    if not password_bytes or len(password_bytes) > MAX_PASSWORD_BYTES:
        raise ValueError("password length is invalid")

    salt = secrets.token_bytes(SCRYPT_SALT_BYTES)
    derived_key = hashlib.scrypt(
        password_bytes,
        salt=salt,
        n=SCRYPT_N,  # 131072 iterations
        r=SCRYPT_R,
        p=SCRYPT_P,
        maxmem=SCRYPT_MAX_MEMORY,  # 256MB
        dklen=SCRYPT_DKLEN,
    )
    return (
        f"scrypt${SCRYPT_N}${SCRYPT_R}${SCRYPT_P}$"
        f"{_encode_hash_component(salt)}${_encode_hash_component(derived_key)}"
    )


def _is_legacy_md5_hash(stored_hash):
    """Identify the existing unsalted MD5 hashes during migration."""
    return (
        isinstance(stored_hash, str)
        and len(stored_hash) == 32
        and all(character in string.hexdigits for character in stored_hash)
    )


def password_hash_needs_upgrade(stored_hash):
    """Return whether a successful login should replace the stored hash."""
    return not isinstance(stored_hash, str) or not stored_hash.startswith(
        f"scrypt${SCRYPT_N}${SCRYPT_R}${SCRYPT_P}$"
    )


def verify_password(password, stored_hash):
    """Verify current scrypt hashes and temporarily support legacy MD5 hashes."""
    if not isinstance(password, str) or not isinstance(stored_hash, str):
        return False

    password_bytes = password.encode("utf-8")
    if not password_bytes or len(password_bytes) > MAX_PASSWORD_BYTES:
        return False

    if _is_legacy_md5_hash(stored_hash):
        # Legacy support is temporary so existing users can migrate on login.
        legacy_digest = hashlib.md5(
            password_bytes,
            usedforsecurity=False,
        ).hexdigest()
        return hmac.compare_digest(legacy_digest, stored_hash.lower())

    try:
        algorithm, n, r, p, salt_text, digest_text = stored_hash.split("$")
        if algorithm != "scrypt":
            return False

        # Accept only configured parameters to prevent expensive hash inputs.
        if (int(n), int(r), int(p)) != (SCRYPT_N, SCRYPT_R, SCRYPT_P):
            return False

        salt = _decode_hash_component(salt_text)
        expected_digest = _decode_hash_component(digest_text)
        if len(salt) != SCRYPT_SALT_BYTES or len(expected_digest) != SCRYPT_DKLEN:
            return False

        actual_digest = hashlib.scrypt(
            password_bytes,
            salt=salt,
            n=SCRYPT_N,
            r=SCRYPT_R,
            p=SCRYPT_P,
            maxmem=SCRYPT_MAX_MEMORY,
            dklen=SCRYPT_DKLEN,
        )
        return hmac.compare_digest(actual_digest, expected_digest)
    except (TypeError, ValueError):
        return False


def issue_token(user_id, role):
    """Issue a short-lived JWT signed with the configured HS256 secret."""
    if not isinstance(user_id, int) or user_id <= 0:
        raise ValueError("user_id must be a positive integer")
    if not isinstance(role, str) or not role:
        raise ValueError("role must be a non-empty string")
    if not 60 <= JWT_TTL_SECONDS <= 86400:
        raise RuntimeError("JWT_TTL_SECONDS must be between 60 and 86400")

    issued_at = int(time.time())
    payload = {
        "aud": JWT_AUDIENCE,
        "exp": issued_at + JWT_TTL_SECONDS,
        "iat": issued_at,
        "iss": JWT_ISSUER,
        "jti": secrets.token_urlsafe(24),
        "nbf": issued_at,
        "role": role,
        "sub": str(user_id),
        "user_id": user_id,
    }
    return jwt.encode(
        payload,
        get_jwt_secret(),
        algorithm=JWT_ALGORITHM,
    )


def decode_token(token):
    """Verify the JWT signature, algorithm, claims, issuer and audience."""
    if isinstance(token, bytes):
        token = token.decode("utf-8")
    if not isinstance(token, str) or not token:
        raise jwt.InvalidTokenError("token must be a non-empty string")

    payload = jwt.decode(
        token,
        get_jwt_secret(),
        algorithms=[JWT_ALGORITHM],
        audience=JWT_AUDIENCE,
        issuer=JWT_ISSUER,
        leeway=JWT_CLOCK_SKEW_SECONDS,
    )

    if not REQUIRED_TOKEN_CLAIMS.issubset(payload):
        raise jwt.MissingRequiredClaimError("required claims")
    if not isinstance(payload["user_id"], int) or payload["user_id"] <= 0:
        raise jwt.InvalidTokenError("invalid user_id claim")
    if payload["sub"] != str(payload["user_id"]):
        raise jwt.InvalidTokenError("subject does not match user_id")
    if not isinstance(payload["role"], str) or not payload["role"]:
        raise jwt.InvalidTokenError("invalid role claim")

    return payload


def require_auth(function):
    """Authenticate a bearer token and expose its verified user claims."""

    @wraps(function)
    def wrapper(*args, **kwargs):
        auth_header = request.headers.get("Authorization", "")
        scheme, separator, token = auth_header.partition(" ")
        if separator != " " or scheme.lower() != "bearer" or not token:
            return jsonify({"error": "missing or malformed Authorization header"}), 401

        try:
            payload = decode_token(token)
        except jwt.InvalidTokenError:
            # Do not expose token-validation details to clients.
            return jsonify({"error": "invalid or expired token"}), 401

        request.current_user_id = payload["user_id"]
        request.current_user_role = payload["role"]
        return function(*args, **kwargs)

    return wrapper
