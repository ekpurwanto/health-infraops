set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${PROJECT_ROOT}/backups"
CONFIG_DIR="${PROJECT_ROOT}/automation/ansible"
LOG_DIR="${PROJECT_ROOT}/logs/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_ID="backup_${TIMESTAMP}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Backup status
SUCCESSFUL=0
FAILED=0
WARNING=0

mkdir -p "$BACKUP_DIR" "$LOG_DIR"
LOG_FILE="${LOG_DIR}/${BACKUP_ID}.log"

# Logging functions
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$1"; }
log_success() { log "SUCCESS" "$1"; SUCCESSFUL=$((SUCCESSFUL + 1)); }
log_warning() { log "WARNING" "$1"; WARNING=$((WARNING + 1)); }
log_error() { log "ERROR" "$1"; FAILED=$((FAILED + 1)); }

show_help() {
    cat << EOF
Health-InfraOps Comprehensive Backup Script

Usage: $0 [options] [environment]

Environments:
  dev       - Development environment
  staging   - Staging environment
  prod      - Production environment

Options:
  -h, --help           Show this help message
  -t, --type TYPE      Backup type (full/incremental/differential)
  -c, --component TYPE Backup component (all/infrastructure/database/apps/config)
  --retention DAYS     Retention period in days (default: 30)
  --verify             Verify backup after creation
  --encrypt            Encrypt backup files
  --upload-cloud       Upload to cloud storage
  --dry-run           Dry run mode

Examples:
  $0 prod --type full --component all
  $0 dev --type incremental --component database
  $0 staging --verify --upload-cloud
  $0 --type full --retention 60 --encrypt
EOF
}

# Configuration
load_config() {
    local environment=$1
    local config_file="${CONFIG_DIR}/group_vars/${environment}/backup.yml"
    
    if [ -f "$config_file" ]; then
        log_info "Loading backup configuration from: $config_file"
        # shellcheck source=/dev/null
        source "$config_file"
    else
        log_warning "No backup configuration found, using defaults"
    fi
    
    # Default values
    BACKUP_TYPE=${BACKUP_TYPE:-"incremental"}
    RETENTION_DAYS=${RETENTION_DAYS:-30}
    ENCRYPT_BACKUPS=${ENCRYPT_BACKUPS:-false}
    UPLOAD_TO_CLOUD=${UPLOAD_TO_CLOUD:-false}
    VERIFY_BACKUPS=${VERIFY_BACKUPS:-true}
}

# Pre-backup checks
pre_backup_checks() {
    log_info "Running pre-backup checks..."
    
    # Check disk space
    local available_space
    available_space=$(df "$BACKUP_DIR" | awk 'NR==2 {print $4}')
    local min_space=$((1024 * 1024 * 1024)) # 1GB in KB
    
    if [ "$available_space" -lt "$min_space" ]; then
        log_error "Insufficient disk space for backup. Available: ${available_space}KB"
        return 1
    fi
    
    # Check required tools
    local required_tools=("tar" "gzip" "openssl" "mysqldump" "mongodump")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_warning "$tool is not installed"
        fi
    done
    
    # Check cloud credentials if upload enabled
    if [ "$UPLOAD_TO_CLOUD" = true ] && [ -z "$AWS_ACCESS_KEY_ID" ]; then
        log_warning "AWS credentials not set for cloud upload"
    fi
    
    log_success "Pre-backup checks completed"
}

# Encryption functions
encrypt_file() {
    local file_path=$1
    local encrypted_file="${file_path}.enc"
    
    if [ "$ENCRYPT_BACKUPS" = true ] && [ -n "$BACKUP_ENCRYPTION_KEY" ]; then
        log_info "Encrypting backup file: $file_path"
        openssl enc -aes-256-cbc -salt -in "$file_path" -out "$encrypted_file" -pass pass:"$BACKUP_ENCRYPTION_KEY"
        
        if [ $? -eq 0 ]; then
            rm -f "$file_path"
            log_success "File encrypted: $encrypted_file"
            echo "$encrypted_file"
        else
            log_error "Encryption failed for: $file_path"
            echo "$file_path"
        fi
    else
        echo "$file_path"
    fi
}

