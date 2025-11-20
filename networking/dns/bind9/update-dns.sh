#!/bin/bash
# Health-InfraOps DNS Update and Management Script

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
ZONE_FILE="/etc/bind/zones/internal/infokes.co.id.zone"
ZONE_NAME="infokes.co.id"
NAMESERVER="10.0.40.42"
BACKUP_DIR="/backup/dns"
DATE=$(date +%Y%m%d_%H%M%S)

log "Starting Health-InfraOps DNS Management..."

# Check if BIND9 is installed
if ! command -v named &> /dev/null; then
    error "BIND9 is not installed"
    exit 1
fi

# Create backup directory
mkdir -p $BACKUP_DIR

# Backup current zone file
log "Backing up current zone file..."
cp $ZONE_FILE $BACKUP_DIR/infokes.co.id.zone.backup-$DATE

# Function to update serial number
update_serial() {
    local zone_file=$1
    local current_serial=$(grep -Po '\d+\s+; Serial' $zone_file | awk '{print $1}')
    local new_serial=$((current_serial + 1))
    
    sed -i "s/$current_serial\s*; Serial/$new_serial ; Serial/" $zone_file
    log "Updated serial number: $current_serial -> $new_serial"
}

# Function to add A record
add_a_record() {
    local hostname=$1
    local ip=$2
    local ttl=${3:-"86400"}
    
    # Check if record already exists
    if grep -q "^$hostname" $ZONE_FILE; then
        warning "Record $hostname already exists. Updating..."
        sed -i "/^$hostname/c\\$hostname IN A $ip" $ZONE_FILE
    else
        echo "$hostname IN A $ip" >> $ZONE_FILE
    fi
    log "Added/Updated A record: $hostname -> $ip"
}

# Function to add CNAME record
add_cname_record() {
    local alias=$1
    local target=$2
    
    # Check if record already exists
    if grep -q "^$alias" $ZONE_FILE; then
        warning "Record $alias already exists. Updating..."
        sed -i "/^$alias/c\\$alias IN CNAME $target" $ZONE_FILE
    else
        echo "$alias IN CNAME $target" >> $ZONE_FILE
    fi
    log "Added/Updated CNAME record: $alias -> $target"
}

# Function to delete record
delete_record() {
    local hostname=$1
    
    if grep -q "^$hostname" $ZONE_FILE; then
        sed -i "/^$hostname/d" $ZONE_FILE
        log "Deleted record: $hostname"
    else
        warning "Record $hostname not found"
    fi
}

# Function to validate zone file
validate_zone() {
    local zone_file=$1
    local zone_name=$2
    
    log "Validating zone file..."
    if named-checkzone $zone_name $zone_file; then
        log "✅ Zone file validation passed"
        return 0
    else
        error "❌ Zone file validation failed"
        return 1
    fi
}

# Function to reload DNS
reload_dns() {
    log "Reloading DNS service..."
    
    if systemctl reload bind9; then
        log "✅ BIND9 reloaded successfully"
    else
        error "❌ BIND9 reload failed"
        return 1
    fi
    
    # Alternatively use rndc
    if command -v rndc &> /dev/null; then
        rndc reload
        log "✅ rndc reload completed"
    fi
}

# Function to test DNS resolution
test_dns() {
    local hostname=$1
    local expected_ip=$2
    
    log "Testing DNS resolution for $hostname..."
    local resolved_ip=$(dig +short @$NAMESERVER $hostname)
    
    if [ "$resolved_ip" = "$expected_ip" ]; then
        log "✅ DNS resolution correct: $hostname -> $resolved_ip"
    else
        error "❌ DNS resolution failed: $hostname -> $resolved_ip (expected: $expected_ip)"
    fi
}

# Main operations based on arguments
case "${1:-}" in
    "add-a")
        if [ $# -ne 3 ]; then
            echo "Usage: $0 add-a <hostname> <ip>"
            exit 1
        fi
        add_a_record "$2" "$3"
        ;;
        
    "add-cname")
        if [ $# -ne 3 ]; then
            echo "Usage: $0 add-cname <alias> <target>"
            exit 1
        fi
        add_cname_record "$2" "$3"
        ;;
        
    "delete")
        if [ $# -ne 2 ]; then
            echo "Usage: $0 delete <hostname>"
            exit 1
        fi
        delete_record "$2"
        ;;
        
    "update-serial")
        update_serial "$ZONE_FILE"
        ;;
        
    "validate")
        validate_zone "$ZONE_FILE" "$ZONE_NAME"
        ;;
        
    "reload")
        reload_dns
        ;;
        
    "test")
        if [ $# -ne 3 ]; then
            echo "Usage: $0 test <hostname> <expected_ip>"
            exit 1
        fi
        test_dns "$2" "$3"
        ;;
        
    "backup")
        log "Creating DNS backup..."
        cp $ZONE_FILE $BACKUP_DIR/infokes.co.id.zone.backup-$DATE
        tar -czf $BACKUP_DIR/dns-full-backup-$DATE.tar.gz /etc/bind/
        log "Backup created: $BACKUP_DIR/dns-full-backup-$DATE.tar.gz"
        ;;
        
    "restore")
        if [ $# -ne 2 ]; then
            echo "Usage: $0 restore <backup_file>"
            exit 1
        fi
        log "Restoring from backup: $2"
        cp "$2" $ZONE_FILE
        ;;
        
    *)
        echo "Health-InfraOps DNS Management Tool"
        echo "==================================="
        echo "Usage: $0 <command> [arguments]"
        echo ""
        echo "Commands:"
        echo "  add-a <hostname> <ip>      Add/Update A record"
        echo "  add-cname <alias> <target> Add/Update CNAME record"
        echo "  delete <hostname>          Delete DNS record"
        echo "  update-serial              Update zone serial number"
        echo "  validate                   Validate zone file"
        echo "  reload                     Reload DNS service"
        echo "  test <hostname> <ip>       Test DNS resolution"
        echo "  backup                     Create DNS backup"
        echo "  restore <file>             Restore from backup"
        echo ""
        echo "Examples:"
        echo "  $0 add-a test-app 10.0.10.99"
        echo "  $0 add-cname app test-app.infokes.co.id."
        echo "  $0 test app-01 10.0.10.11"
        exit 1
        ;;
esac

# Update serial number if changes were made
if [[ "$1" =~ ^(add-a|add-cname|delete)$ ]]; then
    update_serial "$ZONE_FILE"
fi

# Validate zone file if changes were made
if [[ "$1" =~ ^(add-a|add-cname|delete|update-serial)$ ]]; then
    if validate_zone "$ZONE_FILE" "$ZONE_NAME"; then
        reload_dns
    else
        error "Zone validation failed. Restoring from backup..."
        cp $BACKUP_DIR/infokes.co.id.zone.backup-$DATE $ZONE_FILE
        exit 1
    fi
fi

log "✅ DNS management operation completed successfully!"