#!/bin/bash
# Health-InfraOps Proxmox VM Deployer

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

usage() {
    echo "Usage: $0 <vm_name> <vm_id> <memory_mb> <cores> <disk_size> [vlan] [ip]"
    echo "Example: $0 VM-APP-01 101 4096 4 50G 10 10.0.10.11"
    exit 1
}

# Validate parameters
if [ $# -lt 5 ]; then
    usage
fi

VM_NAME="$1"
VM_ID="$2"
MEMORY="$3"
CORES="$4"
DISK_SIZE="$5"
VLAN="${6:-10}"
IP="${7:-dhcp}"

# VM Templates
TEMPLATE_UBUNTU="ubuntu-22.04-server-cloudimg-amd64.img"
TEMPLATE_DEBIAN="debian-11-genericcloud-amd64.qcow2"
TEMPLATE_CENTOS="centos-9-stream.x86_64.qcow2"

# Default to Ubuntu
TEMPLATE=$TEMPLATE_UBUNTU

# Select template based on VM name
case $VM_NAME in
    *mon*|*grafana*|*zabbix*)
        TEMPLATE=$TEMPLATE_DEBIAN
        ;;
    *win*|*ad*)
        TEMPLATE="windows-2022.qcow2"
        ;;
    *centos*)
        TEMPLATE=$TEMPLATE_CENTOS
        ;;
esac

TEMPLATE_PATH="/var/lib/vz/template/iso/${TEMPLATE}"

log "🚀 Deploying VM: $VM_NAME (ID: $VM_ID)"
log "Specs: ${MEMORY}MB RAM, ${CORES} cores, ${DISK_SIZE} disk, VLAN ${VLAN}"

# Check if template exists
if [ ! -f "$TEMPLATE_PATH" ]; then
    error "Template $TEMPLATE not found at $TEMPLATE_PATH"
    error "Available templates:"
    ls -la /var/lib/vz/template/iso/ || true
    exit 1
fi

# Check if VM ID exists
if qm status $VM_ID >/dev/null 2>&1; then
    error "VM ID $VM_ID already exists"
    exit 1
fi

# Create VM
log "Creating VM $VM_ID..."
qm create $VM_ID \
    --name "$VM_NAME" \
    --memory $MEMORY \
    --cores $CORES \
    --net0 virtio,bridge=vmbr0,tag=$VLAN \
    --scsihw virtio-scsi-pci

# Import disk
log "Importing disk from template..."
qm set $VM_ID --scsi0 local-lvm:0,import-from="$TEMPLATE_PATH"

# Resize disk
log "Resizing disk to $DISK_SIZE..."
qm resize $VM_ID scsi0 "$DISK_SIZE"

# Cloud-init setup
log "Configuring cloud-init..."
qm set $VM_ID --ide2 local-lvm:cloudinit
qm set $VM_ID --serial0 socket --vga serial0
qm set $VM_ID --boot c --bootdisk scsi0

# SSH key (if exists)
if [ -f "$HOME/.ssh/id_rsa.pub" ]; then
    qm set $VM_ID --sshkey "$HOME/.ssh/id_rsa.pub"
fi

# IP configuration
if [ "$IP" != "dhcp" ]; then
    qm set $VM_ID --ipconfig0 "ip=$IP/24,gw=10.0.$VLAN.1"
else
    qm set $VM_ID --ipconfig0 ip=dhcp
fi

# Start VM
log "Starting VM..."
qm start $VM_ID

# Wait for VM to get IP
log "Waiting for VM to boot and get IP..."
sleep 30

# Try to get VM IP
VM_IP=$(qm guest exec $VM_ID -- hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")

log "✅ VM $VM_NAME deployed successfully!"
log "📊 VM Details:"
echo "   Name: $VM_NAME"
echo "   ID: $VM_ID"
echo "   IP: $VM_IP"
echo "   VLAN: $VLAN"
echo "   Spec: ${CORES}vCPU, ${MEMORY}MB RAM, ${DISK_SIZE} disk"

# Add to inventory
echo "$VM_ID,$VM_NAME,$VM_IP,$VLAN" >> /etc/pve/infokes-inventory.csv

log "🎉 Deployment completed! Use 'qm console $VM_ID' to access console"