# Cloud upload functions
upload_to_cloud() {
    local file_path=$1
    local cloud_path="s3://health-infraops-backups/$(basename "$file_path")"
    
    if [ "$UPLOAD_TO_CLOUD" = true ]; then
        log_info "Uploading to cloud: $file_path"
        
        if aws s3 cp "$file_path" "$cloud_path" 2>&1 | tee -a "$LOG_FILE"; then
            log_success "Backup uploaded to cloud: $cloud_path"
        else
            log_error "Cloud upload failed: $file_path"
        fi
    fi
}

# Database backup functions
backup_mysql() {
    local server=$1
    local backup_path="$BACKUP_DIR/mysql"
    
    mkdir -p "$backup_path"
    local backup_file="${backup_path}/mysql_${server}_${TIMESTAMP}.sql"
    
    log_info "Backing up MySQL database on: $server"
    
    if ssh "$server" "mysqldump --all-databases --single-transaction --routines --triggers" > "$backup_file"; then
        log_success "MySQL backup completed: $backup_file"
        gzip "$backup_file"
        local final_file="${backup_file}.gz"
        final_file=$(encrypt_file "$final_file")
        upload_to_cloud "$final_file"
    else
        log_error "MySQL backup failed: $server"
    fi
}

backup_mongodb() {
    local server=$1
    local backup_path="$BACKUP_DIR/mongodb"
    
    mkdir -p "$backup_path"
    local backup_file="${backup_path}/mongodb_${server}_${TIMESTAMP}"
    
    log_info "Backing up MongoDB on: $server"
    
    if ssh "$server" "mongodump --out /tmp/mongodump_${TIMESTAMP}"; then
        if scp -r "$server:/tmp/mongodump_${TIMESTAMP}" "$backup_file"; then
            log_success "MongoDB backup completed: $backup_file"
            tar -czf "${backup_file}.tar.gz" "$backup_file"
            rm -rf "$backup_file"
            local final_file="${backup_file}.tar.gz"
            final_file=$(encrypt_file "$final_file")
            upload_to_cloud "$final_file"
        else
            log_error "MongoDB backup copy failed: $server"
        fi
        ssh "$server" "rm -rf /tmp/mongodump_${TIMESTAMP}"
    else
        log_error "MongoDB backup failed: $server"
    fi
}

backup_postgresql() {
    local server=$1
    local backup_path="$BACKUP_DIR/postgresql"
    
    mkdir -p "$backup_path"
    local backup_file="${backup_path}/postgresql_${server}_${TIMESTAMP}.sql"
    
    log_info "Backing up PostgreSQL on: $server"
    
    if ssh "$server" "pg_dumpall" > "$backup_file"; then
        log_success "PostgreSQL backup completed: $backup_file"
        gzip "$backup_file"
        local final_file="${backup_file}.gz"
        final_file=$(encrypt_file "$final_file")
        upload_to_cloud "$final_file"
    else
        log_error "PostgreSQL backup failed: $server"
    fi
}

# Application backup functions
backup_application_data() {
    local server=$1
    local app_type=$2
    local backup_path="$BACKUP_DIR/applications"
    
    mkdir -p "$backup_path"
    local backup_file="${backup_path}/${app_type}_${server}_${TIMESTAMP}.tar.gz"
    
    log_info "Backing up $app_type application data on: $server"
    
    case $app_type in
        nginx)
            ssh "$server" "tar -czf /tmp/nginx_backup.tar.gz /etc/nginx /var/log/nginx /var/www/html"
            ;;
        nodejs)
            ssh "$server" "tar -czf /tmp/app_backup.tar.gz /opt/app /etc/pm2"
            ;;
        *)
            ssh "$server" "tar -czf /tmp/app_backup.tar.gz /opt/app /etc/nginx /var/www/html"
            ;;
    esac
    
    if scp "$server:/tmp/app_backup.tar.gz" "$backup_file"; then
        log_success "Application backup completed: $backup_file"
        ssh "$server" "rm -f /tmp/app_backup.tar.gz"
        final_file=$(encrypt_file "$backup_file")
        upload_to_cloud "$final_file"
    else
        log_error "Application backup failed: $server"
    fi
}

