# Bootstrap

One-time setup that creates the remote backend used by the `infra/` workspace. Run this locally before anything else.

## What it provisions

| Resource | Name | Purpose |
|----------|------|---------|
| S3 Bucket | `project-<account_id>-<region>-an` | Stores Terraform state files |
| DynamoDB Table | `dynamodb-table1` | State locking to prevent concurrent runs |
| KMS Key | — | Encrypts S3 objects and DynamoDB data at rest |
| SNS Topic | `bucket-notifications` | Publishes notifications when objects are created under `logs/` |

## Usage

```bash
cd bootstrap
terraform init
terraform apply
```

> This directory is **not** managed by the CI/CD pipeline. Run it manually once per environment and commit the outputs to `infra/backend.tf`.

## Notes

- The S3 bucket has versioning, KMS encryption, and public access fully blocked.
- DynamoDB uses `PAY_PER_REQUEST` billing and point-in-time recovery.
- KMS key rotation is enabled.
- After applying, copy the bucket name and KMS key ID into `infra/backend.tf`.
