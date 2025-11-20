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
CA_DIR="/etc/ssl/health-infraops-ca"
INTERMEDIATE_DIR="$CA_DIR/intermediate"
DOMAIN="${1:-infokes.co.id}"
DAYS="${2:-365}"
CERT_TYPE="${3:-server}"  # server or client

log "Generating SSL certificate for: $DOMAIN (Type: $CERT_TYPE, Days: $DAYS)"

# Validate inputs
if [ -z "$DOMAIN" ]; then
    error "Domain name is required"
    echo "Usage: $0 <domain> [days] [server|client]"
    exit 1
fi

if [ ! -d "$INTERMEDIATE_DIR" ]; then
    error "Intermediate CA not found. Please run generate-ca.sh first."
    exit 1
fi

# Create output directory
CERT_DIR="/etc/ssl/certs/$DOMAIN"
mkdir -p $CERT_DIR/{private,csr,certs}
chmod 700 $CERT_DIR/private

# Generate private key
log "Generating private key (2048 bits)..."
openssl genrsa -out $CERT_DIR/private/$DOMAIN.key.pem 2048
chmod 400 $CERT_DIR/private/$DOMAIN.key.pem

# Generate certificate configuration
log "Generating certificate configuration..."
cat > $CERT_DIR/cert.conf << EOF
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
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth

[alt_names]
DNS.1 = $DOMAIN
DNS.2 = www.$DOMAIN
DNS.3 = app.$DOMAIN
DNS.4 = api.$DOMAIN
DNS.5 = monitor.$DOMAIN
DNS.6 = *.infokes.co.id
EOF

# Update configuration based on certificate type
if [ "$CERT_TYPE" = "client" ]; then
    sed -i 's/serverAuth/clientAuth/' $CERT_DIR/cert.conf
    sed -i 's/CN = .*/CN = client.'$DOMAIN'/' $CERT_DIR/cert.conf
fi

# Generate certificate signing request
log "Generating Certificate Signing Request..."
openssl req -config $CERT_DIR/cert.conf \
    -key $CERT_DIR/private/$DOMAIN.key.pem \
    -new -sha256 -out $CERT_DIR/csr/$DOMAIN.csr.pem

# Sign the certificate with intermediate CA
log "Signing certificate with intermediate CA..."
if [ "$CERT_TYPE" = "server" ]; then
    openssl ca -config $INTERMEDIATE_DIR/openssl.cnf \
        -extensions server_cert -days $DAYS -notext -md sha256 \
        -in $CERT_DIR/csr/$DOMAIN.csr.pem \
        -out $CERT_DIR/certs/$DOMAIN.cert.pem
else
    openssl ca -config $INTERMEDIATE_DIR/openssl.cnf \
        -extensions client_cert -days $DAYS -notext -md sha256 \
        -in $CERT_DIR/csr/$DOMAIN.csr.pem \
        -out $CERT_DIR/certs/$DOMAIN.cert.pem
fi

chmod 444 $CERT_DIR/certs/$DOMAIN.cert.pem

# Create full chain certificate
log "Creating full chain certificate..."
cat $CERT_DIR/certs/$DOMAIN.cert.pem \
    $INTERMEDIATE_DIR/certs/intermediate.cert.pem \
    $CA_DIR/certs/ca.cert.pem > $CERT_DIR/certs/$DOMAIN-fullchain.cert.pem

# Create combined PEM for HAProxy/Nginx
log "Creating combined PEM file..."
cat $CERT_DIR/certs/$DOMAIN.cert.pem \
    $CERT_DIR/private/$DOMAIN.key.pem > $CERT_DIR/certs/$DOMAIN.pem
chmod 600 $CERT_DIR/certs/$DOMAIN.pem

# Verify the certificate
log "Verifying certificate..."
openssl verify -CAfile $INTERMEDIATE_DIR/certs/ca-chain.cert.pem \
    $CERT_DIR/certs/$DOMAIN.cert.pem

