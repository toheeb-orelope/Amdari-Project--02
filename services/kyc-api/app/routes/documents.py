"""Document upload and retrieval for KYC submissions."""

import base64
import hashlib
import hmac
import os
import re
import uuid

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError
from flask import Blueprint, current_app, jsonify, request

from app.auth import require_auth
from app.extensions import limiter

documents_bp = Blueprint("documents", __name__)

MAX_DOCUMENT_SIZE = 10 * 1024 * 1024
MAX_FILENAME_LENGTH = 255
OBJECT_KEY_PATTERN = re.compile(
    r"^users/(?P<user_id>[1-9]\d*)/"
    r"(?P<object_id>[0-9a-f]{32})\.(?P<extension>pdf|jpg|png)$"
)

DOCUMENT_TYPES = {
    "pdf": {
        "content_type": "application/pdf",
        "signatures": (b"%PDF-",),
    },
    "jpg": {
        "content_type": "image/jpeg",
        "signatures": (b"\xff\xd8\xff",),
    },
    "png": {
        "content_type": "image/png",
        "signatures": (b"\x89PNG\r\n\x1a\n",),
    },
}


def configured_bucket_name():
    """Require the KYC bucket name instead of silently selecting one."""
    bucket_name = os.environ.get("KYC_BUCKET")
    if not bucket_name:
        raise RuntimeError("KYC_BUCKET environment variable is required")
    return bucket_name


def _s3():
    """Create an S3 client using the AWS default credential provider chain."""
    return boto3.client(
        "s3",
        region_name=os.environ.get("AWS_REGION", "af-south-1"),
        config=Config(
            connect_timeout=3,
            read_timeout=10,
            retries={"max_attempts": 2, "mode": "standard"},
            signature_version="s3v4",
        ),
    )


def authenticated_user_key():
    """Use the user ID set by require_auth as the rate-limit key."""
    return f"user:{request.current_user_id}"


def detected_document_type(filename, content):
    """Validate the extension and file signature, not the client MIME type."""
    if not isinstance(filename, str) or not filename:
        return None
    if len(filename) > MAX_FILENAME_LENGTH or "\x00" in filename:
        return None

    extension = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
    document_type = DOCUMENT_TYPES.get(extension)
    if document_type is None:
        return None
    if not any(
        content.startswith(signature) for signature in document_type["signatures"]
    ):
        return None
    return extension, document_type["content_type"]


def encryption_parameters():
    """Use KMS when configured, otherwise require S3-managed encryption."""
    kms_key_id = os.environ.get("KYC_KMS_KEY_ID")
    if kms_key_id:
        return {
            "ServerSideEncryption": "aws:kms",
            "SSEKMSKeyId": kms_key_id,
        }
    return {"ServerSideEncryption": "AES256"}


def owned_object_key(key):
    """Return a canonical key only when it belongs to the authenticated user."""
    if not isinstance(key, str) or len(key) > MAX_FILENAME_LENGTH:
        return None

    match = OBJECT_KEY_PATTERN.fullmatch(key)
    if match is None:
        return None
    if not hmac.compare_digest(
        match.group("user_id"),
        str(request.current_user_id),
    ):
        return None
    return key


def close_s3_body(body):
    """Close an S3 streaming body without masking the endpoint response."""
    if body is not None:
        try:
            body.close()
        except Exception:
            current_app.logger.exception("Failed to close KYC document stream")


