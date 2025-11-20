#!/bin/bash
# Health-InfraOps Bastion Host Setup Script

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
BASTION_HOST="10.0.40.44"
SSH_PORT="2222"
TARGET_NETWORKS=("10.0.10.0/24" "10.0.20.0/24" "10.0.30.0/24" "10.0.50.0/24")
ALLOWED_USERS=("admin" "deploy" "monitor")
BACKUP_DIR="/backup/bastion"

log "Starting Health-InfraOps Bastion Host setup..."

# Check if running on the bastion host
CURRENT_IP=$(hostname -I | awk '{print $1}')
if [ "$CURRENT_IP" != "$BASTION_HOST" ]; then
    warning "This script should be run on the bastion host ($BASTION_HOST)"
    warning "Current IP: $CURRENT_IP"
    read -p "Continue anyway? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Create backup directory
mkdir -p $BACKUP_DIR

# Backup existing SSH configuration
log "Backing up existing SSH configuration..."
cp /etc/ssh/sshd_config $BACKUP_DIR/sshd_config.backup.$(date +%Y%m%d_%H%M%S)

# Install required packages
log "Installing required packages..."
apt update
apt install -y fail2ban ufw auditd tmux

# Configure firewall
log "Configuring firewall..."
ufw reset
ufw default deny incoming
ufw default allow outgoing

# Allow SSH only from management network
ufw allow from 10.0.40.0/24 to any port $SSH_PORT

# Enable firewall
ufw --force enable

# Configure SSH for bastion host
log "Configuring SSH for bastion host..."
cat > /etc/ssh/sshd_config << EOF
# Health-InfraOps Bastion Host SSH Configuration
Port $SSH_PORT
Protocol 2
AddressFamily inet
ListenAddress $BASTION_HOST

# Security Settings
PermitRootLogin no
StrictModes yes
MaxAuthTries 3
MaxSessions 10
ClientAliveInterval 300
ClientAliveCountMax 2
LoginGraceTime 60

# Authentication
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
KerberosAuthentication no
GSSAPIAuthentication no

# X11 and Forwarding
X11Forwarding no
AllowTcpForwarding yes
PermitTTY yes
GatewayPorts no
AllowAgentForwarding no

# Logging
SyslogFacility AUTH
LogLevel VERBOSE

# Access Control
AllowUsers ${ALLOWED_USERS[@]}
AllowGroups ssh-users bastion-users
DenyUsers root bin daemon

# Chroot and jail settings
UsePAM yes
PrintMotd yes
PrintLastLog yes

# Match blocks for specific restrictions
Match User deploy
    AllowTcpForwarding yes
    PermitOpen 10.0.10.0/24:22 10.0.20.0/24:22
    ForceCommand /usr/local/bin/bastion-deploy-filter

Match User monitor
    AllowTcpForwarding yes
    PermitOpen 10.0.40.0/24:22
    ForceCommand /usr/local/bin/bastion-monitor-filter

Match User admin
    AllowTcpForwarding yes
    PermitOpen *
    X11Forwarding no

# Crypto Settings
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256
HostKeyAlgorithms rsa-sha2-512,rsa-sha2-256

# Performance
UseDNS no
Compression no

# Banner
Banner /etc/ssh/bastion-banner
EOF

# Create SSH banner
log "Creating SSH banner..."
cat > /etc/ssh/bastion-banner << EOF
╔══════════════════════════════════════════════════════════════╗
║                   HEALTH-INFRAOPS BASTION                   ║
║                     INFOKES HEALTHCARE SYSTEM               ║
╠══════════════════════════════════════════════════════════════╣
║ NOTICE: This is a restricted access system.                 ║
║ All activities are monitored and logged.                    ║
║ Unauthorized access is prohibited.                          ║
║                                                              ║
║ Accessible Networks:                                        ║
║ - Production (10.0.10.0/24)                                ║
║ - Database (10.0.20.0/24)                                  ║
║ - DMZ (10.0.30.0/24)                                       ║
║ - Backup (10.0.50.0/24)                                    ║
╚══════════════════════════════════════════════════════════════╝
EOF

# Create bastion filter scripts
log "Creating bastion filter scripts..."

# Deploy user filter
cat > /usr/local/bin/bastion-deploy-filter << 'EOF'
#!/bin/bash
# Health-InfraOps Bastion Deploy User Filter

LOG_FILE="/var/log/bastion/deploy-access.log"
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

