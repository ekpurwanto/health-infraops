#!/bin/bash
# Health-InfraOps VM Backup Script

set -e

# Configuration
BACKUP_DIR="/var/lib/vz/dump"
RETENTION_DAYS=7
COMPRESSION="zstd"
DATE=$(date +%Y%m%d_%H%M%S)

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
    echo "Usage: $0 [vm_id] [--all] [--list]"
    echo "  --all    Backup all VMs"
    echo "  --list   List available VMs"
    exit 1
}

backup_vm() {
    local vm_id=$1
    local vm_name=$(qm config $vm_id | grep name | awk '{print $2}' || echo "unknown")
    
    log "Starting backup of VM $vm_id ($vm_name)..."
    
    # Create backup
    if vzdump $vm_id \
        --compress $COMPRESSION \
        --dumpdir $BACKUP_DIR \
        --mode snapshot \
        --storage local \
        --mailto admin@infokes.co.id \
        --notes "Health-InfraOps Automated Backup"; then
        
        log "✅ Backup completed for VM $vm_id ($vm_name)"
        
        # Log backup
        echo "$DATE,$vm_id,$vm_name,SUCCESS" >> /var/log/health-infraops-backup.log
    else
        error "Backup failed for VM $vm_id ($vm_name)"
        echo "$DATE,$vm_id,$vm_name,FAILED" >> /var/log/health-infraops-backup.log
        return 1
    fi
}

cleanup_old_backups() {
    log "Cleaning up backups older than $RETENTION_DAYS days..."
    find $BACKUP_DIR -name "*.vma.*" -type f -mtime +$RETENTION_DAYS -delete
    find $BACKUP_DIR -name "*.log" -type f -mtime +$RETENTION_DAYS -delete
}

list_vms() {
    log "Available VMs for backup:"
    qm list | awk 'NR>1 {print $1 " - " $2 " (" $3 ")"}'
}

# Main script
case "${1:-}" in
    "--list")
        list_vms
        exit 0
        ;;
    "--all")
        log "Starting backup of all VMs..."
        for vm_id in $(qm list | awk 'NR>1 {print $1}'); do
            backup_vm $vm_id
        done
        ;;
    "")
        usage
        ;;
    *)
        # Check if it's a number (VM ID)
        if [[ $1 =~ ^[0-9]+$ ]]; then
            backup_vm $1
        else
            error "Invalid VM ID: $1"
            usage
        fi
        ;;
esac

# Cleanup old backups
cleanup_old_backups

log "🎉 Backup process completed!"
log "📊 Backup location: $BACKUP_DIR"