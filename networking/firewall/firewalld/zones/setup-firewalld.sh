#!/bin/bash
# Health-InfraOps Firewalld Setup Script

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

# Check if firewalld is available
if ! command -v firewall-cmd &> /dev/null; then
    error "firewalld not found. Please install firewalld first: yum install firewalld / apt install firewalld"
    exit 1
fi

log "Starting Health-InfraOps Firewalld Setup..."

# Start and enable firewalld
log "Starting firewalld service..."
systemctl enable firewalld
systemctl start firewalld

# Wait for service to start
sleep 3

# Check firewalld status
if ! firewall-cmd --state &>/dev/null; then
    error "firewalld is not running. Please check the service status."
    exit 1
fi

# Backup current configuration
log "Backing up current firewalld configuration..."
firewall-cmd --runtime-to-permanent
cp -r /etc/firewalld /etc/firewalld.backup.$(date +%Y%m%d_%H%M%S)

# ============ ZONE SETUP ============

# Create Health-InfraOps zone
log "Creating Health-InfraOps zone..."
firewall-cmd --permanent --new-zone=health-infraops

# Copy zone configuration
log "Configuring Health-InfraOps zone..."
cp health-infraops.xml /etc/firewalld/zones/health-infraops.xml
chown root:root /etc/firewalld/zones/health-infraops.xml
chmod 600 /etc/firewalld/zones/health-infraops.xml

# ============ SERVICE DEFINITIONS ============

log "Creating custom service definitions..."

# Infokes Application Service
cat > /etc/firewalld/services/infokes-app.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<service>
  <short>Infokes Application</short>
  <description>Health InfraOps Node.js and Python application services</description>
  <port protocol="tcp" port="3000"/>
  <port protocol="tcp" port="8000"/>
</service>
EOF

# Infokes Database Service
cat > /etc/firewalld/services/infokes-db.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<service>
  <short>Infokes Database</short>
  <description>Health InfraOps database services (MySQL, PostgreSQL, MongoDB)</description>
  <port protocol="tcp" port="3306"/>
  <port protocol="tcp" port="5432"/>
  <port protocol="tcp" port="27017"/>
</service>
EOF

# Infokes Monitoring Service
cat > /etc/firewalld/services/infokes-mon.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<service>
  <short>Infokes Monitoring</short>
  <description>Health InfraOps monitoring and observability services</description>
  <port protocol="tcp" port="9090"/>
  <port protocol="tcp" port="3000"/>
  <port protocol="tcp" port="9100"/>
  <port protocol="tcp" port="10050"/>
  <port protocol="tcp" port="10051"/>
</service>
EOF

# Infokes Backup Service
cat > /etc/firewalld/services/infokes-backup.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<service>
  <short>Infokes Backup</short>
  <description>Health InfraOps backup and storage services</description>
  <port protocol="tcp" port="873"/>
  <port protocol="tcp" port="2049"/>
</service>
EOF

# Set proper permissions for service files
chown root:root /etc/firewalld/services/infokes-*.xml
chmod 600 /etc/firewalld/services/infokes-*.xml

# ============ ZONE CONFIGURATION ============

# Reload firewalld to recognize new services and zones
log "Reloading firewalld..."
firewall-cmd --reload

# Set default zone
log "Setting default zone..."
firewall-cmd --set-default-zone=health-infraops

# Add interfaces to zones based on VLANs
log "Configuring network interfaces..."

# Detect interfaces and assign to zones (this is example - adjust based on your setup)
INTERFACES=$(ip link show | grep -E '^[0-9]+:' | awk -F: '{print $2}' | grep -v lo | tr -d ' ')

for IFACE in $INTERFACES; do
    IP_ADDR=$(ip addr show $IFACE | grep 'inet ' | awk '{print $2}')
    
    case $IP_ADDR in
        10.0.10.*)
            firewall-cmd --permanent --zone=health-infraops --change-interface=$IFACE
            log "Assigned $IFACE (Production) to health-infraops zone"
            ;;
        10.0.20.*)
            firewall-cmd --permanent --zone=health-infraops --change-interface=$IFACE
            log "Assigned $IFACE (Database) to health-infraops zone"
            ;;
        10.0.30.*)
            firewall-cmd --permanent --zone=health-infraops --change-interface=$IFACE
            log "Assigned $IFACE (DMZ) to health-infraops zone"
            ;;
        10.0.40.*)
            firewall-cmd --permanent --zone=health-infraops --change-interface=$IFACE
            log "Assigned $IFACE (Management) to health-infraops zone"
            ;;
        10.0.50.*)
            firewall-cmd --permanent --zone=health-infraops --change-interface=$IFACE
            log "Assigned $IFACE (Backup) to health-infraops zone"
            ;;
        *)
            firewall-cmd --permanent --zone=public --change-interface=$IFACE
            warning "Assigned $IFACE to public zone (external interface)"
            ;;
    esac
done

# ============ APPLY CONFIGURATION ============

# Reload to apply permanent configuration
log "Applying permanent configuration..."
firewall-cmd --reload

# Make runtime configuration permanent
firewall-cmd --runtime-to-permanent

# ============ VERIFICATION ============

log "Verifying firewalld configuration..."

# Check active zones
log "Active zones:"
firewall-cmd --get-active-zones

# Check services in health-infraops zone
log "Services in health-infraops zone:"
firewall-cmd --zone=health-infraops --list-services

# Check ports in health-infraops zone
log "Ports in health-infraops zone:"
firewall-cmd --zone=health-infraops --list-ports

# Check rich rules
log "Rich rules in health-infraops zone:"
firewall-cmd --zone=health-infraops --list-rich-rules

# ============ FIREWALLD OPTIMIZATION ============

log "Optimizing firewalld settings..."

# Set log denied packets
firewall-cmd --set-log-denied=all
firewall-cmd --permanent --set-log-denied=all

# Enable panic mode (disable with: firewall-cmd --panic-off)
# firewall-cmd --panic-on

# Create backup of final configuration
log "Creating final configuration backup..."
firewall-cmd --runtime-to-permanent
cp -r /etc/firewalld /etc/firewalld.final-backup.$(date +%Y%m%d_%H%M%S)

log "✅ Health-InfraOps Firewalld setup completed successfully!"
log "📊 Firewall Configuration Summary:"
echo "   - Default zone: health-infraops"
echo "   - Default target: DROP"
echo "   - Custom services: infokes-app, infokes-db, infokes-mon, infokes-backup"
echo "   - VLAN-based access control enabled"
echo "   - Logging: all denied packets"

# Test basic connectivity
log "Testing basic network connectivity..."
if ping -c 1 -W 2 8.8.8.8 &> /dev/null; then
    log "✅ Internet connectivity: OK"
else
    warning "⚠️ Internet connectivity: Failed - check outgoing rules"
fi

# Display final status
log "Final firewalld status:"
firewall-cmd --state && log "✅ firewalld is running" || error "❌ firewalld is not running"

# Log completion
logger "Health-InfraOps Firewalld setup completed successfully"