#!/bin/bash
# Health-InfraOps SSH Key Pair Generator

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
KEY_DIR="/etc/ssh/health-infraops-keys"
KEY_TYPES=("ed25519" "rsa" "ecdsa")
KEY_COMMENT="health-infraops@infokes.co.id"
BACKUP_DIR="/backup/ssh-keys"
DATE=$(date +%Y%m%d_%H%M%S)

log "Starting Health-InfraOps SSH key pair generation..."

# Create directories
mkdir -p $KEY_DIR $BACKUP_DIR
chmod 700 $KEY_DIR

# Backup existing keys
log "Backing up existing keys..."
if [ "$(ls -A $KEY_DIR 2>/dev/null)" ]; then
    tar -czf $BACKUP_DIR/ssh-keys-backup-$DATE.tar.gz $KEY_DIR
    log "Backup created: $BACKUP_DIR/ssh-keys-backup-$DATE.tar.gz"
fi

# Generate key pairs for each type
for key_type in "${KEY_TYPES[@]}"; do
    log "Generating $key_type key pair..."
    
    case $key_type in
        "ed25519")
            key_file="$KEY_DIR/ssh_host_ed25519_key"
            ssh-keygen -t ed25519 -f $key_file -N "" -C "$KEY_COMMENT"
            ;;
        "rsa")
            key_file="$KEY_DIR/ssh_host_rsa_key"
            ssh-keygen -t rsa -b 4096 -f $key_file -N "" -C "$KEY_COMMENT"
            ;;
        "ecdsa")
            key_file="$KEY_DIR/ssh_host_ecdsa_key"
            ssh-keygen -t ecdsa -b 521 -f $key_file -N "" -C "$KEY_COMMENT"
            ;;
    esac
    
    # Set proper permissions
    chmod 600 $key_file
    chmod 644 ${key_file}.pub
    
    log "✅ $key_type key pair generated: $key_file"
done

# Generate user key pairs for different roles
log "Generating user key pairs for different roles..."

declare -A USERS=(
    ["admin"]="Administrator access"
    ["deploy"]="Deployment service account"
    ["monitor"]="Monitoring service account"
    ["backup"]="Backup service account"
    ["bastion"]="Bastion host access"
)

