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

variable "deletion_window_in_days" {
  description = "KMS key deletion window. Minimum is 7 days."
  type        = number
  default     = 7

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be between 7 and 30."
  }
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  common_tags = {
    Project            = var.project
    Environment        = var.environment
    Service            = "kms"
    Owner              = var.owner
    CostCenter         = var.cost_center
    ManagedBy          = "terraform"
    Repository         = var.repository
    DataClassification = var.data_classification
    Criticality        = var.criticality
  }

  key_purposes = {
    logs = {
      description = "Encrypt CloudTrail, Config, VPC Flow Logs, CloudWatch Logs, and security log storage for ${var.project}-${var.environment}."
      service     = "logging"
    }
    secrets = {
      description = "Encrypt Secrets Manager runtime secrets for ${var.project}-${var.environment}."
      service     = "secrets"
    }
    s3 = {
      description = "Encrypt KYC document and application S3 buckets for ${var.project}-${var.environment}."
      service     = "s3"
    }
    rds = {
      description = "Encrypt RDS PostgreSQL storage for ${var.project}-${var.environment}."
      service     = "rds"
    }
    redis = {
      description = "Encrypt ElastiCache Redis at rest for ${var.project}-${var.environment}."
      service     = "redis"
    }
    ecs = {
      description = "Encrypt ECS application logs and task-related storage for ${var.project}-${var.environment}."
      service     = "ecs"
    }
  }
}

resource "aws_kms_key" "this" {
  for_each = local.key_purposes

  description             = each.value.description
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = true

  tags = merge(local.common_tags, {
    Name    = "${var.project}-${var.environment}-${each.key}-kms-key"
    Service = each.value.service
  })
}

data "aws_iam_policy_document" "key_policy" {
  for_each = local.key_purposes

  statement {
    sid    = "AllowAccountKeyAdministration"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions = [
      "kms:CancelKeyDeletion",
      "kms:CreateAlias",
      "kms:CreateGrant",
      "kms:DeleteAlias",
      "kms:DescribeKey",
      "kms:DisableKey",
      "kms:EnableKey",
      "kms:EnableKeyRotation",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:ListGrants",
      "kms:ListKeyPolicies",
      "kms:ListResourceTags",
      "kms:PutKeyPolicy",
      "kms:RevokeGrant",
      "kms:ScheduleKeyDeletion",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:UpdateAlias",
      "kms:UpdateKeyDescription"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowAccountPrincipalsServiceUse"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:GenerateDataKeyWithoutPlaintext",
      "kms:ReEncryptFrom",
      "kms:ReEncryptTo"
    ]

    resources = ["*"]

    condition {
      test     = "StringLike"
      variable = "kms:ViaService"
      values = [
        "cloudtrail.${data.aws_region.current.region}.amazonaws.com",
        "logs.${data.aws_region.current.region}.amazonaws.com",
        "s3.${data.aws_region.current.region}.amazonaws.com",
        "secretsmanager.${data.aws_region.current.region}.amazonaws.com",
        "rds.${data.aws_region.current.region}.amazonaws.com",
        "elasticache.${data.aws_region.current.region}.amazonaws.com",
        "ecs.${data.aws_region.current.region}.amazonaws.com"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "AllowAwsServicesDirectUse"
    effect = "Allow"

    principals {
      type = "Service"
      identifiers = [
        "cloudtrail.amazonaws.com",
        "config.amazonaws.com",
        "delivery.logs.amazonaws.com",
        "logs.${data.aws_region.current.region}.amazonaws.com",
        "s3.amazonaws.com",
        "secretsmanager.amazonaws.com",
        "rds.amazonaws.com",
        "elasticache.amazonaws.com"
      ]
    }

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:GenerateDataKeyWithoutPlaintext",
      "kms:ReEncryptFrom",
      "kms:ReEncryptTo"
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_kms_key_policy" "this" {
  for_each = aws_kms_key.this

  key_id = each.value.id
  policy = data.aws_iam_policy_document.key_policy[each.key].json
}

resource "aws_kms_alias" "this" {
  for_each = aws_kms_key.this

  name          = "alias/${var.project}-${var.environment}-${each.key}"
  target_key_id = each.value.key_id
}

output "key_ids" {
  description = "KMS key IDs by purpose."
  value       = { for purpose, key in aws_kms_key.this : purpose => key.key_id }
  depends_on  = [aws_kms_key_policy.this]
}

output "key_arns" {
  description = "KMS key ARNs by purpose."
  value       = { for purpose, key in aws_kms_key.this : purpose => key.arn }
  depends_on  = [aws_kms_key_policy.this]
}

output "alias_names" {
  description = "KMS alias names by purpose."
  value       = { for purpose, alias in aws_kms_alias.this : purpose => alias.name }
}

