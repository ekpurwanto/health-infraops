#!/bin/bash
# Health-InfraOps Certificate Authority Generator

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
CA_NAME="Health-InfraOps-Root-CA"
DOMAIN="infokes.co.id"
DAYS=3650  # 10 years for CA

log "Starting Health-InfraOps Certificate Authority generation..."

# Create CA directory structure
log "Creating CA directory structure..."
mkdir -p $CA_DIR/{private,certs,newcerts,crl,csr}
chmod 700 $CA_DIR/private
echo "01" > $CA_DIR/serial
touch $CA_DIR/index.txt

# Generate OpenSSL configuration
log "Generating OpenSSL configuration..."
cat > $CA_DIR/openssl.cnf << EOF
# Health-InfraOps CA Configuration
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = $CA_DIR
certs             = \$dir/certs
crl_dir           = \$dir/crl
new_certs_dir     = \$dir/newcerts
database          = \$dir/index.txt
serial            = \$dir/serial
RANDFILE          = \$dir/private/.rand

private_key       = \$dir/private/ca.key.pem
certificate       = \$dir/certs/ca.cert.pem

crlnumber         = \$dir/crlnumber
crl               = \$dir/crl/ca.crl.pem
crl_extensions    = crl_ext
default_crl_days  = 30

default_md        = sha256
name_opt          = ca_default
cert_opt          = ca_default
default_days      = 375
preserve          = no
policy            = policy_strict

[ policy_strict ]
countryName             = match
stateOrProvinceName     = match
organizationName        = match
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ policy_loose ]
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ req ]
default_bits        = 4096
distinguished_name  = req_distinguished_name
string_mask         = utf8only
default_md          = sha256
x509_extensions     = v3_ca

[ req_distinguished_name ]
countryName                     = Country Name (2 letter code)
stateOrProvinceName             = State or Province Name
localityName                    = Locality Name
0.organizationName              = Organization Name
organizationalUnitName          = Organizational Unit Name
commonName                      = Common Name
emailAddress                    = Email Address

[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ v3_intermediate_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ server_cert ]
basicConstraints = CA:FALSE
nsCertType = server
nsComment = "Health-InfraOps SSL Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth

[ client_cert ]
basicConstraints = CA:FALSE
nsCertType = client
nsComment = "Health-InfraOps Client Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth

[ crl_ext ]
authorityKeyIdentifier=keyid:always

[ ocsp ]
basicConstraints = CA:FALSE
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, OCSPSigning
EOF

# Generate CA private key
log "Generating CA private key (4096 bits)..."
openssl genrsa -aes256 -out $CA_DIR/private/ca.key.pem 4096
chmod 400 $CA_DIR/private/ca.key.pem

# Generate CA certificate
log "Generating CA certificate..."
openssl req -config $CA_DIR/openssl.cnf \
    -key $CA_DIR/private/ca.key.pem \
    -new -x509 -days $DAYS -sha256 -extensions v3_ca \
    -out $CA_DIR/certs/ca.cert.pem \
    -subj "/C=ID/ST=Jakarta/L=Jakarta/O=Health-InfraOps/OU=Security/CN=$CA_NAME/emailAddress=security@$DOMAIN"

chmod 444 $CA_DIR/certs/ca.cert.pem

# Generate intermediate CA
log "Generating intermediate CA..."
mkdir -p $CA_DIR/intermediate/{private,certs,newcerts,crl,csr}
chmod 700 $CA_DIR/intermediate/private
echo "01" > $CA_DIR/intermediate/serial
touch $CA_DIR/intermediate/index.txt

cat > $CA_DIR/intermediate/openssl.cnf << EOF
# Health-InfraOps Intermediate CA Configuration
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = $CA_DIR/intermediate
certs             = \$dir/certs
crl_dir           = \$dir/crl
new_certs_dir     = \$dir/newcerts
database          = \$dir/index.txt
serial            = \$dir/serial
RANDFILE          = \$dir/private/.rand

private_key       = \$dir/private/intermediate.key.pem
certificate       = \$dir/certs/intermediate.cert.pem

crlnumber         = \$dir/crlnumber
crl               = \$dir/crl/intermediate.crl.pem
crl_extensions    = crl_ext
default_crl_days  = 30

default_md        = sha256
name_opt          = ca_default
cert_opt          = ca_default
default_days      = 375
preserve          = no
policy            = policy_loose

