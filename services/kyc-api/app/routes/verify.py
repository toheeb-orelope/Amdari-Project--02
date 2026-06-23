"""Identity verification endpoints."""

import json
import os
from urllib.parse import urlsplit

import requests
from flask import Blueprint, current_app, jsonify, request

from app.auth import require_auth
from app.db import get_connection
from app.extensions import limiter

verify_bp = Blueprint("verify", __name__)

IDENTIFIER_LENGTH = 11
MAX_PROVIDER_RESPONSE_SIZE = 8192
BVN_FIELDS = {"bvn"}


def configured_bvn_lookup_url():
    """Return the server-controlled HTTPS provider URL."""
    provider_url = os.environ.get("BVN_LOOKUP_URL")
    if not provider_url:
        raise RuntimeError("BVN_LOOKUP_URL environment variable is required")

    try:
        parsed = urlsplit(provider_url)
        port = parsed.port
    except ValueError as error:
        raise RuntimeError("BVN_LOOKUP_URL is invalid") from error

    if (
        parsed.scheme.lower() != "https"
        or not parsed.hostname
        or parsed.username is not None
        or parsed.password is not None
        or parsed.fragment
        or port not in (None, 443)
    ):
        raise RuntimeError("BVN_LOOKUP_URL must be an HTTPS URL on port 443")
    return provider_url


def configured_provider_timeout():
    """Return a bounded provider timeout."""
    try:
        timeout = float(os.environ.get("BVN_LOOKUP_TIMEOUT", "5"))
    except ValueError:
        timeout = 5.0
    return min(max(timeout, 1.0), 10.0)


def provider_verification_result(response):
    """Parse only the bounded boolean result required from the provider."""
    content = bytearray()
    for chunk in response.iter_content(chunk_size=4096):
        if not chunk:
            continue
        content.extend(chunk)
        if len(content) > MAX_PROVIDER_RESPONSE_SIZE:
            return None

    try:
        payload = json.loads(content.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return None
    if not isinstance(payload, dict) or not isinstance(payload.get("verified"), bool):
        return None
    return payload["verified"]


def authenticated_user_key():
    """Use the user ID set by require_auth as the rate-limit key."""
    return f"user:{request.current_user_id}"


def close_database_resources(cur, conn):
    """Close partially initialized database resources safely."""
    if cur is not None:
        try:
            cur.close()
        except Exception:
            current_app.logger.exception("Failed to close KYC database cursor")
    if conn is not None:
        try:
            conn.close()
        except Exception:
            current_app.logger.exception("Failed to close KYC database connection")


def validate_json_object(allowed_fields):
    """Validate a JSON object and reject unexpected fields."""
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


def valid_identifier(value):
    """Accept only fixed-length decimal identity identifiers."""
    return (
        isinstance(value, str)
        and len(value) == IDENTIFIER_LENGTH
        and value.isascii()
        and value.isdigit()
    )


@verify_bp.route("/bvn", methods=["POST"])
# Apply an IP limit before authentication.
@limiter.limit("20/hour")
@require_auth
# Apply the stricter identity-provider limit after authentication.
@limiter.limit("5/minute;20/day", key_func=authenticated_user_key)
def verify_bvn():
    """Verify a BVN through the configured upstream provider."""
    data, error_response = validate_json_object(BVN_FIELDS)
    if error_response:
        return error_response

    bvn = data.get("bvn")
    if not valid_identifier(bvn):
        return jsonify({"error": "valid 11-digit BVN required"}), 400

    response = None
    session = None
    try:
        # The client cannot override the destination, closing the SSRF path.
        provider_url = configured_bvn_lookup_url()
        timeout = configured_provider_timeout()
        session = requests.Session()
        # Do not inherit attacker-influenced or ambient proxy environment settings.
        session.trust_env = False
        response = session.post(
            provider_url,
            json={"bvn": bvn},
            allow_redirects=False,
            headers={
                "Accept": "application/json",
                "User-Agent": "SentinelPay-KYC/1.0",
            },
            stream=True,
            timeout=(timeout, timeout),
        )

        if response.status_code == 200:
            verified = provider_verification_result(response)
            if verified is None:
                current_app.logger.error(
                    "BVN provider returned an invalid response user_id=%s",
                    request.current_user_id,
                )
                return jsonify({"error": "verification provider unavailable"}), 502
            # Return only the verification result, never provider identity data.
            return jsonify({
                "status": "verified" if verified else "not_verified"
            }), 200
        if response.status_code in {400, 404, 422}:
            return jsonify({"status": "not_verified"}), 200

        current_app.logger.error(
            "BVN provider returned unexpected status=%s user_id=%s",
            response.status_code,
            request.current_user_id,
        )
        return jsonify({"error": "verification provider unavailable"}), 502
    except requests.RequestException:
        current_app.logger.warning(
            "BVN provider request failed for user_id=%s",
            request.current_user_id,
        )
        return jsonify({"error": "verification provider unavailable"}), 502
    except RuntimeError:
        current_app.logger.exception("BVN provider configuration is invalid")
        return jsonify({"error": "verification unavailable"}), 500
    except Exception:
        current_app.logger.exception("Failed to verify BVN")
        return jsonify({"error": "verification failed"}), 500
    finally:
        if response is not None:
            try:
                response.close()
            except Exception:
                current_app.logger.exception("Failed to close BVN provider response")
        if session is not None:
            try:
                session.close()
            except Exception:
                current_app.logger.exception("Failed to close BVN provider session")


@verify_bp.route("/lookup", methods=["GET"])
# Apply an IP limit before authentication.
@limiter.limit("60/minute")
@require_auth
# Apply a stricter per-user limit after authentication.
@limiter.limit("20/hour", key_func=authenticated_user_key)
def lookup_kyc():
    """Look up the authenticated user's KYC status by BVN or NIN."""
    bvn = request.args.get("bvn")
    nin = request.args.get("nin")

    # Require exactly one identifier to avoid ambiguous or broad queries.
    if (bvn is None) == (nin is None):
        return jsonify({"error": "provide exactly one of bvn or nin"}), 400

    field_name = "bvn" if bvn is not None else "nin"
    identifier = bvn if bvn is not None else nin
    if not valid_identifier(identifier):
        return jsonify({
            "error": f"valid 11-digit {field_name.upper()} required"
        }), 400

    connection = None
    cursor = None
    try:
        connection = get_connection()
        cursor = connection.cursor()
        # The selected column is server-controlled; the identifier remains parameterized.
        query = (
            "SELECT id, verification_status, submitted_at "
            f"FROM kyc_records WHERE user_id = %s AND {field_name} = %s "
            "ORDER BY id"
        )
        cursor.execute(
            query,
            (request.current_user_id, identifier),
        )
        records = cursor.fetchall()
        return jsonify([dict(record) for record in records])
    except Exception:
        current_app.logger.exception("Failed to look up KYC record")
        return jsonify({"error": "KYC lookup failed"}), 500
    finally:
        close_database_resources(cursor, connection)