# Configuration backup
backup_configurations() {
    local environment=$1
    local backup_path="$BACKUP_DIR/configurations"
    
    mkdir -p "$backup_path"
    local backup_file="${backup_path}/config_${environment}_${TIMESTAMP}.tar.gz"
    
    log_info "Backing up configuration files for: $environment"
    
    # Backup Ansible configurations
    tar -czf "$backup_file" \
        "$CONFIG_DIR/inventory/$environment" \
        "$CONFIG_DIR/group_vars/$environment" \
        "$CONFIG_DIR/playbooks" \
        "$PROJECT_ROOT/automation/terraform/environments/$environment" \
        "$PROJECT_ROOT/documentation"
    
    if [ $? -eq 0 ]; then
        log_success "Configuration backup completed: $backup_file"
        final_file=$(encrypt_file "$backup_file")
        upload_to_cloud "$final_file"
    else
        log_error "Configuration backup failed"
    fi
}

# Infrastructure backup
backup_infrastructure() {
    local environment=$1
    local backup_path="$BACKUP_DIR/infrastructure"
    
    mkdir -p "$backup_path"
    local backup_file="${backup_path}/infra_${environment}_${TIMESTAMP}.tar.gz"
    
    log_info "Backing up infrastructure state for: $environment"
    
    # Backup Terraform state
    local tf_state_dir="$PROJECT_ROOT/automation/terraform/environments/$environment"
    if [ -d "$tf_state_dir" ]; then
        tar -czf "$backup_file" \
            "$tf_state_dir/.terraform" \
            "$tf_state_dir/*.tfstate*" \
            "$tf_state_dir/*.tfplan"
        
        if [ $? -eq 0 ]; then
            log_success "Infrastructure backup completed: $backup_file"
            final_file=$(encrypt_file "$backup_file")
            upload_to_cloud "$final_file"
        else
            log_error "Infrastructure backup failed"
        fi
    else
        log_warning "Terraform directory not found: $tf_state_dir"
    fi
}

# Verify backup integrity
verify_backup() {
    local backup_file=$1
    
    log_info "Verifying backup integrity: $backup_file"
    
    if [[ "$backup_file" == *.enc ]]; then
        # For encrypted files, test decryption
        if [ -n "$BACKUP_ENCRYPTION_KEY" ]; then
            if openssl enc -d -aes-256-cbc -in "$backup_file" -out /dev/null -pass pass:"$BACKUP_ENCRYPTION_KEY" 2>/dev/null; then
                log_success "Encrypted backup verification passed: $backup_file"
            else
                log_error "Encrypted backup verification failed: $backup_file"
            fi
        fi
    elif [[ "$backup_file" == *.tar.gz ]] || [[ "$backup_file" == *.gz ]]; then
        # For compressed files, test extraction
        if tar -tzf "$backup_file" > /dev/null 2>&1; then
            log_success "Compressed backup verification passed: $backup_file"
        else
            log_error "Compressed backup verification failed: $backup_file"
        fi
    else
        # For regular files, check if not empty
        if [ -s "$backup_file" ]; then
            log_success "Backup file verification passed: $backup_file"
        else
            log_error "Backup file is empty: $backup_file"
        fi
    fi
}

# Cleanup old backups
cleanup_old_backups() {
    local retention_days=$1
    
    log_info "Cleaning up backups older than $retention_days days"
    
    find "$BACKUP_DIR" -name "*.gz" -type f -mtime "+$retention_days" -delete
    find "$BACKUP_DIR" -name "*.enc" -type f -mtime "+$retention_days" -delete
    find "$BACKUP_DIR" -name "*.sql" -type f -mtime "+$retention_days" -delete
    find "$BACKUP_DIR" -name "*.tar" -type f -mtime "+$retention_days" -delete
    
    log_success "Old backups cleanup completed"
}

