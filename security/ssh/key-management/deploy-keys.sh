#!/bin/bash
# Health-InfraOps SSH Key Deployment Script

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
TARGET_SERVERS=(
    "10.0.10.11"  # app-01
    "10.0.10.12"  # app-02
    "10.0.10.13"  # app-03
    "10.0.20.21"  # db-01
    "10.0.20.22"  # db-02
    "10.0.30.10"  # lb-01
    "10.0.30.11"  # lb-02
    "10.0.40.41"  # mon-01
    "10.0.50.10"  # backup-01
)
SSH_USER="admin"
SSH_PORT="2222"
BACKUP_DIR="/backup/ssh-keys"

log "Starting Health-InfraOps SSH key deployment..."

# Validate key directory
if [ ! -d "$KEY_DIR" ]; then
    error "Key directory not found: $KEY_DIR"
    error "Please run generate-keys.sh first"
    exit 1
fi

# Function to deploy to server
deploy_to_server() {
    local server=$1
    local backup_file="$BACKUP_DIR/ssh-backup-$server-$(date +%Y%m%d_%H%M%S).tar.gz"
    
    log "Deploying to server: $server"
    
    # Test SSH connectivity
    if ! ssh -p $SSH_PORT $SSH_USER@$server "echo 'Connection successful'" &>/dev/null; then
        error "Cannot connect to $server"
        return 1
    fi
    
    # Create backup on remote server
    log "Creating backup on $server..."
    ssh -p $SSH_PORT $SSH_USER@$server "
        sudo mkdir -p $BACKUP_DIR
        sudo tar -czf $backup_file /etc/ssh/ssh_host_* /home/*/.ssh/authorized_keys /root/.ssh/authorized_keys 2>/dev/null || true
    "
    
    # Copy host keys
    log "Copying host keys to $server..."
    scp -P $SSH_PORT $KEY_DIR/ssh_host_* $SSH_USER@$server:/tmp/
    
    # Deploy host keys
    ssh -p $SSH_PORT $SSH_USER@$server "
        sudo cp /tmp/ssh_host_* /etc/ssh/
        sudo chmod 600 /etc/ssh/ssh_host_*key
        sudo chmod 644 /etc/ssh/ssh_host_*key.pub
        sudo rm -f /tmp/ssh_host_*
    "
    
    # Update SSH configuration
    log "Updating SSH configuration on $server..."
    ssh -p $SSH_PORT $SSH_USER@$server "
        sudo sed -i 's|^HostKey.*|# Health-InfraOps Host Keys\nHostKey /etc/ssh/ssh_host_ed25519_key\nHostKey /etc/ssh/ssh_host_rsa_key\nHostKey /etc/ssh/ssh_host_ecdsa_key|' /etc/ssh/sshd_config
        sudo sed -i 's/^#Port 22/Port 2222/' /etc/ssh/sshd_config
        sudo sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
        sudo sed -i 's/^#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    "
    
    # Deploy user keys
    log "Deploying user keys to $server..."
    for user_dir in $KEY_DIR/users/*; do
        local user=$(basename $user_dir)
        local authorized_keys="$user_dir/authorized_keys"
        
        if [ -f "$authorized_keys" ]; then
            log "Deploying keys for user: $user"
            
            # Create .ssh directory if it doesn't exist
            ssh -p $SSH_PORT $SSH_USER@$server "
                sudo mkdir -p /home/$user/.ssh
                sudo chmod 700 /home/$user/.ssh
            "
            
            # Copy authorized_keys
            scp -P $SSH_PORT "$authorized_keys" $SSH_USER@$server:/tmp/authorized_keys_$user
            ssh -p $SSH_PORT $SSH_USER@$server "
                sudo cp /tmp/authorized_keys_$user /home/$user/.ssh/authorized_keys
                sudo chmod 600 /home/$user/.ssh/authorized_keys
                sudo chown $user:$user /home/$user/.ssh/authorized_keys
                sudo rm -f /tmp/authorized_keys_$user
            "
        fi
    done
    
    # Deploy service keys
    log "Deploying service keys to $server..."
    for service_dir in $KEY_DIR/services/*; do
        local service=$(basename $service_dir)
        local authorized_keys="$service_dir/authorized_keys"
        
        if [ -f "$authorized_keys" ]; then
            log "Deploying keys for service: $service"
            
            # Create service account if it doesn't exist
            ssh -p $SSH_PORT $SSH_USER@$server "
                if ! id '$service' &>/dev/null; then
                    sudo useradd -r -s /bin/bash -m -d /home/$service $service
                fi
                sudo mkdir -p /home/$service/.ssh
                sudo chmod 700 /home/$service/.ssh
            "
            
            # Copy authorized_keys
            scp -P $SSH_PORT "$authorized_keys" $SSH_USER@$server:/tmp/authorized_keys_$service
            ssh -p $SSH_PORT $SSH_USER@$server "
                sudo cp /tmp/authorized_keys_$service /home/$service/.ssh/authorized_keys
                sudo chmod 600 /home/$service/.ssh/authorized_keys
                sudo chown $service:$service /home/$service/.ssh/authorized_keys
                sudo rm -f /tmp/authorized_keys_$service
            "
        fi
    done
    
    # Restart SSH service
    log "Restarting SSH service on $server..."
    ssh -p $SSH_PORT $SSH_USER@$server "
        sudo systemctl daemon-reload
        sudo systemctl restart sshd
    "
    
    # Verify deployment
    log "Verifying deployment on $server..."
    if ssh -p $SSH_PORT $SSH_USER@$server "sudo systemctl is-active sshd" | grep -q "active"; then
        log "✅ SSH service is active on $server"
    else
        error "❌ SSH service is not active on $server"
        return 1
    fi
    
    log "✅ Key deployment completed for $server"
}

# Main deployment loop
SUCCESSFUL_DEPLOYS=()
FAILED_DEPLOYS=()

for server in "${TARGET_SERVERS[@]}"; do
    if deploy_to_server "$server"; then
        SUCCESSFUL_DEPLOYS+=("$server")
    else
        FAILED_DEPLOYS+=("$server")
    fi
    echo
done

# Generate deployment report
log "Generating deployment report..."
cat > /var/log/ssh-key-deployment.log << EOF
Health-InfraOps SSH Key Deployment Report
Generated: $(date)

Summary:
- Total servers: ${#TARGET_SERVERS[@]}
- Successful: ${#SUCCESSFUL_DEPLOYS[@]}
- Failed: ${#FAILED_DEPLOYS[@]}

Successful deployments:
$(printf '  - %s\n' "${SUCCESSFUL_DEPLOYS[@]}")

Failed deployments:
$(printf '  - %s\n' "${FAILED_DEPLOYS[@]}")

Deployment details:
- SSH port: $SSH_PORT
- Key directory: $KEY_DIR
- Backup location: $BACKUP_DIR

Next steps:
1. Test SSH connectivity to all servers
2. Verify key-based authentication works
3. Remove old keys from rotation
4. Update documentation
EOF

# Display summary
log "📊 Deployment Summary:"
echo "   Total servers: ${#TARGET_SERVERS[@]}"
echo "   Successful: ${#SUCCESSFUL_DEPLOYS[@]}"
echo "   Failed: ${#FAILED_DEPLOYS[@]}"

if [ ${#FAILED_DEPLOYS[@]} -gt 0 ]; then
    error "Failed deployments:"
    for server in "${FAILED_DEPLOYS[@]}"; do
        echo "   - $server"
    done
fi

# Test connectivity with new keys
log "Testing connectivity with new keys..."
for server in "${SUCCESSFUL_DEPLOYS[@]}"; do
    if ssh -p $SSH_PORT -o PasswordAuthentication=no $SSH_USER@$server "echo 'Key-based authentication successful'" &>/dev/null; then
        log "✅ Key auth working on $server"
    else
        warning "⚠️ Key auth may not be working on $server"
    fi
done

log "✅ SSH key deployment process completed!"
log "📄 Report saved to: /var/log/ssh-key-deployment.log"

# Security recommendations
warning "🔒 Security Recommendations:"
echo "   - Monitor SSH access logs for unauthorized attempts"
echo "   - Consider implementing fail2ban for SSH protection"
echo "   - Regular key rotation (recommended every 90 days)"
echo "   - Use SSH certificates for additional security"