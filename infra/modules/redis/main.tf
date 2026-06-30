variable "project" {
  type = string
}

variable "environment" {
  description = "dev, staging, or prod"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "private_data_subnet_ids" {
  description = "Private data subnet IDs for the ElastiCache subnet group."
  type        = list(string)

  validation {
    condition     = length(var.private_data_subnet_ids) >= 2
    error_message = "private_data_subnet_ids must include at least two subnets across AZs."
  }
}

variable "redis_security_group_id" {
  description = "Security group ID allowing Redis only from application service security groups."
  type        = string
}

variable "redis_kms_key_arn" {
  description = "Customer-managed KMS key ARN used to encrypt Redis at rest."
  type        = string
}

variable "logs_kms_key_arn" {
  description = "Customer-managed KMS key ARN used to encrypt Redis CloudWatch log groups."
  type        = string
}

variable "auth_token" {
  description = "Redis AUTH token. Store and rotate this in Secrets Manager; do not commit it. This sensitive input is a temporary Terraform wiring point."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.auth_token) >= 16 && length(var.auth_token) <= 128
    error_message = "auth_token must be between 16 and 128 characters."
  }
}

variable "engine_version" {
  type    = string
  default = "7.1"
}

variable "node_type" {
  type    = string
  default = "cache.t4g.micro"
}

variable "num_cache_clusters" {
  description = "Use 1 for short dev labs; use 2 or more for automatic failover/Multi-AZ."
  type        = number
  default     = 1

  validation {
    condition     = var.num_cache_clusters >= 1
    error_message = "num_cache_clusters must be at least 1."
  }
}

variable "automatic_failover_enabled" {
  description = "Requires num_cache_clusters greater than 1."
  type        = bool
  default     = false
}

variable "multi_az_enabled" {
  description = "Requires automatic failover and num_cache_clusters greater than 1."
  type        = bool
  default     = false
}

variable "snapshot_retention_limit" {
  type    = number
  default = 1
}

variable "apply_immediately" {
  description = "True is convenient for labs; false is safer for production changes."
  type        = bool
  default     = true
}

variable "owner" {
  type    = string
  default = "toheeb"
}

variable "cost_center" {
  type    = string
  default = "lab"
}

variable "repository" {
  type    = string
  default = "Amdari-Project--02"
}

variable "data_classification" {
  type    = string
  default = "confidential"
}

variable "criticality" {
  type    = string
  default = "high"
}

locals {
  replication_group_id = "${var.project}-${var.environment}-redis"

  failover_enabled = var.num_cache_clusters > 1 && var.automatic_failover_enabled
  multi_az         = var.num_cache_clusters > 1 && var.multi_az_enabled

  common_tags = {
    Project            = var.project
    Environment        = var.environment
    Service            = "redis"
    Owner              = var.owner
    CostCenter         = var.cost_center
    ManagedBy          = "terraform"
    Repository         = var.repository
    DataClassification = var.data_classification
    Criticality        = var.criticality
  }
}

resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.project}-${var.environment}-redis-subnet-group"
  subnet_ids = var.private_data_subnet_ids

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-redis-subnet-group"
  })
}

resource "aws_elasticache_parameter_group" "main" {
  name        = "${var.project}-${var.environment}-redis7-params"
  family      = "redis7"
  description = "Redis 7 parameters for ${var.project}-${var.environment}."

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-redis7-params"
  })
}

resource "aws_cloudwatch_log_group" "slow_log" {
  name              = "/aws/elasticache/${local.replication_group_id}/slow-log"
  retention_in_days = 365
  kms_key_id        = var.logs_kms_key_arn

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-redis-slow-log"
  })
}

resource "aws_cloudwatch_log_group" "engine_log" {
  name              = "/aws/elasticache/${local.replication_group_id}/engine-log"
  retention_in_days = 365
  kms_key_id        = var.logs_kms_key_arn

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-redis-engine-log"
  })
}

resource "aws_elasticache_replication_group" "main" {
  replication_group_id = local.replication_group_id
  description          = "Redis replication group for ${var.project}-${var.environment}."

  engine         = "redis"
  engine_version = var.engine_version
  node_type      = var.node_type
  port           = 6379

  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = [var.redis_security_group_id]
  parameter_group_name = aws_elasticache_parameter_group.main.name

  num_cache_clusters         = var.num_cache_clusters
  automatic_failover_enabled = local.failover_enabled
  multi_az_enabled           = local.multi_az

  at_rest_encryption_enabled = true
  kms_key_id                 = var.redis_kms_key_arn

  transit_encryption_enabled = true
  transit_encryption_mode    = "required"
  auth_token                 = var.auth_token
  auth_token_update_strategy = "SET"

  auto_minor_version_upgrade = true
  apply_immediately          = var.apply_immediately

  snapshot_retention_limit = var.snapshot_retention_limit
  snapshot_window          = "03:00-04:00"
  maintenance_window       = "sun:04:00-sun:05:00"

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.slow_log.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
  }

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.engine_log.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "engine-log"
  }

  tags = merge(local.common_tags, {
    Name = local.replication_group_id
  })
}

output "replication_group_id" {
  value = aws_elasticache_replication_group.main.id
}

output "replication_group_arn" {
  value = aws_elasticache_replication_group.main.arn
}

output "primary_endpoint_address" {
  value = aws_elasticache_replication_group.main.primary_endpoint_address
}

output "reader_endpoint_address" {
  value = aws_elasticache_replication_group.main.reader_endpoint_address
}

output "port" {
  value = aws_elasticache_replication_group.main.port
}
