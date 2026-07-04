# RDS module

## Architecture diagram

```mermaid
flowchart LR
  ecsSG[Application security groups] --> rdsSG[RDS security group]
  rdsSG --> pg[(PostgreSQL RDS<br/>private subnets only)]
  pg --> subnet[RDS subnet group<br/>data subnets across AZs]
  pg --> kms[KMS RDS key]
  pg --> logs[CloudWatch PostgreSQL logs]
  pg --> sm[Managed master user secret<br/>Secrets Manager + CMK]
  monitor[Enhanced monitoring role] --> pg
```

This module owns the PostgreSQL database layer.

Why it matters:

- It provisions PostgreSQL in private data subnets only.
- It encrypts storage and performance insights with customer-managed KMS.
- It enables IAM database authentication and CloudWatch log exports.

Architecture role:

Payments and KYC services access PostgreSQL through security group references, not public endpoints or CIDR-wide access.

Security justification:

- `publicly_accessible = false` keeps the database private.
- Security group references restrict ingress to application security groups.
- RDS-managed master password support avoids storing database credentials directly in Terraform variables.
- Logging supports audit and investigation.
