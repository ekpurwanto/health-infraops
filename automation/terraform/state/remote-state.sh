#!/bin/bash

# Health-InfraOps Terraform Remote State Management Script
# Script untuk inisialisasi dan migrasi Terraform state

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="health-infraops"
TF_STATE_BUCKET="health-infraops-tfstate"
TF_STATE_REGION="ap-southeast-1"
TF_LOCK_TABLE="health-infraops-tfstate-lock"
BACKEND_CONFIG_FILE="backend.hcl"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Help function
show_help() {
    cat << EOF
Health-InfraOps Terraform Remote State Management

Usage: $0 [command]

Commands:
  init-backend      - Initialize remote backend resources (S3 bucket & DynamoDB)
  migrate-local     - Migrate from local state to remote backend
  migrate-remote    - Migrate from one remote backend to another
  list-states       - List all state files in S3 bucket
  backup-state      - Create backup of current state
  restore-state     - Restore state from backup
  lock-info         - Show information about state locks
  force-unlock      - Force unlock state (use with caution)
  setup-workspace   - Setup Terraform workspace for environment
  cleanup           - Clean up remote state resources

Environment variables:
  AWS_PROFILE       - AWS profile to use (optional)
  TF_WORKSPACE      - Terraform workspace name
  TF_ENVIRONMENT    - Environment (dev, staging, prod)

Examples:
  $0 init-backend
  $0 migrate-local
  TF_ENVIRONMENT=prod $0 setup-workspace
EOF
}

# Check dependencies
check_dependencies() {
    local deps=("terraform" "aws")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_error "$dep is not installed. Please install it first."
            exit 1
        fi
    done
}

# Initialize backend resources
init_backend() {
    log_info "Initializing Terraform backend resources..."
    
    # Create S3 bucket
    if aws s3 ls "s3://$TF_STATE_BUCKET" 2>/dev/null; then
        log_warning "S3 bucket $TF_STATE_BUCKET already exists"
    else
        log_info "Creating S3 bucket: $TF_STATE_BUCKET"
        aws s3 mb "s3://$TF_STATE_BUCKET" --region "$TF_STATE_REGION"
        
        # Enable versioning
        aws s3api put-bucket-versioning \
            --bucket "$TF_STATE_BUCKET" \
            --versioning-configuration Status=Enabled
            
        # Enable encryption
        aws s3api put-bucket-encryption \
            --bucket "$TF_STATE_BUCKET" \
            --server-side-encryption-configuration '{
                "Rules": [
                    {
                        "ApplyServerSideEncryptionByDefault": {
                            "SSEAlgorithm": "AES256"
                        }
                    }
                ]
            }'
        
        log_success "S3 bucket created and configured"
    fi
    
    # Create DynamoDB table
    if aws dynamodb describe-table --table-name "$TF_LOCK_TABLE" 2>/dev/null; then
        log_warning "DynamoDB table $TF_LOCK_TABLE already exists"
    else
        log_info "Creating DynamoDB table: $TF_LOCK_TABLE"
        aws dynamodb create-table \
            --table-name "$TF_LOCK_TABLE" \
            --attribute-definitions AttributeName=LockID,AttributeType=S \
            --key-schema AttributeName=LockID,KeyType=HASH \
            --billing-mode PAY_PER_REQUEST \
            --region "$TF_STATE_REGION"
            
        # Wait for table to be active
        aws dynamodb wait table-exists --table-name "$TF_LOCK_TABLE"
        log_success "DynamoDB table created"
    fi
    
    # Create backend configuration file
    cat > "$BACKEND_CONFIG_FILE" << EOF
# Health-InfraOps Backend Configuration
bucket = "$TF_STATE_BUCKET"
key    = "\${terraform.workspace}/terraform.tfstate"
region = "$TF_STATE_REGION"
dynamodb_table = "$TF_LOCK_TABLE"
encrypt = true
EOF

    log_success "Backend configuration file created: $BACKEND_CONFIG_FILE"
}

# Migrate from local to remote state
migrate_local_to_remote() {
    log_info "Migrating from local to remote state..."
    
    if [ ! -f ".terraform/terraform.tfstate" ] && [ ! -f "terraform.tfstate" ]; then
        log_error "No local state file found"
        exit 1
    fi
    
    # Initialize with backend
    terraform init -backend-config="$BACKEND_CONFIG_FILE" -migrate-state
    
    if [ $? -eq 0 ]; then
        log_success "State migration completed successfully"
    else
        log_error "State migration failed"
        exit 1
    fi
}

# Migrate between remote backends
migrate_remote_backend() {
    log_info "Migrating between remote backends..."
    
    read -p "Enter source backend config file: " SOURCE_BACKEND
    read -p "Enter target backend config file: " TARGET_BACKEND
    
    if [ ! -f "$SOURCE_BACKEND" ] || [ ! -f "$TARGET_BACKEND" ]; then
        log_error "Backend config files not found"
        exit 1
    fi
    
    # Initialize with source backend
    terraform init -backend-config="$SOURCE_BACKEND" -reconfigure
    
    # Migrate to target backend
    terraform init -backend-config="$TARGET_BACKEND" -migrate-state
    
    if [ $? -eq 0 ]; then
        log_success "Remote state migration completed successfully"
    else
        log_error "Remote state migration failed"
        exit 1
    fi
}