@documents_bp.route("/upload", methods=["POST"])
# Apply a broad IP limit before authentication.
@limiter.limit("20/hour")
@require_auth
# KYC uploads are expensive and sensitive, so use a stricter per-user limit.
@limiter.limit("5/hour;20/day", key_func=authenticated_user_key)
def upload_document():
    """Upload a bounded private encrypted KYC document."""
    if set(request.files) != {"file"}:
        return jsonify({"error": "exactly one file field is required"}), 400

    uploaded_file = request.files["file"]
    if not uploaded_file.filename:
        return jsonify({"error": "filename required"}), 400

    # Read one extra byte so oversized uploads are rejected before S3 storage.
    content = uploaded_file.stream.read(MAX_DOCUMENT_SIZE + 1)
    if not content:
        return jsonify({"error": "document must not be empty"}), 400
    if len(content) > MAX_DOCUMENT_SIZE:
        return jsonify({"error": "document exceeds 10 MiB limit"}), 413

    document_type = detected_document_type(uploaded_file.filename, content)
    if document_type is None:
        return (
            jsonify({"error": "only valid PDF, JPEG, or PNG documents are allowed"}),
            400,
        )

    extension, content_type = document_type
    # Ignore the user-supplied filename to prevent traversal, overwrite and PII leakage.
    key = f"users/{request.current_user_id}/{uuid.uuid4().hex}.{extension}"
    checksum = base64.b64encode(hashlib.sha256(content).digest()).decode("ascii")

    try:
        _s3().put_object(
            Bucket=configured_bucket_name(),
            Key=key,
            Body=content,
            ContentLength=len(content),
            ContentType=content_type,
            ChecksumSHA256=checksum,
            CacheControl="no-store",
            **encryption_parameters(),
        )
        current_app.logger.info(
            "KYC document uploaded user_id=%s key=%s size=%s",
            request.current_user_id,
            key,
            len(content),
        )
        # Do not expose the internal bucket name.
        return jsonify({"key": key}), 201
    except ClientError:
        current_app.logger.exception("S3 rejected KYC document upload")
        return jsonify({"error": "document upload failed"}), 502
    except Exception:
        current_app.logger.exception("Failed to upload KYC document")
        return jsonify({"error": "document upload failed"}), 500


@documents_bp.route("/<path:key>", methods=["GET"])
# Apply a broad IP limit before authentication.
@limiter.limit("120/minute")
@require_auth
# Apply a tighter limit after require_auth has set current_user_id.
@limiter.limit("30/minute;500/day", key_func=authenticated_user_key)
def get_document(key):
    """Fetch a bounded KYC document owned by the authenticated user."""
    key = owned_object_key(key)
    if key is None:
        # Use the same response for malformed and non-owned keys.
        return jsonify({"error": "document not found"}), 404

    body = None
    try:
        obj = _s3().get_object(
            Bucket=configured_bucket_name(),
            Key=key,
        )
        body = obj["Body"]
        content_length = obj.get("ContentLength")
        if (
            not isinstance(content_length, int)
            or content_length < 1
            or content_length > MAX_DOCUMENT_SIZE
        ):
            current_app.logger.error(
                "Rejected invalid stored KYC document size key=%s size=%s",
                key,
                content_length,
            )
            return jsonify({"error": "document unavailable"}), 500

        content = body.read(MAX_DOCUMENT_SIZE + 1)
        if len(content) != content_length or len(content) > MAX_DOCUMENT_SIZE:
            current_app.logger.error("KYC document length mismatch key=%s", key)
            return jsonify({"error": "document unavailable"}), 500

        extension = key.rsplit(".", 1)[-1]
        expected_type = DOCUMENT_TYPES[extension]["content_type"]
        if not any(
            content.startswith(signature)
            for signature in DOCUMENT_TYPES[extension]["signatures"]
        ):
            current_app.logger.error("KYC document signature mismatch key=%s", key)
            return jsonify({"error": "document unavailable"}), 500

        return (
            content,
            200,
            {
                "Content-Type": expected_type,
                "Content-Disposition": f'attachment; filename="kyc-document.{extension}"',
                "Cache-Control": "no-store, private",
                "Pragma": "no-cache",
                "X-Content-Type-Options": "nosniff",
            },
        )
    except ClientError as error:
        error_code = error.response.get("Error", {}).get("Code", "")
        if error_code in {"NoSuchKey", "404", "NotFound"}:
            return jsonify({"error": "document not found"}), 404
        current_app.logger.exception("S3 rejected KYC document retrieval")
        return jsonify({"error": "document retrieval failed"}), 502
    except Exception:
        current_app.logger.exception("Failed to fetch KYC document")
        return jsonify({"error": "document retrieval failed"}), 500
    finally:
        close_s3_body(body)
