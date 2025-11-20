#!/bin/bash
# Health-InfraOps NFS Server Setup Script

set -e

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

# Configuration
NFS_SERVER_IP="10.0.50.10"
EXPORT_BASE="/export"

log "Setting up NFS server for Health-InfraOps..."

# Install NFS server
log "Installing NFS server packages..."
apt update
apt install -y nfs-kernel-server nfs-common

# Create export directories
log "Creating export directories..."
mkdir -p $EXPORT_BASE/{app-data,backups,media,logs,isos,vm-storage,db-backups,configs}

# Set permissions
log "Setting permissions..."
chown -R nobody:nogroup $EXPORT_BASE
chmod -R 755 $EXPORT_BASE

# Create sample data directories
mkdir -p $EXPORT_BASE/app-data/{uploads,temp,cache}
mkdir -p $EXPORT_BASE/backups/{daily,weekly,monthly}
mkdir -p $EXPORT_BASE/media/{images,documents,videos}
mkdir -p $EXPORT_BASE/logs/{application,database,system}
mkdir -p $EXPORT_BASE/isos/{templates,installers}
mkdir -p $EXPORT_BASE/vm-storage/{disks,images,backups}
mkdir -p $EXPORT_BASE/db-backups/{mysql,mongodb,postgresql}
mkdir -p $EXPORT_BASE/configs/{apps,servers,network}

# Set specific permissions for sensitive directories
chmod 700 $EXPORT_BASE/db-backups
chmod 750 $EXPORT_BASE/configs

# Configure NFS exports
log "Configuring NFS exports..."
cp /etc/exports /etc/exports.backup.$(date +%Y%m%d_%H%M%S)

cat > /etc/exports << 'EOF'
# Health-InfraOps NFS Exports Configuration

# Application data storage
/export/app-data       10.0.10.0/24(rw,sync,no_subtree_check,no_root_squash)
/export/app-data       10.0.20.0/24(rw,sync,no_subtree_check,no_root_squash)

# Backup storage
/export/backups        10.0.50.0/24(rw,sync,no_subtree_check,no_root_squash)
/export/backups        10.0.40.0/24(ro,sync,no_subtree_check,no_root_squash)

# Media and static files
/export/media          10.0.10.0/24(rw,sync,no_subtree_check,no_root_squash)
/export/media          10.0.30.0/24(rw,sync,no_subtree_check,no_root_squash)

# Log storage (centralized logging)
/export/logs           10.0.40.0/24(rw,sync,no_subtree_check,no_root_squash)
/export/logs           10.0.10.0/24(rw,sync,no_subtree_check,no_root_squash)

# ISO and template storage
/export/isos           10.0.40.0/24(ro,sync,no_subtree_check,no_root_squash)
/export/isos           10.0.50.0/24(ro,sync,no_subtree_check,no_root_squash)

# VM storage for Proxmox
/export/vm-storage     10.0.1.0/24(rw,sync,no_subtree_check,no_root_squash)

# Database backups (secure)
/export/db-backups     10.0.20.0/24(rw,sync,no_subtree_check,no_root_squash)
/export/db-backups     10.0.50.0/24(rw,sync,no_subtree_check,no_root_squash)

# Configuration management
/export/configs        10.0.40.0/24(rw,sync,no_subtree_check,no_root_squash)
EOF

# Configure NFS server settings
log "Configuring NFS server settings..."

# Backup original settings
cp /etc/default/nfs-kernel-server /etc/default/nfs-kernel-server.backup

# Optimize NFS settings
cat > /etc/default/nfs-kernel-server << 'EOF'
# Health-InfraOps NFS Server Configuration

RPCMOUNTDOPTS="--manage-gids --no-nfs-version 4.2"
NEED_SVCGSSD="no"
RPCNFSDCOUNT=32
RPCNFSDPRIORITY=0
RPCMOUNTDOPTS="--manage-gids"
STATDOPTS="--no-notify"
EOF

# Configure kernel parameters for NFS performance
cat >> /etc/sysctl.conf << 'EOF'

# Health-InfraOps NFS Performance Tuning
# Increase NFS server performance
sunrpc.tcp_slot_table_entries = 128
sunrpc.udp_slot_table_entries = 128

# Increase network buffers
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 16777216
net.core.wmem_default = 16777216
net.core.optmem_max = 16777216

# Increase NFSd threads
fs.nfs.nfs_callback_tcpport = 0
fs.nfs.nlm_tcpport = 0
EOF

# Reload sysctl settings
sysctl -p

# Start and enable NFS services
log "Starting NFS services..."
systemctl enable nfs-server
systemctl enable rpcbind
systemctl restart rpcbind
systemctl restart nfs-server
systemctl restart nfs-kernel-server

# Configure firewall for NFS
log "Configuring firewall for NFS..."
ufw allow from 10.0.0.0/16 to any port nfs
ufw allow from 10.0.0.0/16 to any port mountd
ufw allow from 10.0.0.0/16 to any port rpc-bind

# Verify NFS exports
log "Verifying NFS exports..."
exportfs -ra
showmount -e localhost

# Create test files for verification
log "Creating test files..."
echo "Health-InfraOps NFS Server - Test File" > $EXPORT_BASE/app-data/test.txt
echo "Backup storage test" > $EXPORT_BASE/backups/test.txt
echo "Media storage test" > $EXPORT_BASE/media/test.txt

# Set up NFS client on other nodes (example)
log "Setting up NFS client configuration..."
cat > /tmp/nfs-client-setup.sh << 'EOF'
#!/bin/bash
# NFS Client Setup Script

NFS_SERVER="10.0.50.10"
MOUNT_BASE="/mnt/nfs"

mkdir -p $MOUNT_BASE/{app-data,backups,media,logs,isos}

mount -t nfs $NFS_SERVER:/export/app-data $MOUNT_BASE/app-data
mount -t nfs $NFS_SERVER:/export/backups $MOUNT_BASE/backups
mount -t nfs $NFS_SERVER:/export/media $MOUNT_BASE/media

# Add to fstab for persistence
echo "$NFS_SERVER:/export/app-data $MOUNT_BASE/app-data nfs defaults 0 0" >> /etc/fstab
echo "$NFS_SERVER:/export/backups $MOUNT_BASE/backups nfs defaults 0 0" >> /etc/fstab
echo "$NFS_SERVER:/export/media $MOUNT_BASE/media nfs defaults 0 0" >> /etc/fstab
EOF

log "NFS server setup completed!"
log "📊 NFS Server Information:"
echo "   Server IP: $NFS_SERVER_IP"
echo "   Export Base: $EXPORT_BASE"
echo "   Available Exports:"
showmount -e localhost

# Performance test
log "Running basic performance test..."
dd if=/dev/zero of=$EXPORT_BASE/app-data/testfile bs=1M count=100 oflag=direct

log "✅ NFS server setup completed successfully!"
log "🚀 Next steps:"
echo "   1. Distribute client setup script to other nodes"
echo "   2. Test mounts from client machines"
echo "   3. Configure backup jobs to use NFS storage"
echo "   4. Set up monitoring for NFS performance"