[ policy_loose ]
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ server_cert ]
basicConstraints = CA:FALSE
nsCertType = server
nsComment = "Health-InfraOps SSL Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = $DOMAIN
DNS.2 = www.$DOMAIN
DNS.3 = app.$DOMAIN
DNS.4 = api.$DOMAIN
DNS.5 = monitor.$DOMAIN

[ crl_ext ]
authorityKeyIdentifier=keyid:always

[ ocsp ]
basicConstraints = CA:FALSE
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, OCSPSigning
EOF

# Generate intermediate CA private key
log "Generating intermediate CA private key..."
openssl genrsa -aes256 -out $CA_DIR/intermediate/private/intermediate.key.pem 4096
chmod 400 $CA_DIR/intermediate/private/intermediate.key.pem

# Generate intermediate CA certificate signing request
log "Generating intermediate CA CSR..."
openssl req -config $CA_DIR/intermediate/openssl.cnf -new -sha256 \
    -key $CA_DIR/intermediate/private/intermediate.key.pem \
    -out $CA_DIR/intermediate/csr/intermediate.csr.pem \
    -subj "/C=ID/ST=Jakarta/L=Jakarta/O=Health-InfraOps/OU=Security/CN=Health-InfraOps-Intermediate-CA/emailAddress=security@$DOMAIN"

# Sign intermediate CA certificate
log "Signing intermediate CA certificate..."
openssl ca -config $CA_DIR/openssl.cnf -extensions v3_intermediate_ca \
    -days 1825 -notext -md sha256 \
    -in $CA_DIR/intermediate/csr/intermediate.csr.pem \
    -out $CA_DIR/intermediate/certs/intermediate.cert.pem

chmod 444 $CA_DIR/intermediate/certs/intermediate.cert.pem

# Create certificate chain
log "Creating certificate chain..."
cat $CA_DIR/intermediate/certs/intermediate.cert.pem \
    $CA_DIR/certs/ca.cert.pem > $CA_DIR/intermediate/certs/ca-chain.cert.pem
chmod 444 $CA_DIR/intermediate/certs/ca-chain.cert.pem

# Generate CRL
log "Generating Certificate Revocation List..."
openssl ca -config $CA_DIR/openssl.cnf -gencrl -out $CA_DIR/crl/ca.crl.pem
openssl ca -config $CA_DIR/intermediate/openssl.cnf -gencrl -out $CA_DIR/intermediate/crl/intermediate.crl.pem

# Verify certificates
log "Verifying certificates..."
openssl x509 -noout -text -in $CA_DIR/certs/ca.cert.pem > /dev/null
openssl x509 -noout -text -in $CA_DIR/intermediate/certs/intermediate.cert.pem > /dev/null
openssl verify -CAfile $CA_DIR/certs/ca.cert.pem $CA_DIR/intermediate/certs/intermediate.cert.pem

# Create distribution packages
log "Creating distribution packages..."
mkdir -p $CA_DIR/distribution

# Root CA for distribution (without private key)
cp $CA_DIR/certs/ca.cert.pem $CA_DIR/distribution/health-infraops-root-ca.crt
cp $CA_DIR/intermediate/certs/ca-chain.cert.pem $CA_DIR/distribution/health-infraops-ca-chain.pem

# Create README
cat > $CA_DIR/distribution/README.md << EOF
# Health-InfraOps Certificate Authority

## Files:
- health-infraops-root-ca.crt - Root CA Certificate
- health-infraops-ca-chain.pem - Certificate Chain

## Installation:

### Linux:
\`\`\`bash
# Copy to system trust store
sudo cp health-infraops-root-ca.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates

# Or for specific applications
cp health-infraops-root-ca.crt /etc/ssl/certs/
\`\`\`

### Windows:
Import to "Trusted Root Certification Authorities"

### macOS:
\`\`\`bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain health-infraops-root-ca.crt
\`\`\`
EOF

log "✅ Health-InfraOps Certificate Authority generation completed!"
log "📊 CA Information:"
echo "   Root CA: $CA_DIR/certs/ca.cert.pem"
echo "   Intermediate CA: $CA_DIR/intermediate/certs/intermediate.cert.pem"
echo "   Certificate Chain: $CA_DIR/intermediate/certs/ca-chain.cert.pem"
echo "   Distribution: $CA_DIR/distribution/"
echo "   Validity: $DAYS days"

# Display certificate information
log "Root CA Certificate:"
openssl x509 -in $CA_DIR/certs/ca.cert.pem -noout -subject -issuer -dates

log "Intermediate CA Certificate:"
openssl x509 -in $CA_DIR/intermediate/certs/intermediate.cert.pem -noout -subject -issuer -dates