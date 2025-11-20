#!/bin/bash

# Health-InfraOps Incremental Backup Script
# Efficient incremental backup of changed data since last backup

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
PROJECT_ROOT="$(dirname "$(dirname "$BACKUP_ROOT")")"
CONFIG_DIR="$PROJECT_ROOT/automation/ansible"

# Configuration
BACKUP_DIR="$BACKUP_ROOT/data/incremental"
FULL_BACKUP_DIR="$BACKUP_ROOT/data/full"
LOG_DIR="$BACKUP_ROOT/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_ID="incremental_${TIMESTAMP}"
RETENTION_DAYS=7

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
Health-InfraOps Incremental Backup Script

Usage: $0 [options]

Options:
  -h, --help           Show this help message
  -e, --environment    Environment (dev/staging/prod)
  --since DATE         Backup changes since specific date (YYYY-MM-DD)
  --since-last-full   Backup changes since last full backup
  --encrypt           Encrypt backup files
  --verify            Verify backup after creation
  --upload-cloud      Upload to cloud storage
  --dry-run          Dry run mode

Examples:
  $0 --environment prod --since-last-full --encrypt
  $0 --environment staging --since 2023-12-01
  $0 --environment dev --dry-run
EOF
}

# Find last full backup
find_last_full_backup() {
    local last_backup
    last_backup=$(find "$FULL_BACKUP_DIR" -name "full_*.manifest" -type f | sort -r | head -1)
    
    if [ -n "$last_backup" ]; then
        local backup_date
        backup_date=$(basename "$last_backup" | cut -d'_' -f2)
        echo "$backup_date"
    else
        log_error "No full backup found. Please run full backup first."
        exit 1
    fi
}

# MySQL incremental backup
backup_mysql_incremental() {
    local server=$1
    local since_date=$2
    local backup_path="$BACKUP_DIR/mysql"
    
    mkdir -p "$backup_path"
    local backup_file="$backup_path/mysql_inc_${server}_${TIMESTAMP}.sql"
    
    log_info "Creating MySQL incremental backup on: $server since $since_date"
    
    # Get list of databases
    local databases
    databases=$(ssh "$server" "mysql -e 'SHOW DATABASES;' | grep -Ev '(Database|information_schema|performance_schema|sys)'")
    
    for db in $databases; do
        log_info "Backing up changes in database: $db"
        
        # Backup new/changed tables data
        ssh "$server" "mysqldump --single-transaction --where=\"updated_at >= '$since_date'\" --databases $db" >> "$backup_file"
        
        # Backup new stored procedures and functions
        ssh "$server" "mysqldump --routines --triggers --no-create-info --no-data --no-create-db --databases $db" >> "$backup_file"
    done
    
    # Compress backup
    gzip "$backup_file"
    local final_file="${backup_file}.gz"
    
    log_success "MySQL incremental backup completed: $(basename "$final_file")"
    echo "$final_file"
}

# MongoDB incremental backup
backup_mongodb_incremental() {
    local server=$1
    local since_date=$2
    local backup_path="$BACKUP_DIR/mongodb"
    
    mkdir -p "$backup_path"
    local backup_file="$backup_path/mongodb_inc_${server}_${TIMESTAMP}"
    
    log_info "Creating MongoDB incremental backup on: $server since $since_date"
    
    # Use mongodump with query for incremental backup
    local since_timestamp
    since_timestamp=$(date -d "$since_date" +%s)
    
    # Backup only documents modified since last backup
    ssh "$server" "mongodump --query '{\"updatedAt\": {\"\$gte\": new Date($since_timestamp * 1000)}}' --out /tmp/mongodump_inc_${TIMESTAMP}"
    
    if scp -r "$server:/tmp/mongodump_inc_${TIMESTAMP}" "$backup_file"; then
        tar -czf "${backup_file}.tar.gz" "$backup_file"
        rm -rf "$backup_file"
        local final_file="${backup_file}.tar.gz"
        
        ssh "$server" "rm -rf /tmp/mongodump_inc_${TIMESTAMP}"
        
        log_success "MongoDB incremental backup completed: $(basename "$final_file")"
        echo "$final_file"
    else
        log_error "MongoDB incremental backup failed: $server"
        return 1
    fi
}

