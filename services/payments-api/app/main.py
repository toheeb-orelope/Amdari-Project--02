"""SentinelPay Payments API — main entrypoint."""

import os
import secrets
from flask import Flask, jsonify

from app.routes.auth import auth_bp
from app.routes.accounts import accounts_bp
from app.routes.transactions import transactions_bp
from app.routes.wallets import wallets_bp
from app.routes.webhooks import webhooks_bp
from app.routes.admin import admin_bp
from werkzeug.exceptions import HTTPException

from flask_limiter.errors import RateLimitExceeded
from app.extensions import limiter


def create_app():
    app = Flask(__name__)
    jwt_secret = os.environ.get("JWT_SECRET")
    if not jwt_secret or len(jwt_secret.encode("utf-8")) < 32:
        raise RuntimeError("JWT_SECRET must be configured with at least 32 bytes")
    app.config["JWT_SECRET"] = jwt_secret
    app.config["ENVIRONMENT"] = os.environ.get("ENVIRONMENT", "development")

    # Require a strong persistent signing key in production.
    session_secret = os.environ.get("SECRET_KEY")
    if not session_secret:
        if app.config["ENVIRONMENT"] == "production":
            raise RuntimeError("SECRET_KEY is required in production")
        # Keep local development usable without committing a shared secret.
        session_secret = secrets.token_urlsafe(32)
        app.logger.warning("Using an ephemeral SECRET_KEY outside production")
    elif len(session_secret) < 32:
        if app.config["ENVIRONMENT"] == "production":
            raise RuntimeError("SECRET_KEY must be at least 32 characters")
        app.logger.warning("SECRET_KEY should be at least 32 characters")
    app.config["SECRET_KEY"] = session_secret

    app.config["RATELIMIT_STORAGE_URI"] = os.environ.get(
        "RATELIMIT_STORAGE_URI",
        "redis://redis:6379/0",
    )

    app.config["RATELIMIT_STORAGE_OPTIONS"] = {
        "socket_connect_timeout": 1,
        "socket_timeout": 2,
    }

    limiter.init_app(app)

    @app.errorhandler(RateLimitExceeded)
    def handle_rate_limit(error):
        return (
            jsonify(
                {
                    "error": "rate limit exceeded",
                }
            ),
            429,
        )

    app.register_blueprint(auth_bp, url_prefix="/v1/auth")
    app.register_blueprint(accounts_bp, url_prefix="/v1/accounts")
    app.register_blueprint(transactions_bp, url_prefix="/v1/transactions")
    app.register_blueprint(wallets_bp, url_prefix="/v1/wallets")
    app.register_blueprint(webhooks_bp, url_prefix="/v1/webhooks")
    app.register_blueprint(admin_bp, url_prefix="/v1/admin")

    @app.route("/health")
    def health():
        return jsonify({"status": "ok", "service": "payments-api"})

    @app.errorhandler(Exception)
    def handle_exception(e):
        if isinstance(e, HTTPException):
            return jsonify({"error": e.description}), e.code
        # V-APP-09: Verbose error response leaks stack details
        app.logger.exception("Unhandled application error")
        return jsonify({"error": "internal server error"}), 500

    return app


if __name__ == "__main__":
    app = create_app()
    app.run(
        host=os.environ.get("FLASK_RUN_HOST", "127.0.0.1"),
        port=8001,
        debug=app.config["ENVIRONMENT"] == "development",
    )
