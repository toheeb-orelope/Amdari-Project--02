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

variable "ecr_repository_arns" {
  description = "ECR repository ARNs the ECS execution role may pull images from."
  type        = list(string)
  default     = []
}

variable "ecs_log_group_arns" {
  description = "CloudWatch log group ARNs used by ECS services."
  type        = list(string)
  default     = []
}

variable "execution_secret_arns" {
  description = "Secrets injected by ECS at task startup."
  type        = list(string)
  default     = []
}

variable "execution_kms_key_arns" {
  description = "KMS keys needed by the ECS execution role to decrypt startup secrets."
  type        = list(string)
  default     = []
}

variable "payments_secret_arns" {
  description = "Secrets readable by payments-api only."
  type        = list(string)
  default     = []
}

variable "payments_kms_key_arns" {
  description = "KMS keys payments-api may use through scoped AWS services."
  type        = list(string)
  default     = []
}

variable "payments_rds_dbuser_arns" {
  description = "Optional rds-db user ARNs for IAM database authentication."
  type        = list(string)
  default     = []
}

variable "kyc_secret_arns" {
  description = "Secrets readable by kyc-api only."
  type        = list(string)
  default     = []
}

variable "kyc_kms_key_arns" {
  description = "KMS keys kyc-api may use for documents and scoped secrets."
  type        = list(string)
  default     = []
}

variable "kyc_rds_dbuser_arns" {
  description = "Optional rds-db user ARNs for IAM database authentication."
  type        = list(string)
  default     = []
}

variable "kyc_bucket_arn" {
  description = "KYC document bucket ARN. Leave null until the S3 module is wired in."
  type        = string
  default     = null
}

variable "github_oidc_provider_arn" {
  description = "GitHub Actions OIDC provider ARN. Create this in the cicd-oidc module and pass it here."
  type        = string
  default     = null
}

variable "github_oidc_provider_url" {
  description = "GitHub Actions OIDC provider URL without https://."
  type        = string
  default     = "token.actions.githubusercontent.com"
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the deploy role, formatted owner/repo."
  type        = string
  default     = "toheeb-orelope/Amdari-Project--02"
}

variable "github_branch" {
  description = "GitHub branch allowed to assume the deploy role."
  type        = string
  default     = "dev"
}

variable "github_deploy_policy_arns" {
  description = "Customer-managed deploy policy ARNs attached to the GitHub Actions role. Keep scoped per environment."
  type        = list(string)
  default     = []
}

variable "enable_break_glass_role" {
  description = "Enable only after the manual approval process and permitted principals are documented."
  type        = bool
  default     = false
}

variable "break_glass_principal_arns" {
  description = "IAM Identity Center or emergency role ARNs allowed to assume the break-glass role."
  type        = list(string)
  default     = []
}

variable "enable_detection_lambda_role" {
  description = "Enable when the GuardDuty containment Lambda is implemented."
  type        = bool
  default     = false
}

variable "detection_lambda_policy_arns" {
  description = "Customer-managed containment policy ARNs for the detection Lambda role."
  type        = list(string)
  default     = []
}

variable "enable_secret_rotation_lambda_role" {
  description = "Enable when the Secrets Manager rotation Lambda is implemented."
  type        = bool
  default     = false
}

variable "rotation_secret_arns" {
  description = "Secret ARNs the rotation Lambda may rotate."
  type        = list(string)
  default     = []
}

variable "rotation_kms_key_arns" {
  description = "KMS key ARNs the rotation Lambda may use for secret encryption/decryption."
  type        = list(string)
  default     = []
}


locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = {
    Project            = var.project
    Environment        = var.environment
    Service            = "iam"
    Owner              = var.owner
    CostCenter         = var.cost_center
    ManagedBy          = "terraform"
    Repository         = var.repository
    DataClassification = var.data_classification
    Criticality        = var.criticality
  }

  kyc_object_arn = var.kyc_bucket_arn == null ? null : "${var.kyc_bucket_arn}/users/*"
}

data "aws_iam_policy_document" "ecs_tasks_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${local.name_prefix}-ecs-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecs-task-execution-role"
  })
}

data "aws_iam_policy_document" "ecs_task_execution" {
  statement {
    sid    = "AllowEcrAuthorizationToken"
    effect = "Allow"

    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = length(var.ecr_repository_arns) == 0 ? [] : [1]

    content {
      sid    = "AllowScopedEcrImagePull"
      effect = "Allow"

      actions = [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer"
      ]

      resources = var.ecr_repository_arns
    }
  }

  dynamic "statement" {
    for_each = length(var.ecs_log_group_arns) == 0 ? [] : [1]

    content {
      sid    = "AllowEcsLogWrites"
      effect = "Allow"

      actions = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]

      resources = [for arn in var.ecs_log_group_arns : "${arn}:*"]
    }
  }

  dynamic "statement" {
    for_each = length(var.execution_secret_arns) == 0 ? [] : [1]

    content {
      sid    = "AllowStartupSecretReads"
      effect = "Allow"

      actions = [
        "secretsmanager:DescribeSecret",
        "secretsmanager:GetSecretValue"
      ]

      resources = var.execution_secret_arns
    }
  }

  dynamic "statement" {
    for_each = length(var.execution_kms_key_arns) == 0 ? [] : [1]

    content {
      sid    = "AllowStartupSecretDecrypt"
      effect = "Allow"

      actions = [
        "kms:Decrypt",
        "kms:DescribeKey"
      ]

      resources = var.execution_kms_key_arns
    }
  }
}

