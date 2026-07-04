# KMS module

## Architecture diagram

```mermaid
flowchart TB
  admins[Key administrators] --> policies[KMS key policies]
  users[Key users / AWS services] --> policies
  policies --> logs[KMS logs key]
  policies --> secrets[KMS secrets key]
  policies --> s3[KMS S3 key]
  policies --> rds[KMS RDS key]
  policies --> redis[KMS Redis key]
  policies --> ecs[KMS ECS/logs key]
  cw[CloudWatch Logs] --> logs
  ct[CloudTrail / Config] --> logs
  sm[Secrets Manager] --> secrets
  buckets[S3 buckets] --> s3
  db[RDS PostgreSQL] --> rds
  cache[ElastiCache Redis] --> redis
```

This module creates customer-managed KMS keys for project encryption domains.

Why it matters:

- It satisfies the requirement that RDS, ElastiCache, S3, logs, secrets, and ECS-related encrypted data use customer-managed keys.
- It separates encryption purposes so access can be reasoned about and audited.

Architecture role:

Other modules receive KMS key ARNs from this module and use them for storage encryption, log encryption, secret encryption, and service-specific encryption.

Security justification:

- Customer-managed keys provide stronger policy control than AWS-managed keys.
- Separate keys reduce blast radius.
- Key rotation supports long-term cryptographic hygiene.

Production note:

Key policies should maintain separation between principals that administer keys and principals that only use keys for encryption/decryption.
