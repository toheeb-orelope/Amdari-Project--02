# Environment Naming

| Environment | Name | Purpose |
|---|---|---|
| Development | sentinelpay-dev | Local and early development testing |
| Staging | sentinelpay-staging | Pre-production validation, DAST, pipeline testing |
| Production Replica | sentinelpay-prod-replica | Hardened production-like environment using synthetic data |

## Naming Convention

All cloud resources will follow:

`sentinelpay-<environment>-<service>-<resource>`

Examples:

- sentinelpay-dev-payments-api
- sentinelpay-staging-kyc-api
- sentinelpay-prod-replica-rds
- sentinelpay-prod-replica-waf
- sentinelpay-prod-replica-cloudtrail