resource "aws_iam_policy" "ecs_task_execution" {
  name        = "${local.name_prefix}-ecs-task-execution-policy"
  description = "Scoped ECS task execution permissions for ${local.name_prefix}."
  policy      = data.aws_iam_policy_document.ecs_task_execution.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecs-task-execution-policy"
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = aws_iam_policy.ecs_task_execution.arn
}

resource "aws_iam_role" "payments_task" {
  name               = "${local.name_prefix}-payments-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-payments-task-role"
    Service = "payments-api"
  })
}

data "aws_iam_policy_document" "payments_task" {
  dynamic "statement" {
    for_each = length(var.payments_secret_arns) == 0 ? [] : [1]

    content {
      sid    = "AllowPaymentsSecretReads"
      effect = "Allow"

      actions = [
        "secretsmanager:DescribeSecret",
        "secretsmanager:GetSecretValue"
      ]

      resources = var.payments_secret_arns
    }
  }

  dynamic "statement" {
    for_each = length(var.payments_kms_key_arns) == 0 ? [] : [1]

    content {
      sid    = "AllowPaymentsKmsUse"
      effect = "Allow"

      actions = [
        "kms:Decrypt",
        "kms:DescribeKey"
      ]

      resources = var.payments_kms_key_arns
    }
  }

  dynamic "statement" {
    for_each = length(var.payments_rds_dbuser_arns) == 0 ? [] : [1]

    content {
      sid    = "AllowPaymentsIamDatabaseConnect"
      effect = "Allow"

      actions   = ["rds-db:connect"]
      resources = var.payments_rds_dbuser_arns
    }
  }
}

resource "aws_iam_policy" "payments_task" {
  name        = "${local.name_prefix}-payments-task-policy"
  description = "Least-privilege runtime permissions for payments-api."
  policy      = data.aws_iam_policy_document.payments_task.json

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-payments-task-policy"
    Service = "payments-api"
  })
}

resource "aws_iam_role_policy_attachment" "payments_task" {
  role       = aws_iam_role.payments_task.name
  policy_arn = aws_iam_policy.payments_task.arn
}

resource "aws_iam_role" "kyc_task" {
  name               = "${local.name_prefix}-kyc-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-kyc-task-role"
    Service = "kyc-api"
  })
}

data "aws_iam_policy_document" "kyc_task" {
  dynamic "statement" {
    for_each = length(var.kyc_secret_arns) == 0 ? [] : [1]

    content {
      sid    = "AllowKycSecretReads"
      effect = "Allow"

      actions = [
        "secretsmanager:DescribeSecret",
        "secretsmanager:GetSecretValue"
      ]

      resources = var.kyc_secret_arns
    }
  }

  dynamic "statement" {
    for_each = length(var.kyc_kms_key_arns) == 0 ? [] : [1]

    content {
      sid    = "AllowKycKmsUse"
      effect = "Allow"

      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:Encrypt",
        "kms:GenerateDataKey"
      ]

      resources = var.kyc_kms_key_arns
    }
  }

  dynamic "statement" {
    for_each = var.kyc_bucket_arn == null ? [] : [1]

    content {
      sid    = "AllowKycListDocumentPrefix"
      effect = "Allow"

      actions   = ["s3:ListBucket"]
      resources = [var.kyc_bucket_arn]

      condition {
        test     = "StringLike"
        variable = "s3:prefix"
        values   = ["users/*"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.kyc_bucket_arn == null ? [] : [1]

    content {
      sid    = "AllowKycReadWriteDocuments"
      effect = "Allow"

      actions = [
        "s3:GetObject",
        "s3:PutObject"
      ]

      resources = [local.kyc_object_arn]
    }
  }

  dynamic "statement" {
    for_each = length(var.kyc_rds_dbuser_arns) == 0 ? [] : [1]

    content {
      sid    = "AllowKycIamDatabaseConnect"
      effect = "Allow"

      actions   = ["rds-db:connect"]
      resources = var.kyc_rds_dbuser_arns
    }
  }
}

resource "aws_iam_policy" "kyc_task" {
  name        = "${local.name_prefix}-kyc-task-policy"
  description = "Least-privilege runtime permissions for kyc-api."
  policy      = data.aws_iam_policy_document.kyc_task.json

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-kyc-task-policy"
    Service = "kyc-api"
  })
}

resource "aws_iam_role_policy_attachment" "kyc_task" {
  role       = aws_iam_role.kyc_task.name
  policy_arn = aws_iam_policy.kyc_task.arn
}

