#!/bin/bash

# Health-InfraOps Database Restoration Script
# Database recovery and restoration procedures

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
PROJECT_ROOT="$(dirname "$(dirname "$BACKUP_ROOT")")"
CONFIG_DIR="$PROJECT_ROOT/automation/ansible"

# Configuration
BACKUP_DIR="$BACKUP_ROOT/data"
LOG_DIR="$BACKUP_ROOT/logs"
RESTORE_DIR="/tmp/db-restore"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESTORE_ID="db_restore_${TIMESTAMP}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$RESTORE_DIR" "$LOG_DIR"
LOG_FILE="$LOG_DIR/${RESTORE_ID}.log"

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
Health-InfraOps Database Restoration Script

Usage: $0 [options] <database_type> <database_name>

Database Types:
  mysql      - MySQL database restoration
  mongodb    - MongoDB database restoration
  postgresql - PostgreSQL database restoration

Options:
  -h, --help           Show this help message
  -b, --backup ID      Use specific backup ID
  -s, --server HOST    Database server hostname
  -u, --user USER      Database username
  -p, --password PASS  Database password
  --tables TABLES      Restore specific tables (comma-separated)
  --where CLAUSE       WHERE clause for selective restore
  --dry-run           Dry run mode
  --force             Force restore without confirmation
  --no-data           Restore schema only, no data

Examples:
  $0 mysql patients --backup full_20231201_120000 --server db-01
  $0 mongodb medical_records --server db-02 --dry-run
  $0 mysql patients --tables "visits,prescriptions" --where "date > '2023-01-01'"
EOF
}

# Find database backup
find_db_backup() {
    local db_type=$1
    local db_name=$2
    local backup_id=$3
    
    if [ -n "$backup_id" ]; then
        local backup_file
        backup_file=$(find "$BACKUP_DIR" -name "*${backup_id}*" -type f | head -1)
        echo "$backup_file"
    else
        # Find latest backup for database type
        local backup_file
        case $db_type in
            mysql)
                backup_file=$(find "$BACKUP_DIR" -name "*mysql*" -type f | sort -r | head -1)
                ;;
            mongodb)
                backup_file=$(find "$BACKUP_DIR" -name "*mongodb*" -type f | sort -r | head -1)
                ;;
            postgresql)
                backup_file=$(find "$BACKUP_DIR" -name "*postgresql*" -type f | sort -r | head -1)
                ;;
        esac
        echo "$backup_file"
    fi
}

