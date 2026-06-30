terraform {
  backend "s3" {
    bucket         = "project-363238514491-us-east-1-an"
    key            = "envs/prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    kms_key_id     = "71eebf76-9222-4c5b-bdda-4f36f2a63756"
    dynamodb_table = "dynamodb-table1"
  }
}