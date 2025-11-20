#!/bin/bash

# Health-InfraOps Disaster Recovery Script
# Comprehensive disaster recovery and failover procedures

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${PROJECT_ROOT}/backups"
CONFIG_DIR="${PROJECT_ROOT}/automation/ansible"
LOG_DIR="${PROJECT_ROOT}/logs/recovery"
RECOVERY_DIR="${PROJECT_ROOT}/disaster-recovery"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RECOVERY_ID="recovery_${TIMESTAMP}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$LOG_DIR" "$RECOVERY_DIR"
LOG_FILE="${LOG_DIR}/${RECOVERY_ID}.log"

# Logging functions
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$1"; }
log_success() { log "SUCCESS" "$1"; }
log_warning() { log "WARNING" "$1"; }
log_error() { log "ERROR" "$1"; }

show_help() {
    cat << EOF
Health-InfraOps Disaster Recovery Script

Usage: $0 [options] <action> [environment]

Actions:
  failover          - Initiate failover to secondary site
  failback          - Failback to primary site
  restore-backup    - Restore from specific backup
  emergency-mode    - Enable emergency maintenance mode
  validate-dr       - Validate DR readiness
  generate-plan     - Generate recovery plan

Environments:
  prod      - Production environment (default)
  staging   - Staging environment

Options:
  -h, --help           Show this help message
  -b, --backup ID      Specific backup ID to restore
  --force              Force operation without confirmation
  --dry-run           Dry run mode
  --rpo MINUTES        Target RPO (Recovery Point Objective)
  --rto MINUTES        Target RTO (Recovery Time Objective)

Examples:
  $0 failover prod
  $0 restore-backup --backup backup_20231201_120000
  $0 validate-dr --dry-run
  $0 emergency-mode --force
EOF
}

# Emergency functions
enable_emergency_mode() {
    local environment=$1
    
    log_info "Enabling emergency maintenance mode for: $environment"
    
    # Update load balancer to show maintenance page
    local lb_servers
    lb_servers=$(grep -E '^[0-9].*lb' "${CONFIG_DIR}/inventory/${environment}" | awk '{print $1}')
    
    for server in $lb_servers; do
        log_info "Configuring maintenance mode on: $server"
        ssh "$server" "cp /etc/nginx/maintenance.conf /etc/nginx/conf.d/"
        ssh "$server" "systemctl reload nginx"
    done
    
    # Send notifications
    send_notification "EMERGENCY_MODE" "Emergency maintenance mode enabled for $environment"
    
    log_success "Emergency maintenance mode enabled"
}

disable_emergency_mode() {
    local environment=$1
    
    log_info "Disabling emergency maintenance mode for: $environment"
    
    local lb_servers
    lb_servers=$(grep -E '^[0-9].*lb' "${CONFIG_DIR}/inventory/${environment}" | awk '{print $1}')
    
    for server in $lb_servers; do
        log_info "Disabling maintenance mode on: $server"
        ssh "$server" "rm -f /etc/nginx/conf.d/maintenance.conf"
        ssh "$server" "systemctl reload nginx"
    done
    
    log_success "Emergency maintenance mode disabled"
}

