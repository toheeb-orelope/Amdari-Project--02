variable "project" {
  description = "Project name used for resource naming and tagging."
  type        = string
  default     = "sentinelpay"
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Resource owner tag."
  type        = string
  default     = "platform-security"
}

variable "cost_center" {
  description = "Cost center tag."
  type        = string
  default     = "lab"
}

variable "repository_name" {
  description = "Repository tag value."
  type        = string
  default     = "Amdari-Project--02"
}

variable "github_owner" {
  description = "GitHub organization or user that owns the repository."
  type        = string
  default     = "toheeb-orelope"
}

variable "github_repo" {
  description = "GitHub repository name allowed to assume these roles."
  type        = string
  default     = "Amdari-Project--02"
}

variable "github_oidc_provider_arn" {
  description = "Existing account-level GitHub Actions OIDC provider ARN. Prefer passing the existing provider ARN instead of creating duplicates."
  type        = string
  default     = "arn:aws:iam::363238514491:oidc-provider/token.actions.githubusercontent.com"
}

variable "github_oidc_provider_url" {
  description = "GitHub Actions OIDC provider URL without https://."
  type        = string
  default     = "token.actions.githubusercontent.com"
}

variable "plan_subjects" {
  description = "GitHub OIDC subject claims allowed to assume the Terraform plan role."
  type        = list(string)
  default = [
    "repo:toheeb-orelope/Amdari-Project--02:pull_request",
    "repo:toheeb-orelope/Amdari-Project--02:ref:refs/heads/dev"
  ]
}

variable "apply_subjects" {
  description = "GitHub OIDC subject claims allowed to assume the protected Terraform apply role."
  type        = list(string)
  default = [
    "repo:toheeb-orelope/Amdari-Project--02:ref:refs/heads/dev"
  ]
}

variable "ecr_push_subjects" {
  description = "GitHub OIDC subject claims allowed to assume the ECR image push role."
  type        = list(string)
  default = [
    "repo:toheeb-orelope/Amdari-Project--02:ref:refs/heads/dev"
  ]
}

variable "lambda_signing_subjects" {
  description = "GitHub OIDC subject claims allowed to assume the Lambda signing role."
  type        = list(string)
  default = [
    "repo:toheeb-orelope/Amdari-Project--02:ref:refs/heads/dev"
  ]
}

variable "terraform_state_bucket_arn" {
  description = "Terraform remote state S3 bucket ARN. Leave null until remote state exists."
  type        = string
  default     = null
}

variable "terraform_lock_table_arn" {
  description = "Terraform remote state DynamoDB lock table ARN. Leave null until the lock table exists."
  type        = string
  default     = null
}

variable "terraform_state_kms_key_arn" {
  description = "KMS key ARN used to encrypt the Terraform remote state bucket. Leave null until remote state encryption exists."
  type        = string
  default     = null
}

variable "terraform_apply_policy_arns" {
  description = "Environment-specific least-privilege policies to attach to the Terraform apply role. Do not use AdministratorAccess for production."
  type        = list(string)
  default     = []
}

variable "ecr_repository_arns" {
  description = "ECR repository ARNs GitHub Actions may push images to."
  type        = list(string)
  default     = []
}

variable "lambda_signing_profile_version_arns" {
  description = "AWS Signer signing profile version ARNs GitHub Actions may use for Lambda zip signing."
  type        = list(string)
  default     = []
}

locals {
  name_prefix       = "${var.project}-${var.environment}"
  github_repository = "${var.github_owner}/${var.github_repo}"

  common_tags = {
    Project            = var.project
    Environment        = var.environment
    Service            = "cicd-oidc"
    Owner              = var.owner
    CostCenter         = var.cost_center
    ManagedBy          = "terraform"
    Repository         = var.repository_name
    DataClassification = "internal"
    Criticality        = "high"
  }
}

data "aws_iam_policy_document" "github_plan_assume_role" {
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
      test     = "StringLike"
      variable = "${var.github_oidc_provider_url}:sub"
      values   = var.plan_subjects
    }
  }
}

data "aws_iam_policy_document" "github_apply_assume_role" {
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
      test     = "StringLike"
      variable = "${var.github_oidc_provider_url}:sub"
      values   = var.apply_subjects
    }
  }
}

data "aws_iam_policy_document" "github_ecr_push_assume_role" {
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
      test     = "StringLike"
      variable = "${var.github_oidc_provider_url}:sub"
      values   = var.ecr_push_subjects
    }
  }
}

data "aws_iam_policy_document" "github_lambda_signing_assume_role" {
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
      test     = "StringLike"
      variable = "${var.github_oidc_provider_url}:sub"
      values   = var.lambda_signing_subjects
    }
  }
}

