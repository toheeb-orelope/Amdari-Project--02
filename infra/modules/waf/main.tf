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

variable "alb_arn" {
  description = "Application Load Balancer ARN to associate with the regional WAF Web ACL."
  type        = string
}

variable "logs_kms_key_arn" {
  description = "Customer-managed KMS key ARN used to encrypt WAF CloudWatch logs."
  type        = string
}

variable "payments_rate_limit" {
  description = "Maximum requests per IP in a 5-minute window for payments endpoints. Adjust based on real traffic."
  type        = number
  default     = 1000

  validation {
    condition     = var.payments_rate_limit >= 100
    error_message = "payments_rate_limit must be at least 100."
  }
}

variable "blocked_country_codes" {
  description = "Optional ISO country codes to block. Empty by default to avoid accidental user lockout."
  type        = list(string)
  default     = []
}

variable "log_retention_in_days" {
  type    = number
  default = 90
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
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = {
    Project            = var.project
    Environment        = var.environment
    Service            = "waf"
    Owner              = var.owner
    CostCenter         = var.cost_center
    ManagedBy          = "terraform"
    Repository         = var.repository
    DataClassification = var.data_classification
    Criticality        = var.criticality
  }

  waf_name = "${local.name_prefix}-web-acl"
}

resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-${local.name_prefix}-alb"
  retention_in_days = var.log_retention_in_days
  kms_key_id        = var.logs_kms_key_arn

  tags = merge(local.common_tags, {
    Name = "aws-waf-logs-${local.name_prefix}-alb"
  })
}

data "aws_iam_policy_document" "waf_logs" {
  statement {
    sid    = "AllowWafLogDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["${aws_cloudwatch_log_group.waf.arn}:*"]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "waf" {
  policy_name     = "${local.name_prefix}-waf-log-delivery-policy"
  policy_document = data.aws_iam_policy_document.waf_logs.json
}

resource "aws_wafv2_web_acl" "main" {
  name        = local.waf_name
  description = "Regional WAF Web ACL for ${local.name_prefix} ALB."
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "PaymentsEndpointRateLimit"
    priority = 0

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.payments_rate_limit
        aggregate_key_type = "IP"

        scope_down_statement {
          or_statement {
            statement {
              byte_match_statement {
                search_string = "/v1/auth"

                field_to_match {
                  uri_path {}
                }

                text_transformation {
                  priority = 0
                  type     = "NONE"
                }

                positional_constraint = "STARTS_WITH"
              }
            }

            statement {
              byte_match_statement {
                search_string = "/v1/accounts"

                field_to_match {
                  uri_path {}
                }

                text_transformation {
                  priority = 0
                  type     = "NONE"
                }

                positional_constraint = "STARTS_WITH"
              }
            }

            statement {
              byte_match_statement {
                search_string = "/v1/transactions"

                field_to_match {
                  uri_path {}
                }

                text_transformation {
                  priority = 0
                  type     = "NONE"
                }

                positional_constraint = "STARTS_WITH"
              }
            }

            statement {
              byte_match_statement {
                search_string = "/v1/wallets"

                field_to_match {
                  uri_path {}
                }

                text_transformation {
                  priority = 0
                  type     = "NONE"
                }

                positional_constraint = "STARTS_WITH"
              }
            }

            statement {
              byte_match_statement {
                search_string = "/v1/webhooks"

                field_to_match {
                  uri_path {}
                }

                text_transformation {
                  priority = 0
                  type     = "NONE"
                }

                positional_constraint = "STARTS_WITH"
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project}-${var.environment}-payments-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  dynamic "rule" {
    for_each = length(var.blocked_country_codes) == 0 ? [] : [1]

    content {
      name     = "BlockConfiguredCountries"
      priority = 5

      action {
        block {}
      }

      statement {
        geo_match_statement {
          country_codes = var.blocked_country_codes
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.project}-${var.environment}-geo-block"
        sampled_requests_enabled   = true
      }
    }
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project}-${var.environment}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project}-${var.environment}-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 30

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project}-${var.environment}-sqli-rules"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 40

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project}-${var.environment}-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project}-${var.environment}-web-acl"
    sampled_requests_enabled   = true
  }

  tags = merge(local.common_tags, {
    Name = local.waf_name
  })
}

resource "aws_wafv2_web_acl_logging_configuration" "main" {
  resource_arn            = aws_wafv2_web_acl.main.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]

  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  redacted_fields {
    single_header {
      name = "cookie"
    }
  }

  redacted_fields {
    query_string {}
  }

  logging_filter {
    default_behavior = "KEEP"

    filter {
      behavior    = "DROP"
      requirement = "MEETS_ANY"

      condition {
        action_condition {
          action = "ALLOW"
        }
      }
    }
  }

  depends_on = [aws_cloudwatch_log_resource_policy.waf]
}

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}

output "web_acl_arn" {
  value = aws_wafv2_web_acl.main.arn
}

output "web_acl_id" {
  value = aws_wafv2_web_acl.main.id
}

output "web_acl_capacity" {
  value = aws_wafv2_web_acl.main.capacity
}

output "waf_log_group_name" {
  value = aws_cloudwatch_log_group.waf.name
}

output "waf_log_group_arn" {
  value = aws_cloudwatch_log_group.waf.arn
}