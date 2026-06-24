terraform {
  backend "s3" {
    bucket         = "project-363238514491-af-south-1-an"
    key            = "envs/prod/terraform.tfstate"
    region         = "af-south-1"
    encrypt        = true
    kms_key_id     = "b2948092-a0d4-4310-b838-316e430bae1f"
    dynamodb_table = "dynamodb-table1"  
  }
}