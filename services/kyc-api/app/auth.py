"""Shared auth helpers (duplicated from payments-api — known tech debt)."""

import os
from functools import wraps

import jwt
from flask import jsonify, request

JWT_ALGORITHM = "HS256"
JWT_ISSUER = os.environ.get(
    "JWT_ISSUER",
    "sentinelpay-payments-api",
)
JWT_AUDIENCE = os.environ.get(
    "JWT_AUDIENCE",
    "sentinelpay-api",
)
JWT_CLOCK_SKEW_SECONDS = 30
MIN_JWT_SECRET_LENGTH = 32

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


def get_jwt_secret():
    """Return the required sufficiently strong JWT secret."""
    jwt_secret = os.environ.get("JWT_SECRET")

    if not jwt_secret:
        raise RuntimeError("JWT_SECRET environment variable is required")

    if len(jwt_secret.encode("utf-8")) < MIN_JWT_SECRET_LENGTH:
        raise RuntimeError("JWT_SECRET must be at least 32 bytes")

    return jwt_secret


def decode_token(token):
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
        raise jwt.InvalidTokenError("invalid subject claim")

    if not isinstance(payload["role"], str) or not payload["role"]:
        raise jwt.InvalidTokenError("invalid role claim")

    return payload


def require_auth(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        auth_header = request.headers.get("Authorization", "")
        scheme, separator, token = auth_header.partition(" ")

        if separator != " " or scheme.lower() != "bearer" or not token:
            return jsonify({"error": "unauthorized"}), 401

        try:
            payload = decode_token(token)
        except jwt.InvalidTokenError:
            return jsonify({"error": "unauthorized"}), 401

        request.current_user_id = payload["user_id"]
        request.current_user_role = payload["role"]
        return f(*args, **kwargs)

    return wrapper
