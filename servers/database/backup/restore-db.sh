#!/bin/bash
# Health-InfraOps MySQL Database Restore Script

set -e

# Configuration
BACKUP_DIR="/backup/mysql"
MYSQL_USER="root"
MYSQL_PASSWORD="secure_password_123"
MYSQL_HOST="localhost"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

usage() {
    echo "Usage: $0 <backup_file> [database_name]"
    echo "Example: $0 mysql_backup_20231015_120000.tar.gz infokes"
    exit 1
}

# Validate arguments
if [ $# -lt 1 ]; then
    usage
fi

BACKUP_FILE="$1"
TARGET_DB="${2:-all}"
RESTORE_DIR="/tmp/mysql_restore_$$"

# Check if backup file exists
if [ ! -f "$BACKUP_DIR/$BACKUP_FILE" ]; then
    error "Backup file not found: $BACKUP_DIR/$BACKUP_FILE"
    echo "Available backups:"
    ls -la $BACKUP_DIR/mysql_backup_*.tar.gz 2>/dev/null || echo "No backups found"
    exit 1
fi

# Verify backup integrity
log "Verifying backup integrity..."
if [ -f "$BACKUP_DIR/$BACKUP_FILE.md5" ]; then
    if ! md5sum -c "$BACKUP_DIR/$BACKUP_FILE.md5" --quiet; then
        error "Backup file integrity check failed"
        exit 1
    fi
else
    warning "No checksum file found, skipping integrity check"
fi

# Create restore directory
mkdir -p $RESTORE_DIR
cd $RESTORE_DIR

# Extract backup
log "Extracting backup file..."
tar -xzf $BACKUP_DIR/$BACKUP_FILE

# Test MySQL connection
if ! mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD -e "SHOW DATABASES;" > /dev/null 2>&1; then
    error "Failed to connect to MySQL"
    exit 1
fi

# Get list of databases in backup
BACKUP_DBS=$(ls *_schema.sql 2>/dev/null | sed 's/_schema.sql//' || echo "")

if [ -z "$BACKUP_DBS" ]; then
    error "No databases found in backup"
    exit 1
fi

log "Databases in backup: $BACKUP_DBS"

# Confirm restore
if [ "$TARGET_DB" = "all" ]; then
    warning "This will restore ALL databases from backup!"
    read -p "Are you sure you want to continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log "Restore cancelled"
        exit 0
    fi
else
    if ! echo "$BACKUP_DBS" | grep -q "$TARGET_DB"; then
        error "Database $TARGET_DB not found in backup"
        exit 1
    fi
    log "Restoring database: $TARGET_DB"
fi

# Restore function
restore_database() {
    local db_name=$1
    
    log "Restoring database: $db_name"
    
    # Drop and recreate database
    mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD -e "DROP DATABASE IF EXISTS $db_name;"
    mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD -e "CREATE DATABASE $db_name CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    
    # Restore schema
    mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD $db_name < ${db_name}_schema.sql
    
    # Restore data
    if [ -f "${db_name}_data.sql.gz" ]; then
        gunzip -c ${db_name}_data.sql.gz | mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD $db_name
    else
        warning "No data file found for $db_name"
    fi
    
    log "✅ Database $db_name restored successfully"
}

# Perform restore
if [ "$TARGET_DB" = "all" ]; then
    for DB in $BACKUP_DBS; do
        restore_database $DB
    done
    
    # Restore MySQL grants
    if [ -f "mysql_grants.sql" ]; then
        log "Restoring user privileges..."
        mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD < mysql_grants.sql
    fi
else
    restore_database $TARGET_DB
fi

# Verify restore
log "Verifying restore..."
for DB in $(if [ "$TARGET_DB" = "all" ]; then echo "$BACKUP_DBS"; else echo "$TARGET_DB"; fi); do
    TABLE_COUNT=$(mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB';")
    log "Database $DB: $TABLE_COUNT tables restored"
done

# Cleanup
cd /
rm -rf $RESTORE_DIR

log "✅ Database restore completed successfully!"
log "📊 Restored databases: $(if [ "$TARGET_DB" = "all" ]; then echo "$BACKUP_DBS"; else echo "$TARGET_DB"; fi)"

# Log restore operation
mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD -e "
INSERT INTO infokes.audit_log (user_id, action, table_name, record_id, ip_address, created_at)
VALUES (1, 'DATABASE_RESTORE', 'system', 1, '$(hostname -I | awk '{print $1}')', NOW());" 2>/dev/null || true