# MySQL restoration
restore_mysql() {
    local backup_file=$1
    local db_name=$2
    local server=$3
    
    log_info "Restoring MySQL database: $db_name from $(basename "$backup_file")"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would restore MySQL database $db_name from $(basename "$backup_file")"
        return 0
    fi
    
    # Prepare backup file
    local restore_source="$backup_file"
    
    if [[ "$backup_file" == *.enc ]]; then
        log_info "Decrypting MySQL backup..."
        local decrypted_file="$RESTORE_DIR/mysql_${db_name}_decrypted.sql"
        openssl enc -d -aes-256-cbc -pbkdf2 \
            -in "$backup_file" \
            -out "$decrypted_file" \
            -pass pass:"$BACKUP_ENCRYPTION_KEY"
        restore_source="$decrypted_file"
    fi
    
    if [[ "$restore_source" == *.gz ]]; then
        log_info "Decompressing MySQL backup..."
        gunzip -c "$restore_source" > "$RESTORE_DIR/mysql_${db_name}_restore.sql"
        restore_source="$RESTORE_DIR/mysql_${db_name}_restore.sql"
    fi
    
    # Create database if it doesn't exist
    log_info "Creating database: $db_name"
    ssh "$server" "mysql -e 'CREATE DATABASE IF NOT EXISTS $db_name;'"
    
    # Restore database
    log_info "Restoring MySQL data..."
    
    if [ -n "$RESTORE_TABLES" ]; then
        # Selective table restore
        IFS=',' read -ra tables <<< "$RESTORE_TABLES"
        for table in "${tables[@]}"; do
            log_info "Restoring table: $table"
            
            if [ -n "$WHERE_CLAUSE" ]; then
                # Selective data restore with WHERE clause
                ssh "$server" "mysql $db_name -e 'CREATE TABLE $table_backup LIKE $table;'"
                ssh "$server" "mysqldump $db_name $table --where=\"$WHERE_CLAUSE\" | mysql $db_name"
            else
                # Full table restore
                grep -E "(CREATE TABLE.*$table|INSERT INTO.*$table|DROP TABLE.*$table)" "$restore_source" | \
                ssh "$server" "mysql $db_name"
            fi
        done
    elif [ "$NO_DATA" = true ]; then
        # Schema only restore
        log_info "Restoring schema only (no data)"
        ssh "$server" "mysql $db_name" < <(grep -v -E "^INSERT INTO|^-- Data" "$restore_source")
    else
        # Full database restore
        log_info "Performing full database restore"
        ssh "$server" "mysql $db_name" < "$restore_source"
    fi
    
    # Cleanup
    rm -f "$RESTORE_DIR"/*.sql
    
    log_success "MySQL database restored: $db_name"
}

# MongoDB restoration
restore_mongodb() {
    local backup_file=$1
    local db_name=$2
    local server=$3
    
    log_info "Restoring MongoDB database: $db_name from $(basename "$backup_file")"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would restore MongoDB database $db_name from $(basename "$backup_file")"
        return 0
    fi
    
    # Prepare backup file
    local restore_source="$backup_file"
    
    if [[ "$backup_file" == *.enc ]]; then
        log_info "Decrypting MongoDB backup..."
        local decrypted_file="${backup_file%.enc}"
        openssl enc -d -aes-256-cbc -pbkdf2 \
            -in "$backup_file" \
            -out "$decrypted_file" \
            -pass pass:"$BACKUP_ENCRYPTION_KEY"
        restore_source="$decrypted_file"
    fi
    
    if [[ "$restore_source" == *.tar.gz ]]; then
        log_info "Extracting MongoDB backup..."
        tar -xzf "$restore_source" -C "$RESTORE_DIR"
        local extracted_dir
        extracted_dir=$(find "$RESTORE_DIR" -type d -name "mongodump*" | head -1)
        restore_source="$extracted_dir"
    fi
    
    # Restore database
    log_info "Restoring MongoDB data..."
    
    if [ -n "$RESTORE_TABLES" ]; then
        # Selective collection restore
        IFS=',' read -ra collections <<< "$RESTORE_TABLES"
        for collection in "${collections[@]}"; do
            log_info "Restoring collection: $collection"
            scp -r "$restore_source/$db_name/$collection.bson" "$server:/tmp/"
            ssh "$server" "mongorestore --db $db_name --collection $collection /tmp/$collection.bson"
            ssh "$server" "rm -f /tmp/$collection.bson"
        done
    else
        # Full database restore
        log_info "Performing full database restore"
        scp -r "$restore_source/$db_name" "$server:/tmp/mongorestore/"
        ssh "$server" "mongorestore --db $db_name /tmp/mongorestore/$db_name"
        ssh "$server" "rm -rf /tmp/mongorestore"
    fi
    
    # Cleanup
    rm -rf "$RESTORE_DIR"/*
    
    log_success "MongoDB database restored: $db_name"
}

# PostgreSQL restoration
restore_postgresql() {
    local backup_file=$1
    local db_name=$2
    local server=$3
    
    log_info "Restoring PostgreSQL database: $db_name from $(basename "$backup_file")"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would restore PostgreSQL database $db_name from $(basename "$backup_file")"
        return 0
    fi
    
    # Prepare backup file
    local restore_source="$backup_file"
    
    if [[ "$backup_file" == *.enc ]]; then
        log_info "Decrypting PostgreSQL backup..."
        local decrypted_file="$RESTORE_DIR/postgresql_${db_name}_decrypted.sql"
        openssl enc -d -aes-256-cbc -pbkdf2 \
            -in "$backup_file" \
            -out "$decrypted_file" \
            -pass pass:"$BACKUP_ENCRYPTION_KEY"
        restore_source="$decrypted_file"
    fi
    
    if [[ "$restore_source" == *.gz ]]; then
        log_info "Decompressing PostgreSQL backup..."
        gunzip -c "$restore_source" > "$RESTORE_DIR/postgresql_${db_name}_restore.sql"
        restore_source="$RESTORE_DIR/postgresql_${db_name}_restore.sql"
    fi
    
    # Create database if it doesn't exist
    log_info "Creating database: $db_name"
    ssh "$server" "psql -c 'CREATE DATABASE $db_name;'" || true
    
    # Restore database
    log_info "Restoring PostgreSQL data..."
    
    if [ "$NO_DATA" = true ]; then
        # Schema only restore
        log_info "Restoring schema only (no data)"
        ssh "$server" "psql $db_name" < <(grep -v -E "^INSERT|^COPY" "$restore_source")
    else
        # Full database restore
        log_info "Performing full database restore"
        ssh "$server" "psql $db_name" < "$restore_source"
    fi
    
    # Cleanup
    rm -f "$RESTORE_DIR"/*.sql
    
    log_success "PostgreSQL database restored: $db_name"
}

# Verify database restoration
verify_database_restoration() {
    local db_type=$1
    local db_name=$2
    local server=$3
    
    log_info "Verifying database restoration: $db_name"
    
    case $db_type in
        mysql)
            local table_count
            table_count=$(ssh "$server" "mysql -e 'USE $db_name; SHOW TABLES;' | wc -l")
            if [ "$table_count" -gt 0 ]; then
                log_success "MySQL restoration verified: $table_count tables in $db_name"
            else
                log_error "MySQL restoration verification failed: no tables found"
                return 1
            fi
            ;;
        mongodb)
            local collection_count
            collection_count=$(ssh "$server" "mongo $db_name --eval 'db.getCollectionNames().length' --quiet")
            if [ "$collection_count" -gt 0 ]; then
                log_success "MongoDB restoration verified: $collection_count collections in $db_name"
            else
                log_error "MongoDB restoration verification failed: no collections found"
                return 1
            fi
            ;;
        postgresql)
            local table_count
            table_count=$(ssh "$server" "psql -d $db_name -c 'SELECT count(*) FROM information_schema.tables;' -t")
            if [ "$table_count" -gt 0 ]; then
                log_success "PostgreSQL restoration verified: $table_count tables in $db_name"
            else
                log_error "PostgreSQL restoration verification failed: no tables found"
                return 1
            fi
            ;;
    esac
}

# Main restoration function
main_restoration() {
    local db_type=$1
    local db_name=$2
    
    log_info "Starting database restoration process - ID: $RESTORE_ID"
    log_info "Database Type: $db_type"
    log_info "Database Name: $db_name"
    log_info "Log file: $LOG_FILE"
    
    # Find backup
    local backup_file
    backup_file=$(find_db_backup "$db_type" "$db_name" "$BACKUP_ID")
    
    if [ -z "$backup_file" ]; then
        log_error "No backup found for database type: $db_type"
        exit 1
    fi
    
    log_info "Found backup: $(basename "$backup_file")"
    
    # Determine server
    local server=${DB_SERVER:-"db-01.infokes.co.id"}
    
    # Confirm restoration
    if [ "$FORCE" != true ] && [ "$DRY_RUN" != true ]; then
        log_warning "This will restore $db_type database '$db_name' from backup: $(basename "$backup_file")"
        log_warning "Target server: $server"
        read -p "Are you sure? This may overwrite existing data! (type 'RESTORE' to confirm): " -r
        if [ "$REPLY" != "RESTORE" ]; then
            log_info "Database restoration cancelled"
            exit 0
        fi
    fi
    
    # Perform restoration based on database type
    case $db_type in
        mysql)
            restore_mysql "$backup_file" "$db_name" "$server"
            ;;
        mongodb)
            restore_mongodb "$backup_file" "$db_name" "$server"
            ;;
        postgresql)
            restore_postgresql "$backup_file" "$db_name" "$server"
            ;;
        *)
            log_error "Unsupported database type: $db_type"
            exit 1
            ;;
    esac
    
    # Verify restoration
    verify_database_restoration "$db_type" "$db_name" "$server"
    
    log_success "Database restoration completed successfully: $db_name"
    log_info "Restoration ID: $RESTORE_ID"
    log_info "Backup used: $(basename "$backup_file")"
    log_info "Target server: $server"
}

# Parse arguments
DB_TYPE=""
DB_NAME=""
BACKUP_ID=""
DB_SERVER="db-01.infokes.co.id"
DB_USER="root"
DB_PASSWORD=""
RESTORE_TABLES=""
WHERE_CLAUSE=""
DRY_RUN=false
FORCE=false
NO_DATA=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -b|--backup)
            BACKUP_ID=$2
            shift 2
            ;;
        -s|--server)
            DB_SERVER=$2
            shift 2
            ;;
        -u|--user)
            DB_USER=$2
            shift 2
            ;;
        -p|--password)
            DB_PASSWORD=$2
            shift 2
            ;;
        --tables)
            RESTORE_TABLES=$2
            shift 2
            ;;
        --where)
            WHERE_CLAUSE=$2
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --no-data)
            NO_DATA=true
            shift
            ;;
        mysql|mongodb|postgresql)
            if [ -z "$DB_TYPE" ]; then
                DB_TYPE=$1
            elif [ -z "$DB_NAME" ]; then
                DB_NAME=$1
            fi
            shift
            ;;
        *)
            if [ -z "$DB_NAME" ]; then
                DB_NAME=$1
            fi
            shift
            ;;
    esac
done

# Validate inputs
if [ -z "$DB_TYPE" ] || [ -z "$DB_NAME" ]; then
    log_error "Database type and name required"
    show_help
    exit 1
fi

# Export environment variables
export BACKUP_ENCRYPTION_KEY=${BACKUP_ENCRYPTION_KEY:-""}

# Execute main restoration function
main_restoration "$DB_TYPE" "$DB_NAME"