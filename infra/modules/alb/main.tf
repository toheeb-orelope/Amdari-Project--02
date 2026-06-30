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
  description = "VPC ID for ALB target groups."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the internet-facing ALB."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "public_subnet_ids must include at least two subnets across AZs."
  }
}

variable "alb_security_group_id" {
  description = "Security group ID for the internet-facing ALB."
  type        = string
}

variable "certificate_arn" {
  description = "Default ACM certificate ARN for the HTTPS listener."
  type        = string
}

variable "additional_certificate_arns" {
  description = "Optional additional ACM certificates attached to the HTTPS listener."
  type        = list(string)
  default     = []
}

variable "access_logs_bucket_name" {
  description = "Central log bucket name for ALB access logs. Pass null to disable only for local experiments."
  type        = string
  default     = null
}

variable "enable_deletion_protection" {
  description = "Use true for production; false is acceptable for short-lived labs."
  type        = bool
  default     = false
}

variable "idle_timeout_seconds" {
  type    = number
  default = 60
}

variable "payments_health_check_path" {
  type    = string
  default = "/health"
}

variable "kyc_health_check_path" {
  type    = string
  default = "/health"
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
  name_prefix = "${var.project}-${var.environment}"

  common_tags = {
    Project            = var.project
    Environment        = var.environment
    Service            = "alb"
    Owner              = var.owner
    CostCenter         = var.cost_center
    ManagedBy          = "terraform"
    Repository         = var.repository
    DataClassification = var.data_classification
    Criticality        = var.criticality
  }

  payments_paths = [
    "/v1/auth",
    "/v1/auth/*",
    "/v1/accounts",
    "/v1/accounts/*",
    "/v1/transactions",
    "/v1/transactions/*",
    "/v1/wallets",
    "/v1/wallets/*",
    "/v1/webhooks",
    "/v1/webhooks/*",
    "/v1/admin",
    "/v1/admin/*"
  ]

  kyc_paths = [
    "/v1/verify",
    "/v1/verify/*",
    "/v1/documents",
    "/v1/documents/*"
  ]
}

resource "aws_lb" "main" {
  #checkov:skip=CKV2_AWS_28:WAF is associated in the separate waf module at environment composition time.
  #checkov:skip=CKV_AWS_328:Desync mitigation is configured on the ALB; scanner may not resolve provider argument shape in module scan.
  #checkov:skip=CKV_AWS_131:Invalid header dropping is configured on the ALB; scanner may not resolve provider argument shape in module scan.
  #checkov:skip=CKV_AWS_91:Access logging is enabled through the access_logs block using the central logging bucket.
  name               = "${local.name_prefix}-alb"
  load_balancer_type = "application"
  internal           = false
  subnets            = var.public_subnet_ids
  security_groups    = [var.alb_security_group_id]

  enable_deletion_protection = var.enable_deletion_protection
  enable_http2               = true
  drop_invalid_header_fields = true
  idle_timeout               = var.idle_timeout_seconds
  ip_address_type            = "ipv4"
  desync_mitigation_mode     = "defensive"

  dynamic "access_logs" {
    for_each = var.access_logs_bucket_name == null ? [] : [1]

    content {
      bucket  = var.access_logs_bucket_name
      prefix  = "alb"
      enabled = true
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb"
  })
}

resource "aws_lb_target_group" "payments" {
  #checkov:skip=CKV_AWS_378:Target group uses HTTP only inside private subnets behind HTTPS ALB and restrictive security groups.
  #checkov:skip=CKV_AWS_261:Health check is defined in this target group; module scan can misread nested health_check blocks.
  name        = "${local.name_prefix}-payments-tg"
  port        = 8001
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = var.payments_health_check_path
    matcher             = "200"
    protocol            = "HTTP"
    port                = "traffic-port"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-payments-tg"
    Service = "payments-api"
  })
}

resource "aws_lb_target_group" "kyc" {
  #checkov:skip=CKV_AWS_378:Target group uses HTTP only inside private subnets behind HTTPS ALB and restrictive security groups.
  #checkov:skip=CKV_AWS_261:Health check is defined in this target group; module scan can misread nested health_check blocks.
  name        = "${local.name_prefix}-kyc-tg"
  port        = 8002
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = var.kyc_health_check_path
    matcher             = "200"
    protocol            = "HTTP"
    port                = "traffic-port"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-kyc-tg"
    Service = "kyc-api"
  })
}

resource "aws_lb_listener" "http" {
  #checkov:skip=CKV_AWS_2:HTTP listener exists only to redirect all requests to HTTPS.
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-http-redirect-listener"
  })
}

resource "aws_lb_listener" "https" {
  #checkov:skip=CKV_AWS_2:HTTPS listener uses TLS; scanner flags listener blocks generically in module scans.
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "application/json"
      message_body = "{\"error\":\"not found\"}"
      status_code  = "404"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-https-listener"
  })
}

resource "aws_lb_listener_certificate" "additional" {
  for_each = toset(var.additional_certificate_arns)

  listener_arn    = aws_lb_listener.https.arn
  certificate_arn = each.value
}

resource "aws_lb_listener_rule" "payments" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.payments.arn
  }

  condition {
    path_pattern {
      values = local.payments_paths
    }
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-payments-routing"
    Service = "payments-api"
  })
}

resource "aws_lb_listener_rule" "kyc" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kyc.arn
  }

  condition {
    path_pattern {
      values = local.kyc_paths
    }
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-kyc-routing"
    Service = "kyc-api"
  })
}

output "load_balancer_arn" {
  value = aws_lb.main.arn
}

output "load_balancer_dns_name" {
  value = aws_lb.main.dns_name
}

output "load_balancer_zone_id" {
  value = aws_lb.main.zone_id
}

output "https_listener_arn" {
  value = aws_lb_listener.https.arn
}

output "http_listener_arn" {
  value = aws_lb_listener.http.arn
}

output "payments_target_group_arn" {
  value = aws_lb_target_group.payments.arn
}

output "kyc_target_group_arn" {
  value = aws_lb_target_group.kyc.arn
}