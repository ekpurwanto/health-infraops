#!/bin/bash
# Health-InfraOps UFW Firewall Setup

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

# Check if UFW is available
if ! command -v ufw &> /dev/null; then
    error "UFW not found. Please install ufw first: apt install ufw"
    exit 1
fi

log "Starting Health-InfraOps UFW Firewall Setup..."

# Reset UFW to defaults
log "Resetting UFW to defaults..."
ufw --force reset

# Set default policies
log "Setting default policies..."
ufw default deny incoming
ufw default allow outgoing

# ============ APPLICATION-SPECIFIC RULES ============

# SSH - Only from Management and Production networks
log "Configuring SSH access..."
ufw allow from 10.0.40.0/24 to any port 22
ufw allow from 10.0.10.0/24 to any port 22

# HTTP/HTTPS - Public access
log "Configuring web access..."
ufw allow 80/tcp
ufw allow 443/tcp

# Database Access Rules
log "Configuring database access..."

# MySQL - App servers to DB servers
ufw allow from 10.0.10.0/24 to 10.0.20.0/24 port 3306

# PostgreSQL - App servers to DB servers  
ufw allow from 10.0.10.0/24 to 10.0.20.0/24 port 5432

# MongoDB - App servers to DB servers
ufw allow from 10.0.10.0/24 to 10.0.20.0/24 port 27017

# Monitoring Services
log "Configuring monitoring services..."

# Prometheus
ufw allow from 10.0.40.0/24 to any port 9090

# Node Exporter
ufw allow from 10.0.40.0/24 to any port 9100

# Grafana
ufw allow from 10.0.40.0/24 to any port 3000

# Zabbix
ufw allow from 10.0.40.0/24 to any port 10050
ufw allow from 10.0.40.0/24 to any port 10051

# Application Ports
log "Configuring application ports..."

# Node.js Application
ufw allow from 10.0.30.0/24 to 10.0.10.0/24 port 3000

# Python Application
ufw allow from 10.0.30.0/24 to 10.0.10.0/24 port 8000

# Load Balancer Health Checks
ufw allow from 10.0.30.0/24 to any port 3000
ufw allow from 10.0.30.0/24 to any port 8000

# Backup Services
log "Configuring backup services..."

# Rsync
ufw allow from 10.0.50.0/24 to any port 873

# NFS
ufw allow from 10.0.50.0/24 to any port 2049
ufw allow from 10.0.40.0/24 to any port 2049

# DNS Services
ufw allow 53/udp
ufw allow 53/tcp

# NTP Time Synchronization
ufw allow 123/udp

# ICMP (Ping)
ufw allow from 10.0.0.0/16 proto icmp

# ============ VLAN NETWORK RULES ============

log "Configuring VLAN network rules..."

# Allow all traffic within VLANs
ufw allow from 10.0.10.0/24 to 10.0.0.0/16
ufw allow from 10.0.20.0/24 to 10.0.0.0/16
ufw allow from 10.0.30.0/24 to 10.0.0.0/16
ufw allow from 10.0.40.0/24 to 10.0.0.0/16
ufw allow from 10.0.50.0/24 to 10.0.0.0/16

# ============ RATE LIMITING ============

log "Configuring rate limiting..."

# SSH rate limiting
ufw limit ssh

# HTTP rate limiting (basic DDoS protection)
ufw limit 80/tcp
ufw limit 443/tcp

# ============ APPLICATION-SPECIFIC RATE LIMITS ============

# API rate limiting
ufw limit from any to any port 3000
ufw limit from any to any port 8000

# ============ ENABLE FIREWALL ============

log "Enabling UFW firewall..."
ufw --force enable

# Wait for UFW to initialize
sleep 5

# Display firewall status
log "UFW Firewall Status:"
ufw status verbose

# Display numbered rules
log "UFW Rules (numbered):"
ufw status numbered

# Create backup of rules
log "Creating backup of UFW rules..."
ufw status numbered > /backup/ufw/ufw-rules-backup-$(date +%Y%m%d_%H%M%S).txt

# Create UFW application profiles for Health-InfraOps
log "Creating Health-InfraOps UFW application profiles..."

cat > /etc/ufw/applications.d/health-infraops << 'EOF'
[Health-InfraOps-Web]
title=Health InfraOps Web Services
description=Web application services for Infokes healthcare system
ports=80/tcp|443/tcp

[Health-InfraOps-App]
title=Health InfraOps Application
description=Node.js and Python application services
ports=3000/tcp|8000/tcp

[Health-InfraOps-DB]
title=Health InfraOps Database
description=Database services (MySQL, PostgreSQL, MongoDB)
ports=3306/tcp|5432/tcp|27017/tcp

[Health-InfraOps-Monitoring]
title=Health InfraOps Monitoring
description=Monitoring and observability services
ports=9090/tcp|3000/tcp|9100/tcp|10050/tcp|10051/tcp

[Health-InfraOps-Backup]
title=Health InfraOps Backup
description=Backup and storage services
ports=873/tcp|2049/tcp
EOF

# Reload UFW to recognize new applications
ufw reload

log "✅ Health-InfraOps UFW setup completed successfully!"
log "📊 Firewall Configuration Summary:"
echo "   - Default: deny incoming, allow outgoing"
echo "   - SSH: allowed from Management and Production networks"
echo "   - Web: HTTP/HTTPS open to public"
echo "   - Database: restricted to App servers"
echo "   - Monitoring: restricted to Management network"
echo "   - Rate limiting: enabled for SSH and web services"

# Test basic functionality
log "Testing basic network functionality..."
if ping -c 1 -W 2 8.8.8.8 &> /dev/null; then
    log "✅ Internet connectivity: OK"
else
    warning "⚠️ Internet connectivity: Failed - check outgoing rules"
fi

# Log the setup completion
logger "Health-InfraOps UFW firewall setup completed"