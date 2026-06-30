variable "project" {
  type = string
}

variable "environment" {
  description = "dev, staging, or prod"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "s3_kms_key_arn" {
  description = "Customer-managed KMS key ARN used to encrypt KYC document bucket objects."
  type        = string
}

variable "access_log_bucket_name" {
  description = "Central S3 server access log bucket name from the logging module."
  type        = string
}

variable "kyc_task_role_arn" {
  description = "Optional kyc-api ECS task role ARN allowed to read and write KYC documents."
  type        = string
  default     = null
}

variable "object_lock_retention_days" {
  description = "Governance-mode Object Lock retention for KYC documents. Keep short for lab teardown."
  type        = number
  default     = 1

  validation {
    condition     = var.object_lock_retention_days >= 1
    error_message = "object_lock_retention_days must be at least 1."
  }
}

variable "document_retention_days" {
  description = "Lifecycle expiration for KYC documents."
  type        = number
  default     = 365

  validation {
    condition     = var.document_retention_days >= 1
    error_message = "document_retention_days must be at least 1."
  }
}

variable "owner" {
  type    = string
  default = "toheeb"
}

variable "cost_center" {
  type    = string
  default = "lab"
}

variable "repository" {
  type    = string
  default = "Amdari-Project--02"
}

variable "data_classification" {
  type    = string
  default = "confidential"
}

variable "enable_replication" {
  description = "Enable same-account/cross-region replication for the KYC documents bucket. Keep disabled in dev unless a destination bucket and KMS key are provided."
  type        = bool
  default     = false
}

variable "replication_destination_bucket_arn" {
  description = "Destination S3 bucket ARN for KYC document replication. Required when enable_replication is true."
  type        = string
  default     = null
}

variable "replication_destination_kms_key_arn" {
  description = "Destination KMS key ARN for encrypted KYC document replication. Required when enable_replication is true."
  type        = string
  default     = null
}

variable "criticality" {
  type    = string
  default = "high"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  kyc_bucket_name = "${var.project}-${var.environment}-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}-kyc-documents"

  common_tags = {
    Project            = var.project
    Environment        = var.environment
    Service            = "s3"
    Owner              = var.owner
    CostCenter         = var.cost_center
    ManagedBy          = "terraform"
    Repository         = var.repository
    DataClassification = var.data_classification
    Criticality        = var.criticality
  }
}

resource "aws_s3_bucket" "kyc_documents" {
  bucket              = local.kyc_bucket_name
  object_lock_enabled = true
  force_destroy       = false

  tags = merge(local.common_tags, {
    Name    = "${var.project}-${var.environment}-kyc-documents"
    Purpose = "KYC document storage"
  })
}

resource "aws_s3_bucket_ownership_controls" "kyc_documents" {
  bucket = aws_s3_bucket.kyc_documents.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "kyc_documents" {
  bucket = aws_s3_bucket.kyc_documents.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "kyc_documents" {
  bucket = aws_s3_bucket.kyc_documents.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "kyc_documents" {
  bucket = aws_s3_bucket.kyc_documents.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.s3_kms_key_arn
      sse_algorithm     = "aws:kms"
    }

    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_object_lock_configuration" "kyc_documents" {
  bucket = aws_s3_bucket.kyc_documents.id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = var.object_lock_retention_days
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "kyc_documents" {
  bucket = aws_s3_bucket.kyc_documents.id

  rule {
    id     = "kyc-document-retention"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = var.document_retention_days
    }

    expiration {
      days = var.document_retention_days
    }
  }
}

resource "aws_s3_bucket_logging" "kyc_documents" {
  bucket = aws_s3_bucket.kyc_documents.id

  target_bucket = var.access_log_bucket_name
  target_prefix = "s3-access/kyc-documents/"
}

data "aws_iam_policy_document" "kyc_documents" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.kyc_documents.arn,
      "${aws_s3_bucket.kyc_documents.arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid    = "DenyUnencryptedObjectUploads"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.kyc_documents.arn}/*"]

    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["aws:kms"]
    }
  }

  statement {
    sid    = "DenyWrongKmsKey"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.kyc_documents.arn}/*"]

    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
      values   = [var.s3_kms_key_arn]
    }
  }

  dynamic "statement" {
    for_each = var.kyc_task_role_arn == null ? [] : [var.kyc_task_role_arn]

    content {
      sid    = "AllowKycApiListUserDocumentsPrefix"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = [statement.value]
      }

      actions   = ["s3:ListBucket"]
      resources = [aws_s3_bucket.kyc_documents.arn]

      condition {
        test     = "StringLike"
        variable = "s3:prefix"
        values   = ["users/*"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.kyc_task_role_arn == null ? [] : [var.kyc_task_role_arn]

    content {
      sid    = "AllowKycApiReadWriteUserDocuments"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = [statement.value]
      }

      actions = [
        "s3:GetObject",
        "s3:PutObject"
      ]

      resources = ["${aws_s3_bucket.kyc_documents.arn}/users/*"]
    }
  }
}

resource "aws_s3_bucket_policy" "kyc_documents" {
  bucket = aws_s3_bucket.kyc_documents.id
  policy = data.aws_iam_policy_document.kyc_documents.json
}



data "aws_iam_policy_document" "replication_assume_role" {
  count = var.enable_replication ? 1 : 0

  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "replication" {
  count = var.enable_replication ? 1 : 0

  name               = "${var.project}-${var.environment}-kyc-documents-replication-role"
  assume_role_policy = data.aws_iam_policy_document.replication_assume_role[0].json

  tags = merge(local.common_tags, {
    Name    = "${var.project}-${var.environment}-kyc-documents-replication-role"
    Service = "s3-replication"
  })
}

data "aws_iam_policy_document" "replication" {
  count = var.enable_replication ? 1 : 0

  statement {
    sid    = "AllowSourceReplicationReads"
    effect = "Allow"

    actions = [
      "s3:GetObjectVersion",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionTagging",
      "s3:ListBucket"
    ]

    resources = [
      aws_s3_bucket.kyc_documents.arn,
      "${aws_s3_bucket.kyc_documents.arn}/*"
    ]
  }

  statement {
    sid    = "AllowDestinationReplicationWrites"
    effect = "Allow"

    actions = [
      "s3:ObjectOwnerOverrideToBucketOwner",
      "s3:ReplicateDelete",
      "s3:ReplicateObject",
      "s3:ReplicateTags"
    ]

    resources = ["${var.replication_destination_bucket_arn}/*"]
  }

  statement {
    sid    = "AllowReplicationKmsUse"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:ReEncryptFrom",
      "kms:ReEncryptTo"
    ]

    resources = [
      var.s3_kms_key_arn,
      var.replication_destination_kms_key_arn
    ]
  }
}

resource "aws_iam_role_policy" "replication" {
  count = var.enable_replication ? 1 : 0

  name   = "${var.project}-${var.environment}-kyc-documents-replication-policy"
  role   = aws_iam_role.replication[0].id
  policy = data.aws_iam_policy_document.replication[0].json
}

resource "aws_s3_bucket_replication_configuration" "kyc_documents" {
  count = var.enable_replication ? 1 : 0

  bucket = aws_s3_bucket.kyc_documents.id
  role   = aws_iam_role.replication[0].arn

  rule {
    id     = "replicate-kyc-documents"
    status = "Enabled"

    filter {
      prefix = ""
    }

    destination {
      bucket        = var.replication_destination_bucket_arn
      storage_class = "STANDARD"

      encryption_configuration {
        replica_kms_key_id = var.replication_destination_kms_key_arn
      }

      access_control_translation {
        owner = "Destination"
      }
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }
  }

  depends_on = [
    aws_iam_role_policy.replication,
    aws_s3_bucket_versioning.kyc_documents
  ]
}

output "kyc_bucket_name" {
  value = aws_s3_bucket.kyc_documents.bucket
}

output "kyc_bucket_arn" {
  value = aws_s3_bucket.kyc_documents.arn
}
