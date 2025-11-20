#!/bin/bash
# Health-InfraOps VirtualBox VM Cloning Script

set -e

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

usage() {
    echo "Usage: $0 <source_vm> <new_vm_name> [--linked] [--full]"
    echo "  --linked: Create linked clone (default)"
    echo "  --full:   Create full clone"
    exit 1
}

# Validate arguments
if [ $# -lt 2 ]; then
    usage
fi

SOURCE_VM="$1"
NEW_VM="$2"
CLONE_TYPE="${3:---linked}"

# Check if source VM exists
if ! VBoxManage showvminfo "$SOURCE_VM" &>/dev/null; then
    echo "❌ Source VM not found: $SOURCE_VM"
    echo "Available VMs:"
    VBoxManage list vms
    exit 1
fi

# Check if new VM name already exists
if VBoxManage showvminfo "$NEW_VM" &>/dev/null; then
    echo "❌ VM already exists: $NEW_VM"
    exit 1
fi

# Clone VM based on type
case $CLONE_TYPE in
    "--linked")
        log "Creating linked clone: $SOURCE_VM -> $NEW_VM"
        VBoxManage clonevm "$SOURCE_VM" --name "$NEW_VM" --register --mode machine --options link
        ;;
    "--full")
        log "Creating full clone: $SOURCE_VM -> $NEW_VM"
        VBoxManage clonevm "$SOURCE_VM" --name "$NEW_VM" --register --mode all
        ;;
    *)
        usage
        ;;
esac

# Generate new MAC addresses to avoid conflicts
log "Generating new MAC addresses..."
VBoxManage modifyvm "$NEW_VM" --macaddress1 auto
VBoxManage modifyvm "$NEW_VM" --macaddress2 auto

# Create snapshot of the clone
log "Creating initial snapshot of clone..."
VBoxManage snapshot "$NEW_VM" take "cloned-from-$SOURCE_VM" --description "Cloned from $SOURCE_VM"

log "✅ VM clone created successfully!"
echo "Source: $SOURCE_VM"
echo "Clone:  $NEW_VM"
echo "Type:   $CLONE_TYPE"

# Start cloned VM
read -p "Start cloned VM? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log "Starting cloned VM..."
    VBoxManage startvm "$NEW_VM" --type headless
fi