#!/bin/bash

# Health-InfraOps Full Backup Script
# Comprehensive full backup of all infrastructure components

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
PROJECT_ROOT="$(dirname "$(dirname "$BACKUP_ROOT")")"
CONFIG_DIR="$PROJECT_ROOT/automation/ansible"

# Configuration
BACKUP_DIR="$BACKUP_ROOT/data/full"
LOG_DIR="$BACKUP_ROOT/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_ID="full_${TIMESTAMP}"
RETENTION_DAYS=30

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$BACKUP_DIR" "$LOG_DIR"
LOG_FILE="$LOG_DIR/${BACKUP_ID}.log"

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

show_help() {
    cat << EOF
Health-InfraOps Full Backup Script

Usage: $0 [options]

Options:
  -h, --help           Show this help message
  -e, --environment    Environment (dev/staging/prod)
  --encrypt            Encrypt backup files
  --verify             Verify backup after creation
  --upload-cloud       Upload to cloud storage
  --retention DAYS     Retention period in days (default: 30)
  --dry-run           Dry run mode

Examples:
  $0 --environment prod --encrypt --verify
  $0 --environment staging --upload-cloud
  $0 --environment dev --dry-run
EOF
}

# Pre-flight checks
preflight_checks() {
    log_info "Running pre-flight checks..."
    
    # Check disk space
    local available_space
    available_space=$(df "$BACKUP_DIR" | awk 'NR==2 {print $4}')
    local min_space=$((50 * 1024 * 1024)) # 50GB in KB
    
    if [ "$available_space" -lt "$min_space" ]; then
        log_error "Insufficient disk space. Available: ${available_space}KB, Required: ${min_space}KB"
        return 1
    fi
    
    # Check required tools
    local required_tools=("tar" "gzip" "openssl" "mysqldump" "mongodump")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_warning "$tool is not installed"
        fi
    done
    
    # Check if servers are accessible
    if [ -n "$ENVIRONMENT" ]; then
        local inventory="$CONFIG_DIR/inventory/$ENVIRONMENT"
        if [ ! -f "$inventory" ]; then
            log_warning "Inventory file not found: $inventory"
        fi
    fi
    
    log_success "Pre-flight checks completed"
}

# Encryption function
encrypt_backup() {
    local file_path=$1
    local encrypted_file="${file_path}.enc"
    
    if [ "$ENCRYPT_BACKUP" = true ] && [ -n "$BACKUP_ENCRYPTION_KEY" ]; then
        log_info "Encrypting backup: $(basename "$file_path")"
        openssl enc -aes-256-cbc -salt -pbkdf2 \
            -in "$file_path" \
            -out "$encrypted_file" \
            -pass pass:"$BACKUP_ENCRYPTION_KEY"
        
        if [ $? -eq 0 ]; then
            rm -f "$file_path"
            log_success "Backup encrypted: $(basename "$encrypted_file")"
            echo "$encrypted_file"
        else
            log_error "Encryption failed: $(basename "$file_path")"
            echo "$file_path"
        fi
    else
        echo "$file_path"
    fi
}

# Cloud upload function
upload_to_cloud() {
    local file_path=$1
    local cloud_destination="s3://health-infraops-backups/full/$(basename "$file_path")"
    
    if [ "$UPLOAD_CLOUD" = true ] && command -v aws &> /dev/null; then
        log_info "Uploading to cloud: $(basename "$file_path")"
        if aws s3 cp "$file_path" "$cloud_destination" 2>&1 | tee -a "$LOG_FILE"; then
            log_success "Backup uploaded to cloud: $cloud_destination"
        else
            log_error "Cloud upload failed: $(basename "$file_path")"
        fi
    fi
}

# Database backups
backup_mysql_databases() {
    local server=$1
    local backup_path="$BACKUP_DIR/mysql"
    
    mkdir -p "$backup_path"
    local backup_file="$backup_path/mysql_${server}_${TIMESTAMP}.sql"
    
    log_info "Backing up MySQL databases on: $server"
    
    # Get list of databases (excluding system databases)
    local databases
    databases=$(ssh "$server" "mysql -e 'SHOW DATABASES;' | grep -Ev '(Database|information_schema|performance_schema|sys)'")
    
    for db in $databases; do
        log_info "Backing up database: $db"
        ssh "$server" "mysqldump --single-transaction --routines --triggers --databases $db" >> "$backup_file"
        
        if [ $? -ne 0 ]; then
            log_error "MySQL backup failed for database: $db on $server"
            return 1
        fi
    done
    
    # Compress backup
    gzip "$backup_file"
    local final_file="${backup_file}.gz"
    
    # Encrypt if requested
    final_file=$(encrypt_backup "$final_file")
    
    # Upload to cloud
    upload_to_cloud "$final_file"
    
    log_success "MySQL backup completed: $(basename "$final_file")"
    echo "$final_file"
}

