data "aws_iam_policy_document" "terraform_apply_identity_management" {
  statement {
    sid    = "AllowProjectIamManagement"
    effect = "Allow"

    actions = [
      "iam:AddUserToGroup",
      "iam:AttachRolePolicy",
      "iam:CreateAccessKey",
      "iam:CreatePolicy",
      "iam:CreatePolicyVersion",
      "iam:CreateRole",
      "iam:CreateUser",
      "iam:DeleteAccessKey",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:DeleteUser",
      "iam:DetachRolePolicy",
      "iam:GetAccessKeyLastUsed",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:GetUser",
      "iam:GetUserPolicy",
      "iam:ListAccessKeys",
      "iam:ListAttachedRolePolicies",
      "iam:ListGroupsForUser",
      "iam:ListInstanceProfilesForRole",
      "iam:ListPolicyVersions",
      "iam:ListRolePolicies",
      "iam:ListUserPolicies",
      "iam:PassRole",
      "iam:PutRolePolicy",
      "iam:PutUserPolicy",
      "iam:RemoveUserFromGroup",
      "iam:SetDefaultPolicyVersion",
      "iam:TagPolicy",
      "iam:TagRole",
      "iam:TagUser",
      "iam:UntagPolicy",
      "iam:UntagRole",
      "iam:UntagUser",
      "iam:UpdateAssumeRolePolicy",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription"
    ]

    resources = [
      format("arn:%s:iam::%s:policy/%s-*", data.aws_partition.current.partition, data.aws_caller_identity.current.account_id, local.name_prefix),
      format("arn:%s:iam::%s:role/%s-*", data.aws_partition.current.partition, data.aws_caller_identity.current.account_id, local.name_prefix),
      format("arn:%s:iam::%s:user/%s-*", data.aws_partition.current.partition, data.aws_caller_identity.current.account_id, local.name_prefix)
    ]
  }

  statement {
    sid    = "AllowSecurityServiceLinkedRoles"
    effect = "Allow"

    actions = [
      "iam:CreateServiceLinkedRole"
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values = [
        "config.amazonaws.com",
        "elasticloadbalancing.amazonaws.com",
        "ecs.amazonaws.com",
        "elasticache.amazonaws.com",
        "guardduty.amazonaws.com",
        "securityhub.amazonaws.com"
      ]
    }
  }
}

resource "aws_iam_policy" "terraform_apply_identity_management" {
  name        = format("%s-github-terraform-apply-identity-management", local.name_prefix)
  description = "Allow Terraform apply to manage project IAM roles, policies, honeytoken user, and required service-linked roles."
  policy      = data.aws_iam_policy_document.terraform_apply_identity_management.json

  tags = merge(local.common_tags, {
    Name = format("%s-github-terraform-apply-identity-management", local.name_prefix)
  })
}

resource "aws_iam_role_policy_attachment" "terraform_apply_identity_management" {
  role       = aws_iam_role.terraform_apply.name
  policy_arn = aws_iam_policy.terraform_apply_identity_management.arn
}

