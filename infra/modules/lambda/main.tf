variable "project" {
  description = "Project name used for resource naming."
  type        = string
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
}

variable "logs_kms_key_arn" {
  description = "Customer-managed KMS key ARN used to encrypt Lambda CloudWatch log groups."
  type        = string
}

variable "enable_code_signing" {
  description = "Enable AWS Signer-backed Lambda code signing. Keep enabled for production."
  type        = bool
  default     = true
}

variable "containment_lambda_role_arn" {
  description = "IAM role ARN for the GuardDuty containment Lambda. Leave null to skip creating it."
  type        = string
  default     = null
}

variable "containment_package_path" {
  description = "Path to the zipped GuardDuty containment Lambda package. Leave null to skip creating it."
  type        = string
  default     = null
}

variable "containment_handler" {
  description = "Handler for the GuardDuty containment Lambda."
  type        = string
  default     = "handler.lambda_handler"
}

variable "containment_runtime" {
  description = "Runtime for the GuardDuty containment Lambda."
  type        = string
  default     = "python3.12"
}

variable "containment_timeout" {
  description = "Timeout in seconds for the GuardDuty containment Lambda."
  type        = number
  default     = 30
}

variable "containment_memory_size" {
  description = "Memory in MB for the GuardDuty containment Lambda."
  type        = number
  default     = 128
}

variable "rotation_lambda_role_arn" {
  description = "IAM role ARN for the Secrets Manager rotation Lambda. Leave null to skip creating it."
  type        = string
  default     = null
}

variable "rotation_package_path" {
  description = "Path to the zipped Secrets Manager rotation Lambda package. Leave null to skip creating it."
  type        = string
  default     = null
}

variable "rotation_handler" {
  description = "Handler for the Secrets Manager rotation Lambda."
  type        = string
  default     = "handler.lambda_handler"
}

variable "rotation_runtime" {
  description = "Runtime for the Secrets Manager rotation Lambda."
  type        = string
  default     = "python3.12"
}

variable "rotation_timeout" {
  description = "Timeout in seconds for the Secrets Manager rotation Lambda."
  type        = number
  default     = 30
}

variable "rotation_memory_size" {
  description = "Memory in MB for the Secrets Manager rotation Lambda."
  type        = number
  default     = 128
}

variable "secret_rotation_secret_ids" {
  description = "Map of logical secret names to Secrets Manager secret ARNs that should use the rotation Lambda."
  type        = map(string)
  default     = {}
}

variable "secret_rotation_days" {
  description = "Number of days between automatic secret rotations."
  type        = number
  default     = 30
}

variable "reserved_concurrent_executions" {
  description = "Reserved concurrency for Lambda functions to limit blast radius and runaway cost."
  type        = number
  default     = 5
}

variable "tags" {
  description = "Standard tags applied to resources."
  type        = map(string)
  default     = {}
}

locals {
  name_prefix         = "${var.project}-${var.environment}"
  signer_profile_name = replace("${var.project}_${var.environment}_lambda", "-", "_")

  create_containment_lambda = var.containment_package_path != null
  create_rotation_lambda    = var.rotation_package_path != null
}

data "aws_caller_identity" "current" {}

resource "aws_signer_signing_profile" "lambda" {
  count = var.enable_code_signing ? 1 : 0

  name_prefix = "${local.signer_profile_name}_"
  platform_id = "AWSLambda-SHA384-ECDSA"

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-lambda-signer-profile"
    Service = "lambda"
  })
}

resource "aws_lambda_code_signing_config" "lambda" {
  count = var.enable_code_signing ? 1 : 0

  description = "Allow only Lambda packages signed by the trusted ${local.name_prefix} AWS Signer profile."

  allowed_publishers {
    signing_profile_version_arns = [
      aws_signer_signing_profile.lambda[0].version_arn
    ]
  }

  policies {
    untrusted_artifact_on_deployment = "Enforce"
  }
}


resource "aws_sqs_queue" "guardduty_containment_dlq" {
  count = local.create_containment_lambda ? 1 : 0

  name              = "${local.name_prefix}-guardduty-containment-dlq"
  kms_master_key_id = var.logs_kms_key_arn

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-guardduty-containment-dlq"
    Service = "lambda"
  })
}

resource "aws_sqs_queue" "secret_rotation_dlq" {
  count = local.create_rotation_lambda ? 1 : 0

  name              = "${local.name_prefix}-secret-rotation-dlq"
  kms_master_key_id = var.logs_kms_key_arn

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-secret-rotation-dlq"
    Service = "lambda"
  })
}

resource "aws_cloudwatch_log_group" "guardduty_containment" {
  count = local.create_containment_lambda ? 1 : 0

  name              = "/aws/lambda/${local.name_prefix}-guardduty-containment"
  retention_in_days = 365
  kms_key_id        = var.logs_kms_key_arn

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-guardduty-containment-logs"
    Service = "lambda"
  })
}

