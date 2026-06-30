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

variable "secrets_kms_key_arn" {
  description = "Customer-managed KMS key ARN used to encrypt Secrets Manager secrets."
  type        = string
}

variable "payments_task_role_arn" {
  description = "Optional payments-api ECS task role ARN allowed to read its runtime secrets."
  type        = string
  default     = null
}

variable "kyc_task_role_arn" {
  description = "Optional kyc-api ECS task role ARN allowed to read its runtime secrets."
  type        = string
  default     = null
}

variable "recovery_window_in_days" {
  description = "Number of days Secrets Manager waits before deleting a secret. Use 7 for short labs, 30 for production."
  type        = number
  default     = 7

  validation {
    condition     = var.recovery_window_in_days >= 7 && var.recovery_window_in_days <= 30
    error_message = "recovery_window_in_days must be between 7 and 30."
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

locals {
  common_tags = {
    Project            = var.project
    Environment        = var.environment
    Service            = "secrets"
    Owner              = var.owner
    CostCenter         = var.cost_center
    ManagedBy          = "terraform"
    Repository         = var.repository
    DataClassification = var.data_classification
    Criticality        = var.criticality
  }

  secret_definitions = {
    jwt_secret = {
      name        = "/${var.project}/${var.environment}/shared/jwt-secret"
      description = "JWT signing secret used by services that validate application tokens. Populate outside Terraform."
      service     = "shared"
      readers     = compact([var.payments_task_role_arn, var.kyc_task_role_arn])
    }
    payments_session_secret = {
      name        = "/${var.project}/${var.environment}/payments-api/session-secret"
      description = "Flask session SECRET_KEY for payments-api. Populate outside Terraform."
      service     = "payments-api"
      readers     = compact([var.payments_task_role_arn])
    }
    database_credentials = {
      name        = "/${var.project}/${var.environment}/database/postgres-credentials"
      description = "PostgreSQL connection credentials or URL for application runtime. Prefer RDS-managed rotation where possible."
      service     = "database"
      readers     = compact([var.payments_task_role_arn, var.kyc_task_role_arn])
    }
    redis_auth_token = {
      name        = "/${var.project}/${var.environment}/redis/auth-token"
      description = "ElastiCache Redis AUTH token. Populate or rotate outside Terraform to avoid storing value in state."
      service     = "redis"
      readers     = compact([var.payments_task_role_arn, var.kyc_task_role_arn])
    }
    bvn_provider_credentials = {
      name        = "/${var.project}/${var.environment}/kyc-api/bvn-provider-credentials"
      description = "KYC provider credentials if the BVN provider requires authentication. Populate outside Terraform."
      service     = "kyc-api"
      readers     = compact([var.kyc_task_role_arn])
    }
    webhook_signing_secret = {
      name        = "/${var.project}/${var.environment}/payments-api/webhook-signing-secret"
      description = "Webhook signing or partner API secret for payments-api. Populate outside Terraform."
      service     = "payments-api"
      readers     = compact([var.payments_task_role_arn])
    }
  }

  secrets_with_reader_policies = {
    for key, definition in local.secret_definitions : key => definition
    if length(definition.readers) > 0
  }
}

resource "aws_secretsmanager_secret" "this" {
  for_each = local.secret_definitions

  name                    = each.value.name
  description             = each.value.description
  kms_key_id              = var.secrets_kms_key_arn
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(local.common_tags, {
    Name    = replace(trimprefix(each.value.name, "/"), "/", "-")
    Service = each.value.service
  })
}

data "aws_iam_policy_document" "readers" {
  for_each = local.secrets_with_reader_policies

  statement {
    sid    = "AllowDesignatedRuntimeRead"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = each.value.readers
    }

    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue"
    ]

    resources = [aws_secretsmanager_secret.this[each.key].arn]
  }
}

resource "aws_secretsmanager_secret_policy" "readers" {
  for_each = local.secrets_with_reader_policies

  secret_arn          = aws_secretsmanager_secret.this[each.key].arn
  policy              = data.aws_iam_policy_document.readers[each.key].json
  block_public_policy = true
}

output "secret_arns" {
  description = "Secret ARNs by logical name. Values are metadata only, not secret values."
  value       = { for name, secret in aws_secretsmanager_secret.this : name => secret.arn }
}

output "secret_names" {
  description = "Secret names by logical name."
  value       = { for name, secret in aws_secretsmanager_secret.this : name => secret.name }
}
