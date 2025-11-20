#!/bin/bash

# Health-InfraOps Deployment Script
# Comprehensive deployment script for infrastructure and applications

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_DIR="${PROJECT_ROOT}/logs/deployments"
CONFIG_DIR="${PROJECT_ROOT}/automation/ansible"
TERRAFORM_DIR="${PROJECT_ROOT}/automation/terraform"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEPLOYMENT_ID="deploy_${TIMESTAMP}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging setup
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/${DEPLOYMENT_ID}.log"

# Logging functions
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$1"; }
log_success() { log "SUCCESS" "$1"; }
log_warning() { log "WARNING" "$1"; }
log_error() { log "ERROR" "$1"; }

# Help function
show_help() {
    cat << EOF
Health-InfraOps Deployment Script

Usage: $0 [options] <environment> <component>

Environments:
  dev       - Development environment
  staging   - Staging environment
  prod      - Production environment

Components:
  infrastructure - Deploy infrastructure only
  application    - Deploy applications only
  database       - Deploy databases only
  monitoring     - Deploy monitoring stack
  all           - Deploy everything

Options:
  -h, --help     Show this help message
  -d, --dry-run  Dry run mode
  -f, --force    Force deployment without confirmation
  -v, --verbose  Verbose output

Examples:
  $0 dev infrastructure
  $0 staging application --dry-run
  $0 prod all --force
EOF
}

# Validation functions
validate_environment() {
    local env=$1
    case $env in
        dev|staging|prod) return 0 ;;
        *) log_error "Invalid environment: $env"; return 1 ;;
    esac
}

validate_component() {
    local component=$1
    case $component in
        infrastructure|application|database|monitoring|all) return 0 ;;
        *) log_error "Invalid component: $component"; return 1 ;;
    esac
}