resource "aws_iam_role" "terraform_plan" {
  name                 = "${local.name_prefix}-github-terraform-plan"
  description          = "GitHub Actions OIDC role for Terraform plan in ${local.github_repository}."
  assume_role_policy   = data.aws_iam_policy_document.github_plan_assume_role.json
  max_session_duration = 3600

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-github-terraform-plan"
  })
}

resource "aws_iam_role" "terraform_apply" {
  name                 = "${local.name_prefix}-github-terraform-apply"
  description          = "Protected GitHub Actions OIDC role for Terraform apply in ${local.github_repository}."
  assume_role_policy   = data.aws_iam_policy_document.github_apply_assume_role.json
  max_session_duration = 3600

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-github-terraform-apply"
  })
}

resource "aws_iam_role" "ecr_push" {
  name                 = "${local.name_prefix}-github-ecr-push"
  description          = "GitHub Actions OIDC role for pushing project container images to ECR."
  assume_role_policy   = data.aws_iam_policy_document.github_ecr_push_assume_role.json
  max_session_duration = 3600

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-github-ecr-push"
  })
}

resource "aws_iam_role" "lambda_signing" {
  name                 = "${local.name_prefix}-github-lambda-signing"
  description          = "GitHub Actions OIDC role for signing Lambda deployment packages with AWS Signer."
  assume_role_policy   = data.aws_iam_policy_document.github_lambda_signing_assume_role.json
  max_session_duration = 3600

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-github-lambda-signing"
  })
}

data "aws_iam_policy_document" "terraform_plan" {
  statement {
    sid    = "AllowTerraformReadOnlyDiscovery"
    effect = "Allow"

    actions = [
      "acm:DescribeCertificate",
      "acm:ListCertificates",
      "application-autoscaling:Describe*",
      "cloudtrail:DescribeTrails",
      "cloudtrail:GetTrailStatus",
      "cloudtrail:ListTags",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:GetDashboard",
      "cloudwatch:ListDashboards",
      "config:Describe*",
      "dynamodb:DescribeTable",
      "dynamodb:ListTagsOfResource",
      "ec2:Describe*",
      "ecr:DescribeRepositories",
      "ecr:ListTagsForResource",
      "ecs:Describe*",
      "ecs:List*",
      "elasticache:Describe*",
      "elasticloadbalancing:Describe*",
      "events:DescribeRule",
      "events:ListTargetsByRule",
      "guardduty:GetDetector",
      "guardduty:List*",
      "iam:Get*",
      "iam:List*",
      "kms:DescribeKey",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:ListAliases",
      "lambda:GetFunction",
      "lambda:GetFunctionCodeSigningConfig",
      "lambda:GetPolicy",
      "lambda:List*",
      "logs:Describe*",
      "rds:Describe*",
      "route53:Get*",
      "route53:List*",
      "s3:GetBucket*",
      "s3:GetEncryptionConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:GetObjectLockConfiguration",
      "s3:GetReplicationConfiguration",
      "s3:ListBucket",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecrets",
      "securityhub:Describe*",
      "securityhub:Get*",
      "securityhub:List*",
      "signer:GetSigningProfile",
      "signer:ListSigningProfiles",
      "sns:GetTopicAttributes",
      "sns:ListSubscriptionsByTopic",
      "wafv2:Get*",
      "wafv2:List*"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "terraform_plan" {
  name        = "${local.name_prefix}-github-terraform-plan"
  description = "Read-only discovery permissions for Terraform plan from GitHub Actions."
  policy      = data.aws_iam_policy_document.terraform_plan.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-github-terraform-plan"
  })
}

resource "aws_iam_role_policy_attachment" "terraform_plan" {
  role       = aws_iam_role.terraform_plan.name
  policy_arn = aws_iam_policy.terraform_plan.arn
}

data "aws_iam_policy_document" "terraform_state_read" {
  count = var.terraform_state_bucket_arn == null ? 0 : 1

  statement {
    sid    = "AllowReadTerraformState"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]

    resources = [
      var.terraform_state_bucket_arn,
      "${var.terraform_state_bucket_arn}/*"
    ]
  }

  dynamic "statement" {
    for_each = var.terraform_state_kms_key_arn == null ? [] : [var.terraform_state_kms_key_arn]

    content {
      sid    = "AllowDecryptTerraformStateKey"
      effect = "Allow"

      actions = [
        "kms:Decrypt",
        "kms:DescribeKey"
      ]

      resources = [statement.value]
    }
  }
}

resource "aws_iam_policy" "terraform_state_read" {
  count = var.terraform_state_bucket_arn == null ? 0 : 1

  name        = "${local.name_prefix}-github-terraform-state-read"
  description = "Read access to Terraform remote state for plan workflows."
  policy      = data.aws_iam_policy_document.terraform_state_read[0].json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-github-terraform-state-read"
  })
}

resource "aws_iam_role_policy_attachment" "terraform_plan_state_read" {
  count = var.terraform_state_bucket_arn == null ? 0 : 1

  role       = aws_iam_role.terraform_plan.name
  policy_arn = aws_iam_policy.terraform_state_read[0].arn
}

