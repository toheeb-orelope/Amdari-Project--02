provider "aws" {
  #checkov:skip=CKV_AWS_41:Provider config contains region/default tags only; no hard-coded AWS credentials.
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = {
    Project            = var.project
    Environment        = var.environment
    Owner              = var.owner
    CostCenter         = var.cost_center
    ManagedBy          = "terraform"
    Repository         = var.repository
    DataClassification = var.data_classification
    Criticality        = var.criticality
  }

  ecs_log_group_arns = [
    "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/${local.name_prefix}/payments-api",
    "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/${local.name_prefix}/kyc-api"
  ]

  payments_secret_arns = [
    module.secrets.secret_arns["jwt_secret"],
    module.secrets.secret_arns["payments_session_secret"],
    module.secrets.secret_arns["database_credentials"],
    module.secrets.secret_arns["redis_auth_token"],
    module.secrets.secret_arns["webhook_signing_secret"],
    module.honeytoken.decoy_secret_arn
  ]

  kyc_secret_arns = [
    module.secrets.secret_arns["jwt_secret"],
    module.secrets.secret_arns["database_credentials"],
    module.secrets.secret_arns["redis_auth_token"],
    module.secrets.secret_arns["bvn_provider_credentials"],
    module.honeytoken.decoy_secret_arn
  ]

  payments_environment = merge(var.payments_environment, {
    DB_HOST     = module.rds.db_address
    DB_PORT     = tostring(module.rds.db_port)
    DB_NAME     = module.rds.db_name
    REDIS_HOST  = module.redis.primary_endpoint_address
    REDIS_PORT  = tostring(module.redis.port)
    KYC_API_URL = "http://placeholder-private-service.local"
  })

  kyc_environment = merge(var.kyc_environment, {
    DB_HOST              = module.rds.db_address
    DB_PORT              = tostring(module.rds.db_port)
    DB_NAME              = module.rds.db_name
    REDIS_HOST           = module.redis.primary_endpoint_address
    REDIS_PORT           = tostring(module.redis.port)
    KYC_DOCUMENTS_BUCKET = module.s3.kyc_bucket_name
  })

  payments_secrets = {
    JWT_SECRET             = module.secrets.secret_arns["jwt_secret"]
    SECRET_KEY             = module.secrets.secret_arns["payments_session_secret"]
    DATABASE_CREDENTIALS   = module.rds.master_user_secret_arn
    REDIS_AUTH_TOKEN       = module.secrets.secret_arns["redis_auth_token"]
    WEBHOOK_SIGNING_SECRET = module.secrets.secret_arns["webhook_signing_secret"]
    DECOY_AWS_CREDENTIALS  = module.honeytoken.decoy_secret_arn
  }

  kyc_secrets = {
    JWT_SECRET               = module.secrets.secret_arns["jwt_secret"]
    DATABASE_CREDENTIALS     = module.rds.master_user_secret_arn
    REDIS_AUTH_TOKEN         = module.secrets.secret_arns["redis_auth_token"]
    BVN_PROVIDER_CREDENTIALS = module.secrets.secret_arns["bvn_provider_credentials"]
    DECOY_AWS_CREDENTIALS    = module.honeytoken.decoy_secret_arn
  }

  alb_arn_suffix   = regex("loadbalancer/(.*)$", module.alb.load_balancer_arn)[0]
  waf_web_acl_name = "${local.name_prefix}-web-acl"

  lambda_rotation_secret_ids = var.rotation_package_path == null ? {} : module.secrets.secret_arns
}

module "kms" {
  source = "../../modules/kms"

  project             = var.project
  environment         = var.environment
  owner               = var.owner
  cost_center         = var.cost_center
  repository          = var.repository
  data_classification = var.data_classification
  criticality         = var.criticality
}

module "network" {
  source = "../../modules/network"

  project             = var.project
  environment         = var.environment
  logs_kms_key_arn    = module.kms.key_arns["logs"]
  owner               = var.owner
  cost_center         = var.cost_center
  repository          = var.repository
  data_classification = var.data_classification
  criticality         = var.criticality
}

