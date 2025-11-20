#!/bin/bash
# Health-InfraOps iptables Rules Restore Script

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Configuration
RULES_FILE="/etc/iptables/rules.v4"
BACKUP_DIR="/backup/iptables"
DATE=$(date +%Y%m%d_%H%M%S)

# Check if iptables is available
if ! command -v iptables &> /dev/null; then
    error "iptables not found. Please install iptables first."
    exit 1
fi

# Create backup directory
mkdir -p $BACKUP_DIR

log "Starting iptables rules restoration..."

# Backup current rules
log "Backing up current rules..."
iptables-save > $BACKUP_DIR/iptables-backup-$DATE.rules

# Check if rules file exists
if [ ! -f "$RULES_FILE" ]; then
    error "Rules file not found: $RULES_FILE"
    error "Please create the rules file first using iptables-rules script"
    exit 1
fi

# Test rules syntax
log "Testing rules syntax..."
if ! iptables-restore -t < $RULES_FILE; then
    error "Rules syntax test failed. Please check the rules file."
    exit 1
fi

# Apply rules
log "Applying iptables rules..."
if iptables-restore < $RULES_FILE; then
    log "✅ iptables rules applied successfully"
else
    error "Failed to apply iptables rules"
    
    # Restore from backup
    warning "Restoring from backup..."
    if iptables-restore < $BACKUP_DIR/iptables-backup-$DATE.rules; then
        log "Previous rules restored successfully"
    else
        error "Failed to restore from backup. Firewall may be in inconsistent state."
        exit 1
    fi
fi

# Verify rules are applied
log "Verifying applied rules..."
iptables -L INPUT -n --line-numbers | head -20
iptables -L FORWARD -n --line-numbers | head -10

# Save rules for persistence
log "Saving rules for persistence..."
if command -v iptables-save &> /dev/null; then
    iptables-save > $RULES_FILE
fi

# Check if we need to install persistence
if [ ! -f "/etc/network/if-pre-up.d/iptables" ]; then
    log "Setting up iptables persistence..."
    cat > /etc/network/if-pre-up.d/iptables << 'EOF'
#!/bin/bash
iptables-restore < /etc/iptables/rules.v4
EOF
    chmod +x /etc/network/if-pre-up.d/iptables
fi

# Create systemd service for persistence
if systemctl is-active --quiet netfilter-persistent 2>/dev/null; then
    log "Netfilter persistent service is active"
else
    cat > /etc/systemd/system/iptables-restore.service << 'EOF'
[Unit]
Description=Restore iptables rules
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore /etc/iptables/rules.v4
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl enable iptables-restore.service
    log "iptables restore service enabled"
fi

log "✅ iptables rules restoration completed successfully!"
log "📊 Rules summary:"
echo "   - INPUT policy: $(iptables -L INPUT | head -1 | awk '{print $4}')"
echo "   - FORWARD policy: $(iptables -L FORWARD | head -1 | awk '{print $4}')"
echo "   - OUTPUT policy: $(iptables -L OUTPUT | head -1 | awk '{print $4}')"
echo "   - Rules file: $RULES_FILE"
echo "   - Backup: $BACKUP_DIR/iptables-backup-$DATE.rules"

# Test basic connectivity
log "Testing basic connectivity..."
ping -c 1 -W 2 8.8.8.8 > /dev/null 2>&1 && log "✅ Internet connectivity: OK" || warning "⚠️ Internet connectivity: Failed"

# Log the restoration
logger "Health-InfraOps iptables rules restored successfully"