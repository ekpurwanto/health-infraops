#!/bin/bash
# Health-InfraOps Network Configuration

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

# Backup original interfaces file
BACKUP_FILE="/etc/network/interfaces.backup.$(date +%Y%m%d_%H%M%S)"
cp /etc/network/interfaces "$BACKUP_FILE"
log "Backed up interfaces to $BACKUP_FILE"

# Network configuration
log "Configuring VLAN segmentation for Health-InfraOps..."

cat > /etc/network/interfaces << 'EOF'
# Health-InfraOps Network Configuration
# =====================================

auto lo
iface lo inet loopback

# Main bridge
auto vmbr0
iface vmbr0 inet static
    address 10.0.1.1/24
    bridge-ports none
    bridge-stp off
    bridge-fd 0

# Production VLAN (Web/App Servers)
auto vmbr0.10
iface vmbr0.10 inet static
    address 10.0.10.1
    netmask 255.255.255.0
    vlan-raw-device vmbr0

# Database VLAN (Database Cluster)
auto vmbr0.20
iface vmbr0.20 inet static
    address 10.0.20.1
    netmask 255.255.255.0
    vlan-raw-device vmbr0

# DMZ VLAN (Load Balancers)
auto vmbr0.30
iface vmbr0.30 inet static
    address 10.0.30.1
    netmask 255.255.255.0
    vlan-raw-device vmbr0

# Management VLAN (Monitoring/Admin)
auto vmbr0.40
iface vmbr0.40 inet static
    address 10.0.40.1
    netmask 255.255.255.0
    vlan-raw-device vmbr0

# Backup VLAN (Backup Network)
auto vmbr0.50
iface vmbr0.50 inet static
    address 10.0.50.1
    netmask 255.255.255.0
    vlan-raw-device vmbr0
EOF

# Configure DHCP for each VLAN
log "Configuring DHCP servers for each VLAN..."

# Install dnsmasq if not present
if ! command -v dnsmasq &> /dev/null; then
    apt update && apt install -y dnsmasq
fi

# DHCP configuration
cat > /etc/dnsmasq.d/health-infraops.conf << 'EOF'
# Health-InfraOps DHCP Configuration

# Production VLAN
dhcp-range=vmbr0.10,10.0.10.100,10.0.10.200,255.255.255.0,12h
dhcp-option=vmbr0.10,3,10.0.10.1
dhcp-option=vmbr0.10,6,8.8.8.8,1.1.1.1

# Database VLAN
dhcp-range=vmbr0.20,10.0.20.100,10.0.20.150,255.255.255.0,24h
dhcp-option=vmbr0.20,3,10.0.20.1

# DMZ VLAN
dhcp-range=vmbr0.30,10.0.30.100,10.0.30.150,255.255.255.0,6h
dhcp-option=vmbr0.30,3,10.0.30.1

# Management VLAN
dhcp-range=vmbr0.40,10.0.40.100,10.0.40.150,255.255.255.0,24h
dhcp-option=vmbr0.40,3,10.0.40.1

# Backup VLAN
dhcp-range=vmbr0.50,10.0.50.100,10.0.50.150,255.255.255.0,24h
dhcp-option=vmbr0.50,3,10.0.50.1

# Static IP assignments
# Load Balancers
dhcp-host=aa:bb:cc:dd:ee:01,vm-lb-01,10.0.30.10
dhcp-host=aa:bb:cc:dd:ee:02,vm-lb-02,10.0.30.11

# App Servers
dhcp-host=aa:bb:cc:dd:ee:11,vm-app-01,10.0.10.11
dhcp-host=aa:bb:cc:dd:ee:12,vm-app-02,10.0.10.12

# Database Servers
dhcp-host=aa:bb:cc:dd:ee:21,vm-db-01,10.0.20.21
dhcp-host=aa:bb:cc:dd:ee:22,vm-db-02,10.0.20.22

# Monitoring
dhcp-host=aa:bb:cc:dd:ee:41,vm-mon-01,10.0.40.41
EOF

# Enable IP forwarding
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

# Configure basic firewall
log "Configuring firewall rules..."

# Reset iptables
iptables -F
iptables -X
iptables -Z

# Default policies
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT

# Allow SSH from management network
iptables -A INPUT -s 10.0.40.0/24 -p tcp --dport 22 -j ACCEPT

# Allow inter-VLAN communication as needed
iptables -A FORWARD -s 10.0.10.0/24 -d 10.0.20.0/24 -p tcp --dport 5432 -j ACCEPT  # App to DB
iptables -A FORWARD -s 10.0.40.0/24 -d 10.0.0.0/16 -j ACCEPT  # Monitoring to all

# Save iptables rules
iptables-save > /etc/iptables/rules.v4

# Restart services
log "Restarting network services..."
systemctl restart networking
systemctl restart dnsmasq

log "✅ Network configuration completed successfully!"
log "📊 Network Summary:"
echo "   VLAN 10 (PROD):    10.0.10.0/24"
echo "   VLAN 20 (DB):      10.0.20.0/24"
echo "   VLAN 30 (DMZ):     10.0.30.0/24"
echo "   VLAN 40 (MGMT):    10.0.40.0/24"
echo "   VLAN 50 (BACKUP):  10.0.50.0/24"