echo "[$TIMESTAMP] User: $USER, Remote: $SSH_CLIENT, Command: $SSH_ORIGINAL_COMMAND" >> $LOG_FILE

# Allowed target networks
ALLOWED_NETWORKS=("10.0.10.0/24" "10.0.20.0/24")

# Check if command is a direct SSH connection
if [[ "$SSH_ORIGINAL_COMMAND" =~ ^ssh\ [-a-zA-Z0-9=]*\ ([a-zA-Z0-9.-]+)$ ]]; then
    TARGET_HOST="${BASH_REMATCH[1]}"
    
    # Validate target host is in allowed networks
    ALLOWED=false
    for network in "${ALLOWED_NETWORKS[@]}"; do
        if python3 -c "import ipaddress; print(ipaddress.ip_address('$TARGET_HOST') in ipaddress.ip_network('$network'))" 2>/dev/null | grep -q "True"; then
            ALLOWED=true
            break
        fi
    done
    
    if [ "$ALLOWED" = true ]; then
        exec $SSH_ORIGINAL_COMMAND
    else
        echo "Access denied: $TARGET_HOST is not in allowed networks"
        exit 1
    fi
else
    echo "This account is restricted to SSH tunneling only."
    echo "Usage: ssh -J bastion.infokes.co.id target-host"
    exit 1
fi
EOF

# Monitor user filter
cat > /usr/local/bin/bastion-monitor-filter << 'EOF'
#!/bin/bash
# Health-InfraOps Bastion Monitor User Filter

LOG_FILE="/var/log/bastion/monitor-access.log"
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

echo "[$TIMESTAMP] User: $USER, Remote: $SSH_CLIENT, Command: $SSH_ORIGINAL_COMMAND" >> $LOG_FILE

# Allowed target networks (monitoring only)
ALLOWED_NETWORKS=("10.0.40.0/24")

# Check if command is a direct SSH connection
if [[ "$SSH_ORIGINAL_COMMAND" =~ ^ssh\ [-a-zA-Z0-9=]*\ ([a-zA-Z0-9.-]+)$ ]]; then
    TARGET_HOST="${BASH_REMATCH[1]}"
    
    # Validate target host is in allowed networks
    ALLOWED=false
    for network in "${ALLOWED_NETWORKS[@]}"; do
        if python3 -c "import ipaddress; print(ipaddress.ip_address('$TARGET_HOST') in ipaddress.ip_network('$network'))" 2>/dev/null | grep -q "True"; then
            ALLOWED=true
            break
        fi
    done
    
    if [ "$ALLOWED" = true ]; then
        exec $SSH_ORIGINAL_COMMAND
    else
        echo "Access denied: $TARGET_HOST is not in monitoring network"
        exit 1
    fi
else
    echo "This account is restricted to monitoring network access only."
    exit 1
fi
EOF

chmod +x /usr/local/bin/bastion-*-filter

# Create bastion users and groups
log "Creating bastion users and groups..."
groupadd -f bastion-users
groupadd -f ssh-users

for user in "${ALLOWED_USERS[@]}"; do
    if ! id "$user" &>/dev/null; then
        useradd -m -s /bin/bash -G bastion-users,ssh-users "$user"
        log "Created user: $user"
    fi
    
    # Create .ssh directory
    mkdir -p /home/$user/.ssh
    chmod 700 /home/$user/.ssh
    chown $user:$user /home/$user/.ssh
done

# Configure enhanced logging
log "Configuring enhanced logging..."
mkdir -p /var/log/bastion
cat > /etc/rsyslog.d/50-bastion.conf << EOF
# Health-InfraOps Bastion Host Logging
if \$programname == 'sshd' then /var/log/bastion/ssh.log
& stop
EOF

systemctl restart rsyslog

# Configure auditd for SSH monitoring
log "Configuring auditd for SSH monitoring..."
cat > /etc/audit/rules.d/70-bastion.rules << EOF
# Health-InfraOps Bastion Audit Rules
-w /etc/ssh/sshd_config -p wa -k sshd_config
-w /etc/ssh/ -p wa -k sshd
-w /var/log/bastion/ -p wa -k bastion_logs
-w /usr/local/bin/bastion- -p wa -k bastion_scripts
-a always,exit -F arch=b64 -S execve -F path=/usr/local/bin/bastion- -k bastion_exec
EOF

augenrules --load
systemctl restart auditd