# Generate PKCS12 bundle (for Java/Windows)
log "Generating PKCS12 bundle..."
openssl pkcs12 -export \
    -in $CERT_DIR/certs/$DOMAIN.cert.pem \
    -inkey $CERT_DIR/private/$DOMAIN.key.pem \
    -out $CERT_DIR/certs/$DOMAIN.p12 \
    -name "$DOMAIN" \
    -passout pass:healthinfraops2023

# Create certificate information file
log "Creating certificate information..."
cat > $CERT_DIR/certificate-info.txt << EOF
Health-InfraOps SSL Certificate
===============================
Domain: $DOMAIN
Type: $CERT_TYPE
Valid Days: $DAYS
Generated: $(date)

Files:
- Private Key: $CERT_DIR/private/$DOMAIN.key.pem
- Certificate: $CERT_DIR/certs/$DOMAIN.cert.pem
- Full Chain: $CERT_DIR/certs/$DOMAIN-fullchain.cert.pem
- Combined PEM: $CERT_DIR/certs/$DOMAIN.pem
- PKCS12: $CERT_DIR/certs/$DOMAIN.p12

Certificate Details:
$(openssl x509 -in $CERT_DIR/certs/$DOMAIN.cert.pem -noout -subject -issuer -dates)

Subject Alternative Names:
$(openssl x509 -in $CERT_DIR/certs/$DOMAIN.cert.pem -noout -text | grep -A1 "Subject Alternative Name")
EOF

# Generate OCSP responder information (if needed)
log "Generating OCSP information..."
openssl ocsp -CAfile $INTERMEDIATE_DIR/certs/ca-chain.cert.pem \
    -issuer $INTERMEDIATE_DIR/certs/intermediate.cert.pem \
    -cert $CERT_DIR/certs/$DOMAIN.cert.pem \
    -url http://ocsp.infokes.co.id -resp_text > $CERT_DIR/ocsp-response.txt 2>/dev/null || true

# Cleanup temporary files
rm -f $CERT_DIR/cert.conf

log "✅ SSL certificate generation completed!"
log "📊 Certificate Information:"
echo "   Domain: $DOMAIN"
echo "   Type: $CERT_TYPE"
echo "   Validity: $DAYS days"
echo "   Private Key: $CERT_DIR/private/$DOMAIN.key.pem"
echo "   Certificate: $CERT_DIR/certs/$DOMAIN.cert.pem"
echo "   Full Chain: $CERT_DIR/certs/$DOMAIN-fullchain.cert.pem"
echo "   Combined PEM: $CERT_DIR/certs/$DOMAIN.pem"

# Display certificate details
log "Certificate Details:"
openssl x509 -in $CERT_DIR/certs/$DOMAIN.cert.pem -noout -subject -issuer -dates

# Check certificate expiration
EXPIRY=$(openssl x509 -in $CERT_DIR/certs/$DOMAIN.cert.pem -noout -enddate | cut -d= -f2)
log "Certificate expires on: $EXPIRY"

# Create deployment script for web servers
cat > $CERT_DIR/deploy-to-webserver.sh << 'EOF'
#!/bin/bash
# Deploy certificate to web server

TARGET_SERVER="${1:-10.0.30.10}"
CERT_DIR="/etc/ssl/certs/$DOMAIN"

echo "Deploying certificate to $TARGET_SERVER..."

# Copy certificate files
scp $CERT_DIR/certs/$DOMAIN.pem admin@$TARGET_SERVER:/etc/ssl/certs/
scp $CERT_DIR/certs/$DOMAIN-fullchain.cert.pem admin@$TARGET_SERVER:/etc/ssl/certs/

# Reload web services
ssh admin@$TARGET_SERVER "sudo systemctl reload nginx && sudo systemctl reload haproxy"

echo "Certificate deployed successfully!"
EOF

chmod +x $CERT_DIR/deploy-to-webserver.sh

log "🚀 Deployment script created: $CERT_DIR/deploy-to-webserver.sh"