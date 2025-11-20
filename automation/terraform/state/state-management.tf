# State Locking Configuration with DynamoDB
resource "aws_dynamodb_table" "terraform_state_lock" {
  name           = "health-infraops-tfstate-lock"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "LockID"
  
  attribute {
    name = "LockID"
    type = "S"
  }
  
  # Enable point-in-time recovery for additional backup
  point_in_time_recovery {
    enabled = true
  }
  
  tags = {
    Name        = "Terraform State Lock Table"
    Environment = "production"
    Project     = "health-infraops"
    ManagedBy   = "terraform"
  }
  
  lifecycle {
    prevent_destroy = true
  }
}

# State Backup Configuration with S3
resource "aws_s3_bucket" "terraform_state" {
  bucket = "health-infraops-tfstate"
  acl    = "private"
  
  versioning {
    enabled = true
  }
  
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
  
  # Enable bucket lifecycle for cost optimization
  lifecycle_rule {
    id      = "state_version_lifecycle"
    enabled = true
    
    # Transition to infrequent access after 30 days
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    
    # Archive to Glacier after 90 days
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
    
    # Expire non-current versions after 1 year
    noncurrent_version_expiration {
      days = 365
    }
  }
  
  # Enable MFA delete protection
  mfa_delete = false
  
  # Enable bucket logging
  logging {
    target_bucket = aws_s3_bucket.terraform_logs.id
    target_prefix = "s3/health-infraops-tfstate/"
  }
  
  tags = {
    Name        = "Terraform State Bucket"
    Environment = "production"
    Project     = "health-infraops"
    ManagedBy   = "terraform"
  }
  
  lifecycle {
    prevent_destroy = true
  }
}

# Additional S3 bucket for logs
resource "aws_s3_bucket" "terraform_logs" {
  bucket = "health-infraops-tfstate-logs"
  acl    = "log-delivery-write"
  
  versioning {
    enabled = true
  }
  
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
  
  tags = {
    Name        = "Terraform State Logs Bucket"
    Project     = "health-infraops"
    ManagedBy   = "terraform"
  }
}

# KMS Key for State Encryption
resource "aws_kms_key" "terraform_state" {
  description             = "KMS key for encrypting Terraform state files"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_policy.json
  
  tags = {
    Name        = "health-infraops-tfstate-kms"
    Project     = "health-infraops"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

resource "aws_kms_alias" "terraform_state" {
  name          = "alias/health-infraops-tfstate"
  target_key_id = aws_kms_key.terraform_state.key_id
}

# State Access Policy
resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequireSSL"
        Effect = "Deny"
        Principal = "*"
        Action = "s3:*"
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid    = "TerraformStateAccess"
        Effect = "Allow"
        Principal = {
          AWS = [
            "arn:aws:iam::${var.aws_account_id}:user/terraform",
            "arn:aws:iam::${var.aws_account_id}:role/TerraformBackendAccess"
          ]
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObjectVersion"
        ]
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
      }
    ]
  })
}

# IAM Policy Document for KMS
data "aws_iam_policy_document" "kms_policy" {
  statement {
    sid    = "Enable IAM User Permissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.aws_account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "Allow Terraform to use the key"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [
        "arn:aws:iam::${var.aws_account_id}:user/terraform",
        "arn:aws:iam::${var.aws_account_id}:role/TerraformBackendAccess"
      ]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = ["*"]
  }
}