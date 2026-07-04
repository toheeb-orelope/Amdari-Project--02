# Logging module

## Architecture diagram

```mermaid
flowchart TB
  ct[CloudTrail org trail] --> ctbucket[CloudTrail log bucket<br/>Object Lock + CMK]
  ct --> cwlogs[CloudWatch log group<br/>CMK encrypted]
  s3[S3 buckets] --> access[S3 access-log bucket]
  vpc[VPC Flow Logs] --> cwlogs
  cfg[AWS Config] --> cfgbucket[Config log bucket]
  ctbucket --> kms[KMS logs key]
  cwlogs --> kms
  access --> kms
  cfgbucket --> kms
```

This module owns audit and security log storage.

Why it matters:

- It creates CloudTrail logging with validation and encryption.
- It provides hardened S3 buckets for audit logs and access logs.
- It provides encrypted CloudWatch log groups and IAM permissions for log delivery.

Architecture role:

AWS services deliver audit and access logs into this module’s storage. Detection and monitoring modules depend on this evidence for investigation and response.

Security justification:

- CloudTrail log file validation protects audit integrity.
- Object Lock and versioning improve tamper resistance.
- KMS encryption protects stored logs.
- S3 public access blocks reduce accidental exposure.
