data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_iam_policy_document" "terraform_apply_refresh" {
  statement {
    sid    = "AllowProjectIamRefresh"
    effect = "Allow"

    actions = [
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:ListPolicyVersions",
      "iam:ListRolePolicies"
    ]

    resources = [
      format("arn:%s:iam::%s:policy/%s-*", data.aws_partition.current.partition, data.aws_caller_identity.current.account_id, local.name_prefix),
      format("arn:%s:iam::%s:role/%s-*", data.aws_partition.current.partition, data.aws_caller_identity.current.account_id, local.name_prefix)
    ]
  }

  statement {
    sid    = "AllowAwsProviderRefreshDiscovery"
    effect = "Allow"

    actions = [
      "ec2:DescribeAvailabilityZones"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "terraform_apply_refresh" {
  name        = format("%s-github-terraform-apply-refresh", local.name_prefix)
  description = "Allow Terraform apply to refresh project IAM resources and provider discovery data."
  policy      = data.aws_iam_policy_document.terraform_apply_refresh.json

  tags = merge(local.common_tags, {
    Name = format("%s-github-terraform-apply-refresh", local.name_prefix)
  })
}

resource "aws_iam_role_policy_attachment" "terraform_apply_refresh" {
  role       = aws_iam_role.terraform_apply.name
  policy_arn = aws_iam_policy.terraform_apply_refresh.arn
}