backup_mongodb_databases() {
    local server=$1
    local backup_path="$BACKUP_DIR/mongodb"
    
    mkdir -p "$backup_path"
    local backup_file="$backup_path/mongodb_${server}_${TIMESTAMP}"
    
    log_info "Backing up MongoDB on: $server"
    
    # Create mongodump on remote server
    if ssh "$server" "mongodump --out /tmp/mongodump_${TIMESTAMP} --quiet"; then
        # Copy backup to local
        if scp -r "$server:/tmp/mongodump_${TIMESTAMP}" "$backup_file"; then
            # Compress backup
            tar -czf "${backup_file}.tar.gz" "$backup_file"
            rm -rf "$backup_file"
            local final_file="${backup_file}.tar.gz"
            
            # Cleanup remote
            ssh "$server" "rm -rf /tmp/mongodump_${TIMESTAMP}"
            
            # Encrypt if requested
            final_file=$(encrypt_backup "$final_file")
            
            # Upload to cloud
            upload_to_cloud "$final_file"
            
            log_success "MongoDB backup completed: $(basename "$final_file")"
            echo "$final_file"
        else
            log_error "MongoDB backup copy failed: $server"
            ssh "$server" "rm -rf /tmp/mongodump_${TIMESTAMP}"
            return 1
        fi
    else
        log_error "MongoDB backup failed: $server"
        return 1
    fi
}

# Configuration backup
backup_configurations() {
    local backup_path="$BACKUP_DIR/configurations"
    local backup_file="$backup_path/config_${TIMESTAMP}.tar.gz"
    
    mkdir -p "$backup_path"
    
    log_info "Backing up configuration files..."
    
    # Backup critical configurations
    tar -czf "$backup_file" \
        "$CONFIG_DIR" \
        "$PROJECT_ROOT/infrastructure" \
        "$PROJECT_ROOT/servers" \
        "$PROJECT_ROOT/networking" \
        "$PROJECT_ROOT/security" \
        "$PROJECT_ROOT/automation" \
        "$PROJECT_ROOT/documentation" \
        2>/dev/null || true
    
    # Encrypt if requested
    local final_file
    final_file=$(encrypt_backup "$backup_file")
    
    # Upload to cloud
    upload_to_cloud "$final_file"
    
    log_success "Configuration backup completed: $(basename "$final_file")"
    echo "$final_file"
}

# Application data backup
backup_application_data() {
    local server=$1
    local app_type=$2
    local backup_path="$BACKUP_DIR/applications"
    
    mkdir -p "$backup_path"
    local backup_file="$backup_path/${app_type}_${server}_${TIMESTAMP}.tar.gz"
    
    log_info "Backing up $app_type application data on: $server"
    
    case $app_type in
        nginx)
            ssh "$server" "tar -czf /tmp/nginx_backup.tar.gz /etc/nginx /var/log/nginx /var/www/html 2>/dev/null"
            ;;
        nodejs)
            ssh "$server" "tar -czf /tmp/app_backup.tar.gz /opt/app /etc/pm2 /var/log/pm2 2>/dev/null"
            ;;
        apache)
            ssh "$server" "tar -czf /tmp/apache_backup.tar.gz /etc/apache2 /var/www/html /var/log/apache2 2>/dev/null"
            ;;
        *)
            ssh "$server" "tar -czf /tmp/app_backup.tar.gz /opt/app /etc/nginx /var/www/html 2>/dev/null"
            ;;
    esac
    
    if scp "$server:/tmp/app_backup.tar.gz" "$backup_file"; then
        ssh "$server" "rm -f /tmp/app_backup.tar.gz"
        
        # Encrypt if requested
        local final_file
        final_file=$(encrypt_backup "$backup_file")
        
        # Upload to cloud
        upload_to_cloud "$final_file"
        
        log_success "Application backup completed: $(basename "$final_file")"
        echo "$final_file"
    else
        log_error "Application backup failed: $server"
        return 1
    fi
}

