# CI/CD OIDC module

This module should own GitHub Actions to AWS federation using OpenID Connect.

What belongs here:

- GitHub OIDC provider, if it is not managed elsewhere in the account.
- IAM role trusted by GitHub Actions OIDC.
- Trust policy scoped to the repository, branch/environment, and workflow context.
- Least-privilege deployment policy for Terraform plan/apply, image publishing, and Lambda artifact signing.
- Optional separation between read-only plan role and apply/deploy role.

Why it matters:

- It satisfies the constraint that GitHub Actions must authenticate to AWS via OIDC federation.
- It avoids long-lived AWS access keys in GitHub secrets.
- It lets AWS issue short-lived credentials only to approved workflows.

Architecture role:

GitHub Actions assumes a short-lived AWS role through OIDC, then deploys infrastructure, pushes container images, and signs Lambda zip artifacts using AWS Signer.

Security justification:

- No static AWS keys are stored in GitHub.
- Trust can be restricted by repository, branch, environment, and audience.
- Production can require GitHub environment approvals before the deploy role is assumable.

Implementation note:

This module is intentionally separate from the general IAM module because CI/CD trust boundaries are different from runtime task-role permissions.
