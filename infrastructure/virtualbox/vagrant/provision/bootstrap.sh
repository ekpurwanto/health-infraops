#!/bin/bash
# Health-InfraOps Bootstrap Provisioning Script

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Update system
log "Updating system packages..."
apt-get update
apt-get upgrade -y

# Install essential packages
log "Installing essential packages..."
apt-get install -y \
    curl \
    wget \
    git \
    vim \
    htop \
    net-tools \
    dnsutils \
    ufw \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release

# Configure firewall
log "Configuring firewall..."
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# Configure timezone
timedatectl set-timezone Asia/Jakarta

# Create health-infraops user
if ! id "health-infraops" &>/dev/null; then
    log "Creating health-infraops user..."
    useradd -m -s /bin/bash health-infraops
    usermod -aG sudo health-infraops
    echo 'health-infraops ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
fi

# Configure SSH
log "Configuring SSH..."
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart ssh

# Create directory structure
log "Creating Health-InfraOps directory structure..."
mkdir -p /opt/health-infraops/{scripts,backups,logs,config}
chown -R health-infraops:health-infraops /opt/health-infraops

# Install monitoring agent
log "Installing monitoring tools..."
apt-get install -y prometheus-node-exporter

# Configure hostname
echo "Health-InfraOps $(hostname)" > /etc/motd

log "✅ Bootstrap provisioning completed!"
