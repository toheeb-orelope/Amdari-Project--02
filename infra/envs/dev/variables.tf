variable "aws_region" {
  description = "AWS region for the dev environment."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name used for resource naming and tagging."
  type        = string
  default     = "sentinelpay"
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Owner tag for dev resources."
  type        = string
  default     = "platform-security"
}

variable "cost_center" {
  description = "Cost center tag for dev resources."
  type        = string
  default     = "lab"
}

variable "repository" {
  description = "Source repository tag."
  type        = string
  default     = "Amdari-Project--02"
}

variable "data_classification" {
  description = "Default data classification tag for dev resources."
  type        = string
  default     = "confidential"
}

variable "criticality" {
  description = "Default criticality tag for dev resources."
  type        = string
  default     = "medium"
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the ALB HTTPS listener. Required when deploying ALB HTTPS."
  type        = string
  default     = null
}

variable "enable_route53" {
  description = "Enable Route 53 delegated subdomain DNS for dev. Keep false until the subdomain is delegated and ACM is ready."
  type        = bool
  default     = false
}
variable "domain_name" {
  description = "Optional Route 53 hosted zone domain name for dev. Leave null to skip Route 53 wiring."
  type        = string
  default     = null
}

variable "record_names" {
  description = "DNS record names to point at the ALB when Route 53 is enabled."
  type        = list(string)
  default     = []
}

variable "force_destroy_route53_zone" {
  description = "Allow Terraform to destroy the dev hosted zone and records. Useful for lab teardown."
  type        = bool
  default     = true
}

variable "payments_image" {
  description = "Container image URI for payments-api."
  type        = string
}

variable "kyc_image" {
  description = "Container image URI for kyc-api."
  type        = string
}

variable "payments_desired_count" {
  description = "Desired ECS task count for payments-api in dev."
  type        = number
  default     = 1
}

variable "kyc_desired_count" {
  description = "Desired ECS task count for kyc-api in dev."
  type        = number
  default     = 1
}

variable "payments_cpu" {
  description = "CPU units for the payments-api Fargate task."
  type        = number
  default     = 256
}

variable "payments_memory" {
  description = "Memory in MiB for the payments-api Fargate task."
  type        = number
  default     = 512
}

variable "kyc_cpu" {
  description = "CPU units for the kyc-api Fargate task."
  type        = number
  default     = 256
}

variable "kyc_memory" {
  description = "Memory in MiB for the kyc-api Fargate task."
  type        = number
  default     = 512
}

variable "payments_environment" {
  description = "Non-secret environment variables for payments-api."
  type        = map(string)
  default     = {}
}

variable "kyc_environment" {
  description = "Non-secret environment variables for kyc-api."
  type        = map(string)
  default     = {}
}

variable "redis_auth_token" {
  description = "Redis AUTH token for dev. Prefer supplying via TF_VAR_redis_auth_token or a secure tfvars file that is not committed."
  type        = string
  sensitive   = true
}

variable "database_name" {
  description = "PostgreSQL database name."
  type        = string
  default     = "sentinelpay"
}

variable "database_master_username" {
  description = "RDS master username. Password is managed by RDS/Secrets Manager, not Terraform."
  type        = string
  default     = "sentinel_admin"
}

variable "rds_instance_class" {
  description = "RDS instance class for dev."
  type        = string
  default     = "db.t3.micro"
}

variable "rds_allocated_storage" {
  description = "Initial RDS storage in GiB for dev."
  type        = number
  default     = 20
}

variable "rds_max_allocated_storage" {
  description = "Maximum autoscaled RDS storage in GiB for dev."
  type        = number
  default     = 100
}

variable "rds_multi_az" {
  description = "Enable RDS Multi-AZ for dev."
  type        = bool
  default     = true
}

variable "rds_deletion_protection" {
  description = "Enable RDS deletion protection. Set false only for explicit teardown windows."
  type        = bool
  default     = true
}

variable "rds_monitoring_interval" {
  description = "RDS Enhanced Monitoring interval in seconds."
  type        = number
  default     = 60
}

variable "redis_node_type" {
  description = "ElastiCache Redis node type for dev."
  type        = string
  default     = "cache.t4g.micro"
}

variable "redis_num_cache_clusters" {
  description = "Number of Redis cache clusters for dev."
  type        = number
  default     = 1
}

variable "redis_multi_az_enabled" {
  description = "Enable Redis Multi-AZ for dev."
  type        = bool
  default     = false
}

variable "redis_automatic_failover_enabled" {
  description = "Enable Redis automatic failover for dev."
  type        = bool
  default     = false
}

variable "enable_ecs_execute_command" {
  description = "Enable ECS Exec. Keep false unless using documented break-glass access."
  type        = bool
  default     = false
}

variable "enable_organization_trail" {
  description = "Create an organization CloudTrail. Requires AWS Organizations permissions."
  type        = bool
  default     = false
}

variable "alert_email_endpoints" {
  description = "Email addresses subscribed to monitoring and honeytoken alerts."
  type        = list(string)
  default     = []
}

variable "honeytoken_access_key_id" {
  description = "Externally-created honeytoken access key ID to alarm on. Do not create/store the secret access key in Terraform."
  type        = string
  default     = null
}

variable "containment_package_path" {
  description = "Path to zipped GuardDuty containment Lambda package. Leave null until the artifact exists."
  type        = string
  default     = null
}

variable "rotation_package_path" {
  description = "Path to zipped Secrets Manager rotation Lambda package. Leave null until the artifact exists."
  type        = string
  default     = null
}

variable "enable_lambda_code_signing" {
  description = "Enable AWS Signer-backed Lambda code signing."
  type        = bool
  default     = true
}

variable "github_oidc_provider_arn" {
  description = "Existing account-level GitHub Actions OIDC provider ARN."
  type        = string
  default     = "arn:aws:iam::363238514491:oidc-provider/token.actions.githubusercontent.com"
}

variable "github_owner" {
  description = "GitHub owner or organization."
  type        = string
  default     = "toheeb-orelope"
}

variable "github_repo" {
  description = "GitHub repository name."
  type        = string
  default     = "Amdari-Project--02"
}

variable "github_dev_branch" {
  description = "Git branch allowed to deploy the dev environment."
  type        = string
  default     = "dev"
}

variable "terraform_state_bucket_arn" {
  description = "Terraform remote state S3 bucket ARN for CI/CD permissions."
  type        = string
  default     = null
}

variable "terraform_lock_table_arn" {
  description = "Terraform state lock DynamoDB table ARN for CI/CD permissions."
  type        = string
  default     = null
}

variable "terraform_state_kms_key_arn" {
  description = "KMS key ARN used by the Terraform remote state bucket for CI/CD permissions."
  type        = string
  default     = null
}

variable "terraform_apply_policy_arns" {
  description = "Least-privilege policy ARNs attached to the GitHub Terraform apply role."
  type        = list(string)
  default     = []
}

variable "ecr_repository_arns" {
  description = "ECR repository ARNs GitHub Actions may push images to."
  type        = list(string)
  default     = []
}

variable "blocked_country_codes" {
  description = "Optional ISO country codes blocked by WAF."
  type        = list(string)
  default     = []
}

variable "payments_rate_limit" {
  description = "WAF request limit per five-minute window for payment paths."
  type        = number
  default     = 1000
}

