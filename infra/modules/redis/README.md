# Redis module

## Architecture diagram

```mermaid
flowchart LR
  ecsSG[Application security groups] --> redisSG[Redis security group]
  redisSG --> redis[(ElastiCache Redis replication group<br/>private subnets)]
  redis --> tls[Transit encryption]
  redis --> kms[KMS Redis key<br/>at-rest encryption]
  redis --> auth[AUTH token from Secrets Manager]
  redis --> logs[Slow log + engine log<br/>CloudWatch Logs CMK]
```

This module owns the ElastiCache Redis layer.

Why it matters:

- It provides shared cache/rate-limit/session backing where needed.
- It runs in private data subnets.
- It enables encryption in transit and at rest.

Architecture role:

Application services connect to Redis privately through security groups. Redis supports app functionality such as rate limiting and transient state.

Security justification:

- Transit encryption protects cache traffic.
- At-rest encryption uses a customer-managed KMS key.
- Security groups restrict access to application tasks only.

Production note:

Avoid placing Redis auth tokens directly in Terraform state where possible. Prefer Secrets Manager and a controlled rotation workflow.