# Pre-flight checks
preflight_checks() {
    log_info "Running pre-flight checks..."
    
    # Check required tools
    local required_tools=("terraform" "ansible-playbook" "git")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is not installed"
            return 1
        fi
    done
    
    # Check configuration files
    local required_files=(
        "${CONFIG_DIR}/inventory/${ENVIRONMENT}"
        "${TERRAFORM_DIR}/environments/${ENVIRONMENT}/terraform.tfvars"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            log_warning "Configuration file not found: $file"
        fi
    done
    
    # Check AWS credentials (if using AWS)
    if [ "$ENVIRONMENT" = "prod" ] && [ -z "$AWS_ACCESS_KEY_ID" ]; then
        log_warning "AWS credentials not set for production environment"
    fi
    
    log_success "Pre-flight checks completed"
}

# Infrastructure deployment
deploy_infrastructure() {
    log_info "Starting infrastructure deployment..."
    
    local tf_env_dir="${TERRAFORM_DIR}/environments/${ENVIRONMENT}"
    
    if [ ! -d "$tf_env_dir" ]; then
        log_error "Terraform environment directory not found: $tf_env_dir"
        return 1
    fi
    
    cd "$tf_env_dir"
    
    # Initialize Terraform
    log_info "Initializing Terraform..."
    terraform init -reconfigure 2>&1 | tee -a "$LOG_FILE"
    
    # Plan deployment
    log_info "Creating deployment plan..."
    if [ "$DRY_RUN" = true ]; then
        terraform plan -var-file="terraform.tfvars" -out="${DEPLOYMENT_ID}.tfplan" 2>&1 | tee -a "$LOG_FILE"
        log_success "Dry run completed - plan saved to ${DEPLOYMENT_ID}.tfplan"
        return 0
    else
        terraform plan -var-file="terraform.tfvars" -out="${DEPLOYMENT_ID}.tfplan" 2>&1 | tee -a "$LOG_FILE"
    fi
    
    # Apply changes
    if [ "$FORCE" = true ]; then
        log_warning "Force applying infrastructure changes..."
        terraform apply -auto-approve "${DEPLOYMENT_ID}.tfplan" 2>&1 | tee -a "$LOG_FILE"
    else
        read -p "Apply infrastructure changes? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            terraform apply "${DEPLOYMENT_ID}.tfplan" 2>&1 | tee -a "$LOG_FILE"
        else
            log_info "Infrastructure deployment cancelled"
            return 1
        fi
    fi
    
    # Output results
    log_info "Infrastructure deployment completed"
    terraform output -json > "${LOG_DIR}/${DEPLOYMENT_ID}_outputs.json"
    
    cd - > /dev/null
}

# Application deployment
deploy_application() {
    log_info "Starting application deployment..."
    
    local playbook="${CONFIG_DIR}/playbooks/deploy-infokes.yml"
    local inventory="${CONFIG_DIR}/inventory/${ENVIRONMENT}"
    
    if [ ! -f "$playbook" ]; then
        log_error "Ansible playbook not found: $playbook"
        return 1
    fi
    
    if [ ! -f "$inventory" ]; then
        log_error "Inventory file not found: $inventory"
        return 1
    fi
    
    # Run Ansible playbook
    local ansible_cmd="ansible-playbook -i $inventory $playbook"
    
    if [ "$DRY_RUN" = true ]; then
        ansible_cmd="$ansible_cmd --check --diff"
        log_info "Dry run mode - no changes will be made"
    fi
    
    if [ "$VERBOSE" = true ]; then
        ansible_cmd="$ansible_cmd -vvv"
    fi
    
    log_info "Executing: $ansible_cmd"
    $ansible_cmd 2>&1 | tee -a "$LOG_FILE"
    
    log_success "Application deployment completed"
}

# Database deployment
deploy_database() {
    log_info "Starting database deployment..."
    
    local playbook="${CONFIG_DIR}/playbooks/deploy-databases.yml"
    local inventory="${CONFIG_DIR}/inventory/${ENVIRONMENT}"
    
    if [ ! -f "$playbook" ]; then
        log_error "Database playbook not found: $playbook"
        return 1
    fi
    
    # Backup existing databases first
    log_info "Creating database backups before deployment..."
    "${SCRIPT_DIR}/backup-all.sh" --database-only --environment "$ENVIRONMENT"
    
    # Run database deployment
    local ansible_cmd="ansible-playbook -i $inventory $playbook --tags database"
    
    if [ "$DRY_RUN" = true ]; then
        ansible_cmd="$ansible_cmd --check --diff"
    fi
    
    log_info "Executing database deployment..."
    $ansible_cmd 2>&1 | tee -a "$LOG_FILE"
    
    log_success "Database deployment completed"
}

# Monitoring deployment
deploy_monitoring() {
    log_info "Starting monitoring stack deployment..."
    
    local playbook="${CONFIG_DIR}/playbooks/setup-monitoring.yml"
    local inventory="${CONFIG_DIR}/inventory/${ENVIRONMENT}"
    
    if [ ! -f "$playbook" ]; then
        log_error "Monitoring playbook not found: $playbook"
        return 1
    fi
    
    local ansible_cmd="ansible-playbook -i $inventory $playbook --tags monitoring"
    
    if [ "$DRY_RUN" = true ]; then
        ansible_cmd="$ansible_cmd --check --diff"
    fi
    
    log_info "Executing monitoring deployment..."
    $ansible_cmd 2>&1 | tee -a "$LOG_FILE"
    
    log_success "Monitoring deployment completed"
}

# Health check after deployment
post_deployment_checks() {
    log_info "Running post-deployment health checks..."
    
    # Wait for services to be ready
    sleep 30
    
    # Run health check script
    "${SCRIPT_DIR}/health-check.sh" --environment "$ENVIRONMENT" --full
    
    if [ $? -eq 0 ]; then
        log_success "Post-deployment health checks passed"
    else
        log_error "Post-deployment health checks failed"
        return 1
    fi
}

# Main deployment function
main_deployment() {
    local environment=$1
    local component=$2
    
    ENVIRONMENT=$environment
    COMPONENT=$component
    
    log_info "Starting deployment: environment=$ENVIRONMENT, component=$COMPONENT"
    log_info "Deployment ID: $DEPLOYMENT_ID"
    log_info "Log file: $LOG_FILE"
    
    # Validate inputs
    validate_environment "$ENVIRONMENT" || exit 1
    validate_component "$COMPONENT" || exit 1
    
    # Pre-flight checks
    preflight_checks || exit 1
    
    # Confirm deployment (unless forced)
    if [ "$FORCE" != true ] && [ "$DRY_RUN" != true ]; then
        if [ "$ENVIRONMENT" = "prod" ]; then
            log_warning "PRODUCTION DEPLOYMENT - Extra caution required"
            read -p "Confirm production deployment? (type 'PROD' to confirm): " -r
            if [ "$REPLY" != "PROD" ]; then
                log_info "Production deployment cancelled"
                exit 0
            fi
        else
            read -p "Proceed with deployment? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Deployment cancelled"
                exit 0
            fi
        fi
    fi
    
    # Execute deployment based on component
    case $COMPONENT in
        infrastructure)
            deploy_infrastructure
            ;;
        application)
            deploy_application
            ;;
        database)
            deploy_database
            ;;
        monitoring)
            deploy_monitoring
            ;;
        all)
            log_info "Starting full deployment..."
            deploy_infrastructure
            deploy_database
            deploy_application
            deploy_monitoring
            ;;
    esac
    
    # Post-deployment checks
    if [ "$DRY_RUN" != true ] && [ "$COMPONENT" != "infrastructure" ]; then
        post_deployment_checks
    fi
    
    # Final report
    local duration=$(( $(date +%s) - $(date -d "$TIMESTAMP" +%s) ))
    log_success "Deployment completed successfully in ${duration} seconds"
    log_info "Deployment ID: $DEPLOYMENT_ID"
    log_info "Log file: $LOG_FILE"
}

# Parse command line arguments
ENVIRONMENT=""
COMPONENT=""
DRY_RUN=false
FORCE=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        *)
            if [ -z "$ENVIRONMENT" ]; then
                ENVIRONMENT=$1
            elif [ -z "$COMPONENT" ]; then
                COMPONENT=$1
            fi
            shift
            ;;
    esac
done

# Validate we have required arguments
if [ -z "$ENVIRONMENT" ] || [ -z "$COMPONENT" ]; then
    log_error "Environment and component arguments required"
    show_help
    exit 1
fi

# Execute main function
main_deployment "$ENVIRONMENT" "$COMPONENT"