# VM backup (Proxmox)
backup_virtual_machines() {
    local backup_path="$BACKUP_DIR/virtual-machines"
    
    mkdir -p "$backup_path"
    
    log_info "Backing up virtual machines..."
    
    # Get list of VMs from Proxmox
    local vm_list
    vm_list=$(pvesh get /cluster/resources --type vm | jq -r '.[] | select(.type == "qemu") | .vmid')
    
    for vmid in $vm_list; do
        log_info "Backing up VM: $vmid"
        local backup_file="$backup_path/vm_${vmid}_${TIMESTAMP}.tar.gz"
        
        # Create VM backup (this would need Proxmox backup tools)
        # For now, we'll document the process
        log_warning "VM backup for $vmid - manual process required"
        echo "Backup process for VM $vmid documented in recovery procedures"
    done
    
    log_success "VM backup process initiated"
}

# Infrastructure state backup
backup_infrastructure_state() {
    local backup_path="$BACKUP_DIR/infrastructure"
    local backup_file="$backup_path/infra_state_${TIMESTAMP}.tar.gz"
    
    mkdir -p "$backup_path"
    
    log_info "Backing up infrastructure state..."
    
    # Backup Terraform states
    tar -czf "$backup_file" \
        "$PROJECT_ROOT/automation/terraform" \
        "$PROJECT_ROOT/infrastructure" \
        2>/dev/null || true
    
    # Encrypt if requested
    local final_file
    final_file=$(encrypt_backup "$backup_file")
    
    # Upload to cloud
    upload_to_cloud "$final_file"
    
    log_success "Infrastructure state backup completed: $(basename "$final_file")"
    echo "$final_file"
}

# Log files backup
backup_log_files() {
    local server=$1
    local backup_path="$BACKUP_DIR/logs"
    
    mkdir -p "$backup_path"
    local backup_file="$backup_path/logs_${server}_${TIMESTAMP}.tar.gz"
    
    log_info "Backing up log files on: $server"
    
    # Backup important log files
    ssh "$server" "tar -czf /tmp/logs_backup.tar.gz /var/log/nginx /var/log/mysql /var/log/syslog /var/log/auth.log 2>/dev/null"
    
    if scp "$server:/tmp/logs_backup.tar.gz" "$backup_file"; then
        ssh "$server" "rm -f /tmp/logs_backup.tar.gz"
        
        # Encrypt if requested
        local final_file
        final_file=$(encrypt_backup "$backup_file")
        
        # Upload to cloud
        upload_to_cloud "$final_file"
        
        log_success "Log files backup completed: $(basename "$final_file")"
        echo "$final_file"
    else
        log_error "Log files backup failed: $server"
        return 1
    fi
}

# Verification function
verify_backup() {
    local backup_file=$1
    
    log_info "Verifying backup: $(basename "$backup_file")"
    
    if [[ "$backup_file" == *.enc ]]; then
        # Test encrypted file
        if openssl enc -d -aes-256-cbc -pbkdf2 \
            -in "$backup_file" \
            -out /dev/null \
            -pass pass:"$BACKUP_ENCRYPTION_KEY" 2>/dev/null; then
            log_success "Encrypted backup verification passed: $(basename "$backup_file")"
        else
            log_error "Encrypted backup verification failed: $(basename "$backup_file")"
            return 1
        fi
    elif [[ "$backup_file" == *.tar.gz ]] || [[ "$backup_file" == *.gz ]]; then
        # Test compressed file
        if tar -tzf "$backup_file" > /dev/null 2>&1; then
            log_success "Compressed backup verification passed: $(basename "$backup_file")"
        else
            log_error "Compressed backup verification failed: $(basename "$backup_file")"
            return 1
        fi
    else
        # Test regular file
        if [ -s "$backup_file" ]; then
            log_success "Backup file verification passed: $(basename "$backup_file")"
        else
            log_error "Backup file is empty: $(basename "$backup_file")"
            return 1
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
    
    # Also cleanup cloud backups if applicable
    if [ "$UPLOAD_CLOUD" = true ] && command -v aws &> /dev/null; then
        aws s3 ls s3://health-infraops-backups/full/ | \
        while read -r line; do
            local date_part
            date_part=$(echo "$line" | awk '{print $1}')
            local file_name
            file_name=$(echo "$line" | awk '{print $4}')
            local file_date
            file_date=$(date -d "$date_part" +%s)
            local cutoff_date
            cutoff_date=$(date -d "$retention_days days ago" +%s)
            
            if [ "$file_date" -lt "$cutoff_date" ]; then
                aws s3 rm "s3://health-infraops-backups/full/$file_name"
                log_info "Deleted old cloud backup: $file_name"
            fi
        done
    fi
    
    log_success "Old backups cleanup completed"
}

