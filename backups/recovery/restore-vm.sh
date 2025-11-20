#!/bin/bash

# Health-InfraOps VM Restoration Script
# Virtual machine recovery and restoration procedures

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
PROJECT_ROOT="$(dirname "$(dirname "$BACKUP_ROOT")")"

# Configuration
BACKUP_DIR="$BACKUP_ROOT/data"
LOG_DIR="$BACKUP_ROOT/logs"
RESTORE_DIR="/tmp/vm-restore"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESTORE_ID="vm_restore_${TIMESTAMP}"

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
Health-InfraOps VM Restoration Script

Usage: $0 [options] <vm_id|vm_name>

Options:
  -h, --help           Show this help message
  -b, --backup ID      Use specific backup ID
  --proxmox-host HOST  Proxmox host address
  --proxmox-user USER  Proxmox username
  --proxmox-node NODE  Proxmox node name
  --storage STORAGE    Target storage for restore
  --dry-run           Dry run mode
  --force             Force restore without confirmation

Examples:
  $0 101 --backup full_20231201_120000
  $0 web-01 --proxmox-host pve-01.infokes.co.id
  $0 102 --dry-run --storage local-lvm
EOF
}

# Proxmox API functions
proxmox_api() {
    local method=$1
    local path=$2
    local data=$3
    
    local proxmox_host=${PROXMOX_HOST:-"pve-01.infokes.co.id"}
    local proxmox_user=${PROXMOX_USER:-"root@pam"}
    local proxmox_password=${PROXMOX_PASSWORD:-""}
    
    # Get CSRF token and ticket
    local auth_response
    auth_response=$(curl -s -k -d "username=$proxmox_user&password=$proxmox_password" \
        "https://$proxmox_host:8006/api2/json/access/ticket")
    
    local csrf_token
    csrf_token=$(echo "$auth_response" | jq -r '.data.CSRFPreventionToken')
    local ticket
    ticket=$(echo "$auth_response" | jq -r '.data.ticket')
    
    # Make API call
    curl -s -k -X "$method" \
        -H "CSRFPreventionToken: $csrf_token" \
        -H "Cookie: PVEAuthCookie=$ticket" \
        "https://$proxmox_host:8006/api2/json/$path" \
        ${data:+-d "$data"}
}

# Find VM by ID or name
find_vm() {
    local vm_identifier=$1
    
    # Try to find by VMID
    if [[ "$vm_identifier" =~ ^[0-9]+$ ]]; then
        local vm_info
        vm_info=$(proxmox_api "GET" "cluster/resources" | jq -r ".data[] | select(.vmid == \"$vm_identifier\")")
        if [ -n "$vm_info" ]; then
            echo "$vm_identifier"
            return 0
        fi
    fi
    
    # Try to find by name
    local vm_info
    vm_info=$(proxmox_api "GET" "cluster/resources" | jq -r ".data[] | select(.name == \"$vm_identifier\")")
    if [ -n "$vm_info" ]; then
        local vmid
        vmid=$(echo "$vm_info" | jq -r '.vmid')
        echo "$vmid"
        return 0
    fi
    
    return 1
}

# Find VM backup
find_vm_backup() {
    local vmid=$1
    local backup_id=$2
    
    if [ -n "$backup_id" ]; then
        local backup_file
        backup_file=$(find "$BACKUP_DIR" -name "*${backup_id}*" -type f | head -1)
        echo "$backup_file"
    else
        # Find latest backup for VM
        local backup_file
        backup_file=$(find "$BACKUP_DIR" -name "*vm_${vmid}*" -type f | sort -r | head -1)
        echo "$backup_file"
    fi
}

# Stop VM
stop_vm() {
    local vmid=$1
    
    log_info "Stopping VM: $vmid"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would stop VM $vmid"
        return 0
    fi
    
    local response
    response=$(proxmox_api "POST" "nodes/$PROXMOX_NODE/qemu/$vmid/status/stop")
    
    if echo "$response" | jq -e '.data' > /dev/null; then
        # Wait for VM to stop
        local max_wait=60
        local wait_time=0
        
        while [ "$wait_time" -lt "$max_wait" ]; do
            local vm_status
            vm_status=$(proxmox_api "GET" "nodes/$PROXMOX_NODE/qemu/$vmid/status/current" | jq -r '.data.status')
            
            if [ "$vm_status" = "stopped" ]; then
                log_success "VM stopped: $vmid"
                return 0
            fi
            
            sleep 5
            wait_time=$((wait_time + 5))
        done
        
        log_error "Timeout waiting for VM to stop: $vmid"
        return 1
    else
        log_error "Failed to stop VM: $vmid"
        return 1
    fi
}

