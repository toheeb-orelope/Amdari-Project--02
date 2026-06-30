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

variable "criticality" {
  type    = string
  default = "high"
}

variable "logs_kms_key_arn" {
  description = "Customer-managed KMS key ARN used for CloudTrail, CloudWatch Logs, and audit log bucket encryption."
  type        = string
}

variable "cloudtrail_object_lock_retention_days" {
  description = "Governance-mode Object Lock retention for CloudTrail log objects."
  type        = number
  default     = 1

  validation {
    condition     = var.cloudtrail_object_lock_retention_days >= 1
    error_message = "cloudtrail_object_lock_retention_days must be at least 1."
  }
}

variable "s3_access_log_retention_days" {
  description = "Retention period for S3 server access logs."
  type        = number
  default     = 365

  validation {
    condition     = var.s3_access_log_retention_days >= 1
    error_message = "s3_access_log_retention_days must be at least 1."
  }
}

variable "enable_organization_trail" {
  description = "Set true only when applying from the AWS Organizations management account."
  type        = bool
  default     = false
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  cloudtrail_name = "${var.project}-${var.environment}-cloudtrail"

  common_tags = {
    Project            = var.project
    Environment        = var.environment
    Service            = "logging"
    Owner              = var.owner
    CostCenter         = var.cost_center
    ManagedBy          = "terraform"
    Repository         = var.repository
    DataClassification = var.data_classification
    Criticality        = var.criticality
  }
}

resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket              = "${var.project}-${var.environment}-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}-cloudtrail-logs"
  object_lock_enabled = true
  force_destroy       = false

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-cloudtrail-logs"
  })
}

resource "aws_s3_bucket_ownership_controls" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    id     = "transition-cloudtrail-logs"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.logs_kms_key_arn
      sse_algorithm     = "aws:kms"
    }

    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_object_lock_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = var.cloudtrail_object_lock_retention_days
    }
  }
}

resource "aws_s3_bucket" "s3_access_logs" {
  bucket        = "${var.project}-${var.environment}-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}-s3-access-logs"
  force_destroy = false

  tags = merge(local.common_tags, {
    Name    = "${var.project}-${var.environment}-s3-access-logs"
    Purpose = "Centralized S3 server access logs"
  })
}

resource "aws_s3_bucket_ownership_controls" "s3_access_logs" {
  bucket = aws_s3_bucket.s3_access_logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "s3_access_logs" {
  bucket = aws_s3_bucket.s3_access_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "s3_access_logs" {
  bucket = aws_s3_bucket.s3_access_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "s3_access_logs" {
  bucket = aws_s3_bucket.s3_access_logs.id

  rule {
    id     = "expire-s3-access-logs"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    expiration {
      days = var.s3_access_log_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.s3_access_log_retention_days
    }
  }
}

# S3 server access log destination buckets must use SSE-S3, not SSE-KMS.
resource "aws_s3_bucket_server_side_encryption_configuration" "s3_access_logs" {
  bucket = aws_s3_bucket.s3_access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_logging" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  target_bucket = aws_s3_bucket.s3_access_logs.id
  target_prefix = "s3-access/cloudtrail/"

  depends_on = [aws_s3_bucket_policy.s3_access_logs]
}

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/${local.cloudtrail_name}"
  retention_in_days = 365
  kms_key_id        = var.logs_kms_key_arn

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-cloudtrail-log-group"
  })
}

data "aws_iam_policy_document" "cloudtrail_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "cloudtrail_cloudwatch" {
  name               = "${var.project}-${var.environment}-cloudtrail-cloudwatch-role"
  assume_role_policy = data.aws_iam_policy_document.cloudtrail_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-cloudtrail-cloudwatch-role"
  })
}

data "aws_iam_policy_document" "cloudtrail_cloudwatch" {
  statement {
    sid    = "AllowCloudTrailWriteToCloudWatchLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["${aws_cloudwatch_log_group.cloudtrail.arn}:*"]
  }
}

resource "aws_iam_role_policy" "cloudtrail_cloudwatch" {
  name   = "${var.project}-${var.environment}-cloudtrail-cloudwatch-policy"
  role   = aws_iam_role.cloudtrail_cloudwatch.id
  policy = data.aws_iam_policy_document.cloudtrail_cloudwatch.json
}

data "aws_iam_policy_document" "s3_access_logs" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.s3_access_logs.arn,
      "${aws_s3_bucket.s3_access_logs.arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid    = "AllowS3ServerAccessLogDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }

    actions = ["s3:PutObject"]

    resources = ["${aws_s3_bucket.s3_access_logs.arn}/s3-access/*"]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:s3:::${var.project}-${var.environment}-*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "AllowAlbAccessLogDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }

    actions = ["s3:PutObject"]

    resources = ["${aws_s3_bucket.s3_access_logs.arn}/alb/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:elasticloadbalancing:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:loadbalancer/app/${var.project}-${var.environment}-*/*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "s3_access_logs" {
  bucket = aws_s3_bucket.s3_access_logs.id
  policy = data.aws_iam_policy_document.s3_access_logs.json
}

data "aws_iam_policy_document" "cloudtrail_bucket" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.cloudtrail_logs.arn,
      "${aws_s3_bucket.cloudtrail_logs.arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail_logs.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudtrail:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:trail/${local.cloudtrail_name}"]
    }
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions = ["s3:PutObject"]

    resources = [
      "${aws_s3_bucket.cloudtrail_logs.arn}/cloudtrail/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudtrail:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:trail/${local.cloudtrail_name}"]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  policy = data.aws_iam_policy_document.cloudtrail_bucket.json
}

resource "aws_cloudtrail" "main" {
  depends_on = [
    aws_s3_bucket_policy.cloudtrail_logs,
    aws_s3_bucket_object_lock_configuration.cloudtrail_logs,
    aws_iam_role_policy.cloudtrail_cloudwatch
  ]

  name                          = local.cloudtrail_name
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
  s3_key_prefix                 = "cloudtrail"
  include_global_service_events = true
  is_multi_region_trail         = true
  is_organization_trail         = var.enable_organization_trail
  enable_log_file_validation    = true
  enable_logging                = true
  kms_key_id                    = var.logs_kms_key_arn
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_cloudwatch.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  insight_selector {
    insight_type = "ApiCallRateInsight"
  }

  insight_selector {
    insight_type = "ApiErrorRateInsight"
  }

  tags = merge(local.common_tags, {
    Name = local.cloudtrail_name
  })
}

output "cloudtrail_name" {
  value = aws_cloudtrail.main.name
}

output "cloudtrail_arn" {
  value = aws_cloudtrail.main.arn
}

output "cloudtrail_log_bucket_name" {
  value = aws_s3_bucket.cloudtrail_logs.bucket
}

output "s3_access_log_bucket_name" {
  value = aws_s3_bucket.s3_access_logs.bucket
}

output "cloudtrail_log_group_name" {
  value = aws_cloudwatch_log_group.cloudtrail.name
}
