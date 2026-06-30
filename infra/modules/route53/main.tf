terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.52"
      configuration_aliases = [aws.us_east_1]
    }
  }
}

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

variable "domain_name" {
  description = "Public hosted zone domain name, for example example.com. Do not include a trailing dot."
  type        = string
}

variable "record_names" {
  description = "DNS names to alias to the ALB. Use the zone apex and/or service names like api.example.com."
  type        = list(string)

  validation {
    condition     = length(var.record_names) >= 1
    error_message = "record_names must include at least one DNS record."
  }
}

variable "alb_dns_name" {
  description = "ALB DNS name from the ALB module."
  type        = string
}

variable "alb_zone_id" {
  description = "ALB hosted zone ID from the ALB module."
  type        = string
}

variable "force_destroy_zone" {
  description = "Whether to destroy all records when destroying the hosted zone. Keep false for production."
  type        = bool
  default     = false
}

variable "enable_dnssec" {
  description = "Enable DNSSEC signing for the public hosted zone. Required by the assignment when introducing Route 53 hosted zones."
  type        = bool
  default     = true
}

variable "dnssec_key_deletion_window_in_days" {
  description = "KMS deletion window for the Route 53 DNSSEC signing key."
  type        = number
  default     = 7

  validation {
    condition     = var.dnssec_key_deletion_window_in_days >= 7 && var.dnssec_key_deletion_window_in_days <= 30
    error_message = "dnssec_key_deletion_window_in_days must be between 7 and 30."
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
  default = "public"
}

variable "enable_query_logging" {
  description = "Enable Route 53 public hosted zone query logging."
  type        = bool
  default     = false
}

variable "query_log_retention_in_days" {
  description = "Retention period for Route 53 query logs."
  type        = number
  default     = 365
}

variable "query_log_kms_key_arn" {
  description = "Optional us-east-1 KMS key ARN for Route 53 query log group encryption."
  type        = string
  default     = null
}

variable "criticality" {
  type    = string
  default = "high"
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  name_prefix = "${var.project}-${var.environment}"
  zone_name   = trimsuffix(var.domain_name, ".")

  normalized_record_names = toset([
    for record_name in var.record_names : trimsuffix(record_name, ".")
  ])

  common_tags = {
    Project            = var.project
    Environment        = var.environment
    Service            = "route53"
    Owner              = var.owner
    CostCenter         = var.cost_center
    ManagedBy          = "terraform"
    Repository         = var.repository
    DataClassification = var.data_classification
    Criticality        = var.criticality
  }
}

resource "aws_route53_zone" "public" {
  name          = local.zone_name
  comment       = "Public hosted zone for ${local.name_prefix}."
  force_destroy = var.force_destroy_zone

  tags = merge(local.common_tags, {
    Name = local.zone_name
  })
}

data "aws_iam_policy_document" "dnssec_kms" {
  statement {
    sid    = "AllowRoute53DnssecServiceUse"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["dnssec-route53.amazonaws.com"]
    }

    actions = [
      "kms:DescribeKey",
      "kms:GetPublicKey",
      "kms:Sign",
      "kms:Verify"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowAccountKeyAdministrationViaIam"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions = [
      "kms:CancelKeyDeletion",
      "kms:DescribeKey",
      "kms:DisableKey",
      "kms:EnableKey",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:GetPublicKey",
      "kms:ListResourceTags",
      "kms:PutKeyPolicy",
      "kms:ScheduleKeyDeletion",
      "kms:Sign",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:UpdateKeyDescription",
      "kms:Verify"
    ]

    resources = ["*"]
  }
}

resource "aws_kms_key" "dnssec" {
  #checkov:skip=CKV_AWS_109:KMS key policies require Resource "*" because the policy is attached to the key itself; principals and actions are scoped.
  #checkov:skip=CKV_AWS_111:KMS key policies require Resource "*" because the policy is attached to the key itself; principals and actions are scoped.
  provider = aws.us_east_1
  count    = var.enable_dnssec ? 1 : 0

  description              = "Route 53 DNSSEC signing key for ${local.zone_name}."
  customer_master_key_spec = "ECC_NIST_P256"
  key_usage                = "SIGN_VERIFY"
  deletion_window_in_days  = var.dnssec_key_deletion_window_in_days
  policy                   = data.aws_iam_policy_document.dnssec_kms.json

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-route53-dnssec"
    Service = "route53-dnssec"
  })
}