module "sg" {
  source = "../../modules/sg"

  project             = var.project
  environment         = var.environment
  vpc_id              = module.network.vpc_id
  owner               = var.owner
  cost_center         = var.cost_center
  repository          = var.repository
  data_classification = var.data_classification
  criticality         = var.criticality
}

module "logging" {
  source = "../../modules/logging"

  project                   = var.project
  environment               = var.environment
  logs_kms_key_arn          = module.kms.key_arns["logs"]
  enable_organization_trail = var.enable_organization_trail
  owner                     = var.owner
  cost_center               = var.cost_center
  repository                = var.repository
  data_classification       = var.data_classification
  criticality               = var.criticality
}

module "secrets" {
  source = "../../modules/secrets"

  project             = var.project
  environment         = var.environment
  secrets_kms_key_arn = module.kms.key_arns["secrets"]
  owner               = var.owner
  cost_center         = var.cost_center
  repository          = var.repository
  data_classification = var.data_classification
  criticality         = var.criticality
}

module "s3" {
  source = "../../modules/s3"

  project                = var.project
  environment            = var.environment
  s3_kms_key_arn         = module.kms.key_arns["s3"]
  access_log_bucket_name = module.logging.s3_access_log_bucket_name
  owner                  = var.owner
  cost_center            = var.cost_center
  repository             = var.repository
  data_classification    = var.data_classification
  criticality            = var.criticality
}

module "rds" {
  source = "../../modules/rds"

  project                 = var.project
  environment             = var.environment
  private_data_subnet_ids = module.network.private_data_subnet_ids
  rds_security_group_id   = module.sg.rds_security_group_id
  rds_kms_key_arn         = module.kms.key_arns["rds"]
  secrets_kms_key_id      = module.kms.key_ids["secrets"]
  database_name           = var.database_name
  master_username         = var.database_master_username
  instance_class          = var.rds_instance_class
  allocated_storage       = var.rds_allocated_storage
  max_allocated_storage   = var.rds_max_allocated_storage
  multi_az                = var.rds_multi_az
  deletion_protection     = var.rds_deletion_protection
  skip_final_snapshot     = false
  monitoring_interval     = var.rds_monitoring_interval
  owner                   = var.owner
  cost_center             = var.cost_center
  repository              = var.repository
  data_classification     = var.data_classification
  criticality             = var.criticality
}

module "redis" {
  source = "../../modules/redis"

  project                    = var.project
  environment                = var.environment
  private_data_subnet_ids    = module.network.private_data_subnet_ids
  redis_security_group_id    = module.sg.redis_security_group_id
  redis_kms_key_arn          = module.kms.key_arns["redis"]
  logs_kms_key_arn           = module.kms.key_arns["logs"]
  auth_token                 = var.redis_auth_token
  node_type                  = var.redis_node_type
  num_cache_clusters         = var.redis_num_cache_clusters
  multi_az_enabled           = var.redis_multi_az_enabled
  automatic_failover_enabled = var.redis_automatic_failover_enabled
  owner                      = var.owner
  cost_center                = var.cost_center
  repository                 = var.repository
  data_classification        = var.data_classification
  criticality                = var.criticality
}

module "iam" {
  source = "../../modules/iam"

  project                            = var.project
  environment                        = var.environment
  ecr_repository_arns                = var.ecr_repository_arns
  ecs_log_group_arns                 = local.ecs_log_group_arns
  execution_secret_arns              = concat(local.payments_secret_arns, [module.rds.master_user_secret_arn])
  execution_kms_key_arns             = [module.kms.key_arns["secrets"]]
  payments_secret_arns               = concat(local.payments_secret_arns, [module.rds.master_user_secret_arn])
  payments_kms_key_arns              = [module.kms.key_arns["secrets"]]
  kyc_secret_arns                    = concat(local.kyc_secret_arns, [module.rds.master_user_secret_arn])
  kyc_kms_key_arns                   = [module.kms.key_arns["secrets"], module.kms.key_arns["s3"]]
  kyc_bucket_arn                     = module.s3.kyc_bucket_arn
  enable_detection_lambda_role       = true
  enable_secret_rotation_lambda_role = true
  rotation_secret_arns               = values(module.secrets.secret_arns)
  rotation_kms_key_arns              = [module.kms.key_arns["secrets"]]
  owner                              = var.owner
  cost_center                        = var.cost_center
  repository                         = var.repository
  data_classification                = var.data_classification
  criticality                        = var.criticality
}