resource "aws_lambda_function" "guardduty_containment" {
  count = local.create_containment_lambda ? 1 : 0

  function_name                  = "${local.name_prefix}-guardduty-containment"
  description                    = "Containment handler for high-severity GuardDuty findings."
  role                           = var.containment_lambda_role_arn
  filename                       = var.containment_package_path
  handler                        = var.containment_handler
  runtime                        = var.containment_runtime
  timeout                        = var.containment_timeout
  memory_size                    = var.containment_memory_size
  reserved_concurrent_executions = var.reserved_concurrent_executions
  kms_key_arn                    = var.logs_kms_key_arn

  dead_letter_config {
    target_arn = aws_sqs_queue.guardduty_containment_dlq[0].arn
  }

  code_signing_config_arn = var.enable_code_signing ? aws_lambda_code_signing_config.lambda[0].arn : null
  source_code_hash        = filebase64sha256(var.containment_package_path)

  environment {
    variables = {
      ENVIRONMENT = var.environment
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-guardduty-containment"
    Service = "lambda"
  })

  depends_on = [aws_cloudwatch_log_group.guardduty_containment]
}

resource "aws_cloudwatch_log_group" "secret_rotation" {
  count = local.create_rotation_lambda ? 1 : 0

  name              = "/aws/lambda/${local.name_prefix}-secret-rotation"
  retention_in_days = 365
  kms_key_id        = var.logs_kms_key_arn

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-secret-rotation-logs"
    Service = "lambda"
  })
}

resource "aws_lambda_function" "secret_rotation" {
  count = local.create_rotation_lambda ? 1 : 0

  function_name                  = "${local.name_prefix}-secret-rotation"
  description                    = "Secrets Manager rotation handler for runtime secrets."
  role                           = var.rotation_lambda_role_arn
  filename                       = var.rotation_package_path
  handler                        = var.rotation_handler
  runtime                        = var.rotation_runtime
  timeout                        = var.rotation_timeout
  memory_size                    = var.rotation_memory_size
  reserved_concurrent_executions = var.reserved_concurrent_executions
  kms_key_arn                    = var.logs_kms_key_arn

  dead_letter_config {
    target_arn = aws_sqs_queue.secret_rotation_dlq[0].arn
  }

  code_signing_config_arn = var.enable_code_signing ? aws_lambda_code_signing_config.lambda[0].arn : null
  source_code_hash        = filebase64sha256(var.rotation_package_path)

  environment {
    variables = {
      ENVIRONMENT = var.environment
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-secret-rotation"
    Service = "lambda"
  })

  depends_on = [aws_cloudwatch_log_group.secret_rotation]
}

resource "aws_lambda_permission" "allow_secretsmanager_rotation" {
  for_each = local.create_rotation_lambda ? var.secret_rotation_secret_ids : {}

  statement_id   = "AllowSecretsManagerRotation-${each.key}"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.secret_rotation[0].function_name
  principal      = "secretsmanager.amazonaws.com"
  source_arn     = each.value
  source_account = data.aws_caller_identity.current.account_id
}

resource "aws_secretsmanager_secret_rotation" "rotated" {
  for_each = local.create_rotation_lambda ? var.secret_rotation_secret_ids : {}

  secret_id           = each.value
  rotation_lambda_arn = aws_lambda_function.secret_rotation[0].arn
  rotate_immediately  = false

  rotation_rules {
    automatically_after_days = var.secret_rotation_days
  }

  depends_on = [aws_lambda_permission.allow_secretsmanager_rotation]
}

output "guardduty_containment_lambda_arn" {
  description = "ARN of the GuardDuty containment Lambda, if created."
  value       = local.create_containment_lambda ? aws_lambda_function.guardduty_containment[0].arn : null
}

output "lambda_signing_profile_version_arn" {
  description = "AWS Signer signing profile version ARN trusted by Lambda code signing, if enabled."
  value       = var.enable_code_signing ? aws_signer_signing_profile.lambda[0].version_arn : null
}

output "lambda_code_signing_config_arn" {
  description = "Lambda code signing config ARN, if enabled."
  value       = var.enable_code_signing ? aws_lambda_code_signing_config.lambda[0].arn : null
}

output "guardduty_containment_lambda_function_name" {
  description = "Function name of the GuardDuty containment Lambda, if created."
  value       = local.create_containment_lambda ? aws_lambda_function.guardduty_containment[0].function_name : null
}

output "secret_rotation_lambda_arn" {
  description = "ARN of the Secrets Manager rotation Lambda, if created."
  value       = local.create_rotation_lambda ? aws_lambda_function.secret_rotation[0].arn : null
}

output "secret_rotation_lambda_function_name" {
  description = "Function name of the Secrets Manager rotation Lambda, if created."
  value       = local.create_rotation_lambda ? aws_lambda_function.secret_rotation[0].function_name : null
}

output "rotated_secret_ids" {
  description = "Secrets configured for automatic rotation by this module."
  value       = keys(aws_secretsmanager_secret_rotation.rotated)
}

