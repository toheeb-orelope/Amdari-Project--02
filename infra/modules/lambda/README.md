# Lambda module

## Architecture diagram

```mermaid
flowchart TB
  eb[EventBridge GuardDuty rule] --> containment[GuardDuty containment Lambda]
  sm[Secrets Manager rotation schedule] --> rotation[Secret rotation Lambda]
  containment --> dlq1[SQS DLQ]
  rotation --> dlq2[SQS DLQ]
  containment --> logs[CloudWatch Logs CMK]
  rotation --> logs
  signer[AWS Signer profile] --> csc[Lambda code signing config<br/>Enforce untrusted artifacts]
  csc --> containment
  csc --> rotation
```

This module owns Lambda functions used for security automation and secret rotation.

Why it matters:

- It supports GuardDuty containment automation.
- It supports Secrets Manager rotation handlers.
- It enforces Lambda code signing with AWS Signer when enabled.

Architecture role:

Detection invokes the containment Lambda through EventBridge. Secrets Manager invokes the rotation Lambda for configured secrets. Lambda logs are encrypted with the logging KMS key.

Security justification:

- Code signing enforces that Lambda accepts only packages signed by the trusted AWS Signer profile.
- Log groups are encrypted with a customer-managed key.
- Secrets Manager invocation permission is scoped to configured secret ARNs.

CI/CD note:

The deployment pipeline must sign Lambda zip artifacts with AWS Signer before deployment when code signing is enabled.
