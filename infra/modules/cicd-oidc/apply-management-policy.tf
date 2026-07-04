data "aws_iam_policy_document" "terraform_apply_network_compute" {
  statement {
    sid    = "AllowNetworkAndComputeApply"
    effect = "Allow"

    actions = [
      "application-autoscaling:DeleteScalingPolicy",
      "application-autoscaling:DeregisterScalableTarget",
      "application-autoscaling:PutScalingPolicy",
      "application-autoscaling:RegisterScalableTarget",
      "ec2:AllocateAddress",
      "ec2:AssociateRouteTable",
      "ec2:AttachInternetGateway",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CreateFlowLogs",
      "ec2:CreateInternetGateway",
      "ec2:CreateNatGateway",
      "ec2:CreateRoute",
      "ec2:CreateRouteTable",
      "ec2:CreateSecurityGroup",
      "ec2:CreateSubnet",
      "ec2:CreateTags",
      "ec2:CreateVpc",
      "ec2:DeleteFlowLogs",
      "ec2:DeleteInternetGateway",
      "ec2:DeleteNatGateway",
      "ec2:DeleteRoute",
      "ec2:DeleteRouteTable",
      "ec2:DeleteSecurityGroup",
      "ec2:DeleteSubnet",
      "ec2:DeleteTags",
      "ec2:DeleteVpc",
      "ec2:DetachInternetGateway",
      "ec2:DisassociateRouteTable",
      "ec2:ModifySubnetAttribute",
      "ec2:ModifyVpcAttribute",
      "ec2:ReleaseAddress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ecs:CreateCluster",
      "ecs:CreateService",
      "ecs:DeleteCluster",
      "ecs:DeleteService",
      "ecs:DeregisterTaskDefinition",
      "ecs:RegisterTaskDefinition",
      "ecs:TagResource",
      "ecs:UntagResource",
      "ecs:UpdateService",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:ModifyRule",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes"
    ]

    resources = ["*"]
  }
}