# File system incremental backup
backup_files_incremental() {
    local server=$1
    local since_date=$2
    local backup_path="$BACKUP_DIR/files"
    
    mkdir -p "$backup_path"
    local backup_file="$backup_path/files_inc_${server}_${TIMESTAMP}.tar.gz"
    
    log_info "Creating filesystem incremental backup on: $server since $since_date"
    
    # Find files modified since last backup and create tar archive
    ssh "$server" "find /etc /opt /var/www -type f -newermt '$since_date' -print0 | tar -czf /tmp/files_inc_${TIMESTAMP}.tar.gz --null -T - 2>/dev/null || true"
    
    if scp "$server:/tmp/files_inc_${TIMESTAMP}.tar.gz" "$backup_file"; then
        ssh "$server" "rm -f /tmp/files_inc_${TIMESTAMP}.tar.gz"
        
        log_success "Filesystem incremental backup completed: $(basename "$backup_file")"
        echo "$backup_file"
    else
        log_error "Filesystem incremental backup failed: $server"
        return 1
    fi
}

# Application log incremental backup
backup_logs_incremental() {
    local server=$1
    local since_date=$2
    local backup_path="$BACKUP_DIR/logs"
    
    mkdir -p "$backup_path"
    local backup_file="$backup_path/logs_inc_${server}_${TIMESTAMP}.tar.gz"
    
    log_info "Creating logs incremental backup on: $server since $since_date"
    
    # Backup log files modified since last backup
    ssh "$server" "find /var/log -name '*.log' -type f -newermt '$since_date' -print0 | tar -czf /tmp/logs_inc_${TIMESTAMP}.tar.gz --null -T - 2>/dev/null || true"
    
    if scp "$server:/tmp/logs_inc_${TIMESTAMP}.tar.gz" "$backup_file"; then
        ssh "$server" "rm -f /tmp/logs_inc_${TIMESTAMP}.tar.gz"
        
        log_success "Logs incremental backup completed: $(basename "$backup_file")"
        echo "$backup_file"
    else
        log_error "Logs incremental backup failed: $server"
        return 1
    fi
}

# Configuration changes backup
backup_config_changes() {
    local since_date=$1
    local backup_path="$BACKUP_DIR/config"
    local backup_file="$backup_path/config_changes_${TIMESTAMP}.tar.gz"
    
    mkdir -p "$backup_path"
    
    log_info "Backing up configuration changes since $since_date"
    
    # Find changed configuration files in project
    find "$PROJECT_ROOT" -type f -name "*.conf" -o -name "*.yml" -o -name "*.yaml" -o -name "*.json" | \
    while read -r file; do
        if [ -f "$file" ] && [ "$(stat -c %Y "$file")" -ge "$(date -d "$since_date" +%s)" ]; then
            echo "$file"
        fi
    done | tar -czf "$backup_file" -T -
    
    log_success "Configuration changes backup completed: $(basename "$backup_file")"
    echo "$backup_file"
}

