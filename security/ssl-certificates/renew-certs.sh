#!/bin/bash
# Health-InfraOps SSL Certificate Renewal Script

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
CERT_DIR="/etc/ssl/certs"
DOMAINS=("infokes.co.id" "api.infokes.co.id" "app.infokes.co.id" "monitor.infokes.co.id")
DAYS_BEFORE_EXPIRE=30
BACKUP_DIR="/backup/ssl"
DATE=$(date +%Y%m%d_%H%M%S)

log "Starting Health-InfraOps SSL certificate renewal check..."

# Create backup directory
mkdir -p $BACKUP_DIR

# Function to check certificate expiration
check_cert_expiry() {
    local domain=$1
    local cert_file="$CERT_DIR/$domain/certs/$domain.cert.pem"
    
    if [ ! -f "$cert_file" ]; then
        warning "Certificate not found for $domain: $cert_file"
        return 1
    fi
    
    local expiry_date=$(openssl x509 -in "$cert_file" -enddate -noout | cut -d= -f2)
    local expiry_epoch=$(date -d "$expiry_date" +%s)
    local current_epoch=$(date +%s)
    local days_until_expire=$(( (expiry_epoch - current_epoch) / 86400 ))
    
    echo "$days_until_expire"
}

# Function to renew certificate
renew_certificate() {
    local domain=$1
    local days=365
    
    log "Renewing certificate for: $domain"
    
    # Backup current certificate
    local backup_path="$BACKUP_DIR/$domain-$DATE"
    mkdir -p "$backup_path"
    
    if [ -d "$CERT_DIR/$domain" ]; then
        cp -r "$CERT_DIR/$domain" "$backup_path/"
        log "Backup created: $backup_path"
    fi
    
    # Renew certificate
    if ./create-cert.sh "$domain" "$days"; then
        log "✅ Certificate renewed for $domain"
        return 0
    else
        error "❌ Certificate renewal failed for $domain"
        # Restore from backup
        warning "Restoring from backup..."
        rm -rf "$CERT_DIR/$domain"
        cp -r "$backup_path/$domain" "$CERT_DIR/"
        return 1
    fi
}

# Function to deploy certificate
deploy_certificate() {
    local domain=$1
    
    log "Deploying certificate for: $domain"
    
    # List of servers to deploy to
    local servers=("10.0.30.10" "10.0.30.11" "10.0.40.41")
    
    for server in "${servers[@]}"; do
        log "Deploying to $server..."
        
        # Copy certificate files
        if scp "$CERT_DIR/$domain/certs/$domain.pem" "admin@$server:/tmp/" 2>/dev/null; then
            ssh "admin@$server" "sudo cp /tmp/$domain.pem /etc/ssl/certs/ && sudo chmod 644 /etc/ssl/certs/$domain.pem"
            
            # Reload web services
            if ssh "admin@$server" "sudo systemctl is-active nginx" &>/dev/null; then
                ssh "admin@$server" "sudo nginx -t && sudo systemctl reload nginx"
            fi
            
            if ssh "admin@$server" "sudo systemctl is-active haproxy" &>/dev/null; then
                ssh "admin@$server" "sudo systemctl reload haproxy"
            fi
            
            log "✅ Deployed to $server"
        else
            warning "⚠️ Failed to deploy to $server"
        fi
    done
}

# Function to verify certificate deployment
verify_certificate() {
    local domain=$1
    
    log "Verifying certificate deployment for: $domain"
    
    # Test HTTPS connection
    if curl -s -f --max-time 10 "https://$domain/health" > /dev/null; then
        log "✅ HTTPS connectivity verified for $domain"
        
        # Verify certificate chain
        local verify_result=$(openssl s_client -connect "$domain:443" -servername "$domain" -verify_return_error < /dev/null 2>&1 | grep "Verify return code")
        if echo "$verify_result" | grep -q "Verify return code: 0"; then
            log "✅ Certificate chain verified for $domain"
        else
            error "❌ Certificate chain verification failed: $verify_result"
        fi
    else
        error "❌ HTTPS connectivity failed for $domain"
    fi
}

# Main renewal process
log "Checking certificate expiration for ${#DOMAINS[@]} domains..."

for domain in "${DOMAINS[@]}"; do
    log "Checking certificate for: $domain"
    
    days_until_expire=$(check_cert_expiry "$domain")
    
    if [ -n "$days_until_expire" ] && [ "$days_until_expire" -lt "$DAYS_BEFORE_EXPIRE" ]; then
        warning "Certificate for $domain expires in $days_until_expire days. Renewing..."
        
        if renew_certificate "$domain"; then
            if deploy_certificate "$domain"; then
                verify_certificate "$domain"
            fi
        fi
    else
        if [ -n "$days_until_expire" ]; then
            log "✅ Certificate for $domain is valid for $days_until_expire days"
        fi
    fi
done

# Check for any wildcard certificates
log "Checking for wildcard certificates..."
for cert_dir in "$CERT_DIR"/*; do
    if [ -d "$cert_dir" ]; then
        domain=$(basename "$cert_dir")
        if [[ $domain == *"*"* ]]; then
            log "Found wildcard certificate: $domain"
            days_until_expire=$(check_cert_expiry "$domain")
            
            if [ -n "$days_until_expire" ] && [ "$days_until_expire" -lt "$DAYS_BEFORE_EXPIRE" ]; then
                warning "Wildcard certificate $domain expires in $days_until_expire days. Renewing..."
                renew_certificate "$domain"
            fi
        fi
    fi
done

# Update certificate monitoring
log "Updating certificate monitoring..."
cat > /var/log/ssl-certificate-renewal.log << EOF
Health-InfraOps SSL Certificate Renewal Report
Generated: $(date)

Domains checked: ${DOMAINS[*]}

Certificate Expiration Status:
$(for domain in "${DOMAINS[@]}"; do
    days=$(check_cert_expiry "$domain" 2>/dev/null || echo "NOT_FOUND")
    echo "  $domain: $days days"
done)

Renewal actions performed:
- Backup created: $BACKUP_DIR
- Certificates renewed if expiration < $DAYS_BEFORE_EXPIRE days
- Deployment to load balancers and web servers
EOF

# Send notification (if configured)
if command -v sendmail &> /dev/null; then
    log "Sending notification email..."
    cat << EOF | sendmail -t
To: admin@infokes.co.id
Subject: Health-InfraOps SSL Certificate Renewal Report

SSL certificate renewal completed for Health-InfraOps infrastructure.

$(cat /var/log/ssl-certificate-renewal.log)

Please verify certificate functionality.

- Health-InfraOps Security Team
EOF
fi

log "✅ SSL certificate renewal process completed!"
log "📊 Report saved to: /var/log/ssl-certificate-renewal.log"

# Display summary
log "Certificate Expiration Summary:"
for domain in "${DOMAINS[@]}"; do
    days=$(check_cert_expiry "$domain" 2>/dev/null || echo "NOT_FOUND")
    if [ "$days" = "NOT_FOUND" ]; then
        warning "  $domain: Certificate not found"
    elif [ "$days" -lt 30 ]; then
        error "  $domain: $days days (NEEDS ATTENTION)"
    elif [ "$days" -lt 60 ]; then
        warning "  $domain: $days days"
    else
        log "  $domain: $days days"
    fi
done