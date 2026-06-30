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
  description = "Private data subnet IDs for the RDS subnet group."
  type        = list(string)

  validation {
    condition     = length(var.private_data_subnet_ids) >= 2
    error_message = "private_data_subnet_ids must include at least two subnets across AZs."
  }
}

variable "rds_security_group_id" {
  description = "Security group ID allowing PostgreSQL only from application service security groups."
  type        = string
}

variable "rds_kms_key_arn" {
  description = "Customer-managed KMS key ARN used to encrypt RDS storage and Performance Insights."
  type        = string
}

variable "secrets_kms_key_id" {
  description = "Customer-managed KMS key ID or ARN used by RDS managed master user secret."
  type        = string
}

variable "database_name" {
  type    = string
  default = "sentinelpay"
}

variable "master_username" {
  description = "RDS master username."
  type        = string
}

variable "engine_version" {
  type    = string
  default = "15.10"
}

variable "instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "max_allocated_storage" {
  type    = number
  default = 100
}

variable "backup_retention_period" {
  type    = number
  default = 7
}

variable "multi_az" {
  description = "Enable Multi-AZ for production. Can be false for short-lived dev labs."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Enable for production; keep false for short-lived lab teardown."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Use false for production; true is acceptable for short-lived lab teardown."
  type        = bool
  default     = true
}

variable "monitoring_interval" {
  description = "Enhanced Monitoring interval in seconds. Set to 0 to disable."
  type        = number
  default     = 60
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
  common_tags = {
    Project            = var.project
    Environment        = var.environment
    Service            = "rds"
    Owner              = var.owner
    CostCenter         = var.cost_center
    ManagedBy          = "terraform"
    Repository         = var.repository
    DataClassification = var.data_classification
    Criticality        = var.criticality
  }
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-${var.environment}-postgres-subnet-group"
  subnet_ids = var.private_data_subnet_ids

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-postgres-subnet-group"
  })
}

resource "aws_db_parameter_group" "main" {
  name_prefix = "${var.project}-${var.environment}-postgres15-"
  family      = "postgres15"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-postgres-parameter-group"
  })
}


data "aws_iam_policy_document" "enhanced_monitoring_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "enhanced_monitoring" {
  name               = "${var.project}-${var.environment}-rds-enhanced-monitoring-role"
  assume_role_policy = data.aws_iam_policy_document.enhanced_monitoring_assume_role.json

  tags = merge(local.common_tags, {
    Name    = "${var.project}-${var.environment}-rds-enhanced-monitoring-role"
    Service = "rds"
  })
}

resource "aws_iam_role_policy_attachment" "enhanced_monitoring" {
  role       = aws_iam_role.enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_db_instance" "main" {
  identifier = "${var.project}-${var.environment}-postgres"

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = var.database_name
  username = var.master_username

  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.secrets_kms_key_id

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.rds_kms_key_arn

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_security_group_id]
  publicly_accessible    = false

  parameter_group_name = aws_db_parameter_group.main.name

  backup_retention_period  = var.backup_retention_period
  copy_tags_to_snapshot    = true
  delete_automated_backups = true
  deletion_protection      = var.deletion_protection
  skip_final_snapshot      = var.skip_final_snapshot

  auto_minor_version_upgrade = true
  multi_az                   = var.multi_az

  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql", "upgrade"]

  performance_insights_enabled    = true
  performance_insights_kms_key_id = var.rds_kms_key_arn
  monitoring_interval             = var.monitoring_interval
  monitoring_role_arn             = var.monitoring_interval == 0 ? null : aws_iam_role.enhanced_monitoring.arn

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-postgres"
  })
}

output "db_instance_id" {
  value = aws_db_instance.main.id
}

output "db_instance_arn" {
  value = aws_db_instance.main.arn
}

output "db_endpoint" {
  value = aws_db_instance.main.endpoint
}

output "db_address" {
  value = aws_db_instance.main.address
}

output "db_port" {
  value = aws_db_instance.main.port
}

output "db_name" {
  value = aws_db_instance.main.db_name
}

output "master_user_secret_arn" {
  value = aws_db_instance.main.master_user_secret[0].secret_arn
}