resource "aws_kms_alias" "dnssec" {
  provider = aws.us_east_1
  count    = var.enable_dnssec ? 1 : 0

  name          = "alias/${local.name_prefix}-route53-dnssec"
  target_key_id = aws_kms_key.dnssec[0].key_id
}

resource "aws_route53_key_signing_key" "public" {
  count = var.enable_dnssec ? 1 : 0

  hosted_zone_id             = aws_route53_zone.public.zone_id
  key_management_service_arn = aws_kms_key.dnssec[0].arn
  name                       = replace("${var.project}-${var.environment}-ksk", "-", "_")
}

resource "aws_route53_hosted_zone_dnssec" "public" {
  count = var.enable_dnssec ? 1 : 0

  hosted_zone_id = aws_route53_zone.public.zone_id
  signing_status = "SIGNING"

  depends_on = [aws_route53_key_signing_key.public]
}

resource "aws_route53_record" "a_alias" {
  for_each = local.normalized_record_names

  zone_id = aws_route53_zone.public.zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "aaaa_alias" {
  for_each = local.normalized_record_names

  zone_id = aws_route53_zone.public.zone_id
  name    = each.value
  type    = "AAAA"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}





data "aws_iam_policy_document" "query_logs_kms" {
  count = var.enable_query_logging && var.query_log_kms_key_arn == null ? 1 : 0

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
      "kms:DescribeKey",
      "kms:DisableKey",
      "kms:EnableKey",
      "kms:EnableKeyRotation",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:ListResourceTags",
      "kms:PutKeyPolicy",
      "kms:ScheduleKeyDeletion",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:UpdateKeyDescription"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogsUse"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logs.us-east-1.amazonaws.com"]
    }

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:ReEncryptFrom",
      "kms:ReEncryptTo"
    ]

    resources = ["*"]
  }
}

resource "aws_kms_key" "query_logs" {
  provider = aws.us_east_1
  count    = var.enable_query_logging && var.query_log_kms_key_arn == null ? 1 : 0

  description             = "Route 53 query log encryption key for ${local.zone_name}."
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.query_logs_kms[0].json

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-route53-query-logs-kms"
    Service = "route53-query-logs"
  })
}

resource "aws_kms_alias" "query_logs" {
  provider = aws.us_east_1
  count    = var.enable_query_logging && var.query_log_kms_key_arn == null ? 1 : 0

  name          = "alias/${local.name_prefix}-route53-query-logs"
  target_key_id = aws_kms_key.query_logs[0].key_id
}

resource "aws_cloudwatch_log_group" "route53_query_logs" {
  provider = aws.us_east_1
  count    = var.enable_query_logging ? 1 : 0

  name              = "/aws/route53/${local.zone_name}"
  retention_in_days = var.query_log_retention_in_days
  kms_key_id        = var.query_log_kms_key_arn == null ? aws_kms_key.query_logs[0].arn : var.query_log_kms_key_arn

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-route53-query-logs"
    Service = "route53-query-logs"
  })
}

data "aws_iam_policy_document" "route53_query_logs" {
  count = var.enable_query_logging ? 1 : 0

  statement {
    sid    = "AllowRoute53QueryLogDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["route53.amazonaws.com"]
    }

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["${aws_cloudwatch_log_group.route53_query_logs[0].arn}:*"]
  }
}

resource "aws_cloudwatch_log_resource_policy" "route53_query_logs" {
  provider = aws.us_east_1
  count    = var.enable_query_logging ? 1 : 0

  policy_name     = "${local.name_prefix}-route53-query-logs"
  policy_document = data.aws_iam_policy_document.route53_query_logs[0].json
}

resource "aws_route53_query_log" "public" {
  count = var.enable_query_logging ? 1 : 0

  cloudwatch_log_group_arn = aws_cloudwatch_log_group.route53_query_logs[0].arn
  zone_id                  = aws_route53_zone.public.zone_id

  depends_on = [aws_cloudwatch_log_resource_policy.route53_query_logs]
}

output "zone_id" {
  value = aws_route53_zone.public.zone_id
}

output "zone_arn" {
  value = aws_route53_zone.public.arn
}

output "name_servers" {
  value = aws_route53_zone.public.name_servers
}

output "record_fqdns" {
  value = sort([for record in aws_route53_record.a_alias : record.fqdn])
}

output "dnssec_enabled" {
  value = var.enable_dnssec
}

output "dnssec_ds_record" {
  value = var.enable_dnssec ? aws_route53_key_signing_key.public[0].ds_record : null
}

output "dnssec_key_signing_key_id" {
  value = var.enable_dnssec ? aws_route53_key_signing_key.public[0].id : null
}


