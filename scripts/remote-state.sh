#!/bin/bash

# Health-InfraOps Remote State Management Script
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
STATE_BUCKET="health-infraops-tfstate"
LOCK_TABLE="health-infraops-tfstate-lock"
AWS_REGION="ap-southeast-1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed"
        exit 1
    fi
    
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured properly"
        exit 1
    fi
    
    log_info "All prerequisites satisfied"
}

# Initialize remote state backend
init_backend() {
    local environment="${1:-production}"
    local component="${2:-infrastructure}"
    
    log_info "Initializing Terraform backend for $component in $environment"
    
    cd "$PROJECT_ROOT/$component"
    
    # Select workspace
    terraform workspace select "$environment" || terraform workspace new "$environment"
    
    # Initialize with backend
    terraform init -reconfigure \
        -backend-config="bucket=$STATE_BUCKET" \
        -backend-config="key=$component/terraform.tfstate" \
        -backend-config="region=$AWS_REGION" \
        -backend-config="dynamodb_table=$LOCK_TABLE" \
        -backend-config="encrypt=true"
    
    log_info "Backend initialization completed for $component"
}

# Create backend resources
create_backend_resources() {
    log_info "Creating backend resources..."
    
    cd "$PROJECT_ROOT/backend"
    
    terraform init
    terraform apply -auto-approve
    
    log_info "Backend resources created successfully"
}

# Migrate state from local to remote
migrate_state() {
    local component="${1:-infrastructure}"
    local environment="${2:-production}"
    
    log_info "Migrating state for $component from local to remote"
    
    cd "$PROJECT_ROOT/$component"
    
    # Initialize with local backend first
    terraform init
    
    # Now migrate to remote backend
    terraform init -migrate-state \
        -backend-config="bucket=$STATE_BUCKET" \
        -backend-config="key=$component/terraform.tfstate" \
        -backend-config="region=$AWS_REGION" \
        -backend-config="dynamodb_table=$LOCK_TABLE" \
        -backend-config="encrypt=true"
    
    log_info "State migration completed for $component"
}

# List all state files
list_state_files() {
    log_info "Listing state files in S3 bucket..."
    
    aws s3 ls "s3://$STATE_BUCKET/" --recursive --human-readable | grep -E "\.tfstate$"
}

# Backup state file
backup_state() {
    local component="${1}"
    local backup_date=$(date +%Y%m%d_%H%M%S)
    
    if [ -z "$component" ]; then
        log_error "Component name is required for backup"
        exit 1
    fi
    
    log_info "Backing up state file for $component"
    
    aws s3 cp \
        "s3://$STATE_BUCKET/$component/terraform.tfstate" \
        "s3://$STATE_BUCKET/backups/$component/terraform.tfstate.backup_$backup_date"
    
    log_info "State backup completed: backups/$component/terraform.tfstate.backup_$backup_date"
}

# Restore state file
restore_state() {
    local component="${1}"
    local backup_file="${2}"
    
    if [ -z "$component" ] || [ -z "$backup_file" ]; then
        log_error "Component name and backup file are required for restore"
        exit 1
    fi
    
    log_warn "Restoring state file for $component from $backup_file"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Restore cancelled"
        exit 0
    fi
    
    aws s3 cp \
        "s3://$STATE_BUCKET/backups/$component/$backup_file" \
        "s3://$STATE_BUCKET/$component/terraform.tfstate"
    
    log_info "State restore completed"
}

# Force unlock state (use with caution)
force_unlock() {
    local lock_id="${1}"
    
    if [ -z "$lock_id" ]; then
        log_error "Lock ID is required"
        exit 1
    fi
    
    log_warn "Force unlocking state with ID: $lock_id"
    read -p "This is a dangerous operation. Are you sure? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Unlock cancelled"
        exit 0
    fi
    
    terraform force-unlock "$lock_id"
    log_info "State force-unlock completed"
}

# Show usage
usage() {
    cat << EOF
Health-InfraOps Remote State Management

Usage: $0 <command> [options]

Commands:
    init [environment] [component]  - Initialize remote backend
    create-backend                 - Create backend resources
    migrate [component] [env]      - Migrate state from local to remote
    list                           - List all state files
    backup <component>             - Backup state file
    restore <component> <file>     - Restore state from backup
    unlock <lock_id>               - Force unlock state (dangerous)
    help                           - Show this help message

Examples:
    $0 init production infrastructure
    $0 init development network
    $0 migrate infrastructure production
    $0 backup compute
    $0 list

EOF
}

# Main script execution
main() {
    local command="${1}"
    local arg1="${2}"
    local arg2="${3}"
    
    case "$command" in
        "init")
            check_prerequisites
            init_backend "$arg1" "$arg2"
            ;;
        "create-backend")
            check_prerequisites
            create_backend_resources
            ;;
        "migrate")
            check_prerequisites
            migrate_state "$arg1" "$arg2"
            ;;
        "list")
            list_state_files
            ;;
        "backup")
            check_prerequisites
            backup_state "$arg1"
            ;;
        "restore")
            check_prerequisites
            restore_state "$arg1" "$arg2"
            ;;
        "unlock")
            check_prerequisites
            force_unlock "$arg1"
            ;;
        "help"|"")
            usage
            ;;
        *)
            log_error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"