for user in "${!USERS[@]}"; do
    log "Generating key pair for $user: ${USERS[$user]}"
    
    user_key_dir="$KEY_DIR/users/$user"
    mkdir -p $user_key_dir
    chmod 700 $user_key_dir
    
    # Generate Ed25519 key (primary)
    ssh-keygen -t ed25519 -f $user_key_dir/id_ed25519 -N "" -C "$user@infokes.co.id"
    
    # Generate RSA key (backup)
    ssh-keygen -t rsa -b 4096 -f $user_key_dir/id_rsa -N "" -C "$user@infokes.co.id"
    
    # Create authorized_keys file
    cat $user_key_dir/id_ed25519.pub > $user_key_dir/authorized_keys
    cat $user_key_dir/id_rsa.pub >> $user_key_dir/authorized_keys
    
    # Set permissions
    chmod 600 $user_key_dir/id_ed25519 $user_key_dir/id_rsa
    chmod 644 $user_key_dir/*.pub $user_key_dir/authorized_keys
    
    log "✅ User key pair generated for $user in $user_key_dir"
done

# Generate service account keys
log "Generating service account keys..."

declare -A SERVICES=(
    ["ansible"]="Ansible automation"
    ["ci-cd"]="CI/CD pipeline"
    ["monitoring"]="Monitoring system"
    ["backup"]="Backup system"
)

for service in "${!SERVICES[@]}"; do
    log "Generating key pair for $service service: ${SERVICES[$service]}"
    
    service_key_dir="$KEY_DIR/services/$service"
    mkdir -p $service_key_dir
    chmod 700 $service_key_dir
    
    ssh-keygen -t ed25519 -f $service_key_dir/id_ed25519 -N "" -C "$service-service@infokes.co.id"
    
    # Create restricted authorized_keys
    cat > $service_key_dir/authorized_keys << EOF
# $service Service Key
# ${SERVICES[$service]}
# Generated: $(date)
restrict $(cat $service_key_dir/id_ed25519.pub | cut -d' ' -f2-)
EOF
    
    chmod 600 $service_key_dir/id_ed25519
    chmod 644 $service_key_dir/*.pub $service_key_dir/authorized_keys
    
    log "✅ Service key pair generated for $service in $service_key_dir"
done

# Create key inventory
log "Creating key inventory..."
cat > $KEY_DIR/KEY-INVENTORY.md << EOF
# Health-InfraOps SSH Key Inventory
Generated: $(date)

## Host Keys
- ssh_host_ed25519_key - Ed25519 host key
- ssh_host_rsa_key - RSA 4096 host key  
- ssh_host_ecdsa_key - ECDSA 521 host key

## User Keys
$(for user in "${!USERS[@]}"; do
    echo "- $user: ${USERS[$user]}"
    echo "  - Ed25519: users/$user/id_ed25519"
    echo "  - RSA: users/$user/id_rsa"
done)

## Service Keys
$(for service in "${!SERVICES[@]}"; do
    echo "- $service: ${SERVICES[$service]}"
    echo "  - Key: services/$service/id_ed25519"
done)

## Key Fingerprints
\`\`\`
$(for key_file in $KEY_DIR/ssh_host_* $KEY_DIR/users/*/* $KEY_DIR/services/*/*; do
    if [[ $key_file == *.pub ]]; then
        echo "$(basename $key_file): $(ssh-keygen -lf $key_file)"
    fi
done)
\`\`\`

## Deployment Instructions

1. Copy host keys to /etc/ssh/
2. Distribute user keys to respective users
3. Deploy service keys to automation systems
4. Update SSH configuration to use new keys

## Security Notes
- Private keys are stored with 600 permissions
- Regular key rotation recommended every 90 days
- Monitor for unauthorized key usage
EOF

# Generate deployment script
log "Generating deployment script..."
cat > $KEY_DIR/deploy-keys.sh << 'EOF'
#!/bin/bash
# Health-InfraOps SSH Key Deployment Script

set -e

KEY_DIR="/etc/ssh/health-infraops-keys"
BACKUP_DIR="/backup/ssh-keys"

echo "Deploying Health-InfraOps SSH keys..."

# Backup existing host keys
echo "Backing up existing host keys..."
mkdir -p $BACKUP_DIR
tar -czf $BACKUP_DIR/ssh-host-keys-backup-$(date +%Y%m%d_%H%M%S).tar.gz /etc/ssh/ssh_host_* 2>/dev/null || true

# Deploy new host keys
echo "Deploying new host keys..."
cp $KEY_DIR/ssh_host_* /etc/ssh/
chmod 600 /etc/ssh/ssh_host_*key
chmod 644 /etc/ssh/ssh_host_*key.pub

# Update SSH configuration to use new keys
echo "Updating SSH configuration..."
sed -i 's|^HostKey.*|# Health-InfraOps Host Keys\nHostKey /etc/ssh/ssh_host_ed25519_key\nHostKey /etc/ssh/ssh_host_rsa_key\nHostKey /etc/ssh/ssh_host_ecdsa_key|' /etc/ssh/sshd_config

# Restart SSH service
echo "Restarting SSH service..."
systemctl restart sshd

echo "SSH key deployment completed successfully!"
EOF

chmod +x $KEY_DIR/deploy-keys.sh

# Display key fingerprints
log "SSH Key Fingerprints:"
for key_file in $KEY_DIR/ssh_host_*key; do
    if [ -f "$key_file" ]; then
        log "$(basename $key_file): $(ssh-keygen -lf $key_file)"
    fi
done

log "✅ Health-InfraOps SSH key generation completed!"
log "📊 Key Information:"
echo "   Host keys: $KEY_DIR/ssh_host_*"
echo "   User keys: $KEY_DIR/users/"
echo "   Service keys: $KEY_DIR/services/"
echo "   Inventory: $KEY_DIR/KEY-INVENTORY.md"
echo "   Deployment script: $KEY_DIR/deploy-keys.sh"

# Security reminder
warning "🔒 IMPORTANT:"
echo "   - Secure private keys with proper permissions"
echo "   - Distribute keys securely to intended users/systems"
echo "   - Consider implementing key rotation policy"
echo "   - Monitor SSH access logs for unauthorized usage"