#!/bin/bash
# Health-InfraOps PM2 Log Rotation Script

set -e

# Configuration
LOG_DIR="/var/log/pm2"
MAX_SIZE="100M"
BACKUP_COUNT=5
DATE_SUFFIX=$(date +%Y%m%d_%H%M%S)

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Check if PM2 is running
if ! command -v pm2 &> /dev/null; then
    warning "PM2 is not installed"
    exit 1
fi

# Create backup directory
BACKUP_DIR="/backup/pm2-logs/$DATE_SUFFIX"
mkdir -p $BACKUP_DIR

log "Starting PM2 log rotation..."

# Flush PM2 logs
log "Flushing PM2 logs..."
pm2 flush

# Rotate logs for each app
for app in $(pm2 jlist | jq -r '.[] | .name'); do
    log "Rotating logs for: $app"
    
    # Get log paths
    OUT_LOG=$(pm2 show $app | grep "out log path" | awk '{print $6}')
    ERROR_LOG=$(pm2 show $app | grep "error log path" | awk '{print $6}')
    
    # Rotate out log
    if [ -f "$OUT_LOG" ] && [ -s "$OUT_LOG" ]; then
        log "Rotating out log: $OUT_LOG"
        cp "$OUT_LOG" "$BACKUP_DIR/${app}_out.log"
        : > "$OUT_LOG"
    fi
    
    # Rotate error log
    if [ -f "$ERROR_LOG" ] && [ -s "$ERROR_LOG" ]; then
        log "Rotating error log: $ERROR_LOG"
        cp "$ERROR_LOG" "$BACKUP_DIR/${app}_error.log"
        : > "$ERROR_LOG"
    fi
done

# Compress backup
log "Compressing log backup..."
tar -czf "$BACKUP_DIR.tar.gz" -C "$BACKUP_DIR" .
rm -rf "$BACKUP_DIR"

# Clean up old backups
log "Cleaning up old backups..."
find /backup/pm2-logs -name "*.tar.gz" -mtime +30 -delete

# Reload PM2 to reopen log files
log "Reloading PM2..."
pm2 reload all

log "✅ PM2 log rotation completed successfully!"
log "📁 Backup created: $BACKUP_DIR.tar.gz"