# Main backup function
main_backup() {
    local environment=$1
    local backup_type=$2
    local component=$3
    
    ENVIRONMENT=${environment:-"prod"}
    BACKUP_TYPE=${backup_type:-"incremental"}
    COMPONENT=${component:-"all"}
    
    log_info "Starting backup - Environment: $ENVIRONMENT, Type: $BACKUP_TYPE, Component: $COMPONENT"
    
    # Load configuration
    load_config "$ENVIRONMENT"
    
    # Pre-backup checks
    pre_backup_checks || exit 1
    
    # Get server list from inventory
    local inventory="${CONFIG_DIR}/inventory/${ENVIRONMENT}"
    
    if [ ! -f "$inventory" ]; then
        log_error "Inventory file not found: $inventory"
        exit 1
    fi
    
    # Perform backups based on component
    case $COMPONENT in
        all)
            backup_infrastructure "$ENVIRONMENT"
            backup_configurations "$ENVIRONMENT"
            
            # Database backups
            local db_servers
            db_servers=$(grep -E '^[0-9].*db' "$inventory" | awk '{print $1}')
            for server in $db_servers; do
                if ssh "$server" "which mysql" &> /dev/null; then
                    backup_mysql "$server"
                fi
                if ssh "$server" "which mongod" &> /dev/null; then
                    backup_mongodb "$server"
                fi
                if ssh "$server" "which psql" &> /dev/null; then
                    backup_postgresql "$server"
                fi
            done
            
            # Application backups
            local app_servers
            app_servers=$(grep -E '^[0-9].*app' "$inventory" | awk '{print $1}')
            for server in $app_servers; do
                backup_application_data "$server" "nodejs"
            done
            
            local web_servers
            web_servers=$(grep -E '^[0-9].*web' "$inventory" | awk '{print $1}')
            for server in $web_servers; do
                backup_application_data "$server" "nginx"
            done
            ;;
        
        database)
            local db_servers
            db_servers=$(grep -E '^[0-9].*db' "$inventory" | awk '{print $1}')
            for server in $db_servers; do
                if ssh "$server" "which mysql" &> /dev/null; then
                    backup_mysql "$server"
                fi
                if ssh "$server" "which mongod" &> /dev/null; then
                    backup_mongodb "$server"
                fi
            done
            ;;
        
        infrastructure)
            backup_infrastructure "$ENVIRONMENT"
            ;;
        
        apps)
            local app_servers
            app_servers=$(grep -E '^[0-9].*app' "$inventory" | awk '{print $1}')
            for server in $app_servers; do
                backup_application_data "$server" "nodejs"
            done
            ;;
        
        config)
            backup_configurations "$ENVIRONMENT"
            ;;
    esac
    
    # Verify backups if requested
    if [ "$VERIFY_BACKUPS" = true ]; then
        log_info "Verifying backups..."
        find "$BACKUP_DIR" -name "*${TIMESTAMP}*" -type f | while read -r backup_file; do
            verify_backup "$backup_file"
        done
    fi
    
    # Cleanup old backups
    cleanup_old_backups "$RETENTION_DAYS"
    
    # Generate summary
    local total_backups=$((SUCCESSFUL + FAILED + WARNING))
    log_info "Backup summary:"
    log_info "  Total operations: $total_backups"
    log_info "  Successful: $SUCCESSFUL"
    log_info "  Failed: $FAILED"
    log_info "  Warnings: $WARNING"
    log_info "  Backup ID: $BACKUP_ID"
    log_info "  Log file: $LOG_FILE"
    
    # Final status
    if [ "$FAILED" -gt 0 ]; then
        log_error "Backup completed with failures"
        exit 1
    elif [ "$WARNING" -gt 0 ]; then
        log_warning "Backup completed with warnings"
        exit 0
    else
        log_success "All backups completed successfully"
        exit 0
    fi
}

# Parse arguments
ENVIRONMENT="prod"
BACKUP_TYPE="incremental"
COMPONENT="all"
RETENTION_DAYS=30
VERIFY_BACKUPS=false
ENCRYPT_BACKUPS=false
UPLOAD_TO_CLOUD=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -t|--type)
            BACKUP_TYPE=$2
            shift 2
            ;;
        -c|--component)
            COMPONENT=$2
            shift 2
            ;;
        --retention)
            RETENTION_DAYS=$2
            shift 2
            ;;
        --verify)
            VERIFY_BACKUPS=true
            shift
            ;;
        --encrypt)
            ENCRYPT_BACKUPS=true
            shift
            ;;
        --upload-cloud)
            UPLOAD_TO_CLOUD=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        dev|staging|prod)
            ENVIRONMENT=$1
            shift
            ;;
        *)
            log_error "Unknown argument: $1"
            show_help
            exit 1
            ;;
    esac
done

# Export settings
export BACKUP_ENCRYPTION_KEY=${BACKUP_ENCRYPTION_KEY:-""}
export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-""}
export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-""}

# Execute main function
if [ "$DRY_RUN" = true ]; then
    log_info "DRY RUN - No backups will be actually performed"
    log_info "Environment: $ENVIRONMENT"
    log_info "Backup type: $BACKUP_TYPE"
    log_info "Component: $COMPONENT"
    log_info "Retention: $RETENTION_DAYS days"
    exit 0
else
    main_backup "$ENVIRONMENT" "$BACKUP_TYPE" "$COMPONENT"
fi
