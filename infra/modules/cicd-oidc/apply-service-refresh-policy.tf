data "aws_iam_policy_document" "terraform_apply_service_refresh" {
  statement {
    sid    = "AllowTerraformServiceRefresh"
    effect = "Allow"

    actions = [
      "config:DescribeConfigurationRecorders",
      "config:DescribeConfigurationRecorderStatus",
      "config:DescribeConformancePacks",
      "config:DescribeDeliveryChannels",
      "config:DescribeRetentionConfigurations",
      "ec2:DescribeAddresses",
      "ec2:DescribeFlowLogs",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeNatGateways",
      "ec2:DescribeNetworkAcls",
      "ec2:DescribeRouteTables",
      "ec2:DescribeSecurityGroupRules",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeTags",
      "ec2:DescribeVpcAttribute",
      "ec2:DescribeVpcEndpoints",
      "ec2:DescribeVpcs",
      "ecs:DescribeClusters",
      "ecs:DescribeServices",
      "ecs:DescribeTaskDefinition",
      "ecs:ListClusters",
      "ecs:ListServices",
      "ecs:ListTagsForResource",
      "elasticloadbalancing:DescribeListenerCertificates",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeTags",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeTargetGroups",
      "events:DescribeRule",
      "events:ListTagsForResource",
      "events:ListTargetsByRule",
      "events:TagResource",
      "events:UntagResource",
      "guardduty:GetDetector",
      "guardduty:GetDetectorFeature",
      "guardduty:ListDetectors",
      "guardduty:ListTagsForResource",
      "kms:GetKeyRotationStatus",
      "kms:ListAliases",
      "kms:ListResourceTags",
      "rds:DescribeDBInstances",
      "rds:DescribeDBParameterGroups",
      "rds:DescribeDBParameters",
      "rds:DescribeDBSubnetGroups",
      "rds:ListTagsForResource",
      "securityhub:DescribeHub",
      "securityhub:GetEnabledStandards",
      "securityhub:ListTagsForResource",
      "signer:GetSigningProfile",
      "signer:ListProfilePermissions",
      "signer:ListSigningProfiles",
      "sns:GetTopicAttributes",
      "sns:ListSubscriptionsByTopic",
      "sns:ListTagsForResource",
      "sns:UntagResource",
      "wafv2:GetLoggingConfiguration",
      "wafv2:GetWebACL",
      "wafv2:ListTagsForResource",
      "wafv2:ListWebACLs"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "terraform_apply_service_refresh" {
  name        = format("%s-github-terraform-apply-service-refresh", local.name_prefix)
  description = "Allow Terraform apply to refresh and tag AWS service resources created by the dev stack."
  policy      = data.aws_iam_policy_document.terraform_apply_service_refresh.json

  tags = merge(local.common_tags, {
    Name = format("%s-github-terraform-apply-service-refresh", local.name_prefix)
  })
}

resource "aws_iam_role_policy_attachment" "terraform_apply_service_refresh" {
  role       = aws_iam_role.terraform_apply.name
  policy_arn = aws_iam_policy.terraform_apply_service_refresh.arn
}
