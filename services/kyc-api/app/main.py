"""SentinelPay KYC API — identity verification service."""

import os

from flask import Flask, jsonify
from flask_limiter.errors import RateLimitExceeded
from werkzeug.exceptions import HTTPException

from app.extensions import limiter
from app.routes.verify import verify_bp
from app.routes.documents import documents_bp


def create_app():
    app = Flask(__name__)
    app.config["ENVIRONMENT"] = os.environ.get("ENVIRONMENT", "development")

    # Fail closed instead of using a repository default signing secret.
    jwt_secret = os.environ.get("JWT_SECRET")
    if not jwt_secret or len(jwt_secret.encode("utf-8")) < 32:
        raise RuntimeError("JWT_SECRET must be configured with at least 32 bytes")
    app.config["JWT_SECRET"] = jwt_secret

    rate_limit_storage = os.environ.get("RATELIMIT_STORAGE_URI")
    if not rate_limit_storage:
        if app.config["ENVIRONMENT"] == "testing":
            # Keep isolated tests independent from an external Redis service.
            rate_limit_storage = "memory://"
        else:
            raise RuntimeError(
                "RATELIMIT_STORAGE_URI environment variable is required"
            )

    app.config["RATELIMIT_STORAGE_URI"] = rate_limit_storage
    app.config["RATELIMIT_STORAGE_OPTIONS"] = {
        "socket_connect_timeout": 1,
        "socket_timeout": 2,
    }
    app.config["RATELIMIT_SWALLOW_ERRORS"] = False
    app.config["RATELIMIT_IN_MEMORY_FALLBACK_ENABLED"] = False

    limiter.init_app(app)

    @app.errorhandler(RateLimitExceeded)
    def handle_rate_limit(error):
        return jsonify({"error": "rate limit exceeded"}), 429

    app.register_blueprint(verify_bp, url_prefix="/v1/verify")
    app.register_blueprint(documents_bp, url_prefix="/v1/documents")

    @app.route("/health")
    def health():
        return jsonify({"status": "ok", "service": "kyc-api"})

    @app.errorhandler(Exception)
    def handle_exception(error):
        if isinstance(error, HTTPException):
            return jsonify({"error": error.description}), error.code

        app.logger.exception("Unhandled application error")
        return jsonify({"error": "internal server error"}), 500

    return app


if __name__ == "__main__":
    app = create_app()
    app.run(
        host=os.environ.get("FLASK_RUN_HOST", "127.0.0.1"),
        port=8002,
        debug=app.config["ENVIRONMENT"] == "development",
    )
