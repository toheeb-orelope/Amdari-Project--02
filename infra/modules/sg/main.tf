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

variable "vpc_id" {
  description = "VPC ID where security groups are created."
  type        = string
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
  default = "internal"
}

variable "criticality" {
  type    = string
  default = "high"
}

locals {
  common_tags = {
    Project            = var.project
    Environment        = var.environment
    Service            = "security-groups"
    Owner              = var.owner
    CostCenter         = var.cost_center
    ManagedBy          = "terraform"
    Repository         = var.repository
    DataClassification = var.data_classification
    Criticality        = var.criticality
  }
}

resource "aws_security_group" "alb" {
  name        = "${var.project}-${var.environment}-alb-sg"
  description = "Allow public HTTPS ingress to the application load balancer."
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name    = "${var.project}-${var.environment}-alb-sg"
    Service = "alb"
  })
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "Allow public HTTPS to ALB; WAF is attached at Layer 7."
}

resource "aws_vpc_security_group_ingress_rule" "alb_http_redirect" {
  #checkov:skip=CKV_AWS_260:Port 80 is open only on the ALB to redirect HTTP to HTTPS; application compute remains private.
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  description       = "Allow HTTP only for redirect to HTTPS at ALB."
}

resource "aws_vpc_security_group_egress_rule" "alb_to_payments" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.payments_service.id
  from_port                    = 8001
  to_port                      = 8001
  ip_protocol                  = "tcp"
  description                  = "Allow ALB to reach payments-api tasks."
}

resource "aws_vpc_security_group_egress_rule" "alb_to_kyc" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.kyc_service.id
  from_port                    = 8002
  to_port                      = 8002
  ip_protocol                  = "tcp"
  description                  = "Allow ALB to reach kyc-api tasks."
}

resource "aws_security_group" "payments_service" {
  name        = "${var.project}-${var.environment}-payments-service-sg"
  description = "Allow only ALB ingress to payments-api ECS tasks."
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name    = "${var.project}-${var.environment}-payments-service-sg"
    Service = "payments-api"
  })
}

resource "aws_vpc_security_group_ingress_rule" "payments_from_alb" {
  security_group_id            = aws_security_group.payments_service.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 8001
  to_port                      = 8001
  ip_protocol                  = "tcp"
  description                  = "Allow payments-api traffic only from ALB."
}

resource "aws_vpc_security_group_egress_rule" "payments_to_rds" {
  security_group_id            = aws_security_group.payments_service.id
  referenced_security_group_id = aws_security_group.rds.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "Allow payments-api to reach PostgreSQL."
}

resource "aws_vpc_security_group_egress_rule" "payments_to_redis" {
  security_group_id            = aws_security_group.payments_service.id
  referenced_security_group_id = aws_security_group.redis.id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
  description                  = "Allow payments-api to reach Redis."
}

resource "aws_vpc_security_group_egress_rule" "payments_https_aws_services" {
  security_group_id = aws_security_group.payments_service.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "Allow payments-api HTTPS egress to AWS APIs through VPC endpoints or NAT."
}

resource "aws_security_group" "kyc_service" {
  name        = "${var.project}-${var.environment}-kyc-service-sg"
  description = "Allow only ALB ingress to kyc-api ECS tasks."
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name    = "${var.project}-${var.environment}-kyc-service-sg"
    Service = "kyc-api"
  })
}

resource "aws_vpc_security_group_ingress_rule" "kyc_from_alb" {
  security_group_id            = aws_security_group.kyc_service.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 8002
  to_port                      = 8002
  ip_protocol                  = "tcp"
  description                  = "Allow kyc-api traffic only from ALB."
}

resource "aws_vpc_security_group_egress_rule" "kyc_to_rds" {
  security_group_id            = aws_security_group.kyc_service.id
  referenced_security_group_id = aws_security_group.rds.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "Allow kyc-api to reach PostgreSQL."
}

resource "aws_vpc_security_group_egress_rule" "kyc_to_redis" {
  security_group_id            = aws_security_group.kyc_service.id
  referenced_security_group_id = aws_security_group.redis.id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
  description                  = "Allow kyc-api to reach Redis."
}

resource "aws_vpc_security_group_egress_rule" "kyc_https_aws_services" {
  security_group_id = aws_security_group.kyc_service.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "Allow kyc-api HTTPS egress to AWS APIs and BVN provider through VPC endpoints or NAT."
}

resource "aws_security_group" "rds" {
  name        = "${var.project}-${var.environment}-rds-sg"
  description = "Allow PostgreSQL only from application ECS task security groups."
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name    = "${var.project}-${var.environment}-rds-sg"
    Service = "rds"
  })
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_payments" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.payments_service.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "Allow PostgreSQL from payments-api SG only."
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_kyc" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.kyc_service.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "Allow PostgreSQL from kyc-api SG only."
}

resource "aws_security_group" "redis" {
  name        = "${var.project}-${var.environment}-redis-sg"
  description = "Allow Redis only from application ECS task security groups."
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name    = "${var.project}-${var.environment}-redis-sg"
    Service = "redis"
  })
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_payments" {
  security_group_id            = aws_security_group.redis.id
  referenced_security_group_id = aws_security_group.payments_service.id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
  description                  = "Allow Redis from payments-api SG only."
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_kyc" {
  security_group_id            = aws_security_group.redis.id
  referenced_security_group_id = aws_security_group.kyc_service.id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
  description                  = "Allow Redis from kyc-api SG only."
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "payments_service_security_group_id" {
  value = aws_security_group.payments_service.id
}

output "kyc_service_security_group_id" {
  value = aws_security_group.kyc_service.id
}

output "rds_security_group_id" {
  value = aws_security_group.rds.id
}

output "redis_security_group_id" {
  value = aws_security_group.redis.id
}
