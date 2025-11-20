#!/bin/bash
# Health-InfraOps SSL Certificate Renewal Script

set -e

# Configuration
DOMAIN="infokes.co.id"
SSL_DIR="/etc/ssl"
KEY_FILE="$SSL_DIR/private/$DOMAIN.key"
CRT_FILE="$SSL_DIR/certs/$DOMAIN.crt"
BACKUP_DIR="/backup/ssl/$(date +%Y%m%d)"
DAYS_BEFORE_EXPIRE=30

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Check if certificate exists
if [ ! -f "$CRT_FILE" ]; then
    warning "Certificate not found: $CRT_FILE"
    exit 1
fi

# Check certificate expiration
EXPIRY_DATE=$(openssl x509 -in $CRT_FILE -enddate -noout | cut -d= -f2)
EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s)
CURRENT_EPOCH=$(date +%s)
DAYS_UNTIL_EXPIRE=$(( (EXPIRY_EPOCH - CURRENT_EPOCH) / 86400 ))

log "Certificate expires on: $EXPIRY_DATE"
log "Days until expiration: $DAYS_UNTIL_EXPIRE"

if [ $DAYS_UNTIL_EXPIRE -gt $DAYS_BEFORE_EXPIRE ]; then
    log "Certificate is still valid for more than $DAYS_BEFORE_EXPIRE days. No renewal needed."
    exit 0
fi

warning "Certificate will expire in $DAYS_UNTIL_EXPIRE days. Renewing..."

# Create backup
mkdir -p $BACKUP_DIR
cp $KEY_FILE $CRT_FILE $BACKUP_DIR/
log "Backup created in: $BACKUP_DIR"

# Generate new certificate
log "Generating new certificate..."
./generate-ssl.sh $DOMAIN 365

# Reload web servers
log "Reloading web servers..."

# Nginx
if systemctl is-active --quiet nginx; then
    if nginx -t; then
        systemctl reload nginx
        log "✅ Nginx reloaded successfully"
    else
        warning "Nginx configuration test failed. Rolling back..."
        cp $BACKUP_DIR/$DOMAIN.key $KEY_FILE
        cp $BACKUP_DIR/$DOMAIN.crt $CRT_FILE
        systemctl reload nginx
        exit 1
    fi
fi

# HAProxy
if systemctl is-active --quiet haproxy; then
    if systemctl reload haproxy; then
        log "✅ HAProxy reloaded successfully"
    else
        warning "HAProxy reload failed. Rolling back..."
        cp $BACKUP_DIR/$DOMAIN.key $KEY_FILE
        cp $BACKUP_DIR/$DOMAIN.crt $CRT_FILE
        systemctl reload haproxy
        exit 1
    fi
fi

# Update certificate monitoring
log "Updating certificate monitoring..."
echo "$(date): SSL certificate renewed for $DOMAIN (valid until $EXPIRY_DATE)" >> /var/log/ssl-renewal.log

log "✅ SSL certificate renewal completed successfully!"