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

variable "private_app_subnet_ids" {
  description = "Private application subnet IDs for ECS Fargate tasks."
  type        = list(string)

  validation {
    condition     = length(var.private_app_subnet_ids) >= 2
    error_message = "private_app_subnet_ids must include at least two subnets across AZs."
  }
}

variable "payments_security_group_id" {
  description = "Security group ID for the payments-api ECS service."
  type        = string
}

variable "kyc_security_group_id" {
  description = "Security group ID for the kyc-api ECS service."
  type        = string
}

variable "ecs_task_execution_role_arn" {
  description = "IAM role ARN used by ECS to pull images, write logs, and read startup secrets."
  type        = string
}

variable "payments_task_role_arn" {
  description = "Runtime IAM role ARN for payments-api."
  type        = string
}

variable "kyc_task_role_arn" {
  description = "Runtime IAM role ARN for kyc-api."
  type        = string
}

variable "logs_kms_key_arn" {
  description = "Customer-managed KMS key ARN used to encrypt ECS CloudWatch log groups."
  type        = string
}

variable "payments_image" {
  description = "Container image URI for payments-api. Prefer immutable image digests in CI/CD."
  type        = string
}

variable "kyc_image" {
  description = "Container image URI for kyc-api. Prefer immutable image digests in CI/CD."
  type        = string
}

variable "payments_target_group_arn" {
  description = "ALB target group ARN for payments-api."
  type        = string
}

variable "kyc_target_group_arn" {
  description = "ALB target group ARN for kyc-api."
  type        = string
}

variable "payments_desired_count" {
  type    = number
  default = 1

  validation {
    condition     = var.payments_desired_count >= 1
    error_message = "payments_desired_count must be at least 1."
  }
}

variable "kyc_desired_count" {
  type    = number
  default = 1

  validation {
    condition     = var.kyc_desired_count >= 1
    error_message = "kyc_desired_count must be at least 1."
  }
}

variable "payments_cpu" {
  description = "Fargate task CPU units for payments-api."
  type        = number
  default     = 256
}

variable "payments_memory" {
  description = "Fargate task memory MiB for payments-api."
  type        = number
  default     = 512
}

variable "kyc_cpu" {
  description = "Fargate task CPU units for kyc-api."
  type        = number
  default     = 256
}

variable "kyc_memory" {
  description = "Fargate task memory MiB for kyc-api."
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

variable "payments_secrets" {
  description = "Secrets Manager or SSM parameter ARNs exposed to payments-api by environment variable name."
  type        = map(string)
  default     = {}
}

variable "kyc_secrets" {
  description = "Secrets Manager or SSM parameter ARNs exposed to kyc-api by environment variable name."
  type        = map(string)
  default     = {}
}

variable "enable_execute_command" {
  description = "Keep false by default. Enable only for documented break-glass access."
  type        = bool
  default     = false
}

variable "platform_version" {
  description = "Fargate platform version."
  type        = string
  default     = "LATEST"
}

variable "log_retention_in_days" {
  type    = number
  default = 365
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

data "aws_region" "current" {}

locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = {
    Project            = var.project
    Environment        = var.environment
    Service            = "ecs"
    Owner              = var.owner
    CostCenter         = var.cost_center
    ManagedBy          = "terraform"
    Repository         = var.repository
    DataClassification = var.data_classification
    Criticality        = var.criticality
  }

  payments_container_name = "payments-api"
  kyc_container_name      = "kyc-api"
  payments_container_port = 8001
  kyc_container_port      = 8002

  base_environment = {
    ENVIRONMENT = var.environment
    AWS_REGION  = data.aws_region.current.region
  }

  payments_environment = merge(local.base_environment, var.payments_environment)
  kyc_environment      = merge(local.base_environment, var.kyc_environment)
}

resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cluster"
  })
}

resource "aws_cloudwatch_log_group" "payments" {
  name              = "/ecs/${local.name_prefix}/payments-api"
  retention_in_days = var.log_retention_in_days
  kms_key_id        = var.logs_kms_key_arn

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-payments-api-logs"
    Service = "payments-api"
  })
}

resource "aws_cloudwatch_log_group" "kyc" {
  name              = "/ecs/${local.name_prefix}/kyc-api"
  retention_in_days = var.log_retention_in_days
  kms_key_id        = var.logs_kms_key_arn

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-kyc-api-logs"
    Service = "kyc-api"
  })
}