data "aws_iam_policy_document" "terraform_apply_data_security" {
  statement {
    sid    = "AllowDataSecurityAndObservabilityApply"
    effect = "Allow"

    actions = [
      "cloudtrail:AddTags",
      "cloudtrail:CreateTrail",
      "cloudtrail:DeleteTrail",
      "cloudtrail:PutEventSelectors",
      "cloudtrail:StartLogging",
      "cloudtrail:StopLogging",
      "cloudtrail:UpdateTrail",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:DeleteDashboards",
      "cloudwatch:PutDashboard",
      "cloudwatch:PutMetricAlarm",
      "config:DeleteConfigurationRecorder",
      "config:DeleteConformancePack",
      "config:DeleteDeliveryChannel",
      "config:DeleteRetentionConfiguration",
      "config:PutConfigurationRecorder",
      "config:PutConformancePack",
      "config:PutDeliveryChannel",
      "config:PutRetentionConfiguration",
      "config:StartConfigurationRecorder",
      "config:StopConfigurationRecorder",
      "dynamodb:CreateTable",
      "dynamodb:DeleteTable",
      "dynamodb:TagResource",
      "dynamodb:UntagResource",
      "elasticache:AddTagsToResource",
      "elasticache:CreateCacheParameterGroup",
      "elasticache:CreateCacheSubnetGroup",
      "elasticache:CreateReplicationGroup",
      "elasticache:DeleteCacheParameterGroup",
      "elasticache:DeleteCacheSubnetGroup",
      "elasticache:DeleteReplicationGroup",
      "elasticache:ModifyCacheParameterGroup",
      "elasticache:ModifyCacheSubnetGroup",
      "elasticache:ModifyReplicationGroup",
      "events:DeleteRule",
      "events:DescribeRule",
      "events:PutRule",
      "events:PutTargets",
      "events:RemoveTargets",
      "guardduty:CreateDetector",
      "guardduty:DeleteDetector",
      "guardduty:GetDetector",
      "guardduty:TagResource",
      "guardduty:UpdateDetector",
      "guardduty:UpdateDetectorFeature",
      "lambda:AddPermission",
      "lambda:CreateCodeSigningConfig",
      "lambda:CreateFunction",
      "lambda:DeleteCodeSigningConfig",
      "lambda:DeleteFunction",
      "lambda:DeleteFunctionConcurrency",
      "lambda:DeleteFunctionEventInvokeConfig",
      "lambda:PutFunctionConcurrency",
      "lambda:PutFunctionEventInvokeConfig",
      "lambda:RemovePermission",
      "lambda:TagResource",
      "lambda:UntagResource",
      "lambda:UpdateCodeSigningConfig",
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:UpdateFunctionEventInvokeConfig",
      "logs:AssociateKmsKey",
      "logs:CreateLogDelivery",
      "logs:CreateLogGroup",
      "logs:DeleteLogDelivery",
      "logs:DeleteLogGroup",
      "logs:DeleteResourcePolicy",
      "logs:PutResourcePolicy",
      "logs:PutRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource",
      "rds:AddTagsToResource",
      "rds:CreateDBInstance",
      "rds:CreateDBParameterGroup",
      "rds:CreateDBSubnetGroup",
      "rds:DeleteDBInstance",
      "rds:DeleteDBParameterGroup",
      "rds:DeleteDBSubnetGroup",
      "rds:ModifyDBInstance",
      "rds:ModifyDBParameterGroup",
      "rds:ModifyDBSubnetGroup",
      "secretsmanager:CreateSecret",
      "secretsmanager:DeleteSecret",
      "secretsmanager:PutResourcePolicy",
      "secretsmanager:PutSecretValue",
      "secretsmanager:RotateSecret",
      "secretsmanager:TagResource",
      "secretsmanager:UntagResource",
      "secretsmanager:UpdateSecret",
      "securityhub:BatchDisableStandards",
      "securityhub:BatchEnableStandards",
      "securityhub:DisableSecurityHub",
      "securityhub:EnableSecurityHub",
      "securityhub:UpdateSecurityHubConfiguration",
      "securityhub:TagResource",
      "securityhub:UntagResource",
      "signer:CancelSigningProfile",
      "signer:PutSigningProfile",
      "signer:TagResource",
      "sns:CreateTopic",
      "sns:DeleteTopic",
      "sns:SetTopicAttributes",
      "sns:Subscribe",
      "sns:TagResource",
      "sns:Unsubscribe",
      "sqs:CreateQueue",
      "sqs:DeleteQueue",
      "sqs:SetQueueAttributes",
      "sqs:TagQueue",
      "sqs:UntagQueue",
      "wafv2:AssociateWebACL",
      "wafv2:CreateWebACL",
      "wafv2:DeleteLoggingConfiguration",
      "wafv2:DeleteWebACL",
      "wafv2:DisassociateWebACL",
      "wafv2:PutLoggingConfiguration",
      "wafv2:TagResource",
      "wafv2:UpdateWebACL"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowProjectS3Management"
    effect = "Allow"

    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:DeleteBucketPolicy",
      "s3:DeleteObject",
      "s3:GetAccelerateConfiguration",
      "s3:GetBucketCORS",
      "s3:GetBucketEncryption",
      "s3:GetBucketLifecycleConfiguration",
      "s3:GetBucketLocation",
      "s3:GetBucketLogging",
      "s3:GetBucketObjectLockConfiguration",
      "s3:GetBucketOwnershipControls",
      "s3:GetBucketPolicy",
      "s3:GetBucketPublicAccessBlock",
      "s3:GetBucketRequestPayment",
      "s3:GetBucketTagging",
      "s3:GetBucketVersioning",
      "s3:GetBucketWebsite",
      "s3:GetObject",
      "s3:PutBucketEncryption",
      "s3:PutBucketLifecycleConfiguration",
      "s3:PutBucketLogging",
      "s3:PutBucketObjectLockConfiguration",
      "s3:PutBucketOwnershipControls",
      "s3:PutBucketPolicy",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketTagging",
      "s3:PutBucketVersioning",
      "s3:PutObject",
      "s3:PutObjectLegalHold",
      "s3:PutObjectRetention",
      "s3:PutObjectTagging",
      "s3:PutReplicationConfiguration"
    ]

    resources = [
      format("arn:%s:s3:::%s-*", data.aws_partition.current.partition, local.name_prefix),
      format("arn:%s:s3:::%s-*/*", data.aws_partition.current.partition, local.name_prefix),
      format("arn:%s:s3:::%s-%s-*", data.aws_partition.current.partition, var.project, var.environment),
      format("arn:%s:s3:::%s-%s-*/*", data.aws_partition.current.partition, var.project, var.environment)
    ]
  }

  statement {
    sid    = "AllowKmsApplyForCustomerManagedKeys"
    effect = "Allow"

    actions = [
      "kms:CancelKeyDeletion",
      "kms:CreateAlias",
      "kms:CreateGrant",
      "kms:CreateKey",
      "kms:DeleteAlias",
      "kms:DescribeKey",
      "kms:DisableKey",
      "kms:EnableKey",
      "kms:EnableKeyRotation",
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:GenerateDataKeyWithoutPlaintext",
      "kms:GetKeyPolicy",
      "kms:PutKeyPolicy",
      "kms:ReEncryptFrom",
      "kms:ReEncryptTo",
      "kms:ScheduleKeyDeletion",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:UpdateAlias",
      "kms:UpdateKeyDescription"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "terraform_apply_network_compute" {
  name        = format("%s-github-terraform-apply-network-compute", local.name_prefix)
  description = "Allow Terraform apply to manage dev network, ALB, and ECS resources."
  policy      = data.aws_iam_policy_document.terraform_apply_network_compute.json

  tags = merge(local.common_tags, {
    Name = format("%s-github-terraform-apply-network-compute", local.name_prefix)
  })
}

resource "aws_iam_policy" "terraform_apply_data_security" {
  name        = format("%s-github-terraform-apply-data-security", local.name_prefix)
  description = "Allow Terraform apply to manage dev data, logging, detection, and security resources."
  policy      = data.aws_iam_policy_document.terraform_apply_data_security.json

  tags = merge(local.common_tags, {
    Name = format("%s-github-terraform-apply-data-security", local.name_prefix)
  })
}

resource "aws_iam_role_policy_attachment" "terraform_apply_network_compute" {
  role       = aws_iam_role.terraform_apply.name
  policy_arn = aws_iam_policy.terraform_apply_network_compute.arn
}

resource "aws_iam_role_policy_attachment" "terraform_apply_data_security" {
  role       = aws_iam_role.terraform_apply.name
  policy_arn = aws_iam_policy.terraform_apply_data_security.arn
}




