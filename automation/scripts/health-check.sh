set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="${PROJECT_ROOT}/automation/ansible"
LOG_DIR="${PROJECT_ROOT}/logs/health-checks"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HEALTH_CHECK_ID="health_${TIMESTAMP}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Health status
HEALTHY=0
UNHEALTHY=0
WARNING=0

mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/${HEALTH_CHECK_ID}.log"
REPORT_FILE="${LOG_DIR}/${HEALTH_CHECK_ID}_report.html"

# Logging functions
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$1"; }
log_success() { log "SUCCESS" "$1"; HEALTHY=$((HEALTHY + 1)); }
log_warning() { log "WARNING" "$1"; WARNING=$((WARNING + 1)); }
log_error() { log "ERROR" "$1"; UNHEALTHY=$((UNHEALTHY + 1)); }

show_help() {
    cat << EOF
Health-InfraOps Health Check Script

Usage: $0 [options] [environment]

Environments:
  dev       - Development environment
  staging   - Staging environment  
  prod      - Production environment

Options:
  -h, --help         Show this help
  -f, --full         Full health check (default)
  -q, --quick        Quick health check
  -s, --server       Check specific server
  -c, --component    Check specific component
  --html-report      Generate HTML report
  --alert-on-failure Send alerts on failure

Components:
  all           - All components (default)
  infrastructure - Infrastructure only
  application    - Applications only
  database       - Databases only
  monitoring     - Monitoring stack
  network        - Network connectivity

Examples:
  $0 prod --full
  $0 dev --quick
  $0 --component database --server db-01
  $0 staging --html-report
EOF
}

# Check functions
check_disk_usage() {
    local server=$1
    local threshold=${2:-80}
    
    log_info "Checking disk usage on $server"
    
    local disk_usage
    disk_usage=$(ssh "$server" "df -h / | awk 'NR==2 {print \$5}' | sed 's/%//'")
    
    if [ "$disk_usage" -lt "$threshold" ]; then
        log_success "Disk usage on $server: ${disk_usage}% (OK)"
    else
        log_error "Disk usage on $server: ${disk_usage}% (CRITICAL - above ${threshold}%)"
    fi
}

check_memory_usage() {
    local server=$1
    local threshold=${2:-80}
    
    log_info "Checking memory usage on $server"
    
    local memory_usage
    memory_usage=$(ssh "$server" "free | awk 'NR==2{printf \"%.0f\", \$3/\$2 * 100}'")
    
    if [ "$memory_usage" -lt "$threshold" ]; then
        log_success "Memory usage on $server: ${memory_usage}% (OK)"
    else
        log_error "Memory usage on $server: ${memory_usage}% (CRITICAL - above ${threshold}%)"
    fi
}

check_cpu_load() {
    local server=$1
    local threshold=${2:-80}
    
    log_info "Checking CPU load on $server"
    
    local cpu_cores
    cpu_cores=$(ssh "$server" "nproc")
    local load_avg
    load_avg=$(ssh "$server" "cat /proc/loadavg | awk '{print \$1}'")
    local load_percent
    load_percent=$(echo "scale=0; ($load_avg / $cpu_cores) * 100" | bc)
    
    if [ "$load_percent" -lt "$threshold" ]; then
        log_success "CPU load on $server: ${load_percent}% (OK)"
    else
        log_error "CPU load on $server: ${load_percent}% (CRITICAL - above ${threshold}%)"
    fi
}

check_service_status() {
    local server=$1
    local service=$2
    
    log_info "Checking service $service on $server"
    
    if ssh "$server" "systemctl is-active --quiet $service"; then
        log_success "Service $service on $server: ACTIVE"
    else
        log_error "Service $service on $server: INACTIVE"
    fi
}

check_port_listening() {
    local server=$1
    local port=$2
    local service=${3:-"port $port"}
    
    log_info "Checking $service on $server:$port"
    
    if ssh "$server" "netstat -tuln | grep -q ':$port '"; then
        log_success "$service on $server:$port: LISTENING"
    else
        log_error "$service on $server:$port: NOT LISTENING"
    fi
}

