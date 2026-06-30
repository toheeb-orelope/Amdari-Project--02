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

variable "logs_kms_key_arn" {
  description = "Customer-managed KMS key ARN used to encrypt detection logs and AWS Config delivery objects."
  type        = string
}

variable "config_retention_period_in_days" {
  description = "Number of days AWS Config stores historical configuration information."
  type        = number
  default     = 90

  validation {
    condition     = var.config_retention_period_in_days >= 30 && var.config_retention_period_in_days <= 2557
    error_message = "config_retention_period_in_days must be between 30 and 2557."
  }
}

variable "config_include_global_resource_types" {
  description = "Record supported global resources for CIS checks. Set false only if the selected region does not support global resource recording."
  type        = bool
  default     = true
}

variable "guardduty_containment_lambda_arn" {
  description = "Optional Lambda ARN invoked by EventBridge for high-severity GuardDuty findings. Pass null until the containment Lambda exists."
  type        = string
  default     = null
}

variable "guardduty_containment_lambda_function_name" {
  description = "Optional Lambda function name or ARN used by aws_lambda_permission for EventBridge invocation. Pass null until the containment Lambda exists."
  type        = string
  default     = null
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
    Service            = "detection"
    Owner              = var.owner
    CostCenter         = var.cost_center
    ManagedBy          = "terraform"
    Repository         = var.repository
    DataClassification = var.data_classification
    Criticality        = var.criticality
  }

  securityhub_standards = {
    aws_foundational_security_best_practices = "arn:${data.aws_partition.current.partition}:securityhub:${data.aws_region.current.region}::standards/aws-foundational-security-best-practices/v/1.0.0"
    cis_aws_foundations_benchmark            = "arn:${data.aws_partition.current.partition}:securityhub:${data.aws_region.current.region}::standards/cis-aws-foundations-benchmark/v/3.0.0"
  }

  guardduty_features = {
    s3_data_events = {
      name = "S3_DATA_EVENTS"
    }
    rds_login_events = {
      name = "RDS_LOGIN_EVENTS"
    }
    lambda_network_logs = {
      name = "LAMBDA_NETWORK_LOGS"
    }
    ebs_malware_protection = {
      name = "EBS_MALWARE_PROTECTION"
    }
  }

  config_bucket_name = "${var.project}-${var.environment}-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}-config-logs"

  enable_guardduty_containment_lambda = var.guardduty_containment_lambda_arn != null && var.guardduty_containment_lambda_function_name != null
}

resource "aws_s3_bucket" "config_logs" {
  bucket        = local.config_bucket_name
  force_destroy = false

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-config-logs"
    Service = "aws-config"
  })
}

resource "aws_s3_bucket_ownership_controls" "config_logs" {
  bucket = aws_s3_bucket.config_logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "config_logs" {
  bucket = aws_s3_bucket.config_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "config_logs" {
  bucket = aws_s3_bucket.config_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config_logs" {
  bucket = aws_s3_bucket.config_logs.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.logs_kms_key_arn
      sse_algorithm     = "aws:kms"
    }

    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "config_logs" {
  bucket = aws_s3_bucket.config_logs.id

  rule {
    id     = "retain-config-history"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    expiration {
      days = var.config_retention_period_in_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.config_retention_period_in_days
    }
  }
}

data "aws_iam_policy_document" "config_bucket" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.config_logs.arn,
      "${aws_s3_bucket.config_logs.arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid    = "AWSConfigBucketPermissionsCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    actions = [
      "s3:GetBucketAcl",
      "s3:ListBucket"
    ]

    resources = [aws_s3_bucket.config_logs.arn]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "AWSConfigBucketDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    actions = ["s3:PutObject"]

    resources = ["${aws_s3_bucket.config_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "config_logs" {
  bucket = aws_s3_bucket.config_logs.id
  policy = data.aws_iam_policy_document.config_bucket.json
}

data "aws_iam_policy_document" "config_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "config" {
  name               = "${local.name_prefix}-aws-config-role"
  assume_role_policy = data.aws_iam_policy_document.config_assume_role.json

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-aws-config-role"
    Service = "aws-config"
  })
}

resource "aws_iam_role_policy_attachment" "config_managed" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWS_ConfigRole"
}

