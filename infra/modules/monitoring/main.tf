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

variable "alert_email_endpoints" {
  description = "Email addresses subscribed to operational/security alerts. Confirm subscriptions after apply."
  type        = list(string)
  default     = []
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix for CloudWatch metrics, e.g. app/name/id."
  type        = string
  default     = null
}

variable "ecs_cluster_name" {
  type    = string
  default = null
}

variable "payments_service_name" {
  type    = string
  default = null
}

variable "kyc_service_name" {
  type    = string
  default = null
}

variable "rds_instance_id" {
  type    = string
  default = null
}

variable "redis_replication_group_id" {
  type    = string
  default = null
}

variable "guardduty_containment_lambda_function_name" {
  type    = string
  default = null
}

variable "waf_web_acl_name" {
  type    = string
  default = null
}

variable "waf_web_acl_scope" {
  type    = string
  default = "REGIONAL"
}

variable "alb_5xx_threshold" {
  type    = number
  default = 10
}

variable "ecs_cpu_threshold" {
  type    = number
  default = 80
}

variable "rds_cpu_threshold" {
  type    = number
  default = 80
}

variable "lambda_error_threshold" {
  type    = number
  default = 1
}

variable "custom_log_metric_filters" {
  description = "Optional CloudWatch Logs metric filters keyed by name."
  type = map(object({
    log_group_name = string
    pattern        = string
    namespace      = string
    metric_name    = string
    metric_value   = optional(string, "1")
  }))
  default = {}
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
  default = "internal"
}

variable "criticality" {
  type    = string
  default = "high"
}

data "aws_region" "current" {}

locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = {
    Project            = var.project
    Environment        = var.environment
    Service            = "monitoring"
    Owner              = var.owner
    CostCenter         = var.cost_center
    ManagedBy          = "terraform"
    Repository         = var.repository
    DataClassification = var.data_classification
    Criticality        = var.criticality
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  dashboard_widgets = concat(
    [{
      type   = "text"
      x      = 0
      y      = 0
      width  = 24
      height = 2
      properties = {
        markdown = "# ${local.name_prefix} operational and security dashboard\nALB, ECS, RDS, Redis, Lambda, and WAF signals."
      }
    }],
    var.alb_arn_suffix == null ? [] : [{
      type   = "metric"
      x      = 0
      y      = 2
      width  = 12
      height = 6
      properties = {
        title   = "ALB 5XX responses"
        region  = data.aws_region.current.region
        period  = 300
        stat    = "Sum"
        metrics = [["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", var.alb_arn_suffix]]
      }
    }],
    var.ecs_cluster_name == null || var.payments_service_name == null ? [] : [{
      type   = "metric"
      x      = 12
      y      = 2
      width  = 6
      height = 6
      properties = {
        title   = "payments-api ECS CPU"
        region  = data.aws_region.current.region
        period  = 300
        stat    = "Average"
        metrics = [["AWS/ECS", "CPUUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.payments_service_name]]
      }
    }],
    var.ecs_cluster_name == null || var.kyc_service_name == null ? [] : [{
      type   = "metric"
      x      = 18
      y      = 2
      width  = 6
      height = 6
      properties = {
        title   = "kyc-api ECS CPU"
        region  = data.aws_region.current.region
        period  = 300
        stat    = "Average"
        metrics = [["AWS/ECS", "CPUUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.kyc_service_name]]
      }
    }],
    var.rds_instance_id == null ? [] : [{
      type   = "metric"
      x      = 0
      y      = 8
      width  = 8
      height = 6
      properties = {
        title   = "RDS CPU"
        region  = data.aws_region.current.region
        period  = 300
        stat    = "Average"
        metrics = [["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.rds_instance_id]]
      }
    }],
    var.redis_replication_group_id == null ? [] : [{
      type   = "metric"
      x      = 8
      y      = 8
      width  = 8
      height = 6
      properties = {
        title   = "Redis CPU"
        region  = data.aws_region.current.region
        period  = 300
        stat    = "Average"
        metrics = [["AWS/ElastiCache", "CPUUtilization", "ReplicationGroupId", var.redis_replication_group_id]]
      }
    }],
    var.guardduty_containment_lambda_function_name == null ? [] : [{
      type   = "metric"
      x      = 16
      y      = 8
      width  = 8
      height = 6
      properties = {
        title   = "Containment Lambda errors"
        region  = data.aws_region.current.region
        period  = 300
        stat    = "Sum"
        metrics = [["AWS/Lambda", "Errors", "FunctionName", var.guardduty_containment_lambda_function_name]]
      }
    }]
  )
}

resource "aws_sns_topic" "alerts" {
  name              = "${local.name_prefix}-alerts"
  kms_master_key_id = "alias/aws/sns"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alerts"
  })
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.alert_email_endpoints)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  count = var.alb_arn_suffix == null ? 0 : 1

  alarm_name          = "${local.name_prefix}-alb-5xx-high"
  alarm_description   = "ALB generated elevated 5XX responses."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.alb_5xx_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "payments_cpu" {
  count = var.ecs_cluster_name == null || var.payments_service_name == null ? 0 : 1

  alarm_name          = "${local.name_prefix}-payments-cpu-high"
  alarm_description   = "payments-api ECS service CPU is high."
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.ecs_cpu_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.payments_service_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "kyc_cpu" {
  count = var.ecs_cluster_name == null || var.kyc_service_name == null ? 0 : 1

  alarm_name          = "${local.name_prefix}-kyc-cpu-high"
  alarm_description   = "kyc-api ECS service CPU is high."
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.ecs_cpu_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.kyc_service_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  count = var.rds_instance_id == null ? 0 : 1

  alarm_name          = "${local.name_prefix}-rds-cpu-high"
  alarm_description   = "RDS CPU utilization is high."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.rds_cpu_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = var.guardduty_containment_lambda_function_name == null ? 0 : 1

  alarm_name          = "${local.name_prefix}-guardduty-containment-lambda-errors"
  alarm_description   = "GuardDuty containment Lambda has errors."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.lambda_error_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  dimensions = {
    FunctionName = var.guardduty_containment_lambda_function_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_log_metric_filter" "custom" {
  for_each = var.custom_log_metric_filters

  name           = "${local.name_prefix}-${each.key}"
  log_group_name = each.value.log_group_name
  pattern        = each.value.pattern

  metric_transformation {
    name      = each.value.metric_name
    namespace = each.value.namespace
    value     = each.value.metric_value
  }
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.name_prefix}-dashboard"

  dashboard_body = jsonencode({
    widgets = local.dashboard_widgets
  })
}

output "alerts_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "dashboard_arn" {
  value = aws_cloudwatch_dashboard.main.dashboard_arn
}

output "dashboard_name" {
  value = aws_cloudwatch_dashboard.main.dashboard_name
}