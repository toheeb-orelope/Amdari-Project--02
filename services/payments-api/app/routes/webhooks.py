"""Webhook registration and callback testing."""

import ipaddress
import os
import socket
from urllib.parse import urlsplit, urlunsplit

import requests
from flask import Blueprint, current_app, jsonify, request

from app.auth import require_auth
from app.db import get_connection
from app.extensions import limiter

webhooks_bp = Blueprint("webhooks", __name__)

MAX_CALLBACK_URL_LENGTH = 500
MAX_EVENT_TYPE_LENGTH = 50
ALLOWED_EVENT_TYPES = {"transaction.completed"}
REGISTRATION_FIELDS = {"callback_url", "event_type"}
TEST_FIELDS = {"url"}
BLOCKED_HOSTNAMES = {
    "localhost",
    "metadata.google.internal",
}


def configured_webhook_timeout():
    """Return a bounded timeout even when the environment value is invalid."""
    try:
        timeout = float(os.environ.get("WEBHOOK_TIMEOUT", "5"))
    except ValueError:
        timeout = 5.0
    return min(max(timeout, 1.0), 10.0)


WEBHOOK_TIMEOUT = configured_webhook_timeout()


def authenticated_user_key():
    """Use the user ID set by require_auth as the rate-limit key."""
    return f"user:{request.current_user_id}"


def close_database_resources(cur, conn):
    """Close partially initialized database resources safely."""
    if cur is not None:
        try:
            cur.close()
        except Exception:
            current_app.logger.exception("Failed to close webhook database cursor")
    if conn is not None:
        try:
            conn.close()
        except Exception:
            current_app.logger.exception("Failed to close webhook database connection")


def validate_json_object(allowed_fields):
    """Validate a JSON object and reject unexpected fields."""
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


def normalized_public_https_url(value):
    """Validate and normalize a public HTTPS callback URL."""
    if not isinstance(value, str):
        return None

    value = value.strip()
    if not value or len(value) > MAX_CALLBACK_URL_LENGTH:
        return None

    try:
        parsed = urlsplit(value)
        hostname = (parsed.hostname or "").rstrip(".").lower()
        port = parsed.port
    except ValueError:
        return None

    if parsed.scheme.lower() != "https":
        return None
    if not hostname or hostname in BLOCKED_HOSTNAMES:
        return None
    if parsed.username is not None or parsed.password is not None:
        return None
    if parsed.fragment:
        return None
    if port not in (None, 443):
        return None

    try:
        ascii_hostname = hostname.encode("idna").decode("ascii")
        addresses = socket.getaddrinfo(
            ascii_hostname,
            443,
            type=socket.SOCK_STREAM,
        )
    except (UnicodeError, socket.gaierror):
        return None

    if not addresses:
        return None
    for address in addresses:
        ip_text = address[4][0]
        try:
            ip_address = ipaddress.ip_address(ip_text)
        except ValueError:
            return None
        if ip_address.version == 6 and ip_address.ipv4_mapped is not None:
            ip_address = ip_address.ipv4_mapped
        # is_global rejects private, loopback, link-local, reserved and metadata IPs.
        if not ip_address.is_global:
            return None

    netloc_host = f"[{ascii_hostname}]" if ":" in ascii_hostname else ascii_hostname
    netloc = netloc_host
    if port == 443:
        netloc = f"{netloc_host}:443"
    path = parsed.path or "/"
    return urlunsplit(("https", netloc, path, parsed.query, ""))


def registered_webhook(cur, callback_url):
    """Return a webhook only when it belongs to the authenticated user."""
    cur.execute(
        "SELECT id FROM webhooks "
        "WHERE user_id = %s AND callback_url = %s "
        "ORDER BY id LIMIT 1",
        (request.current_user_id, callback_url),
    )
    return cur.fetchone()


@webhooks_bp.route("/", methods=["POST"])
@limiter.limit("30/minute")
@require_auth
@limiter.limit("10/minute;100/day", key_func=authenticated_user_key)
def register_webhook():
    """Register a validated public HTTPS callback URL."""
    data, error_response = validate_json_object(REGISTRATION_FIELDS)
    if error_response:
        return error_response

    callback_url = normalized_public_https_url(data.get("callback_url"))
    event_type = data.get("event_type", "transaction.completed")

    if callback_url is None:
        return jsonify({"error": "callback_url must be a public HTTPS URL"}), 400
    if (
        not isinstance(event_type, str)
        or len(event_type) > MAX_EVENT_TYPE_LENGTH
        or event_type not in ALLOWED_EVENT_TYPES
    ):
        return jsonify({"error": "unsupported event_type"}), 400

    conn = None
    cur = None
    try:
        conn = get_connection()
        cur = conn.cursor()
        existing_webhook = registered_webhook(cur, callback_url)
        if existing_webhook:
            return (
                jsonify(
                    {
                        "id": existing_webhook["id"],
                        "callback_url": callback_url,
                    }
                ),
                200,
            )

        cur.execute(
            "INSERT INTO webhooks (user_id, callback_url, event_type) "
            "VALUES (%s, %s, %s) RETURNING id",
            (request.current_user_id, callback_url, event_type),
        )
        webhook_id = cur.fetchone()["id"]
        conn.commit()
        return (
            jsonify(
                {
                    "id": webhook_id,
                    "callback_url": callback_url,
                }
            ),
            201,
        )
    except Exception:
        if conn is not None:
            conn.rollback()
        current_app.logger.exception("Webhook registration failed")
        return jsonify({"error": "webhook registration failed"}), 500
    finally:
        close_database_resources(cur, conn)


@webhooks_bp.route("/test", methods=["POST"])
@limiter.limit("10/minute")
@require_auth
@limiter.limit("3/minute;20/hour", key_func=authenticated_user_key)
def test_webhook():
    """Test a registered webhook without exposing the remote response body."""
    data, error_response = validate_json_object(TEST_FIELDS)
    if error_response:
        return error_response

    callback_url = normalized_public_https_url(data.get("url"))
    if callback_url is None:
        return jsonify({"error": "url must be a public HTTPS URL"}), 400

    conn = None
    cur = None
    response = None
    session = None
    try:
        conn = get_connection()
        cur = conn.cursor()
        if not registered_webhook(cur, callback_url):
            return jsonify({"error": "registered webhook not found"}), 404

        # Ignore environment proxy settings and never follow redirects to a new target.
        session = requests.Session()
        session.trust_env = False
        response = session.get(
            callback_url,
            allow_redirects=False,
            headers={
                "Accept": "application/json",
                "User-Agent": "SentinelPay-Webhook-Test/1.0",
            },
            stream=True,
            timeout=(WEBHOOK_TIMEOUT, WEBHOOK_TIMEOUT),
        )
        return jsonify(
            {
                "delivered": 200 <= response.status_code < 300,
                "status_code": response.status_code,
            }
        )
    except requests.RequestException:
        current_app.logger.warning(
            "Webhook test delivery failed for user_id=%s",
            request.current_user_id,
        )
        return jsonify({"error": "webhook delivery failed"}), 502
    except Exception:
        current_app.logger.exception("Webhook test failed")
        return jsonify({"error": "webhook test failed"}), 500
    finally:
        if response is not None:
            try:
                response.close()
            except Exception:
                current_app.logger.exception("Failed to close webhook response")
        if session is not None:
            try:
                session.close()
            except Exception:
                current_app.logger.exception("Failed to close webhook HTTP session")
        close_database_resources(cur, conn)
