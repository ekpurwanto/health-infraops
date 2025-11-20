#!/bin/bash
# Health-InfraOps Hosts File Generator
# Creates a comprehensive /etc/hosts file for all infrastructure

set -e

# Colors
GREEN='\033[0;32m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

# Configuration
HOSTS_FILE="/etc/hosts.health-infraops"
BACKUP_DIR="/backup/hosts"
DATE=$(date +%Y%m%d_%H%M%S)

log "Generating Health-InfraOps hosts file..."

# Create backup
mkdir -p $BACKUP_DIR
cp /etc/hosts $BACKUP_DIR/hosts.backup-$DATE

# Generate new hosts file
cat > $HOSTS_FILE << 'EOF'
# Health-InfraOps Infrastructure Hosts File
# Generated automatically - DO NOT EDIT MANUALLY
# 
# Infokes Healthcare System
# Last updated: $(date)

127.0.0.1       localhost
::1             localhost ip6-localhost ip6-loopback

# ============ LOAD BALANCERS (VLAN 30) ============
10.0.30.10      lb-01.infokes.co.id lb-01
10.0.30.11      lb-02.infokes.co.id lb-02

# Public domains point to load balancers
10.0.30.10      infokes.co.id www.infokes.co.id app.infokes.co.id api.infokes.co.id

# ============ APPLICATION SERVERS (VLAN 10) ============
10.0.10.11      app-01.infokes.co.id app-01
10.0.10.12      app-02.infokes.co.id app-02
10.0.10.13      app-03.infokes.co.id app-03
10.0.10.14      app-04.infokes.co.id app-04

# API Servers
10.0.10.15      api-01.infokes.co.id api-01
10.0.10.16      api-02.infokes.co.id api-02
10.0.10.17      api-03.infokes.co.id api-03

# Static Content Servers
10.0.10.19      static-01.infokes.co.id static-01
10.0.10.20      static-02.infokes.co.id static-02

# ============ DATABASE SERVERS (VLAN 20) ============
# MySQL Servers
10.0.20.21      db-mysql-01.infokes.co.id db-mysql-01 mysql-01
10.0.20.22      db-mysql-02.infokes.co.id db-mysql-02 mysql-02

# PostgreSQL Servers
10.0.20.23      db-pg-01.infokes.co.id db-pg-01 postgres-01
10.0.20.24      db-pg-02.infokes.co.id db-pg-02 postgres-02

# MongoDB Servers
10.0.20.25      db-mongo-01.infokes.co.id db-mongo-01 mongo-01
10.0.20.26      db-mongo-02.infokes.co.id db-mongo-02 mongo-02

# Database service names
10.0.20.21      mysql.infokes.co.id
10.0.20.23      postgres.infokes.co.id
10.0.20.25      mongodb.infokes.co.id

# ============ MONITORING & MANAGEMENT (VLAN 40) ============
10.0.40.41      mon-01.infokes.co.id mon-01
10.0.40.41      grafana.infokes.co.id grafana
10.0.40.41      prometheus.infokes.co.id prometheus
10.0.40.41      zabbix.infokes.co.id zabbix
10.0.40.41      monitor.infokes.co.id monitor

# DNS Servers
10.0.40.42      ns1.infokes.co.id ns1 dns-01
10.0.40.43      ns2.infokes.co.id ns2 dns-02

# ============ BACKUP & STORAGE (VLAN 50) ============
10.0.50.10      backup-01.infokes.co.id backup-01
10.0.50.11      nfs-01.infokes.co.id nfs-01
10.0.50.12      ceph-01.infokes.co.id ceph-01
10.0.50.13      ceph-02.infokes.co.id ceph-02
10.0.50.14      ceph-03.infokes.co.id ceph-03

# ============ NETWORK INFRASTRUCTURE ============
# Gateways
10.0.10.1       gateway-10.infokes.co.id
10.0.20.1       gateway-20.infokes.co.id
10.0.30.1       gateway-30.infokes.co.id
10.0.40.1       gateway-40.infokes.co.id
10.0.50.1       gateway-50.infokes.co.id

# Proxmox Hosts (if applicable)
10.0.1.10       proxmox-01.infokes.co.id pve-01
10.0.1.11       proxmox-02.infokes.co.id pve-02
10.0.1.12       proxmox-03.infokes.co.id pve-03

# ============ DEVELOPMENT & STAGING ============
# Staging Environment
10.0.60.10      staging.infokes.co.id staging
10.0.60.11      staging-app-01.infokes.co.id
10.0.60.12      staging-db-01.infokes.co.id

# Development Environment
10.0.70.10      dev.infokes.co.id dev
10.0.70.11      dev-app-01.infokes.co.id
10.0.70.12      dev-db-01.infokes.co.id

# ============ SERVICE DISCOVERY ALIASES ============
# Load balanced services
10.0.30.10      app.infokes.co.id
10.0.30.10      api.infokes.co.id

# Database clusters
10.0.20.21      mysql-master.infokes.co.id
10.0.20.22      mysql-slave.infokes.co.id
10.0.20.23      postgres-master.infokes.co.id
10.0.20.24      postgres-slave.infokes.co.id

# Monitoring endpoints
10.0.40.41      alerts.infokes.co.id
10.0.40.41      metrics.infokes.co.id
10.0.40.41      dashboards.infokes.co.id

# Backup services
10.0.50.10      backups.infokes.co.id
10.0.50.11      storage.infokes.co.id
EOF

log "Hosts file generated: $HOSTS_FILE"

# Optionally replace /etc/hosts
read -p "Replace /etc/hosts with generated file? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    cp $HOSTS_FILE /etc/hosts
    log "✅ /etc/hosts updated successfully"
else
    log "Hosts file saved to: $HOSTS_FILE"
    log "To apply manually: cp $HOSTS_FILE /etc/hosts"
fi

# Test host resolution
log "Testing host resolution..."
if ping -c 1 -W 2 app-01.infokes.co.id &> /dev/null; then
    log "✅ Host resolution test passed"
else
    log "⚠️ Host resolution test failed - check network configuration"
fi

log "✅ Health-InfraOps hosts file generation completed!"