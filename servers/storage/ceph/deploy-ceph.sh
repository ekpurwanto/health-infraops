#!/bin/bash
# Health-InfraOps Ceph Storage Deployment Script

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
CEPH_USER="ceph"
CEPH_CLUSTER="health-infraops"
MON_NODES=("10.0.50.11" "10.0.50.12" "10.0.50.13")
OSD_NODES=("10.0.50.14" "10.0.50.15" "10.0.50.16")
ADMIN_NODE="10.0.50.11"

# Check if running on admin node
CURRENT_IP=$(hostname -I | awk '{print $1}')
if [ "$CURRENT_IP" != "$ADMIN_NODE" ]; then
    error "This script must be run on the admin node: $ADMIN_NODE"
    exit 1
fi

log "Starting Ceph storage deployment for Health-InfraOps..."

# Install Ceph on all nodes
log "Installing Ceph on all nodes..."
for node in "${MON_NODES[@]}" "${OSD_NODES[@]}"; do
    log "Installing Ceph on $node"
    ssh $node "apt update && apt install -y ceph ceph-common ceph-mon ceph-osd ceph-mgr"
done

# Create Ceph user on all nodes
log "Creating Ceph user..."
for node in "${MON_NODES[@]}" "${OSD_NODES[@]}"; do
    ssh $node "useradd -d /home/ceph -m ceph && echo 'ceph ALL = (root) NOPASSWD:ALL' | tee /etc/sudoers.d/ceph && chmod 0440 /etc/sudoers.d/ceph"
done

# Generate cluster FSID
FSID=$(uuidgen)
log "Generated cluster FSID: $FSID"

# Create Ceph configuration
log "Creating Ceph configuration..."
cat > /etc/ceph/ceph.conf << EOF
[global]
fsid = $FSID
mon initial members = ${MON_NODES[0]}, ${MON_NODES[1]}, ${MON_NODES[2]}
mon host = $(IFS=,; echo "${MON_NODES[*]}")
public network = 10.0.50.0/24
cluster network = 10.0.50.0/24
auth cluster required = cephx
auth service required = cephx
auth client required = cephx
osd pool default size = 3
osd pool default min size = 2
osd pool default pg num = 128
osd pool default pgp num = 128
osd crush chooseleaf type = 1

[mon]
mon data = /var/lib/ceph/mon/ceph-\$id

[mgr]
mgr modules = dashboard

[osd]
osd data = /var/lib/ceph/osd/ceph-\$id
osd journal size = 1024
EOF

# Distribute configuration to all nodes
for node in "${MON_NODES[@]}" "${OSD_NODES[@]}"; do
    scp /etc/ceph/ceph.conf $node:/etc/ceph/ceph.conf
done

# Create monitor keyring
log "Creating monitor keyring..."
ceph-authtool --create-keyring /tmp/ceph.mon.keyring --gen-key -n mon. --cap mon 'allow *'

# Create admin keyring
log "Creating admin keyring..."
ceph-authtool --create-keyring /etc/ceph/ceph.client.admin.keyring --gen-key -n client.admin --set-uid=0 --cap mon 'allow *' --cap osd 'allow *' --cap mds 'allow *' --cap mgr 'allow *'

# Create bootstrap keyrings
log "Creating bootstrap keyrings..."
ceph-authtool /tmp/ceph.mon.keyring --import-keyring /etc/ceph/ceph.client.admin.keyring

# Generate monitor map
log "Generating monitor map..."
monmaptool --create --add ${MON_NODES[0]} 10.0.50.11 --add ${MON_NODES[1]} 10.0.50.12 --add ${MON_NODES[2]} 10.0.50.13 --fsid $FSID /tmp/monmap