resource "aws_ecs_task_definition" "payments" {
  family                   = "${local.name_prefix}-payments-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.payments_cpu)
  memory                   = tostring(var.payments_memory)
  execution_role_arn       = var.ecs_task_execution_role_arn
  task_role_arn            = var.payments_task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = local.payments_container_name
      image     = var.payments_image
      essential = true

      portMappings = [
        {
          name          = "http"
          containerPort = local.payments_container_port
          hostPort      = local.payments_container_port
          protocol      = "tcp"
          appProtocol   = "http"
        }
      ]

      environment = [for name, value in local.payments_environment : {
        name  = name
        value = value
      }]

      secrets = [for name, value_from in var.payments_secrets : {
        name      = name
        valueFrom = value_from
      }]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.payments.name
          awslogs-region        = data.aws_region.current.region
          awslogs-stream-prefix = "app"
        }
      }

      healthCheck = {
        command = [
          "CMD-SHELL",
          "python -c \"import urllib.request; urllib.request.urlopen('http://127.0.0.1:8001/health', timeout=2)\""
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 20
      }

      linuxParameters = {
        initProcessEnabled = true
        capabilities = {
          drop = ["ALL"]
        }
      }
    }
  ])

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-payments-api-task"
    Service = "payments-api"
  })
}

resource "aws_ecs_task_definition" "kyc" {
  family                   = "${local.name_prefix}-kyc-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.kyc_cpu)
  memory                   = tostring(var.kyc_memory)
  execution_role_arn       = var.ecs_task_execution_role_arn
  task_role_arn            = var.kyc_task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = local.kyc_container_name
      image     = var.kyc_image
      essential = true

      portMappings = [
        {
          name          = "http"
          containerPort = local.kyc_container_port
          hostPort      = local.kyc_container_port
          protocol      = "tcp"
          appProtocol   = "http"
        }
      ]

      environment = [for name, value in local.kyc_environment : {
        name  = name
        value = value
      }]

      secrets = [for name, value_from in var.kyc_secrets : {
        name      = name
        valueFrom = value_from
      }]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.kyc.name
          awslogs-region        = data.aws_region.current.region
          awslogs-stream-prefix = "app"
        }
      }

      healthCheck = {
        command = [
          "CMD-SHELL",
          "python -c \"import urllib.request; urllib.request.urlopen('http://127.0.0.1:8002/health', timeout=2)\""
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 20
      }

      linuxParameters = {
        initProcessEnabled = true
        capabilities = {
          drop = ["ALL"]
        }
      }
    }
  ])

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-kyc-api-task"
    Service = "kyc-api"
  })
}

resource "aws_ecs_service" "payments" {
  name             = "${local.name_prefix}-payments-api"
  cluster          = aws_ecs_cluster.main.id
  task_definition  = aws_ecs_task_definition.payments.arn
  desired_count    = var.payments_desired_count
  launch_type      = "FARGATE"
  platform_version = var.platform_version

  enable_ecs_managed_tags = true
  enable_execute_command  = var.enable_execute_command
  propagate_tags          = "SERVICE"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 60

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_app_subnet_ids
    security_groups  = [var.payments_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.payments_target_group_arn
    container_name   = local.payments_container_name
    container_port   = local.payments_container_port
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-payments-api-service"
    Service = "payments-api"
  })
}

resource "aws_ecs_service" "kyc" {
  name             = "${local.name_prefix}-kyc-api"
  cluster          = aws_ecs_cluster.main.id
  task_definition  = aws_ecs_task_definition.kyc.arn
  desired_count    = var.kyc_desired_count
  launch_type      = "FARGATE"
  platform_version = var.platform_version

  enable_ecs_managed_tags = true
  enable_execute_command  = var.enable_execute_command
  propagate_tags          = "SERVICE"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 60

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_app_subnet_ids
    security_groups  = [var.kyc_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.kyc_target_group_arn
    container_name   = local.kyc_container_name
    container_port   = local.kyc_container_port
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-kyc-api-service"
    Service = "kyc-api"
  })
}

output "cluster_id" {
  value = aws_ecs_cluster.main.id
}

output "cluster_arn" {
  value = aws_ecs_cluster.main.arn
}

output "payments_service_name" {
  value = aws_ecs_service.payments.name
}

output "payments_service_arn" {
  value = aws_ecs_service.payments.arn
}

output "payments_task_definition_arn" {
  value = aws_ecs_task_definition.payments.arn
}

output "payments_log_group_arn" {
  value = aws_cloudwatch_log_group.payments.arn
}

output "kyc_service_name" {
  value = aws_ecs_service.kyc.name
}

output "kyc_service_arn" {
  value = aws_ecs_service.kyc.arn
}

output "kyc_task_definition_arn" {
  value = aws_ecs_task_definition.kyc.arn
}

output "kyc_log_group_arn" {
  value = aws_cloudwatch_log_group.kyc.arn
}