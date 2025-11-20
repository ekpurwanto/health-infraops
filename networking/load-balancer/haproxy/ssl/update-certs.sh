#!/bin/bash
# Health-InfraOps HAProxy SSL Certificate Update

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
SSL_DIR="/etc/ssl/certs"
HAPROXY_CERT_DIR="/etc/haproxy/certs"
DOMAIN="infokes.co.id"
BACKUP_DIR="/backup/haproxy/ssl"
DATE=$(date +%Y%m%d_%H%M%S)

log "Starting HAProxy SSL certificate update for $DOMAIN..."

# Check if HAProxy is installed
if ! command -v haproxy &> /dev/null; then
    error "HAProxy is not installed"
    exit 1
fi

# Create directories
mkdir -p $HAPROXY_CERT_DIR $BACKUP_DIR

# Check if certificate files exist
CERT_FILE="$SSL_DIR/$DOMAIN.crt"
KEY_FILE="$SSL_DIR/private/$DOMAIN.key"

if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    error "Certificate files not found: $CERT_FILE or $KEY_FILE"
    exit 1
fi

# Create backup of current certificate
log "Creating backup of current certificate..."
if [ -f "$HAPROXY_CERT_DIR/$DOMAIN.pem" ]; then
    cp "$HAPROXY_CERT_DIR/$DOMAIN.pem" "$BACKUP_DIR/$DOMAIN.pem.backup-$DATE"
fi

# Combine certificate and key for HAProxy
log "Combining certificate and key for HAProxy..."
cat $CERT_FILE $KEY_FILE > $HAPROXY_CERT_DIR/$DOMAIN.pem

# Set proper permissions
chmod 600 $HAPROXY_CERT_DIR/$DOMAIN.pem
chown haproxy:haproxy $HAPROXY_CERT_DIR/$DOMAIN.pem

# Verify the combined certificate
log "Verifying combined certificate..."
if ! openssl x509 -in $HAPROXY_CERT_DIR/$DOMAIN.pem -noout > /dev/null 2>&1; then
    error "Combined certificate verification failed"
    
    # Restore from backup
    if [ -f "$BACKUP_DIR/$DOMAIN.pem.backup-$DATE" ]; then
        warning "Restoring from backup..."
        cp "$BACKUP_DIR/$DOMAIN.pem.backup-$DATE" "$HAPROXY_CERT_DIR/$DOMAIN.pem"
        chmod 600 $HAPROXY_CERT_DIR/$DOMAIN.pem
        chown haproxy:haproxy $HAPROXY_CERT_DIR/$DOMAIN.pem
    fi
    exit 1
fi

# Test HAProxy configuration
log "Testing HAProxy configuration..."
if haproxy -c -f /etc/haproxy/haproxy.cfg; then
    log "✅ HAProxy configuration test passed"
else
    error "❌ HAProxy configuration test failed"
    
    # Restore from backup
    if [ -f "$BACKUP_DIR/$DOMAIN.pem.backup-$DATE" ]; then
        warning "Restoring from backup..."
        cp "$BACKUP_DIR/$DOMAIN.pem.backup-$DATE" "$HAPROXY_CERT_DIR/$DOMAIN.pem"
        chmod 600 $HAPROXY_CERT_DIR/$DOMAIN.pem
        chown haproxy:haproxy $HAPROXY_CERT_DIR/$DOMAIN.pem
    fi
    exit 1
fi

# Reload HAProxy
log "Reloading HAProxy..."
if systemctl reload haproxy; then
    log "✅ HAProxy reloaded successfully"
else
    error "❌ HAProxy reload failed"
    exit 1
fi

# Verify SSL certificate in use
log "Verifying SSL certificate in use..."
echo | openssl s_client -connect localhost:443 -servername $DOMAIN 2>/dev/null | openssl x509 -noout -subject -dates

# Check certificate expiration
EXPIRY=$(openssl x509 -in $HAPROXY_CERT_DIR/$DOMAIN.pem -noout -enddate | cut -d= -f2)
log "Certificate expires on: $EXPIRY"

# Update certificate monitoring
log "Updating certificate monitoring..."
echo "$(date): SSL certificate updated for $DOMAIN" >> /var/log/haproxy-ssl-update.log

log "✅ HAProxy SSL certificate update completed successfully!"
log "📊 Certificate Information:"
echo "   Domain: $DOMAIN"
echo "   Certificate: $HAPROXY_CERT_DIR/$DOMAIN.pem"
echo "   Expiration: $EXPIRY"
echo "   Backup: $BACKUP_DIR/$DOMAIN.pem.backup-$DATE"

# Test HTTPS connectivity
log "Testing HTTPS connectivity..."
if curl -s -o /dev/null -w "%{http_code}" https://$DOMAIN/health | grep -q "200"; then
    log "✅ HTTPS connectivity test passed"
else
    warning "⚠️ HTTPS connectivity test failed"
fi