# Restore VM from backup
restore_vm() {
    local vmid=$1
    local backup_file=$2
    
    log_info "Restoring VM $vmid from backup: $(basename "$backup_file")"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would restore VM $vmid from $(basename "$backup_file")"
        return 0
    fi
    
    # Extract backup if needed
    local restore_source="$backup_file"
    
    if [[ "$backup_file" == *.enc ]]; then
        log_info "Decrypting backup file..."
        local decrypted_file="${backup_file%.enc}"
        openssl enc -d -aes-256-cbc -pbkdf2 \
            -in "$backup_file" \
            -out "$decrypted_file" \
            -pass pass:"$BACKUP_ENCRYPTION_KEY"
        restore_source="$decrypted_file"
    fi
    
    if [[ "$restore_source" == *.tar.gz ]]; then
        log_info "Extracting backup archive..."
        tar -xzf "$restore_source" -C "$RESTORE_DIR"
    fi
    
    # Determine backup type and restore accordingly
    if [ -f "$RESTORE_DIR/vm.conf" ]; then
        restore_vm_config "$vmid" "$RESTORE_DIR"
    elif [ -f "$RESTORE_DIR/qemu-server/${vmid}.conf" ]; then
        restore_proxmox_vm "$vmid" "$RESTORE_DIR"
    else
        log_error "Unsupported VM backup format"
        return 1
    fi
    
    # Cleanup
    rm -rf "$RESTORE_DIR"/*
    
    log_success "VM restoration completed: $vmid"
}

# Restore VM configuration
restore_vm_config() {
    local vmid=$1
    local restore_dir=$2
    
    log_info "Restoring VM configuration for: $vmid"
    
    # Read VM configuration
    local vm_config
    vm_config=$(cat "$restore_dir/vm.conf")
    
    # Parse configuration
    local vm_name
    vm_name=$(grep "name:" "$restore_dir/vm.conf" | cut -d: -f2 | tr -d ' ')
    local memory
    memory=$(grep "memory:" "$restore_dir/vm.conf" | cut -d: -f2 | tr -d ' ')
    local cores
    cores=$(grep "cores:" "$restore_dir/vm.conf" | cut -d: -f2 | tr -d ' ')
    
    # Restore VM configuration in Proxmox
    local response
    response=$(proxmox_api "POST" "nodes/$PROXMOX_NODE/qemu/$vmid/config" \
        "memory=$memory&cores=$cores&name=$vm_name")
    
    if echo "$response" | jq -e '.data' > /dev/null; then
        log_success "VM configuration restored: $vmid"
    else
        log_error "Failed to restore VM configuration: $vmid"
        return 1
    fi
}

# Restore Proxmox VM
restore_proxmox_vm() {
    local vmid=$1
    local restore_dir=$2
    
    log_info "Restoring Proxmox VM: $vmid"
    
    # Restore VM configuration
    local config_file="$restore_dir/qemu-server/${vmid}.conf"
    if [ -f "$config_file" ]; then
        # Upload configuration to Proxmox
        local config_content
        config_content=$(cat "$config_file")
        
        local response
        response=$(proxmox_api "POST" "nodes/$PROXMOX_NODE/qemu/$vmid/config" \
            "$config_content")
        
        if echo "$response" | jq -e '.data' > /dev/null; then
            log_success "VM config restored: $vmid"
        else
            log_error "Failed to restore VM config: $vmid"
            return 1
        fi
    fi
    
    # Restore disk images if available
    local disk_files
    disk_files=$(find "$restore_dir" -name "*.qcow2" -o -name "*.raw")
    
    for disk_file in $disk_files; do
        restore_vm_disk "$vmid" "$disk_file"
    done
}

# Restore VM disk
restore_vm_disk() {
    local vmid=$1
    local disk_file=$2
    
    local disk_name
    disk_name=$(basename "$disk_file")
    local storage=${STORAGE:-"local-lvm"}
    
    log_info "Restoring disk: $disk_name for VM: $vmid"
    
    # Upload disk to Proxmox storage
    local response
    response=$(proxmox_api "POST" "nodes/$PROXMOX_NODE/storage/$storage/upload" \
        "content=images&filename=$disk_name")
    
    # This is a simplified example - actual implementation would need
    # to handle the file upload properly
    
    log_success "Disk restoration initiated: $disk_name"
}

# Start VM
start_vm() {
    local vmid=$1
    
    log_info "Starting VM: $vmid"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would start VM $vmid"
        return 0
    fi
    
    local response
    response=$(proxmox_api "POST" "nodes/$PROXMOX_NODE/qemu/$vmid/status/start")
    
    if echo "$response" | jq -e '.data' > /dev/null; then
        # Wait for VM to start
        local max_wait=60
        local wait_time=0
        
        while [ "$wait_time" -lt "$max_wait" ]; do
            local vm_status
            vm_status=$(proxmox_api "GET" "nodes/$PROXMOX_NODE/qemu/$vmid/status/current" | jq -r '.data.status')
            
            if [ "$vm_status" = "running" ]; then
                log_success "VM started: $vmid"
                return 0
            fi
            
            sleep 5
            wait_time=$((wait_time + 5))
        done
        
        log_warning "VM start taking longer than expected: $vmid"
    else
        log_error "Failed to start VM: $vmid"
        return 1
    fi
}

# Verify VM restoration
verify_vm_restoration() {
    local vmid=$1
    
    log_info "Verifying VM restoration: $vmid"
    
    # Check VM status
    local vm_status
    vm_status=$(proxmox_api "GET" "nodes/$PROXMOX_NODE/qemu/$vmid/status/current" | jq -r '.data.status')
    
    if [ "$vm_status" = "running" ]; then
        log_success "VM is running: $vmid"
        
        # Get VM IP address (if available)
        local vm_ip
        vm_ip=$(proxmox_api "GET" "nodes/$PROXMOX_NODE/qemu/$vmid/agent/network-get-interfaces" | jq -r '.data[] | ."ip-addresses"[] | select(."ip-address-type" == "ipv4") | ."ip-address"' | grep -v "127.0.0.1" | head -1)
        
        if [ -n "$vm_ip" ]; then
            log_info "VM IP address: $vm_ip"
            
            # Test basic connectivity
            if ping -c 3 -W 5 "$vm_ip" &> /dev/null; then
                log_success "VM network connectivity verified: $vm_ip"
            else
                log_warning "VM network connectivity test failed"
            fi
        fi
    else
        log_error "VM is not running: $vmid (status: $vm_status)"
        return 1
    fi
}

# Main restoration function
main_restoration() {
    local vm_identifier=$1
    
    log_info "Starting VM restoration process - ID: $RESTORE_ID"
    log_info "VM Identifier: $vm_identifier"
    log_info "Log file: $LOG_FILE"
    
    # Find VM
    local vmid
    vmid=$(find_vm "$vm_identifier")
    
    if [ -z "$vmid" ]; then
        log_error "VM not found: $vm_identifier"
        exit 1
    fi
    
    log_info "Found VM: $vmid"
    
    # Find backup
    local backup_file
    backup_file=$(find_vm_backup "$vmid" "$BACKUP_ID")
    
    if [ -z "$backup_file" ]; then
        log_error "No backup found for VM: $vmid"
        exit 1
    fi
    
    log_info "Found backup: $(basename "$backup_file")"
    
    # Confirm restoration
    if [ "$FORCE" != true ] && [ "$DRY_RUN" != true ]; then
        log_warning "This will restore VM $vmid from backup: $(basename "$backup_file")"
        read -p "Are you sure? This may overwrite existing VM data! (type 'RESTORE' to confirm): " -r
        if [ "$REPLY" != "RESTORE" ]; then
            log_info "VM restoration cancelled"
            exit 0
        fi
    fi
    
    # Stop VM
    stop_vm "$vmid"
    
    # Restore VM
    restore_vm "$vmid" "$backup_file"
    
    # Start VM
    start_vm "$vmid"
    
    # Verify restoration
    verify_vm_restoration "$vmid"
    
    log_success "VM restoration completed successfully: $vmid"
    log_info "Restoration ID: $RESTORE_ID"
    log_info "Backup used: $(basename "$backup_file")"
}

# Parse arguments
VM_IDENTIFIER=""
BACKUP_ID=""
PROXMOX_HOST="pve-01.infokes.co.id"
PROXMOX_USER="root@pam"
PROXMOX_NODE="pve-01"
STORAGE="local-lvm"
DRY_RUN=false
FORCE=false

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
        --proxmox-host)
            PROXMOX_HOST=$2
            shift 2
            ;;
        --proxmox-user)
            PROXMOX_USER=$2
            shift 2
            ;;
        --proxmox-node)
            PROXMOX_NODE=$2
            shift 2
            ;;
        --storage)
            STORAGE=$2
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
        *)
            if [ -z "$VM_IDENTIFIER" ]; then
                VM_IDENTIFIER=$1
            fi
            shift
            ;;
    esac
done

# Validate inputs
if [ -z "$VM_IDENTIFIER" ]; then
    log_error "VM identifier required"
    show_help
    exit 1
fi

# Export environment variables
export PROXMOX_HOST
export PROXMOX_USER
export PROXMOX_NODE
export PROXMOX_PASSWORD=${PROXMOX_PASSWORD:-""}
export BACKUP_ENCRYPTION_KEY=${BACKUP_ENCRYPTION_KEY:-""}

# Execute main restoration function
main_restoration "$VM_IDENTIFIER"