# Validation functions
validate_dr_readiness() {
    local environment=$1
    
    log_info "Validating disaster recovery readiness for: $environment"
    
    local checks_passed=0
    local checks_failed=0
    
    # Check backup availability
    log_info "Checking backup availability..."
    if find "$BACKUP_DIR" -name "*.gz" -mtime -1 | grep -q .; then
        log_success "Recent backups available"
        checks_passed=$((checks_passed + 1))
    else
        log_error "No recent backups found"
        checks_failed=$((checks_failed + 1))
    fi
    
    # Check secondary site connectivity
    log_info "Checking secondary site connectivity..."
    if ping -c 3 "secondary.infokes.co.id" &> /dev/null; then
        log_success "Secondary site is reachable"
        checks_passed=$((checks_passed + 1))
    else
        log_error "Secondary site is unreachable"
        checks_failed=$((checks_failed + 1))
    fi
    
    # Check database replication
    log_info "Checking database replication status..."
    local primary_db
    primary_db=$(grep -E '^[0-9].*db.*primary' "${CONFIG_DIR}/inventory/${environment}" | awk '{print $1}')
    
    if [ -n "$primary_db" ]; then
        if ssh "$primary_db" "mysql -e 'SHOW SLAVE STATUS\G' | grep -q 'Slave_IO_Running: Yes'"; then
            log_success "Database replication is running"
            checks_passed=$((checks_passed + 1))
        else
            log_error "Database replication is not running"
            checks_failed=$((checks_failed + 1))
        fi
    fi
    
    # Check DR configuration files
    log_info "Checking DR configuration files..."
    local required_files=(
        "${CONFIG_DIR}/inventory/dr_secondary"
        "${RECOVERY_DIR}/recovery-plan.md"
        "${BACKUP_DIR}/latest_full_backup.txt"
    )
    
    for file in "${required_files[@]}"; do
        if [ -f "$file" ]; then
            log_success "DR file exists: $(basename "$file")"
            checks_passed=$((checks_passed + 1))
        else
            log_error "DR file missing: $(basename "$file")"
            checks_failed=$((checks_failed + 1))
        fi
    done
    
    # Generate validation report
    local total_checks=$((checks_passed + checks_failed))
    log_info "DR Readiness Validation Report:"
    log_info "  Total checks: $total_checks"
    log_info "  Passed: $checks_passed"
    log_info "  Failed: $checks_failed"
    
    if [ "$checks_failed" -eq 0 ]; then
        log_success "DR validation PASSED - Environment is ready for disaster recovery"
        return 0
    else
        log_error "DR validation FAILED - $checks_failed checks failed"
        return 1
    fi
}

# Failover functions
initiate_failover() {
    local environment=$1
    
    log_info "Initiating failover to secondary site for: $environment"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would initiate failover to secondary site"
        return 0
    fi
    
    # Step 1: Enable emergency mode
    enable_emergency_mode "$environment"
    
    # Step 2: Stop replication and promote secondary database
    log_info "Promoting secondary database..."
    local secondary_db
    secondary_db=$(grep -E '^[0-9].*db.*secondary' "${CONFIG_DIR}/inventory/dr_secondary" | awk '{print $1}')
    
    if [ -n "$secondary_db" ]; then
        ssh "$secondary_db" "mysql -e 'STOP SLAVE;'"
        ssh "$secondary_db" "mysql -e 'RESET SLAVE ALL;'"
        log_success "Secondary database promoted"
    fi
    
    # Step 3: Update DNS to point to secondary site
    log_info "Updating DNS records to secondary site..."
    update_dns_records "secondary"
    
    # Step 4: Start services on secondary site
    log_info "Starting services on secondary site..."
    ansible-playbook -i "${CONFIG_DIR}/inventory/dr_secondary" \
        "${CONFIG_DIR}/playbooks/start-services.yml"
    
    # Step 5: Disable emergency mode
    disable_emergency_mode "$environment"
    
    # Step 6: Validate failover
    log_info "Validating failover..."
    if validate_failover; then
        log_success "Failover completed successfully"
        send_notification "FAILOVER_SUCCESS" "Failover to secondary site completed successfully"
    else
        log_error "Failover validation failed"
        send_notification "FAILOVER_FAILED" "Failover to secondary site failed"
        return 1
    fi
}

# Failback functions
initiate_failback() {
    local environment=$1
    
    log_info "Initiating failback to primary site for: $environment"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would initiate failback to primary site"
        return 0
    fi
    
    # Step 1: Enable emergency mode
    enable_emergency_mode "$environment"
    
    # Step 2: Sync data back to primary
    log_info "Synchronizing data to primary site..."
    sync_data_to_primary
    
    # Step 3: Update DNS to point to primary site
    log_info "Updating DNS records to primary site..."
    update_dns_records "primary"
    
    # Step 4: Start services on primary site
    log_info "Starting services on primary site..."
    ansible-playbook -i "${CONFIG_DIR}/inventory/${environment}" \
        "${CONFIG_DIR}/playbooks/start-services.yml"
    
    # Step 5: Reconfigure replication
    log_info "Reconfiguring database replication..."
    setup_database_replication
    
    # Step 6: Disable emergency mode
    disable_emergency_mode "$environment"
    
    # Step 7: Validate failback
    log_info "Validating failback..."
    if validate_failback; then
        log_success "Failback completed successfully"
        send_notification "FAILBACK_SUCCESS" "Failback to primary site completed successfully"
    else
        log_error "Failback validation failed"
        send_notification "FAILBACK_FAILED" "Failback to primary site failed"
        return 1
    fi
}