check_website_health() {
    local url=$1
    local expected_status=${2:-200}
    
    log_info "Checking website health: $url"
    
    local response_code
    response_code=$(curl -s -o /dev/null -w "%{http_code}" "$url")
    
    if [ "$response_code" -eq "$expected_status" ]; then
        log_success "Website $url: HTTP $response_code (OK)"
    else
        log_error "Website $url: HTTP $response_code (Expected: $expected_status)"
    fi
}

check_database_connection() {
    local server=$1
    local db_type=$2
    local db_name=${3:-"mysql"}
    
    log_info "Checking $db_type database connection on $server"
    
    case $db_type in
        mysql)
            if ssh "$server" "mysql -e 'SELECT 1;'"; then
                log_success "MySQL database on $server: CONNECTED"
            else
                log_error "MySQL database on $server: CONNECTION FAILED"
            fi
            ;;
        mongodb)
            if ssh "$server" "mongo --eval 'db.adminCommand(\"ping\")'"; then
                log_success "MongoDB on $server: CONNECTED"
            else
                log_error "MongoDB on $server: CONNECTION FAILED"
            fi
            ;;
        postgresql)
            if ssh "$server" "psql -c 'SELECT 1;'"; then
                log_success "PostgreSQL on $server: CONNECTED"
            else
                log_error "PostgreSQL on $server: CONNECTION FAILED"
            fi
            ;;
    esac
}

check_ssl_certificate() {
    local domain=$1
    local days_threshold=${2:-30}
    
    log_info "Checking SSL certificate for: $domain"
    
    local expiry_date
    expiry_date=$(openssl s_client -connect "$domain:443" -servername "$domain" < /dev/null 2>/dev/null | \
                 openssl x509 -noout -enddate | cut -d= -f2)
    
    local expiry_epoch
    expiry_epoch=$(date -d "$expiry_date" +%s)
    local current_epoch
    current_epoch=$(date +%s)
    local days_until_expiry
    days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
    
    if [ "$days_until_expiry" -gt "$days_threshold" ]; then
        log_success "SSL certificate for $domain: Valid for ${days_until_expiry} days (OK)"
    elif [ "$days_until_expiry" -gt 0 ]; then
        log_warning "SSL certificate for $domain: Expires in ${days_until_expiry} days (WARNING)"
    else
        log_error "SSL certificate for $domain: EXPIRED"
    fi
}

check_backup_status() {
    local server=$1
    local backup_type=$2
    
    log_info "Checking $backup_type backup status on $server"
    
    # Check if backup scripts are running
    if ssh "$server" "crontab -l | grep -q backup"; then
        log_success "Backup cron jobs configured on $server"
    else
        log_warning "No backup cron jobs found on $server"
    fi
    
    # Check recent backup files
    if ssh "$server" "find /backups -name '*${backup_type}*' -mtime -1 | grep -q ."; then
        log_success "Recent $backup_type backups found on $server"
    else
        log_error "No recent $backup_type backups found on $server"
    fi
}

# Infrastructure health checks
check_infrastructure_health() {
    local environment=$1
    
    log_info "Starting infrastructure health checks for $environment"
    
    # Get server list from inventory
    local inventory="${CONFIG_DIR}/inventory/${environment}"
    
    if [ ! -f "$inventory" ]; then
        log_error "Inventory file not found: $inventory"
        return 1
    fi
    
    # Extract server list
    local servers
    servers=$(grep -E '^[0-9]' "$inventory" | awk '{print $1}')
    
    for server in $servers; do
        log_info "Checking server: $server"
        
        # Basic system checks
        check_disk_usage "$server"
        check_memory_usage "$server"
        check_cpu_load "$server"
        
        # Common services
        check_service_status "$server" "ssh"
        check_service_status "$server" "chrony"
        check_service_status "$server" "fail2ban"
    done
    
    log_success "Infrastructure health checks completed"
}

