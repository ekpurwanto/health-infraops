#!/bin/bash
# Health-InfraOps SSL Certificate Generator

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
DOMAIN="${1:-infokes.co.id}"
DAYS="${2:-365}"
SSL_DIR="/etc/ssl"
KEY_FILE="$SSL_DIR/private/$DOMAIN.key"
CRT_FILE="$SSL_DIR/certs/$DOMAIN.crt"
CSR_FILE="$SSL_DIR/certs/$DOMAIN.csr"
CONF_FILE="/tmp/ssl_${DOMAIN}.conf"

# Create SSL directories
mkdir -p $SSL_DIR/private $SSL_DIR/certs
chmod 700 $SSL_DIR/private

# Generate OpenSSL configuration
cat > $CONF_FILE << EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = req_ext

[dn]
C = ID
ST = Jakarta
L = Jakarta
O = Health-InfraOps
OU = IT Department
CN = $DOMAIN
emailAddress = admin@$DOMAIN

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = $DOMAIN
DNS.2 = www.$DOMAIN
DNS.3 = app.$DOMAIN
DNS.4 = api.$DOMAIN
DNS.5 = monitor.$DOMAIN
EOF

log "Generating SSL certificate for: $DOMAIN"

# Generate private key
log "Generating private key..."
openssl genrsa -out $KEY_FILE 2048
chmod 600 $KEY_FILE

# Generate certificate signing request
log "Generating certificate signing request..."
openssl req -new -key $KEY_FILE -out $CSR_FILE -config $CONF_FILE

# Generate self-signed certificate
log "Generating self-signed certificate (valid for $DAYS days)..."
openssl x509 -req \
    -days $DAYS \
    -in $CSR_FILE \
    -signkey $KEY_FILE \
    -out $CRT_FILE \
    -extensions req_ext \
    -extfile $CONF_FILE

# Verify certificate
log "Verifying certificate..."
openssl x509 -in $CRT_FILE -text -noout | grep -E "Subject:|Issuer:|Not Before:|Not After :"

# Set proper permissions
chmod 644 $CRT_FILE

# Create combined PEM file for HAProxy
log "Creating combined PEM file for load balancer..."
cat $CRT_FILE $KEY_FILE > $SSL_DIR/certs/$DOMAIN.pem
chmod 600 $SSL_DIR/certs/$DOMAIN.pem

# Create DHParam for perfect forward secrecy
log "Generating DH parameters (this may take a while)..."
openssl dhparam -out $SSL_DIR/certs/dhparam.pem 2048

# Cleanup
rm -f $CSR_FILE $CONF_FILE

log "✅ SSL certificate generation completed!"
log "📁 Files generated:"
echo "   Private Key: $KEY_FILE"
echo "   Certificate: $CRT_FILE"
echo "   Combined PEM: $SSL_DIR/certs/$DOMAIN.pem"
echo "   DH Param: $SSL_DIR/certs/dhparam.pem"

# Test SSL configuration
log "Testing SSL configuration..."
if openssl verify -CAfile $CRT_FILE $CRT_FILE &>/dev/null; then
    log "✅ SSL certificate is valid"
else
    error "❌ SSL certificate verification failed"
    exit 1
fi