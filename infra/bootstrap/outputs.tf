# Data source for the DynamoDB table
data "aws_dynamodb_table" "dynamodb_table1_data" {
  name = aws_dynamodb_table.dynamodb_table1.name
}

# Data source for the S3 bucket 
data "aws_s3_bucket" "s3_bucket1_data" {
  bucket = aws_s3_bucket.s3_bucket1.bucket
}

# Data source for the KMS key
data "aws_kms_key" "kms_key1_data" {
  key_id = aws_kms_key.mykey.id
}

# OUTPUTS
output "dynamodb_table_name" {
  value = data.aws_dynamodb_table.dynamodb_table1_data.name
}

output "dynamodb_table_id" {
  value = data.aws_dynamodb_table.dynamodb_table1_data.id
}

output "dynamodb_environment" {
  value = data.aws_dynamodb_table.dynamodb_table1_data.tags["Environment"]
}
output "dynamodb_table_arn" {
  value = data.aws_dynamodb_table.dynamodb_table1_data.arn
}

output "s3_bucket_name" {
  value = data.aws_s3_bucket.s3_bucket1_data.bucket
}

output "s3_bucket_arn" {
  value = data.aws_s3_bucket.s3_bucket1_data.arn
}

output "s3_bucket_regional_domain" {
  value = data.aws_s3_bucket.s3_bucket1_data.bucket_regional_domain_name
}

# output for KMS key
output "kms_key_id" {
  value = data.aws_kms_key.kms_key1_data.id
}