module "lambda" {
  source = "../../modules/lambda"

  project                     = var.project
  environment                 = var.environment
  logs_kms_key_arn            = module.kms.key_arns["logs"]
  enable_code_signing         = var.enable_lambda_code_signing
  containment_lambda_role_arn = module.iam.detection_lambda_role_arn
  containment_package_path    = var.containment_package_path
  rotation_lambda_role_arn    = module.iam.secret_rotation_lambda_role_arn
  rotation_package_path       = var.rotation_package_path
  secret_rotation_secret_ids  = local.lambda_rotation_secret_ids
  tags                        = local.common_tags
}

module "alb" {
  source = "../../modules/alb"

  project                    = var.project
  environment                = var.environment
  vpc_id                     = module.network.vpc_id
  public_subnet_ids          = module.network.public_subnet_ids
  alb_security_group_id      = module.sg.alb_security_group_id
  certificate_arn            = var.certificate_arn
  access_logs_bucket_name    = module.logging.s3_access_log_bucket_name
  enable_deletion_protection = false
  owner                      = var.owner
  cost_center                = var.cost_center
  repository                 = var.repository
  data_classification        = var.data_classification
  criticality                = var.criticality
}

module "ecs" {
  source = "../../modules/ecs"

  project                     = var.project
  environment                 = var.environment
  private_app_subnet_ids      = module.network.private_app_subnet_ids
  payments_security_group_id  = module.sg.payments_service_security_group_id
  kyc_security_group_id       = module.sg.kyc_service_security_group_id
  ecs_task_execution_role_arn = module.iam.ecs_task_execution_role_arn
  payments_task_role_arn      = module.iam.payments_task_role_arn
  kyc_task_role_arn           = module.iam.kyc_task_role_arn
  logs_kms_key_arn            = module.kms.key_arns["logs"]
  payments_image              = var.payments_image
  kyc_image                   = var.kyc_image
  payments_target_group_arn   = module.alb.payments_target_group_arn
  kyc_target_group_arn        = module.alb.kyc_target_group_arn
  payments_desired_count      = var.payments_desired_count
  kyc_desired_count           = var.kyc_desired_count
  payments_cpu                = var.payments_cpu
  payments_memory             = var.payments_memory
  kyc_cpu                     = var.kyc_cpu
  kyc_memory                  = var.kyc_memory
  payments_environment        = local.payments_environment
  kyc_environment             = local.kyc_environment
  payments_secrets            = local.payments_secrets
  kyc_secrets                 = local.kyc_secrets
  enable_execute_command      = var.enable_ecs_execute_command
  owner                       = var.owner
  cost_center                 = var.cost_center
  repository                  = var.repository
  data_classification         = var.data_classification
  criticality                 = var.criticality
}

module "waf" {
  source = "../../modules/waf"

  project               = var.project
  environment           = var.environment
  alb_arn               = module.alb.load_balancer_arn
  logs_kms_key_arn      = module.kms.key_arns["logs"]
  payments_rate_limit   = var.payments_rate_limit
  blocked_country_codes = var.blocked_country_codes
  owner                 = var.owner
  cost_center           = var.cost_center
  repository            = var.repository
  data_classification   = var.data_classification
  criticality           = var.criticality
}

module "route53" {
  count  = var.enable_route53 ? 1 : 0
  source = "../../modules/route53"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  project             = var.project
  environment         = var.environment
  domain_name         = var.domain_name
  record_names        = var.record_names
  alb_dns_name        = module.alb.load_balancer_dns_name
  alb_zone_id         = module.alb.load_balancer_zone_id
  force_destroy_zone  = var.force_destroy_route53_zone
  enable_dnssec       = false
  owner               = var.owner
  cost_center         = var.cost_center
  repository          = var.repository
  data_classification = var.data_classification
  criticality         = var.criticality
}

