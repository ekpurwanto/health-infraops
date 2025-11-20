#!/bin/bash
# Health-InfraOps VirtualBox VM Creation Script

set -e

# Configuration
VM_NAME="${1:-health-infraops-vm}"
MEMORY=${2:-2048}
CPUS=${3:-2}
DISK_SIZE=${4:-32768}
OSTYPE="${5:-Ubuntu_64}"
NETWORK="${6:-health-infraops-network}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Check if VBoxManage is available
if ! command -v VBoxManage &> /dev/null; then
    echo "❌ VBoxManage not found. Please install VirtualBox first."
    exit 1
fi

# Create VM
log "Creating VM: $VM_NAME"
VBoxManage createvm --name "$VM_NAME" --ostype "$OSTYPE" --register

# Configure system settings
log "Configuring system settings..."
VBoxManage modifyvm "$VM_NAME" \
    --memory "$MEMORY" \
    --cpus "$CPUS" \
    --nic1 nat \
    --nic2 hostonly \
    --hostonlyadapter2 "$NETWORK" \
    --audio none \
    --usb off \
    --graphicscontroller vmsvga \
    --vram 16

# Create storage controller
VBoxManage storagectl "$VM_NAME" \
    --name "SATA Controller" \
    --add sata \
    --controller IntelAHCI

# Create and attach disk
log "Creating disk ($DISK_SIZE MB)..."
VBoxManage createmedium disk \
    --filename "$HOME/VirtualBox VMs/$VM_NAME/$VM_NAME.vdi" \
    --size "$DISK_SIZE" \
    --format VDI

VBoxManage storageattach "$VM_NAME" \
    --storagectl "SATA Controller" \
    --port 0 \
    --device 0 \
    --type hdd \
    --medium "$HOME/VirtualBox VMs/$VM_NAME/$VM_NAME.vdi"

# Configure boot order
VBoxManage modifyvm "$VM_NAME" --boot1 dvd --boot2 disk --boot3 none --boot4 none

# Enable RDP
VBoxManage modifyvm "$VM_NAME" --vrde on --vrdeport 3389

# Create snapshot
log "Creating initial snapshot..."
VBoxManage snapshot "$VM_NAME" take "initial-setup" --description "Health-InfraOps Initial Setup"

# Show VM info
log "VM created successfully!"
info "VM Name: $VM_NAME"
info "Memory: $MEMORY MB"
info "CPUs: $CPUS"
info "Disk: $DISK_SIZE MB"
info "Network: $NETWORK"

# Start VM
read -p "Start VM now? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log "Starting VM..."
    VBoxManage startvm "$VM_NAME" --type headless
    info "VM started in headless mode. Use RDP to connect."
fi

log "✅ VM creation completed!"