# Application health checks
check_application_health() {
    local environment=$1
    
    log_info "Starting application health checks for $environment"
    
    case $environment in
        dev)
            check_website_health "https://dev.health.com"
            check_website_health "https://api.dev.health.com/health"
            ;;
        staging)
            check_website_health "https://staging.health.com"
            check_website_health "https://api.staging.health.com/health"
            ;;
        prod)
            check_website_health "https://health.com"
            check_website_health "https://api.health.com/health"
            check_ssl_certificate "health.com"
            ;;
    esac
    
    # Check application services
    local inventory="${CONFIG_DIR}/inventory/${environment}"
    local app_servers
    app_servers=$(grep -E '^[0-9].*app' "$inventory" | awk '{print $1}')
    
    for server in $app_servers; do
        check_service_status "$server" "nginx"
        check_service_status "$server" "pm2"
        check_port_listening "$server" "80" "HTTP"
        check_port_listening "$server" "443" "HTTPS"
        check_port_listening "$server" "3000" "Node.js App"
    done
    
    log_success "Application health checks completed"
}

# Database health checks
check_database_health() {
    local environment=$1
    
    log_info "Starting database health checks for $environment"
    
    local inventory="${CONFIG_DIR}/inventory/${environment}"
    local db_servers
    db_servers=$(grep -E '^[0-9].*db' "$inventory" | awk '{print $1}')
    
    for server in $db_servers; do
        # Determine database type
        if ssh "$server" "which mysql" &> /dev/null; then
            check_database_connection "$server" "mysql"
            check_service_status "$server" "mysql"
            check_port_listening "$server" "3306" "MySQL"
        fi
        
        if ssh "$server" "which mongod" &> /dev/null; then
            check_database_connection "$server" "mongodb"
            check_service_status "$server" "mongod"
            check_port_listening "$server" "27017" "MongoDB"
        fi
        
        check_backup_status "$server" "database"
    done
    
    log_success "Database health checks completed"
}

# Monitoring health checks
check_monitoring_health() {
    local environment=$1
    
    log_info "Starting monitoring stack health checks for $environment"
    
    local inventory="${CONFIG_DIR}/inventory/${environment}"
    local monitoring_servers
    monitoring_servers=$(grep -E '^[0-9].*monitoring' "$inventory" | awk '{print $1}')
    
    for server in $monitoring_servers; do
        check_service_status "$server" "prometheus"
        check_service_status "$server" "grafana-server"
        check_service_status "$server" "alertmanager"
        
        check_port_listening "$server" "9090" "Prometheus"
        check_port_listening "$server" "3000" "Grafana"
        check_port_listening "$server" "9093" "Alertmanager"
    done
    
    # Check monitoring endpoints
    case $environment in
        prod)
            check_website_health "https://monitoring.health.com" 200
            ;;
        staging)
            check_website_health "https://monitoring.staging.health.com" 200
            ;;
    esac
    
    log_success "Monitoring health checks completed"
}

# Network health checks
check_network_health() {
    local environment=$1
    
    log_info "Starting network health checks for $environment"
    
    local inventory="${CONFIG_DIR}/inventory/${environment}"
    local servers
    servers=$(grep -E '^[0-9]' "$inventory" | awk '{print $1}')
    
    for server in $servers; do
        # Check basic connectivity
        if ping -c 3 -W 5 "$server" &> /dev/null; then
            log_success "Network connectivity to $server: OK"
        else
            log_error "Network connectivity to $server: FAILED"
        fi
    done
    
    log_success "Network health checks completed"
}

