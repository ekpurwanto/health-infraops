#!/bin/bash
# Health-InfraOps MySQL Automated Backup Script

set -e

# Configuration
BACKUP_DIR="/backup/mysql"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=7
MYSQL_USER="backup_user"
MYSQL_PASSWORD="backup_password_123"
MYSQL_HOST="localhost"
DATABASES="infokes mysql"  # Space separated list

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

# Create backup directory
mkdir -p $BACKUP_DIR/$DATE
cd $BACKUP_DIR/$DATE

log "Starting MySQL backup process..."

# Test MySQL connection
if ! mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD -e "SHOW DATABASES;" > /dev/null 2>&1; then
    error "Failed to connect to MySQL"
    exit 1
fi

# Get list of all databases if not specified
if [ -z "$DATABASES" ]; then
    DATABASES=$(mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD -e "SHOW DATABASES;" | grep -Ev "(Database|information_schema|performance_schema|sys)")
fi

# Backup each database
for DB in $DATABASES; do
    log "Backing up database: $DB"
    
    # Dump schema
    mysqldump -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD \
        --no-data --skip-comments $DB > ${DB}_schema.sql
    
    # Dump data with compression
    mysqldump -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD \
        --single-transaction \
        --quick \
        --skip-comments \
        $DB | gzip > ${DB}_data.sql.gz
    
    # Verify backup
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        error "Backup failed for database: $DB"
        continue
    fi
    
    log "✅ Database $DB backed up successfully"
done

# Backup users and privileges
log "Backing up users and privileges..."
mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD \
    --skip-column-names -A -e"SELECT CONCAT('SHOW GRANTS FOR ''',user,'''@''',host,''';') FROM mysql.user WHERE user<>''" | \
    mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD --skip-column-names -A | \
    sed 's/$/;/g' > mysql_grants.sql

# Create backup manifest
cat > backup_manifest.txt << EOF
Health-InfraOps MySQL Backup
============================
Backup Date: $(date)
MySQL Host: $MYSQL_HOST
Databases: $DATABASES
Backup Directory: $BACKUP_DIR/$DATE
Size: $(du -sh . | cut -f1)

Files:
$(ls -la)

Verification:
$(for DB in $DATABASES; do
    echo -n "$DB: "
    if [ -f "${DB}_data.sql.gz" ] && gzip -t "${DB}_data.sql.gz" 2>/dev/null; then
        echo "VALID"
    else
        echo "INVALID"
    fi
done)
EOF

# Compress entire backup
log "Compressing backup..."
tar -czf ../mysql_backup_$DATE.tar.gz .

# Create checksum
md5sum ../mysql_backup_$DATE.tar.gz > ../mysql_backup_$DATE.tar.gz.md5

# Cleanup temporary files
cd ..
rm -rf $DATE

# Clean up old backups
log "Cleaning up backups older than $RETENTION_DAYS days..."
find $BACKUP_DIR -name "mysql_backup_*.tar.gz" -mtime +$RETENTION_DAYS -delete
find $BACKUP_DIR -name "mysql_backup_*.md5" -mtime +$RETENTION_DAYS -delete

# Sync to remote storage (if configured)
if [ -f "/etc/backup/remote.config" ]; then
    log "Syncing to remote storage..."
    source /etc/backup/remote.config
    rsync -avz $BACKUP_DIR/mysql_backup_$DATE.tar.gz $REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH/
fi

# Log backup completion
log "✅ MySQL backup completed successfully!"
log "📁 Backup file: $BACKUP_DIR/mysql_backup_$DATE.tar.gz"
log "📊 Backup size: $(du -h $BACKUP_DIR/mysql_backup_$DATE.tar.gz | cut -f1)"

# Send notification (if configured)
if command -v sendmail &> /dev/null; then
    echo "Subject: MySQL Backup Completed - $DATE
MySQL backup completed successfully on $(hostname)
Backup size: $(du -h $BACKUP_DIR/mysql_backup_$DATE.tar.gz | cut -f1)
Location: $BACKUP_DIR/mysql_backup_$DATE.tar.gz" | sendmail admin@infokes.co.id
fi