data "aws_iam_policy_document" "terraform_state_write" {
  count = var.terraform_state_bucket_arn == null || var.terraform_lock_table_arn == null ? 0 : 1

  statement {
    sid    = "AllowReadWriteTerraformState"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket"
    ]

    resources = [
      var.terraform_state_bucket_arn,
      "${var.terraform_state_bucket_arn}/*"
    ]
  }

  statement {
    sid    = "AllowTerraformStateLocking"
    effect = "Allow"

    actions = [
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem"
    ]

    resources = [var.terraform_lock_table_arn]
  }

  dynamic "statement" {
    for_each = var.terraform_state_kms_key_arn == null ? [] : [var.terraform_state_kms_key_arn]

    content {
      sid    = "AllowReadWriteTerraformStateKey"
      effect = "Allow"

      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:Encrypt",
        "kms:GenerateDataKey",
        "kms:ReEncryptFrom",
        "kms:ReEncryptTo"
      ]

      resources = [statement.value]
    }
  }
}

resource "aws_iam_policy" "terraform_state_write" {
  count = var.terraform_state_bucket_arn == null || var.terraform_lock_table_arn == null ? 0 : 1

  name        = "${local.name_prefix}-github-terraform-state-write"
  description = "Read/write Terraform remote state and lock permissions for apply workflows."
  policy      = data.aws_iam_policy_document.terraform_state_write[0].json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-github-terraform-state-write"
  })
}

resource "aws_iam_role_policy_attachment" "terraform_apply_state_write" {
  count = var.terraform_state_bucket_arn == null || var.terraform_lock_table_arn == null ? 0 : 1

  role       = aws_iam_role.terraform_apply.name
  policy_arn = aws_iam_policy.terraform_state_write[0].arn
}

resource "aws_iam_role_policy_attachment" "terraform_apply_extra" {
  for_each = toset(var.terraform_apply_policy_arns)

  role       = aws_iam_role.terraform_apply.name
  policy_arn = each.value
}

data "aws_iam_policy_document" "ecr_push" {
  statement {
    sid    = "AllowEcrAuthorization"
    effect = "Allow"

    actions = [
      "ecr:GetAuthorizationToken"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowProjectImagePush"
    effect = "Allow"

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:InitiateLayerUpload",
      "ecr:ListImages",
      "ecr:PutImage",
      "ecr:UploadLayerPart"
    ]

    resources = var.ecr_repository_arns
  }
}

resource "aws_iam_policy" "ecr_push" {
  count = length(var.ecr_repository_arns) == 0 ? 0 : 1

  name        = "${local.name_prefix}-github-ecr-push"
  description = "Allow GitHub Actions to push images to project ECR repositories."
  policy      = data.aws_iam_policy_document.ecr_push.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-github-ecr-push"
  })
}

resource "aws_iam_role_policy_attachment" "ecr_push" {
  count = length(var.ecr_repository_arns) == 0 ? 0 : 1

  role       = aws_iam_role.ecr_push.name
  policy_arn = aws_iam_policy.ecr_push[0].arn
}

data "aws_iam_policy_document" "lambda_signing" {
  statement {
    sid    = "AllowLambdaArtifactSigning"
    effect = "Allow"

    actions = [
      "signer:DescribeSigningJob",
      "signer:GetSigningProfile",
      "signer:ListSigningJobs",
      "signer:StartSigningJob"
    ]

    resources = var.lambda_signing_profile_version_arns
  }
}

resource "aws_iam_policy" "lambda_signing" {
  count = length(var.lambda_signing_profile_version_arns) == 0 ? 0 : 1

  name        = "${local.name_prefix}-github-lambda-signing"
  description = "Allow GitHub Actions to sign Lambda artifacts with project AWS Signer profiles."
  policy      = data.aws_iam_policy_document.lambda_signing.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-github-lambda-signing"
  })
}

resource "aws_iam_role_policy_attachment" "lambda_signing" {
  count = length(var.lambda_signing_profile_version_arns) == 0 ? 0 : 1

  role       = aws_iam_role.lambda_signing.name
  policy_arn = aws_iam_policy.lambda_signing[0].arn
}

output "terraform_plan_role_arn" {
  description = "GitHub Actions role ARN for Terraform plan."
  value       = aws_iam_role.terraform_plan.arn
}

output "terraform_apply_role_arn" {
  description = "GitHub Actions role ARN for protected Terraform apply."
  value       = aws_iam_role.terraform_apply.arn
}

output "ecr_push_role_arn" {
  description = "GitHub Actions role ARN for ECR image pushes."
  value       = aws_iam_role.ecr_push.arn
}

output "lambda_signing_role_arn" {
  description = "GitHub Actions role ARN for Lambda package signing."
  value       = aws_iam_role.lambda_signing.arn
}