module "detection" {
  source = "../../modules/detection"

  project                                    = var.project
  environment                                = var.environment
  logs_kms_key_arn                           = module.kms.key_arns["logs"]
  guardduty_containment_lambda_arn           = module.lambda.guardduty_containment_lambda_arn
  guardduty_containment_lambda_function_name = module.lambda.guardduty_containment_lambda_function_name
  owner                                      = var.owner
  cost_center                                = var.cost_center
  repository                                 = var.repository
  data_classification                        = var.data_classification
  criticality                                = var.criticality
}

module "monitoring" {
  source = "../../modules/monitoring"

  project                                    = var.project
  environment                                = var.environment
  alert_email_endpoints                      = var.alert_email_endpoints
  alb_arn_suffix                             = local.alb_arn_suffix
  ecs_cluster_name                           = module.ecs.cluster_id
  payments_service_name                      = module.ecs.payments_service_name
  kyc_service_name                           = module.ecs.kyc_service_name
  rds_instance_id                            = module.rds.db_instance_id
  redis_replication_group_id                 = module.redis.replication_group_id
  guardduty_containment_lambda_function_name = module.lambda.guardduty_containment_lambda_function_name
  waf_web_acl_name                           = local.waf_web_acl_name
  owner                                      = var.owner
  cost_center                                = var.cost_center
  repository                                 = var.repository
  data_classification                        = var.data_classification
  criticality                                = var.criticality
}

module "honeytoken" {
  source = "../../modules/honeytoken"

  project                  = var.project
  environment              = var.environment
  secrets_kms_key_arn      = module.kms.key_arns["secrets"]
  honeytoken_access_key_id = var.honeytoken_access_key_id
  alert_email_endpoints    = var.alert_email_endpoints
  owner                    = var.owner
  cost_center              = var.cost_center
  repository               = var.repository
  data_classification      = var.data_classification
  criticality              = var.criticality
}

module "cicd_oidc" {
  source = "../../modules/cicd-oidc"

  project                  = var.project
  environment              = var.environment
  owner                    = var.owner
  cost_center              = var.cost_center
  repository_name          = var.repository
  github_owner             = var.github_owner
  github_repo              = var.github_repo
  github_oidc_provider_arn = var.github_oidc_provider_arn
  plan_subjects = [
    "repo:${var.github_owner}/${var.github_repo}:pull_request",
    "repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/${var.github_dev_branch}"
  ]
  apply_subjects = [
    "repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/${var.github_dev_branch}"
  ]
  ecr_push_subjects = [
    "repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/${var.github_dev_branch}"
  ]
  lambda_signing_subjects = [
    "repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/${var.github_dev_branch}"
  ]
  terraform_state_bucket_arn          = var.terraform_state_bucket_arn
  terraform_lock_table_arn            = var.terraform_lock_table_arn
  terraform_state_kms_key_arn         = var.terraform_state_kms_key_arn
  terraform_apply_policy_arns         = var.terraform_apply_policy_arns
  ecr_repository_arns                 = var.ecr_repository_arns
  lambda_signing_profile_version_arns = [] # Bootstrap CI/CD first; wire Lambda signing profile after Lambda resources exist.
}

output "alb_dns_name" {
  description = "Dev ALB DNS name."
  value       = module.alb.load_balancer_dns_name
}

output "payments_service_name" {
  description = "Dev payments ECS service name."
  value       = module.ecs.payments_service_name
}

output "kyc_service_name" {
  description = "Dev KYC ECS service name."
  value       = module.ecs.kyc_service_name
}

output "rds_endpoint" {
  description = "Dev RDS endpoint."
  value       = module.rds.db_endpoint
}

output "redis_primary_endpoint" {
  description = "Dev Redis primary endpoint."
  value       = module.redis.primary_endpoint_address
}

output "kyc_bucket_name" {
  description = "Dev KYC document bucket name."
  value       = module.s3.kyc_bucket_name
}