data "aws_iam_policy_document" "config_delivery" {
  statement {
    sid    = "AllowConfigDeliveryBucketAccess"
    effect = "Allow"

    actions = [
      "s3:GetBucketAcl",
      "s3:ListBucket"
    ]

    resources = [aws_s3_bucket.config_logs.arn]
  }

  statement {
    sid    = "AllowConfigDeliveryObjectWrites"
    effect = "Allow"

    actions = ["s3:PutObject"]

    resources = ["${aws_s3_bucket.config_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"]
  }

  statement {
    sid    = "AllowConfigDeliveryKmsUse"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey"
    ]

    resources = [var.logs_kms_key_arn]
  }
}

resource "aws_iam_role_policy" "config_delivery" {
  name   = "${local.name_prefix}-aws-config-delivery-policy"
  role   = aws_iam_role.config.id
  policy = data.aws_iam_policy_document.config_delivery.json
}

resource "aws_config_configuration_recorder" "main" {
  name     = "${local.name_prefix}-config-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = var.config_include_global_resource_types
  }

  recording_mode {
    recording_frequency = "CONTINUOUS"
  }

  depends_on = [
    aws_iam_role_policy_attachment.config_managed,
    aws_iam_role_policy.config_delivery
  ]
}

resource "aws_config_delivery_channel" "main" {
  name           = "${local.name_prefix}-config-delivery-channel"
  s3_bucket_name = aws_s3_bucket.config_logs.bucket
  s3_key_prefix  = "AWSLogs/${data.aws_caller_identity.current.account_id}/Config"
  s3_kms_key_arn = var.logs_kms_key_arn

  snapshot_delivery_properties {
    delivery_frequency = "TwentyFour_Hours"
  }

  depends_on = [
    aws_config_configuration_recorder.main,
    aws_s3_bucket_policy.config_logs
  ]
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.main]
}

resource "aws_config_retention_configuration" "main" {
  retention_period_in_days = var.config_retention_period_in_days
}

resource "aws_config_conformance_pack" "cis" {
  name = "${local.name_prefix}-cis-benchmark"

  template_body = <<-YAML
    Parameters:
      AccessKeysRotatedParameterMaxAccessKeyAge:
        Type: String
        Default: "90"
    Resources:
      AccessKeysRotated:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: access-keys-rotated
          Source:
            Owner: AWS
            SourceIdentifier: ACCESS_KEYS_ROTATED
          InputParameters:
            maxAccessKeyAge:
              Ref: AccessKeysRotatedParameterMaxAccessKeyAge
      IAMPasswordPolicy:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: iam-password-policy
          Source:
            Owner: AWS
            SourceIdentifier: IAM_PASSWORD_POLICY
      MFAEnabledForIAMConsoleAccess:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: mfa-enabled-for-iam-console-access
          Source:
            Owner: AWS
            SourceIdentifier: MFA_ENABLED_FOR_IAM_CONSOLE_ACCESS
      RootAccountMFAEnabled:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: root-account-mfa-enabled
          Source:
            Owner: AWS
            SourceIdentifier: ROOT_ACCOUNT_MFA_ENABLED
      CloudTrailEnabled:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: cloudtrail-enabled
          Source:
            Owner: AWS
            SourceIdentifier: CLOUD_TRAIL_ENABLED
      CloudTrailLogFileValidationEnabled:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: cloud-trail-log-file-validation-enabled
          Source:
            Owner: AWS
            SourceIdentifier: CLOUD_TRAIL_LOG_FILE_VALIDATION_ENABLED
      CloudTrailEncryptionEnabled:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: cloud-trail-encryption-enabled
          Source:
            Owner: AWS
            SourceIdentifier: CLOUD_TRAIL_ENCRYPTION_ENABLED
      IncomingSSHDisabled:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: incoming-ssh-disabled
          Source:
            Owner: AWS
            SourceIdentifier: INCOMING_SSH_DISABLED
      VPCDefaultSecurityGroupClosed:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: vpc-default-security-group-closed
          Source:
            Owner: AWS
            SourceIdentifier: VPC_DEFAULT_SECURITY_GROUP_CLOSED
      S3BucketPublicReadProhibited:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: s3-bucket-public-read-prohibited
          Source:
            Owner: AWS
            SourceIdentifier: S3_BUCKET_PUBLIC_READ_PROHIBITED
      S3BucketPublicWriteProhibited:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: s3-bucket-public-write-prohibited
          Source:
            Owner: AWS
            SourceIdentifier: S3_BUCKET_PUBLIC_WRITE_PROHIBITED
      S3BucketServerSideEncryptionEnabled:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: s3-bucket-server-side-encryption-enabled
          Source:
            Owner: AWS
            SourceIdentifier: S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED
      RDSStorageEncrypted:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: rds-storage-encrypted
          Source:
            Owner: AWS
            SourceIdentifier: RDS_STORAGE_ENCRYPTED
      RDSInstancePublicAccessCheck:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: rds-instance-public-access-check
          Source:
            Owner: AWS
            SourceIdentifier: RDS_INSTANCE_PUBLIC_ACCESS_CHECK
  YAML

  input_parameter {
    parameter_name  = "AccessKeysRotatedParameterMaxAccessKeyAge"
    parameter_value = "90"
  }

  depends_on = [aws_config_configuration_recorder_status.main]
}