# Generate HTML report
generate_html_report() {
    log_info "Generating HTML health report..."
    
    cat > "$REPORT_FILE" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Health Check Report - $HEALTH_CHECK_ID</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f4f4f4; padding: 20px; border-radius: 5px; }
        .summary { margin: 20px 0; padding: 15px; border-radius: 5px; }
        .healthy { background: #d4edda; border: 1px solid #c3e6cb; }
        .warning { background: #fff3cd; border: 1px solid #ffeaa7; }
        .unhealthy { background: #f8d7da; border: 1px solid #f5c6cb; }
        .log-entry { margin: 5px 0; padding: 8px; border-left: 4px solid #007bff; }
        .success { border-left-color: #28a745; }
        .warning { border-left-color: #ffc107; }
        .error { border-left-color: #dc3545; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Health Check Report</h1>
        <p><strong>Environment:</strong> $ENVIRONMENT</p>
        <p><strong>Check ID:</strong> $HEALTH_CHECK_ID</p>
        <p><strong>Timestamp:</strong> $(date)</p>
    </div>
    
    <div class="summary">
        <h2>Summary</h2>
        <p><strong>Healthy:</strong> $HEALTHY checks</p>
        <p><strong>Warnings:</strong> $WARNING checks</p>
        <p><strong>Unhealthy:</strong> $UNHEALTHY checks</p>
        <p><strong>Overall Status:</strong> 
EOF

    if [ "$UNHEALTHY" -eq 0 ]; then
        echo "<span style='color: green;'>HEALTHY</span>" >> "$REPORT_FILE"
    elif [ "$UNHEALTHY" -lt 3 ]; then
        echo "<span style='color: orange;'>DEGRADED</span>" >> "$REPORT_FILE"
    else
        echo "<span style='color: red;'>UNHEALTHY</span>" >> "$REPORT_FILE"
    fi

    cat >> "$REPORT_FILE" << EOF
        </p>
    </div>
    
    <div class="logs">
        <h2>Detailed Logs</h2>
EOF

    # Add log entries to HTML
    while IFS= read -r line; do
        local class=""
        if [[ $line == *"SUCCESS"* ]]; then
            class="success"
        elif [[ $line == *"WARNING"* ]]; then
            class="warning"
        elif [[ $line == *"ERROR"* ]]; then
            class="error"
        fi
        echo "<div class='log-entry $class'>$line</div>" >> "$REPORT_FILE"
    done < "$LOG_FILE"

    cat >> "$REPORT_FILE" << EOF
    </div>
</body>
</html>
EOF

    log_success "HTML report generated: $REPORT_FILE"
}

# Main health check function
main_health_check() {
    local environment=$1
    local check_type=$2
    
    ENVIRONMENT=${environment:-"prod"}
    CHECK_TYPE=${check_type:-"full"}
    
    log_info "Starting health checks - Environment: $ENVIRONMENT, Type: $CHECK_TYPE"
    
    case $CHECK_TYPE in
        quick)
            check_infrastructure_health "$ENVIRONMENT"
            check_application_health "$ENVIRONMENT"
            ;;
        full|all)
            check_infrastructure_health "$ENVIRONMENT"
            check_application_health "$ENVIRONMENT"
            check_database_health "$ENVIRONMENT"
            check_monitoring_health "$ENVIRONMENT"
            check_network_health "$ENVIRONMENT"
            ;;
        infrastructure)
            check_infrastructure_health "$ENVIRONMENT"
            ;;
        application)
            check_application_health "$ENVIRONMENT"
            ;;
        database)
            check_database_health "$ENVIRONMENT"
            ;;
        monitoring)
            check_monitoring_health "$ENVIRONMENT"
            ;;
        network)
            check_network_health "$ENVIRONMENT"
            ;;
    esac
    
    # Generate summary
    local total_checks=$((HEALTHY + WARNING + UNHEALTHY))
    log_info "Health check summary:"
    log_info "  Total checks: $total_checks"
    log_info "  Healthy: $HEALTHY"
    log_info "  Warnings: $WARNING" 
    log_info "  Unhealthy: $UNHEALTHY"
    
    # Generate HTML report if requested
    if [ "$GENERATE_HTML" = true ]; then
        generate_html_report
    fi
    
    # Exit with appropriate code
    if [ "$UNHEALTHY" -gt 0 ]; then
        log_error "Health checks completed with failures"
        exit 1
    elif [ "$WARNING" -gt 0 ]; then
        log_warning "Health checks completed with warnings"
        exit 0
    else
        log_success "All health checks passed"
        exit 0
    fi
}

# Parse arguments
ENVIRONMENT="prod"
CHECK_TYPE="full"
GENERATE_HTML=false
SPECIFIC_SERVER=""
SPECIFIC_COMPONENT=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -f|--full)
            CHECK_TYPE="full"
            shift
            ;;
        -q|--quick)
            CHECK_TYPE="quick"
            shift
            ;;
        --html-report)
            GENERATE_HTML=true
            shift
            ;;
        -s|--server)
            SPECIFIC_SERVER=$2
            shift 2
            ;;
        -c|--component)
            SPECIFIC_COMPONENT=$2
            shift 2
            ;;
        dev|staging|prod)
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

# Execute main function
main_health_check "$ENVIRONMENT" "${SPECIFIC_COMPONENT:-$CHECK_TYPE}"
