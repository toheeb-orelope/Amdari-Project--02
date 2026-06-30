terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.52"
    }
  }
}
provider "aws" {
  #checkov:skip=CKV_AWS_41:Provider alias contains region only; no hard-coded AWS credentials.
  alias  = "us_east_1"
  region = "us-east-1"
}