# Main backup function
main_backup() {
    log_info "Starting FULL backup process - ID: $BACKUP_ID"
    log_info "Backup directory: $BACKUP_DIR"
    log_info "Log file: $LOG_FILE"
    
    # Pre-flight checks
    preflight_checks || exit 1
    
    local backup_files=()
    
    # Get server list from inventory
    if [ -n "$ENVIRONMENT" ]; then
        local inventory="$CONFIG_DIR/inventory/$ENVIRONMENT"
        if [ -f "$inventory" ]; then
            local servers
            servers=$(grep -E '^[0-9]' "$inventory" | awk '{print $1}')
            
            # Backup databases
            local db_servers
            db_servers=$(grep -E '^[0-9].*db' "$inventory" | awk '{print $1}')
            for server in $db_servers; do
                if ssh "$server" "which mysql" &> /dev/null; then
                    local mysql_backup
                    mysql_backup=$(backup_mysql_databases "$server")
                    backup_files+=("$mysql_backup")
                fi
                
                if ssh "$server" "which mongod" &> /dev/null; then
                    local mongodb_backup
                    mongodb_backup=$(backup_mongodb_databases "$server")
                    backup_files+=("$mongodb_backup")
                fi
            done
            
            # Backup applications
            local app_servers
            app_servers=$(grep -E '^[0-9].*app' "$inventory" | awk '{print $1}')
            for server in $app_servers; do
                local app_backup
                app_backup=$(backup_application_data "$server" "nodejs")
                backup_files+=("$app_backup")
            done
            
            local web_servers
            web_servers=$(grep -E '^[0-9].*web' "$inventory" | awk '{print $1}')
            for server in $web_servers; do
                local web_backup
                web_backup=$(backup_application_data "$server" "nginx")
                backup_files+=("$web_backup")
            done
            
            # Backup logs
            for server in $servers; do
                local log_backup
                log_backup=$(backup_log_files "$server")
                backup_files+=("$log_backup")
            done
        fi
    fi
    
    # Backup configurations and infrastructure
    local config_backup
    config_backup=$(backup_configurations)
    backup_files+=("$config_backup")
    
    local infra_backup
    infra_backup=$(backup_infrastructure_state)
    backup_files+=("$infra_backup")
    
    # Backup VMs (if Proxmox environment)
    if command -v pvesh &> /dev/null; then
        backup_virtual_machines
    fi
    
    # Verify backups if requested
    if [ "$VERIFY_BACKUP" = true ]; then
        log_info "Verifying all backups..."
        for backup_file in "${backup_files[@]}"; do
            if [ -n "$backup_file" ] && [ -f "$backup_file" ]; then
                verify_backup "$backup_file"
            fi
        done
    fi
    
    # Cleanup old backups
    cleanup_old_backups "$RETENTION_DAYS"
    
    # Generate backup manifest
    local manifest_file="$BACKUP_DIR/${BACKUP_ID}.manifest"
    {
        echo "Backup ID: $BACKUP_ID"
        echo "Timestamp: $(date)"
        echo "Environment: $ENVIRONMENT"
        echo "Backup Files:"
        for backup_file in "${backup_files[@]}"; do
            if [ -n "$backup_file" ] && [ -f "$backup_file" ]; then
                echo "  - $(basename "$backup_file")"
            fi
        done
        echo "Total Size: $(du -sh "$BACKUP_DIR" | cut -f1)"
    } > "$manifest_file"
    
    log_success "FULL backup completed successfully"
    log_info "Backup ID: $BACKUP_ID"
    log_info "Manifest file: $manifest_file"
    log_info "Total backup size: $(du -sh "$BACKUP_DIR" | cut -f1)"
}

# Parse arguments
ENVIRONMENT=""
ENCRYPT_BACKUP=false
VERIFY_BACKUP=false
UPLOAD_CLOUD=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -e|--environment)
            ENVIRONMENT=$2
            shift 2
            ;;
        --encrypt)
            ENCRYPT_BACKUP=true
            shift
            ;;
        --verify)
            VERIFY_BACKUP=true
            shift
            ;;
        --upload-cloud)
            UPLOAD_CLOUD=true
            shift
            ;;
        --retention)
            RETENTION_DAYS=$2
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            log_error "Unknown argument: $1"
            show_help
            exit 1
            ;;
    esac
done

# Export encryption key if provided
export BACKUP_ENCRYPTION_KEY=${BACKUP_ENCRYPTION_KEY:-""}

if [ "$DRY_RUN" = true ]; then
    log_info "DRY RUN - No backups will be actually performed"
    log_info "Environment: $ENVIRONMENT"
    log_info "Encryption: $ENCRYPT_BACKUP"
    log_info "Verification: $VERIFY_BACKUP"
    log_info "Cloud Upload: $UPLOAD_CLOUD"
    log_info "Retention: $RETENTION_DAYS days"
    exit 0
fi

# Execute main backup function
main_backup