# Configure fail2ban for SSH protection
log "Configuring fail2ban..."
cat > /etc/fail2ban/jail.d/sshd.conf << EOF
[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600

[sshd-ddos]
enabled = true
port = $SSH_PORT
filter = sshd-ddos
logpath = /var/log/auth.log
maxretry = 10
bantime = 86400
findtime = 3600
EOF

systemctl enable fail2ban
systemctl restart fail2ban

# Create bastion access script for users
log "Creating user access scripts..."
cat > /usr/local/bin/bastion-access << 'EOF'
#!/bin/bash
# Health-InfraOps Bastion Access Helper

BASTION_HOST="bastion.infokes.co.id"
BASTION_PORT="2222"

echo "Health-InfraOps Bastion Host Access Helper"
echo "=========================================="

case "$1" in
    "production")
        echo "Connecting to production servers..."
        ssh -J $BASTION_HOST:$BASTION_PORT app-01.infokes.co.id
        ;;
    "database")
        echo "Connecting to database servers..."
        ssh -J $BASTION_HOST:$BASTION_PORT db-mysql-01.infokes.co.id
        ;;
    "monitoring")
        echo "Connecting to monitoring servers..."
        ssh -J $BASTION_HOST:$BASTION_PORT mon-01.infokes.co.id
        ;;
    "backup")
        echo "Connecting to backup servers..."
        ssh -J $BASTION_HOST:$BASTION_PORT backup-01.infokes.co.id
        ;;
    *)
        echo "Usage: $0 {production|database|monitoring|backup}"
        echo ""
        echo "Examples:"
        echo "  $0 production    # Connect to production servers"
        echo "  $0 database      # Connect to database servers"
        echo "  $0 monitoring    # Connect to monitoring servers"
        echo "  $0 backup        # Connect to backup servers"
        echo ""
        echo "Manual connection:"
        echo "  ssh -J $BASTION_HOST:$BASTION_PORT target-server"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/bastion-access

# Restart SSH service
log "Restarting SSH service..."
systemctl daemon-reload
systemctl restart sshd

# Verify setup
log "Verifying bastion host setup..."
if systemctl is-active sshd | grep -q "active"; then
    log "✅ SSH service is running"
else
    error "❌ SSH service is not running"
    exit 1
fi

if systemctl is-active fail2ban | grep -q "active"; then
    log "✅ Fail2ban is running"
else
    warning "⚠️ Fail2ban is not running"
fi

# Test bastion functionality
log "Testing bastion functionality..."
if ssh-keyscan -p $SSH_PORT $BASTION_HOST &>/dev/null; then
    log "✅ Bastion host is accessible on port $SSH_PORT"
else
    warning "⚠️ Bastion host may not be accessible"
fi

# Create setup report
log "Creating setup report..."
cat > /var/log/bastion/setup-report.log << EOF
Health-InfraOps Bastion Host Setup Report
Generated: $(date)

Configuration:
- Bastion Host: $BASTION_HOST
- SSH Port: $SSH_PORT
- Allowed Users: ${ALLOWED_USERS[@]}
- Target Networks: ${TARGET_NETWORKS[@]}

Services:
- SSH: $(systemctl is-active sshd)
- Fail2ban: $(systemctl is-active fail2ban)
- Auditd: $(systemctl is-active auditd)
- UFW: $(systemctl is-active ufw)

Files:
- SSH Config: /etc/ssh/sshd_config
- Banner: /etc/ssh/bastion-banner
- Filters: /usr/local/bin/bastion-*-filter
- Access Helper: /usr/local/bin/bastion-access

Security Features:
- Key-based authentication only
- Restricted user commands
- Network-level filtering
- Comprehensive logging
- Fail2ban protection
- Audit trail

Usage:
- Production: bastion-access production
- Database: bastion-access database
- Monitoring: bastion-access monitoring
- Manual: ssh -J $BASTION_HOST:$SSH_PORT target-host
EOF

log "✅ Health-InfraOps Bastion Host setup completed!"
log "📊 Setup Summary:"
echo "   Host: $BASTION_HOST"
echo "   SSH Port: $SSH_PORT"
echo "   Allowed Users: ${ALLOWED_USERS[@]}"
echo "   Access Helper: bastion-access {production|database|monitoring|backup}"
echo "   Report: /var/log/bastion/setup-report.log"

# Security recommendations
warning "🔒 Security Recommendations:"
echo "   - Regularly review /var/log/bastion/ access logs"
echo "   - Monitor fail2ban status and adjust rules as needed"
echo "   - Keep SSH keys secure and rotate regularly"
echo "   - Regular security audits of bastion host"