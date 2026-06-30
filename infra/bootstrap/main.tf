
terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.42"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 2.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  common_tags = {
    Project            = "sentinelpay"
    Environment        = "shared"
    Service            = "terraform-state"
    Owner              = "toheeb"
    CostCenter         = "lab"
    ManagedBy          = "terraform"
    Repository         = "Amdari-Project--02"
    DataClassification = "confidential"
    Criticality        = "high"
  }
}

# Create an S3 bucket with a unique name using the account ID and region
resource "aws_s3_bucket" "s3_bucket1" {
  bucket        = format("project-%s-%s-an", data.aws_caller_identity.current.account_id, data.aws_region.current.region)
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "sentinelpay-shared-terraform-state"
  })


}

resource "aws_s3_bucket" "state_access_logs" {
  #tfsec:ignore:aws-s3-enable-bucket-logging Access log buckets are intentionally not access-logged to avoid recursive log delivery.
  bucket        = format("project-%s-%s-state-access-logs", data.aws_caller_identity.current.account_id, data.aws_region.current.region)
  force_destroy = true

  tags = merge(local.common_tags, {
    Name    = "sentinelpay-shared-terraform-state-access-logs"
    Service = "terraform-state-logging"
  })
}

resource "aws_s3_bucket_versioning" "state_access_logs" {
  bucket = aws_s3_bucket.state_access_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "state_access_logs" {
  bucket = aws_s3_bucket.state_access_logs.id

  block_public_acls       = true
  block_public_policy     = true
  restrict_public_buckets = true
  ignore_public_acls      = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state_access_logs" {
  bucket = aws_s3_bucket.state_access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "state_access_logs" {
  bucket = aws_s3_bucket.state_access_logs.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "state_access_logs" {
  bucket = aws_s3_bucket.state_access_logs.id
  acl    = "log-delivery-write"

  depends_on = [
    aws_s3_bucket_ownership_controls.state_access_logs,
    aws_s3_bucket_public_access_block.state_access_logs
  ]
}

resource "aws_s3_bucket_logging" "s3_bucket1" {
  bucket = aws_s3_bucket.s3_bucket1.id

  target_bucket = aws_s3_bucket.state_access_logs.id
  target_prefix = "terraform-state/"

  depends_on = [aws_s3_bucket_acl.state_access_logs]
}

# Enable versioning on the S3 bucket
resource "aws_s3_bucket_versioning" "s3_bucket_versioning1" {
  bucket = aws_s3_bucket.s3_bucket1.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Create a KMS key for encrypting S3 bucket objects
resource "aws_kms_key" "mykey" {
  description             = "This key is used to encrypt bucket objects"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = merge(local.common_tags, {
    Name = "sentinelpay-shared-terraform-state-kms"
  })
}



# Define a key policy that allows the S3 bucket to use the KMS key for encryption
resource "aws_kms_key_policy" "s3_bucket_kms_policy1" {
  key_id = aws_kms_key.mykey.id
  policy = jsonencode({
    Id = "s3-bucket-kms-policy1"
    Statement = [
      {
        Action = "kms:*"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Resource = "*"
        Sid      = "Enable IAM User Permissions"
      },
      {
        Sid    = "Allow DynamoDB to use the key"
        Effect = "Allow"
        Principal = {
          Service = "dynamodb.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ]
        Resource = "*"
      }
    ]
    Version = "2012-10-17"
  })
}

# Configure server-side encryption for the S3 bucket using the KMS key
resource "aws_s3_bucket_server_side_encryption_configuration" "s3_bucket_encryption1" {
  bucket = aws_s3_bucket.s3_bucket1.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.mykey.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

# Block public access to the S3 bucket
resource "aws_s3_bucket_public_access_block" "access_good_1" {
  bucket = aws_s3_bucket.s3_bucket1.id

  block_public_acls       = true
  block_public_policy     = true
  restrict_public_buckets = true
  ignore_public_acls      = true
}


# Create a DynamoDB table with server-side encryption using the existing KMS key
resource "aws_dynamodb_table" "dynamodb_table1" {
  name         = "dynamodb-table1"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  point_in_time_recovery {
    enabled = true
  }

  # Define all attributes first
  attribute {
    name = "LockID"
    type = "S"
  }


  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.mykey.arn
  }

  tags = merge(local.common_tags, {
    Name = "sentinelpay-shared-terraform-locks"
  })
}


resource "aws_s3_bucket_lifecycle_configuration" "s3_bucket1" {
  bucket = aws_s3_bucket.s3_bucket1.id

  rule {
    id     = "retain-versioned-state"
    status = "Enabled"

    filter {
      prefix = ""
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state_access_logs" {
  bucket = aws_s3_bucket.state_access_logs.id

  rule {
    id     = "expire-old-access-logs"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 365
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "state_bucket_secure_transport" {
  statement {
    sid    = "DenyInsecureTransportToStateBucket"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.s3_bucket1.arn,
      "${aws_s3_bucket.s3_bucket1.arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "s3_bucket1" {
  bucket = aws_s3_bucket.s3_bucket1.id
  policy = data.aws_iam_policy_document.state_bucket_secure_transport.json
}

data "aws_iam_policy_document" "state_access_logs_secure_transport" {
  statement {
    sid    = "DenyInsecureTransportToStateAccessLogBucket"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.state_access_logs.arn,
      "${aws_s3_bucket.state_access_logs.arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state_access_logs" {
  bucket = aws_s3_bucket.state_access_logs.id
  policy = data.aws_iam_policy_document.state_access_logs_secure_transport.json
}


