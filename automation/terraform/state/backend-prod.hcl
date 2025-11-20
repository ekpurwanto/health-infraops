# Production environment backend
bucket         = "health-infraops-tfstate"
key            = "prod/terraform.tfstate"
region         = "ap-southeast-1"
dynamodb_table = "health-infraops-tfstate-lock"
encrypt        = true