# Backup restoration
restore_from_backup() {
    local backup_id=$1
    local environment=$2
    
    log_info "Restoring from backup: $backup_id"
    
    # Find backup file
    local backup_file
    backup_file=$(find "$BACKUP_DIR" -name "*${backup_id}*" -type f | head -1)
    
    if [ -z "$backup_file" ]; then
        log_error "Backup not found: $backup_id"
        return 1
    fi
    
    log_info "Found backup file: $backup_file"
    
    # Decrypt if encrypted
    if [[ "$backup_file" == *.enc ]]; then
        log_info "Decrypting backup file..."
        local decrypted_file="${backup_file%.enc}"
        openssl enc -d -aes-256-cbc -in "$backup_file" -out "$decrypted_file" -pass pass:"$BACKUP_ENCRYPTION_KEY"
        backup_file="$decrypted_file"
    fi
    
    # Determine backup type and restore
    if [[ "$backup_file" == *mysql* ]]; then
        restore_mysql_backup "$backup_file" "$environment"
    elif [[ "$backup_file" == *mongodb* ]]; then
        restore_mongodb_backup "$backup_file" "$environment"
    elif [[ "$backup_file" == *infra* ]]; then
        restore_infrastructure_backup "$backup_file" "$environment"
    elif [[ "$backup_file" == *app* ]]; then
        restore_application_backup "$backup_file" "$environment"
    else
        log_error "Unknown backup type: $backup_file"
        return 1
    fi
    
    log_success "Backup restoration completed: $backup_id"
}

# Database restoration functions
restore_mysql_backup() {
    local backup_file=$1
    local environment=$2
    
    log_info "Restoring MySQL backup..."
    
    local db_servers
    db_servers=$(grep -E '^[0-9].*db' "${CONFIG_DIR}/inventory/${environment}" | awk '{print $1}')
    
    for server in $db_servers; do
        log_info "Restoring to MySQL server: $server"
        
        # Stop applications that use database
        stop_application_services "$environment"
        
        # Restore database
        if [[ "$backup_file" == *.gz ]]; then
            gunzip -c "$backup_file" | ssh "$server" "mysql"
        else
            ssh "$server" "mysql" < "$backup_file"
        fi
        
        # Start applications
        start_application_services "$environment"
    done
}

