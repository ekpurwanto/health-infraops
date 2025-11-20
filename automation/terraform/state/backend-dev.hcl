# Development environment backend
bucket         = "health-infraops-tfstate"
key            = "dev/terraform.tfstate"
region         = "ap-southeast-1"
dynamodb_table = "health-infraops-tfstate-lock"
encrypt        = true