# List all state files
list_states() {
    log_info "Listing state files in S3 bucket..."
    
    aws s3 ls "s3://$TF_STATE_BUCKET/" --recursive | \
    grep -E '\.tfstate$|\.tfstate.backup$' | \
    while read -r line; do
        echo "$line"
    done
}

# Backup current state
backup_state() {
    local workspace=${1:-$(terraform workspace show)}
    local backup_file="terraform.tfstate.backup.$(date +%Y%m%d_%H%M%S)"
    
    log_info "Creating state backup for workspace: $workspace"
    
    # Pull current state
    terraform state pull > "$backup_file"
    
    if [ $? -eq 0 ]; then
        log_success "State backup created: $backup_file"
        
        # Upload to S3 for additional safety
        aws s3 cp "$backup_file" "s3://$TF_STATE_BUCKET/backups/$backup_file"
        log_success "Backup uploaded to S3: backups/$backup_file"
    else
        log_error "State backup failed"
        exit 1
    fi
}

# Restore state from backup
restore_state() {
    local backup_file=$1
    local workspace=${2:-$(terraform workspace show)}
    
    if [ -z "$backup_file" ]; then
        log_error "Backup file parameter required"
        echo "Usage: $0 restore-state <backup-file> [workspace]"
        exit 1
    fi
    
    log_info "Restoring state from backup: $backup_file"
    
    # Check if backup file exists
    if [ ! -f "$backup_file" ]; then
        # Try to download from S3
        aws s3 cp "s3://$TF_STATE_BUCKET/backups/$backup_file" "./$backup_file"
        
        if [ ! -f "$backup_file" ]; then
            log_error "Backup file not found: $backup_file"
            exit 1
        fi
    fi
    
    # Push state back
    terraform state push "$backup_file"
    
    if [ $? -eq 0 ]; then
        log_success "State restored successfully from: $backup_file"
    else
        log_error "State restoration failed"
        exit 1
    fi
}

# Show lock information
lock_info() {
    log_info "Checking for state locks..."
    
    # List locks from DynamoDB
    aws dynamodb scan \
        --table-name "$TF_LOCK_TABLE" \
        --query "Items[].{LockID: LockID.S, Info: Info.S}" \
        --output table
}

# Force unlock state
force_unlock() {
    local lock_id=$1
    
    if [ -z "$lock_id" ]; then
        log_error "Lock ID parameter required"
        echo "Usage: $0 force-unlock <lock-id>"
        echo "Get lock ID from: $0 lock-info"
        exit 1
    fi
    
    log_warning "Force unlocking state: $lock_id"
    read -p "Are you sure? This can cause data loss! (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        terraform force-unlock "$lock_id"
        
        if [ $? -eq 0 ]; then
            log_success "State force-unlocked successfully"
        else
            log_error "Force unlock failed"
            exit 1
        fi
    else
        log_info "Force unlock cancelled"
    fi
}

# Setup workspace for environment
setup_workspace() {
    local environment=${TF_ENVIRONMENT:-$1}
    
    if [ -z "$environment" ]; then
        log_error "Environment not specified"
        echo "Usage: $0 setup-workspace <environment>"
        echo "Or set TF_ENVIRONMENT environment variable"
        exit 1
    fi
    
    log_info "Setting up workspace for environment: $environment"
    
    # Create or select workspace
    terraform workspace new "$environment" 2>/dev/null || \
    terraform workspace select "$environment"
    
    # Initialize with backend if not already done
    if [ ! -f ".terraform/terraform.tfstate" ]; then
        terraform init -backend-config="$BACKEND_CONFIG_FILE"
    fi
    
    log_success "Workspace '$environment' is ready"
}

# Clean up resources
cleanup() {
    log_warning "This will destroy all Terraform state resources!"
    log_warning "This includes:"
    log_warning "  - S3 bucket: $TF_STATE_BUCKET"
    log_warning "  - DynamoDB table: $TF_LOCK_TABLE"
    log_warning "  - All state files and backups"
    
    read -p "Are you absolutely sure? This cannot be undone! (type 'DESTROY' to confirm): " -r
    echo
    
    if [ "$REPLY" != "DESTROY" ]; then
        log_info "Cleanup cancelled"
        exit 0
    fi
    
    # Empty S3 bucket first
    log_info "Emptying S3 bucket..."
    aws s3 rm "s3://$TF_STATE_BUCKET" --recursive
    
    # Delete S3 bucket
    log_info "Deleting S3 bucket..."
    aws s3 rb "s3://$TF_STATE_BUCKET" --force
    
    # Delete DynamoDB table
    log_info "Deleting DynamoDB table..."
    aws dynamodb delete-table --table-name "$TF_LOCK_TABLE"
    
    # Remove local files
    rm -f "$BACKEND_CONFIG_FILE"
    rm -f terraform.tfstate*
    rm -rf .terraform
    
    log_success "Cleanup completed successfully"
}

# Main script execution
main() {
    local command=$1
    
    check_dependencies
    
    case $command in
        "init-backend")
            init_backend
            ;;
        "migrate-local")
            migrate_local_to_remote
            ;;
        "migrate-remote")
            migrate_remote_backend
            ;;
        "list-states")
            list_states
            ;;
        "backup-state")
            backup_state "$2"
            ;;
        "restore-state")
            restore_state "$2" "$3"
            ;;
        "lock-info")
            lock_info
            ;;
        "force-unlock")
            force_unlock "$2"
            ;;
        "setup-workspace")
            setup_workspace "$2"
            ;;
        "cleanup")
            cleanup
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"