# Initialize monitors
log "Initializing monitors..."
for i in "${!MON_NODES[@]}"; do
    node=${MON_NODES[$i]}
    mon_id=$(printf "mon%02d" $((i+1)))
    
    log "Initializing monitor $mon_id on $node"
    
    ssh $node "mkdir -p /var/lib/ceph/mon/ceph-$mon_id"
    
    ceph-mon --mkfs -i $mon_id --monmap /tmp/monmap --keyring /tmp/ceph.mon.keyring
    
    scp /tmp/ceph.mon.keyring $node:/var/lib/ceph/mon/ceph-$mon_id/keyring
    
    ssh $node "chown -R ceph:ceph /var/lib/ceph && systemctl enable ceph-mon@$mon_id && systemctl start ceph-mon@$mon_id"
done

# Wait for monitors to form quorum
log "Waiting for monitor quorum..."
sleep 30

# Check monitor status
ceph -s

# Deploy manager daemons
log "Deploying manager daemons..."
for i in "${!MON_NODES[@]}"; do
    node=${MON_NODES[$i]}
    mgr_id=$(printf "mgr%02d" $((i+1)))
    
    log "Deploying manager $mgr_id on $node"
    ssh $node "ceph auth get-or-create mgr.$mgr_id mon 'allow profile mgr' osd 'allow *' mds 'allow *' > /var/lib/ceph/mgr/ceph-$mgr_id/keyring"
    ssh $node "chown -R ceph:ceph /var/lib/ceph/mgr/ceph-$mgr_id && systemctl enable ceph-mgr@$mgr_id && systemctl start ceph-mgr@$mgr_id"
done

# Enable dashboard module
log "Enabling dashboard module..."
ceph mgr module enable dashboard
ceph dashboard create-self-signed-cert

# Create dashboard user
ceph dashboard ac-user-create admin -i /etc/ceph/ceph.client.admin.keyring administrator

# Prepare OSD nodes
log "Preparing OSD nodes..."
for node in "${OSD_NODES[@]}"; do
    log "Preparing OSD node: $node"
    
    # Find available disks (excluding system disk)
    DISKS=$(ssh $node "lsblk -dn -o NAME | grep -v $(lsblk -n -o MOUNTPOINT / | grep '^/$' | cut -d' ' -f1)")
    
    for disk in $DISKS; do
        log "Creating OSD on $node for disk $disk"
        
        osd_id=$(ceph osd create)
        ssh $node "mkdir -p /var/lib/ceph/osd/ceph-$osd_id"
        
        # Prepare disk
        ssh $node "ceph-disk prepare --bluestore /dev/$disk --osd-id $osd_id"
        ssh $node "ceph-disk activate /dev/${disk}1"
        
        # Update ownership
        ssh $node "chown -R ceph:ceph /var/lib/ceph/osd/ceph-$osd_id"
    done
done

# Create initial pools
log "Creating initial pools..."
ceph osd pool create infokes-data 128 128
ceph osd pool create infokes-metadata 64 64
ceph osd pool create infokes-backups 128 128

# Set pool sizes
ceph osd pool set infokes-data size 3
ceph osd pool set infokes-metadata size 3
ceph osd pool set infokes-backups size 3

# Enable application tags
ceph osd pool application enable infokes-data rbd
ceph osd pool application enable infokes-metadata rbd
ceph osd pool application enable infokes-backups rbd

# Create RBD for VM storage
log "Creating RBD images..."
ceph osd pool create vm-images 128 128
ceph osd pool application enable vm-images rbd

# Create RBD image for Proxmox
rbd create --size 1024G --pool vm-images proxmox-vm-storage

# Configure CRUSH map for better data distribution
log "Configuring CRUSH map..."
ceph osd crush add-bucket dc1 datacenter
ceph osd crush add-bucket rack1 rack

for node in "${OSD_NODES[@]}"; do
    hostname=$(ssh $node "hostname -s")
    ceph osd crush add-bucket $hostname host
    ceph osd crush move $hostname rack=rack1
done

ceph osd crush move rack1 datacenter=dc1

# Final cluster status
log "Ceph cluster deployment completed!"
log "Cluster status:"
ceph -s

log "Dashboard access: https://${MON_NODES[0]}:8443"
log "Username: admin"
log "Password: (use 'ceph dashboard ac-user-show admin' to view)"

log "✅ Ceph storage deployment completed successfully!"