# Main incremental backup function
main_incremental_backup() {
    local since_date=$1
    
    log_info "Starting INCREMENTAL backup process - ID: $BACKUP_ID"
    log_info "Backup directory: $BACKUP_DIR"
    log_info "Since date: $since_date"
    log_info "Log file: $LOG_FILE"
    
    local backup_files=()
    
    # Get server list from inventory
    if [ -n "$ENVIRONMENT" ]; then
        local inventory="$CONFIG_DIR/inventory/$ENVIRONMENT"
        if [ -f "$inventory" ]; then
            local servers
            servers=$(grep -E '^[0-9]' "$inventory" | awk '{print $1}')
            
            # Database incremental backups
            local db_servers
            db_servers=$(grep -E '^[0-9].*db' "$inventory" | awk '{print $1}')
            for server in $db_servers; do
                if ssh "$server" "which mysql" &> /dev/null; then
                    local mysql_backup
                    mysql_backup=$(backup_mysql_incremental "$server" "$since_date")
                    backup_files+=("$mysql_backup")
                fi
                
                if ssh "$server" "which mongod" &> /dev/null; then
                    local mongodb_backup
                    mongodb_backup=$(backup_mongodb_incremental "$server" "$since_date")
                    backup_files+=("$mongodb_backup")
                fi
            done
            
            # Filesystem incremental backups
            for server in $servers; do
                local files_backup
                files_backup=$(backup_files_incremental "$server" "$since_date")
                backup_files+=("$files_backup")
                
                local logs_backup
                logs_backup=$(backup_logs_incremental "$server" "$since_date")
                backup_files+=("$logs_backup")
            done
        fi
    fi
    
    # Configuration changes backup
    local config_backup
    config_backup=$(backup_config_changes "$since_date")
    backup_files+=("$config_backup")
    
    # Generate incremental backup manifest
    local manifest_file="$BACKUP_DIR/${BACKUP_ID}.manifest"
    {
        echo "Incremental Backup ID: $BACKUP_ID"
        echo "Timestamp: $(date)"
        echo "Environment: $ENVIRONMENT"
        echo "Since Date: $since_date"
        echo "Backup Files:"
        for backup_file in "${backup_files[@]}"; do
            if [ -n "$backup_file" ] && [ -f "$backup_file" ]; then
                echo "  - $(basename "$backup_file")"
            fi
        done
        echo "Total Size: $(du -sh "$BACKUP_DIR" | cut -f1)"
    } > "$manifest_file"
    
    # Cleanup old incremental backups
    cleanup_old_backups
    
    log_success "INCREMENTAL backup completed successfully"
    log_info "Backup ID: $BACKUP_ID"
    log_info "Manifest file: $manifest_file"
    log_info "Total backup size: $(du -sh "$BACKUP_DIR" | cut -f1)"
}

# Cleanup old incremental backups
cleanup_old_backups() {
    log_info "Cleaning up incremental backups older than $RETENTION_DAYS days"
    
    find "$BACKUP_DIR" -name "*.gz" -type f -mtime "+$RETENTION_DAYS" -delete
    find "$BACKUP_DIR" -name "*.sql" -type f -mtime "+$RETENTION_DAYS" -delete
    find "$BACKUP_DIR" -name "*.tar" -type f -mtime "+$RETENTION_DAYS" -delete
    find "$BACKUP_DIR" -name "*.manifest" -type f -mtime "+$RETENTION_DAYS" -delete
    
    log_success "Old incremental backups cleanup completed"
}

# Parse arguments
ENVIRONMENT=""
SINCE_DATE=""
SINCE_LAST_FULL=false
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
        --since)
            SINCE_DATE=$2
            shift 2
            ;;
        --since-last-full)
            SINCE_LAST_FULL=true
            shift
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

# Determine since date
if [ "$SINCE_LAST_FULL" = true ]; then
    SINCE_DATE=$(find_last_full_backup)
elif [ -z "$SINCE_DATE" ]; then
    # Default to 1 day ago
    SINCE_DATE=$(date -d "1 day ago" +%Y-%m-%d)
fi

if [ "$DRY_RUN" = true ]; then
    log_info "DRY RUN - No backups will be actually performed"
    log_info "Environment: $ENVIRONMENT"
    log_info "Since Date: $SINCE_DATE"
    log_info "Encryption: $ENCRYPT_BACKUP"
    log_info "Verification: $VERIFY_BACKUP"
    log_info "Cloud Upload: $UPLOAD_CLOUD"
    exit 0
fi

# Execute main incremental backup function
main_incremental_backup "$SINCE_DATE"