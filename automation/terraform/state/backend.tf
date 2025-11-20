# Health-InfraOps Terraform State Backend Configuration
# Multiple backend options for flexibility

# Option 1: AWS S3 Backend (Recommended for production)
terraform {
  backend "s3" {
    bucket = "health-infraops-tfstate"
    key    = "infrastructure/terraform.tfstate"
    region = "ap-southeast-1"
    
    # State locking with DynamoDB
    dynamodb_table = "health-infraops-tfstate-lock"
    encrypt        = true
    
    # Assume role for cross-account access (if needed)
    # role_arn = "arn:aws:iam::ACCOUNT_ID:role/Terraform"
  }
}

# Option 2: Proxmox HTTP Backend (Alternative)
/*
terraform {
  backend "http" {
    address        = "https://pve-01.infokes.co.id:8006/api2/json/terraform/state/production"
    lock_address   = "https://pve-01.infokes.co.id:8006/api2/json/terraform/lock/production"
    unlock_address = "https://pve-01.infokes.co.id:8006/api2/json/terraform/unlock/production"
    username       = "terraform@pve"
    password       = "your-terraform-password"
  }
}
*/

# Option 3: Local Backend (Development only)
/*
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
*/

# Option 4: GitLab Backend (if using GitLab)
/*
terraform {
  backend "http" {
    address = "https://gitlab.com/api/v4/projects/PROJECT_ID/terraform/state/health-infraops"
    lock_address   = "https://gitlab.com/api/v4/projects/PROJECT_ID/terraform/state/health-infraops/lock"
    unlock_address = "https://gitlab.com/api/v4/projects/PROJECT_ID/terraform/state/health-infraops/unlock"
    username       = "your-gitlab-username"
    password       = "your-gitlab-token"
  }
}
*/

# State Configuration for Modules
data "terraform_remote_state" "network" {
  backend = "s3"
  
  config = {
    bucket = "health-infraops-tfstate"
    key    = "network/terraform.tfstate"
    region = "ap-southeast-1"
  }
}

data "terraform_remote_state" "compute" {
  backend = "s3"
  
  config = {
    bucket = "health-infraops-tfstate"
    key    = "compute/terraform.tfstate"
    region = "ap-southeast-1"
  }
}

data "terraform_remote_state" "storage" {
  backend = "s3"
  
  config = {
    bucket = "health-infraops-tfstate"
    key    = "storage/terraform.tfstate"
    region = "ap-southeast-1"
  }
}

# State Locking Configuration
resource "aws_dynamodb_table" "terraform_state_lock" {
  name           = "health-infraops-tfstate-lock"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "LockID"
  
  attribute {
    name = "LockID"
    type = "S"
  }
  
  tags = {
    Name        = "Terraform State Lock Table"
    Environment = "production"
    Project     = "health-infraops"
  }
}

# State Backup Configuration
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
  
  lifecycle_rule {
    enabled = true
    
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    
    transition {
      days          = 60
      storage_class = "GLACIER"
    }
    
    expiration {
      days = 365
    }
  }
  
  tags = {
    Name        = "Terraform State Bucket"
    Environment = "production"
    Project     = "health-infraops"
  }
}

# State Access Policy
resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TerraformStateAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::ACCOUNT_ID:user/terraform"
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
      },
      {
        Sid    = "TerraformStateLock"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::ACCOUNT_ID:user/terraform"
        }
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.terraform_state_lock.arn
      }
    ]
  })
}

# Outputs for other modules to reference
output "terraform_state_bucket" {
  description = "Name of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.bucket
}

output "terraform_lock_table" {
  description = "Name of the DynamoDB table for state locking"
  value       = aws_dynamodb_table.terraform_state_lock.name
}

output "state_bucket_arn" {
  description = "ARN of the Terraform state bucket"
  value       = aws_s3_bucket.terraform_state.arn
}

output "lock_table_arn" {
  description = "ARN of the DynamoDB lock table"
  value       = aws_dynamodb_table.terraform_state_lock.arn
}

# Remote state data sources for cross-referencing
data "terraform_remote_state" "infrastructure" {
  backend = "s3"
  
  config = {
    bucket = "health-infraops-tfstate"
    key    = "infrastructure/terraform.tfstate"
    region = "ap-southeast-1"
  }
}

# Backend initialization script reference
# This should be placed in automation/terraform/state/backend-init.sh
/*
#!/bin/bash
# Backend initialization script for Health-InfraOps

echo "Initializing Terraform backend for Health-InfraOps..."

# Create S3 bucket for state storage
aws s3 mb s3://health-infraops-tfstate --region ap-southeast-1

# Create DynamoDB table for state locking
aws dynamodb create-table \
    --table-name health-infraops-tfstate-lock \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region ap-southeast-1

echo "Backend initialization completed!"
*/