data "aws_iam_policy_document" "github_actions_assume_role" {
  count = var.github_oidc_provider_arn == null ? 0 : 1

  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [var.github_oidc_provider_arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${var.github_oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.github_oidc_provider_url}:sub"
      values   = ["repo:${var.github_repository}:ref:refs/heads/${var.github_branch}"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  count = var.github_oidc_provider_arn == null ? 0 : 1

  name               = "${local.name_prefix}-github-actions-role"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role[0].json

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-github-actions-role"
    Service = "github-actions"
  })
}

resource "aws_iam_role_policy_attachment" "github_actions" {
  for_each = var.github_oidc_provider_arn == null ? toset([]) : toset(var.github_deploy_policy_arns)

  role       = aws_iam_role.github_actions[0].name
  policy_arn = each.value
}

data "aws_iam_policy_document" "break_glass_assume_role" {
  count = var.enable_break_glass_role ? 1 : 0

  statement {
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = var.break_glass_principal_arns
    }

    actions = ["sts:AssumeRole"]

    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }
}

resource "aws_iam_role" "break_glass" {
  count = var.enable_break_glass_role ? 1 : 0

  name                 = "${local.name_prefix}-break-glass-role"
  assume_role_policy   = data.aws_iam_policy_document.break_glass_assume_role[0].json
  max_session_duration = 3600

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-break-glass-role"
    Service = "break-glass"
  })
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "detection_lambda" {
  count = var.enable_detection_lambda_role ? 1 : 0

  name               = "${local.name_prefix}-detection-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-detection-lambda-role"
    Service = "detection"
  })
}

data "aws_iam_policy_document" "detection_lambda_logs" {
  count = var.enable_detection_lambda_role ? 1 : 0

  statement {
    sid    = "AllowDetectionLambdaLogWrites"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["arn:aws:logs:*:*:log-group:/aws/lambda/${local.name_prefix}-guardduty-containment:*"]
  }

  statement {
    sid       = "AllowDetectionLambdaDeadLetterQueueWrites"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = ["arn:aws:sqs:*:*:${local.name_prefix}-guardduty-containment-dlq"]
  }
}

resource "aws_iam_role_policy" "detection_lambda_logs" {
  count = var.enable_detection_lambda_role ? 1 : 0

  name   = "${local.name_prefix}-detection-lambda-logs-policy"
  role   = aws_iam_role.detection_lambda[0].id
  policy = data.aws_iam_policy_document.detection_lambda_logs[0].json
}

resource "aws_iam_role_policy_attachment" "detection_lambda" {
  for_each = var.enable_detection_lambda_role ? toset(var.detection_lambda_policy_arns) : toset([])

  role       = aws_iam_role.detection_lambda[0].name
  policy_arn = each.value
}

resource "aws_iam_role" "secret_rotation_lambda" {
  count = var.enable_secret_rotation_lambda_role ? 1 : 0

  name               = "${local.name_prefix}-secret-rotation-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-secret-rotation-lambda-role"
    Service = "secret-rotation"
  })
}

data "aws_iam_policy_document" "secret_rotation_lambda" {
  count = var.enable_secret_rotation_lambda_role ? 1 : 0

  statement {
    sid    = "AllowRotationLambdaLogWrites"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["arn:aws:logs:*:*:log-group:/aws/lambda/${local.name_prefix}-secret-rotation:*"]
  }

  dynamic "statement" {
    for_each = length(var.rotation_secret_arns) == 0 ? [] : [1]

    content {
      sid    = "AllowSecretRotation"
      effect = "Allow"

      actions = [
        "secretsmanager:DescribeSecret",
        "secretsmanager:GetSecretValue",
        "secretsmanager:PutSecretValue",
        "secretsmanager:UpdateSecretVersionStage"
      ]

      resources = var.rotation_secret_arns
    }
  }

  dynamic "statement" {
    for_each = length(var.rotation_kms_key_arns) == 0 ? [] : [1]

    content {
      sid    = "AllowRotationKmsUse"
      effect = "Allow"

      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:GenerateDataKey"
      ]

      resources = var.rotation_kms_key_arns
    }
  }
}

resource "aws_iam_role_policy" "secret_rotation_lambda" {
  count = var.enable_secret_rotation_lambda_role ? 1 : 0

  name   = "${local.name_prefix}-secret-rotation-lambda-policy"
  role   = aws_iam_role.secret_rotation_lambda[0].id
  policy = data.aws_iam_policy_document.secret_rotation_lambda[0].json
}

output "ecs_task_execution_role_arn" {
  value = aws_iam_role.ecs_task_execution.arn
}

output "payments_task_role_arn" {
  value = aws_iam_role.payments_task.arn
}

output "kyc_task_role_arn" {
  value = aws_iam_role.kyc_task.arn
}

output "github_actions_role_arn" {
  value = var.github_oidc_provider_arn == null ? null : aws_iam_role.github_actions[0].arn
}

output "break_glass_role_arn" {
  value = var.enable_break_glass_role ? aws_iam_role.break_glass[0].arn : null
}

output "detection_lambda_role_arn" {
  value = var.enable_detection_lambda_role ? aws_iam_role.detection_lambda[0].arn : null
}

output "secret_rotation_lambda_role_arn" {
  value = var.enable_secret_rotation_lambda_role ? aws_iam_role.secret_rotation_lambda[0].arn : null
}