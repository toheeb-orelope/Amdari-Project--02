# Honeytoken module

This module creates the detection wiring for a decoy credential.

Why it matters:

- It supports the requirement to deploy a honeytoken and alarm when it is used.
- It creates a decoy IAM identity and alerting path without storing secret access keys in Terraform state.

Architecture role:

The module creates a decoy IAM user, a decoy Secrets Manager location, and EventBridge/SNS alerting for use of a supplied honeytoken access key ID.

Security justification:

- Terraform does not create `aws_iam_access_key`, because that would store secret key material in state.
- The decoy IAM user is denied access.
- Any use of the honeytoken is suspicious and should trigger an alert.

Operational note:

Create the actual decoy access key outside Terraform using a controlled one-time process, then pass only the access key ID into this module.

Deployment note:

To satisfy the honeytoken constraint, create the real decoy access key outside Terraform, store the decoy credential value in the decoy Secrets Manager secret, pass only the access key ID to this module, and expose the decoy secret to application tasks as `DECOY_AWS_CREDENTIALS`. Terraform intentionally does not create `aws_iam_access_key` because that would store secret key material in state.