resource "aws_cloudwatch_event_rule" "guardduty_high_severity" {
  name        = "${local.name_prefix}-guardduty-high-severity"
  description = "Route high-severity GuardDuty findings to the containment Lambda."
  state       = "ENABLED"

  event_pattern = jsonencode({
    source        = ["aws.guardduty"]
    "detail-type" = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 7] }]
    }
  })

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-guardduty-high-severity"
    Service = "guardduty"
  })
}

resource "aws_cloudwatch_event_target" "guardduty_containment_lambda" {
  count = local.enable_guardduty_containment_lambda ? 1 : 0

  rule      = aws_cloudwatch_event_rule.guardduty_high_severity.name
  target_id = "GuardDutyContainmentLambda"
  arn       = var.guardduty_containment_lambda_arn

  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 2
  }
}

resource "aws_lambda_permission" "allow_eventbridge_guardduty" {
  count = local.enable_guardduty_containment_lambda ? 1 : 0

  statement_id  = "AllowEventBridgeGuardDutyHighSeverity"
  action        = "lambda:InvokeFunction"
  function_name = var.guardduty_containment_lambda_function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.guardduty_high_severity.arn
}

resource "aws_securityhub_account" "main" {
  enable_default_standards  = false
  control_finding_generator = "SECURITY_CONTROL"
  auto_enable_controls      = true
}

resource "aws_securityhub_standards_subscription" "enabled" {
  for_each = local.securityhub_standards

  standards_arn = each.value

  depends_on = [aws_securityhub_account.main]
}

resource "aws_guardduty_detector" "main" {
  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-guardduty-detector"
  })
}

resource "aws_guardduty_detector_feature" "standard" {
  for_each = local.guardduty_features

  detector_id = aws_guardduty_detector.main.id
  name        = each.value.name
  status      = "ENABLED"
}

resource "aws_guardduty_detector_feature" "runtime_monitoring" {
  detector_id = aws_guardduty_detector.main.id
  name        = "RUNTIME_MONITORING"
  status      = "ENABLED"

  additional_configuration {
    name   = "ECS_FARGATE_AGENT_MANAGEMENT"
    status = "ENABLED"
  }
}

output "guardduty_high_severity_event_rule_arn" {
  value = aws_cloudwatch_event_rule.guardduty_high_severity.arn
}

output "guardduty_containment_lambda_target_enabled" {
  value = local.enable_guardduty_containment_lambda
}

output "config_bucket_name" {
  value = aws_s3_bucket.config_logs.bucket
}

output "config_recorder_name" {
  value = aws_config_configuration_recorder.main.name
}

output "config_delivery_channel_name" {
  value = aws_config_delivery_channel.main.name
}

output "config_conformance_pack_arn" {
  value = aws_config_conformance_pack.cis.arn
}

output "securityhub_account_arn" {
  value = aws_securityhub_account.main.arn
}

output "securityhub_enabled_standards" {
  value = { for standard, subscription in aws_securityhub_standards_subscription.enabled : standard => subscription.arn }
}

output "guardduty_detector_id" {
  value = aws_guardduty_detector.main.id
}

output "guardduty_detector_arn" {
  value = aws_guardduty_detector.main.arn
}

output "guardduty_detector_account_id" {
  value = aws_guardduty_detector.main.account_id
}

output "guardduty_enabled_features" {
  value = concat(
    [for feature in aws_guardduty_detector_feature.standard : feature.name],
    [aws_guardduty_detector_feature.runtime_monitoring.name]
  )
}