restore_mongodb_backup() {
    local backup_file=$1
    local environment=$2
    
    log_info "Restoring MongoDB backup..."
    
    local db_servers
    db_servers=$(grep -E '^[0-9].*db' "${CONFIG_DIR}/inventory/${environment}" | awk '{print $1}')
    
    for server in $db_servers; do
        log_info "Restoring to MongoDB server: $server"
        
        # Stop applications
        stop_application_services "$environment"
        
        # Restore database
        if [[ "$backup_file" == *.tar.gz ]]; then
            local temp_dir
            temp_dir=$(mktemp -d)
            tar -xzf "$backup_file" -C "$temp_dir"
            scp -r "$temp_dir"/* "$server:/tmp/mongorestore/"
            ssh "$server" "mongorestore /tmp/mongorestore/"
            ssh "$server" "rm -rf /tmp/mongorestore"
            rm -rf "$temp_dir"
        fi
        
        # Start applications
        start_application_services "$environment"
    done
}

# Infrastructure restoration
restore_infrastructure_backup() {
    local backup_file=$1
    local environment=$2
    
    log_info "Restoring infrastructure from backup..."
    
    local tf_env_dir="${PROJECT_ROOT}/automation/terraform/environments/${environment}"
    
    if [ ! -d "$tf_env_dir" ]; then
        log_error "Terraform environment directory not found: $tf_env_dir"
        return 1
    fi
    
    # Extract backup
    tar -xzf "$backup_file" -C "/tmp"
    
    # Restore Terraform state
    cp "/tmp/.terraform" "$tf_env_dir/" -r
    cp "/tmp/*.tfstate" "$tf_env_dir/" 2>/dev/null || true
    cp "/tmp/*.tfplan" "$tf_env_dir/" 2>/dev/null || true
    
    # Re-initialize and apply
    cd "$tf_env_dir"
    terraform init
    terraform apply -auto-approve
    
    log_success "Infrastructure restoration completed"
}

# Service management
stop_application_services() {
    local environment=$1
    
    log_info "Stopping application services..."
    
    ansible-playbook -i "${CONFIG_DIR}/inventory/${environment}" \
        "${CONFIG_DIR}/playbooks/stop-services.yml" \
        --tags application
}

start_application_services() {
    local environment=$1
    
    log_info "Starting application services..."
    
    ansible-playbook -i "${CONFIG_DIR}/inventory/${environment}" \
        "${CONFIG_DIR}/playbooks/start-services.yml" \
        --tags application
}

# DNS management
update_dns_records() {
    local site=$1
    
    log_info "Updating DNS records to: $site"
    
    # Update A records
    local new_ip
    if [ "$site" = "primary" ]; then
        new_ip="192.168.1.10"  # Primary site IP
    else
        new_ip="192.168.2.10"  # Secondary site IP
    fi
    
    # Update using AWS Route53 or other DNS provider
    if command -v aws &> /dev/null; then
        aws route53 change-resource-record-sets \
            --hosted-zone-id "$ROUTE53_ZONE_ID" \
            --change-batch "{
                \"Changes\": [{
                    \"Action\": \"UPSERT\",
                    \"ResourceRecordSet\": {
                        \"Name\": \"infokes.co.id\",
                        \"Type\": \"A\",
                        \"TTL\": 300,
                        \"ResourceRecords\": [{\"Value\": \"$new_ip\"}]
                    }
                }]
            }"
    fi
    
    log_success "DNS records updated to $site"
}

# Notification functions
send_notification() {
    local event_type=$1
    local message=$2
    
    log_info "Sending notification: $event_type - $message"
    
    # Send to Slack
    if [ -n "$SLACK_WEBHOOK_URL" ]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"🚨 DR Event: $event_type - $message\"}" \
            "$SLACK_WEBHOOK_URL"
    fi
    
    # Send email
    if [ -n "$ALERT_EMAIL" ]; then
        echo "Subject: DR Event: $event_type

        $message" | sendmail "$ALERT_EMAIL"
    fi
}

# Recovery plan generation
generate_recovery_plan() {
    local environment=$1
    
    log_info "Generating disaster recovery plan for: $environment"
    
    local plan_file="${RECOVERY_DIR}/recovery-plan-${environment}-${TIMESTAMP}.md"
    
    cat > "$plan_file" << EOF
# Disaster Recovery Plan - $environment
## Generated: $(date)
## Recovery ID: $RECOVERY_ID

## Recovery Objectives
- RPO (Recovery Point Objective): $RPO minutes
- RTO (Recovery Time Objective): $RTO minutes

## Recovery Procedures

### 1. Failover to Secondary Site
\`\`\`bash
./disaster-recovery.sh failover $environment
\`\`\`

### 2. Restore from Backup
\`\`\`bash
./disaster-recovery.sh restore-backup --backup <backup_id> $environment
\`\`\`

### 3. Emergency Mode
\`\`\`bash
# Enable
./disaster-recovery.sh emergency-mode $environment --force

# Disable  
./disaster-recovery.sh emergency-mode --disable $environment
\`\`\`

## Contact Information
- Primary Admin: $(whoami)
- Secondary Admin: admin@infokes.co.id
- Emergency Contact: +62-XXX-XXXX-XXXX

## Recovery Validation Steps
1. Validate database integrity
2. Check application functionality
3. Verify DNS propagation
4. Confirm monitoring alerts

## Backup Information
- Latest Backup: $(find "$BACKUP_DIR" -name "*.gz" -type f -exec ls -1t {} + | head -1)
- Backup Location: $BACKUP_DIR
EOF

    log_success "Recovery plan generated: $plan_file"
}

# Validation functions
validate_failover() {
    log_info "Validating failover..."
    
    # Check if services are running on secondary site
    local secondary_services=("nginx" "mysql" "nodejs")
    local secondary_server
    secondary_server=$(grep -E '^[0-9].*app' "${CONFIG_DIR}/inventory/dr_secondary" | awk '{print $1}' | head -1)
    
    for service in "${secondary_services[@]}"; do
        if ssh "$secondary_server" "systemctl is-active --quiet $service"; then
            log_success "Service $service is active on secondary site"
        else
            log_error "Service $service is not active on secondary site"
            return 1
        fi
    done
    
    # Check DNS resolution
    if nslookup "infokes.co.id" | grep -q "192.168.2"; then
        log_success "DNS correctly points to secondary site"
    else
        log_error "DNS does not point to secondary site"
        return 1
    fi
    
    return 0
}

validate_failback() {
    log_info "Validating failback..."
    
    # Similar checks as validate_failover but for primary site
    local primary_services=("nginx" "mysql" "nodejs")
    local primary_server
    primary_server=$(grep -E '^[0-9].*app' "${CONFIG_DIR}/inventory/prod" | awk '{print $1}' | head -1)
    
    for service in "${primary_services[@]}"; do
        if ssh "$primary_server" "systemctl is-active --quiet $service"; then
            log_success "Service $service is active on primary site"
        else
            log_error "Service $service is not active on primary site"
            return 1
        fi
    done
    
    return 0
}

# Main recovery function
main_recovery() {
    local action=$1
    local environment=$2
    
    ACTION=${action}
    ENVIRONMENT=${environment:-"prod"}
    
    log_info "Starting disaster recovery action: $ACTION for environment: $ENVIRONMENT"
    
    # Load environment variables
    export BACKUP_ENCRYPTION_KEY=${BACKUP_ENCRYPTION_KEY:-""}
    export SLACK_WEBHOOK_URL=${SLACK_WEBHOOK_URL:-""}
    export ALERT_EMAIL=${ALERT_EMAIL:-""}
    export ROUTE53_ZONE_ID=${ROUTE53_ZONE_ID:-""}
    
    case $ACTION in
        failover)
            if [ "$FORCE" != true ]; then
                log_warning "This will initiate failover to secondary site!"
                read -p "Are you sure? This is a destructive operation! (type 'FAILOVER' to confirm): " -r
                if [ "$REPLY" != "FAILOVER" ]; then
                    log_info "Failover cancelled"
                    exit 0
                fi
            fi
            initiate_failover "$ENVIRONMENT"
            ;;
        
        failback)
            if [ "$FORCE" != true ]; then
                log_warning "This will initiate failback to primary site!"
                read -p "Are you sure? (type 'FAILBACK' to confirm): " -r
                if [ "$REPLY" != "FAILBACK" ]; then
                    log_info "Failback cancelled"
                    exit 0
                fi
            fi
            initiate_failback "$ENVIRONMENT"
            ;;
        
        restore-backup)
            if [ -z "$BACKUP_ID" ]; then
                log_error "Backup ID required for restore operation"
                show_help
                exit 1
            fi
            restore_from_backup "$BACKUP_ID" "$ENVIRONMENT"
            ;;
        
        emergency-mode)
            if [ "$DISABLE_EMERGENCY" = true ]; then
                disable_emergency_mode "$ENVIRONMENT"
            else
                enable_emergency_mode "$ENVIRONMENT"
            fi
            ;;
        
        validate-dr)
            validate_dr_readiness "$ENVIRONMENT"
            ;;
        
        generate-plan)
            generate_recovery_plan "$ENVIRONMENT"
            ;;
        
        *)
            log_error "Unknown action: $ACTION"
            show_help
            exit 1
            ;;
    esac
    
    log_success "Disaster recovery action completed: $ACTION"
}

# Parse arguments
ACTION=""
ENVIRONMENT="prod"
BACKUP_ID=""
FORCE=false
DRY_RUN=false
DISABLE_EMERGENCY=false
RPO=60    # 60 minutes RPO
RTO=120   # 120 minutes RTO

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -b|--backup)
            BACKUP_ID=$2
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --disable)
            DISABLE_EMERGENCY=true
            shift
            ;;
        --rpo)
            RPO=$2
            shift 2
            ;;
        --rto)
            RTO=$2
            shift 2
            ;;
        failover|failback|restore-backup|emergency-mode|validate-dr|generate-plan)
            ACTION=$1
            shift
            ;;
        prod|staging)
            ENVIRONMENT=$1
            shift
            ;;
        *)
            log_error "Unknown argument: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate required action
if [ -z "$ACTION" ]; then
    log_error "Action argument required"
    show_help
    exit 1
fi

# Execute main function
main_recovery "$ACTION" "$ENVIRONMENT"