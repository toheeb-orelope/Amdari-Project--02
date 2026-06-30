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
  description = "Customer-managed KMS key ARN for the decoy Secrets Manager secret metadata."
  type        = string
}

variable "honeytoken_access_key_id" {
  description = "Externally-created honeytoken access key ID to alarm on. Do not create the secret access key in Terraform."
  type        = string
  default     = null
}

variable "alert_email_endpoints" {
  description = "Email addresses subscribed to honeytoken-use alerts. Confirm subscriptions after apply."
  type        = list(string)
  default     = []
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

data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = {
    Project            = var.project
    Environment        = var.environment
    Service            = "honeytoken"
    Owner              = var.owner
    CostCenter         = var.cost_center
    ManagedBy          = "terraform"
    Repository         = var.repository
    DataClassification = var.data_classification
    Criticality        = var.criticality
  }
}

resource "aws_iam_user" "decoy" {
  name          = "${local.name_prefix}-decoy-ci-user"
  force_destroy = false

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-decoy-ci-user"
  })
}

data "aws_iam_policy_document" "decoy_deny_all" {
  statement {
    sid    = "DenyAllHoneytokenUserActions"
    effect = "Deny"

    actions   = ["*"]
    resources = ["*"]
  }
}

resource "aws_iam_user_policy" "decoy_deny_all" {
  name   = "${local.name_prefix}-decoy-deny-all"
  user   = aws_iam_user.decoy.name
  policy = data.aws_iam_policy_document.decoy_deny_all.json
}

resource "aws_secretsmanager_secret" "decoy_location" {
  name                    = "/${var.project}/${var.environment}/decoy/ci-credentials"
  description             = "Decoy honeytoken credential location. Populate manually outside Terraform to avoid storing access key secrets in state."
  kms_key_id              = var.secrets_kms_key_arn
  recovery_window_in_days = 7

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-decoy-ci-credentials"
  })
}

resource "aws_sns_topic" "alerts" {
  name              = "${local.name_prefix}-honeytoken-alerts"
  kms_master_key_id = "alias/aws/sns"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-honeytoken-alerts"
  })
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.alert_email_endpoints)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_cloudwatch_event_rule" "honeytoken_used" {
  count = var.honeytoken_access_key_id == null ? 0 : 1

  name        = "${local.name_prefix}-honeytoken-used"
  description = "Alarm when the decoy honeytoken access key is used."
  state       = "ENABLED"

  event_pattern = jsonencode({
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      userIdentity = {
        accessKeyId = [var.honeytoken_access_key_id]
      }
    }
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-honeytoken-used"
  })
}

data "aws_iam_policy_document" "alerts_topic" {
  statement {
    sid    = "AllowEventBridgeHoneytokenAlertPublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.alerts.arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = var.honeytoken_access_key_id == null ? [] : [aws_cloudwatch_event_rule.honeytoken_used[0].arn]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  count = var.honeytoken_access_key_id == null ? 0 : 1

  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts_topic.json
}

resource "aws_cloudwatch_event_target" "honeytoken_alerts" {
  count = var.honeytoken_access_key_id == null ? 0 : 1

  rule      = aws_cloudwatch_event_rule.honeytoken_used[0].name
  target_id = "HoneytokenAlerts"
  arn       = aws_sns_topic.alerts.arn

  depends_on = [aws_sns_topic_policy.alerts]
}

output "decoy_iam_user_name" {
  value = aws_iam_user.decoy.name
}

output "decoy_secret_name" {
  value = aws_secretsmanager_secret.decoy_location.name
}

output "decoy_secret_arn" {
  description = "Secrets Manager ARN for the decoy honeytoken location. Populate the value outside Terraform."
  value       = aws_secretsmanager_secret.decoy_location.arn
}

output "honeytoken_alert_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "honeytoken_event_rule_arn" {
  value = var.honeytoken_access_key_id == null ? null : aws_cloudwatch_event_rule.honeytoken_used[0].arn
}