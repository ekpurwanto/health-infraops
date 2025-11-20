#!/bin/bash
# Health-InfraOps Load Balancer Health Check Script

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
APP_SERVERS=("10.0.10.11" "10.0.10.12" "10.0.10.13" "10.0.10.14")
API_SERVERS=("10.0.10.15" "10.0.10.16" "10.0.10.17")
STATIC_SERVERS=("10.0.10.19" "10.0.10.20")
LOAD_BALANCERS=("10.0.30.10" "10.0.30.11")

DOMAINS=("infokes.co.id" "www.infokes.co.id" "api.infokes.co.id")

# Health check function
check_server() {
    local server=$1
    local port=$2
    local endpoint=$3
    local service=$4
    
    local url="http://$server:$port$endpoint"
    
    if curl -s -f --max-time 5 "$url" > /dev/null; then
        log "✅ $service - $server:$port - HEALTHY"
        return 0
    else
        error "❌ $service - $server:$port - UNHEALTHY"
        return 1
    fi
}

check_https() {
    local domain=$1
    
    if curl -s -f --max-time 5 "https://$domain/health" > /dev/null; then
        log "✅ HTTPS - $domain - HEALTHY"
        return 0
    else
        error "❌ HTTPS - $domain - UNHEALTHY"
        return 1
    fi
}

check_ssl_cert() {
    local domain=$1
    
    local expiry=$(echo | openssl s_client -connect $domain:443 -servername $domain 2>/dev/null | openssl x509 -noout -enddate | cut -d= -f2)
    local days_until_expiry=$(( ($(date -d "$expiry" +%s) - $(date +%s)) / 86400 ))
    
    if [ $days_until_expiry -gt 30 ]; then
        log "✅ SSL - $domain - Valid for $days_until_expiry days"
    elif [ $days_until_expiry -gt 7 ]; then
        warning "⚠️ SSL - $domain - Expires in $days_until_expiry days"
    else
        error "❌ SSL - $domain - EXPIRES IN $days_until_expiry DAYS!"
    fi
}

check_load_balancer() {
    local lb=$1
    
    # Check HAProxy stats
    if curl -s -f --max-time 5 "http://$lb:1936/haproxy?stats" > /dev/null; then
        log "✅ Load Balancer - $lb - HAProxy stats accessible"
    else
        error "❌ Load Balancer - $lb - HAProxy stats inaccessible"
    fi
    
    # Check Nginx status
    if curl -s -f --max-time 5 "http://$lb/nginx_status" > /dev/null 2>&1; then
        log "✅ Load Balancer - $lb - Nginx status accessible"
    else
        warning "⚠️ Load Balancer - $lb - Nginx status inaccessible"
    fi
}

log "Starting Health-InfraOps Load Balancer Health Check..."

# Check application servers
log "Checking application servers..."
for server in "${APP_SERVERS[@]}"; do
    check_server "$server" 3000 "/health" "Application"
done

# Check API servers
log "Checking API servers..."
for server in "${API_SERVERS[@]}"; do
    check_server "$server" 8000 "/api/health" "API"
done

# Check static servers
log "Checking static servers..."
for server in "${STATIC_SERVERS[@]}"; do
    check_server "$server" 80 "/health" "Static"
done

# Check HTTPS connectivity
log "Checking HTTPS connectivity..."
for domain in "${DOMAINS[@]}"; do
    check_https "$domain"
done

# Check SSL certificates
log "Checking SSL certificates..."
for domain in "${DOMAINS[@]}"; do
    check_ssl_cert "$domain"
done

# Check load balancers
log "Checking load balancers..."
for lb in "${LOAD_BALANCERS[@]}"; do
    check_load_balancer "$lb"
done

# Check backend server status via HAProxy
log "Checking HAProxy backend status..."
for lb in "${LOAD_BALANCERS[@]}"; do
    if command -v haproxy &> /dev/null; then
        echo "Backend status for $lb:"
        echo "show stat" | socat /var/run/haproxy/admin.sock stdio 2>/dev/null | grep -v "^#" | awk -F, '{print $1","$2","$18","$37","$50}' | column -t -s, || warning "Could not connect to HAProxy admin socket"
    fi
done

# Check Nginx upstream status
log "Checking Nginx upstream status..."
if command -v nginx &> /dev/null; then
    for upstream in infokes_app infokes_api infokes_static; do
        echo "Upstream: $upstream"
        curl -s http://localhost/nginx_status 2>/dev/null || warning "Nginx status not accessible"
    done
fi

# Performance checks
log "Running performance checks..."

# Check response time
for domain in "${DOMAINS[@]}"; do
    response_time=$(curl -s -w "%{time_total}\n" -o /dev/null "https://$domain/health")
    log "Response time - $domain: ${response_time}s"
done

# Check active connections
if command -v haproxy &> /dev/null; then
    current_conn=$(echo "show info" | socat /var/run/haproxy/admin.sock stdio 2>/dev/null | grep "CurrConn" | cut -d: -f2)
    log "HAProxy current connections: $current_conn"
fi

if command -v nginx &> /dev/null; then
    nginx_conn=$(curl -s http://localhost/nginx_status 2>/dev/null | grep "Active connections" | cut -d: -f2)
    log "Nginx active connections: $nginx_conn"
fi

log "✅ Health-InfraOps Load Balancer health check completed!"

# Generate report
REPORT_FILE="/var/log/loadbalancer-health-$(date +%Y%m%d_%H%M%S).log"
{
    echo "Health-InfraOps Load Balancer Health Report"
    echo "Generated: $(date)"
    echo "==========================================="
    echo ""
    echo "Application Servers: ${#APP_SERVERS[@]}"
    echo "API Servers: ${#API_SERVERS[@]}"
    echo "Static Servers: ${#STATIC_SERVERS[@]}"
    echo "Load Balancers: ${#LOAD_BALANCERS[@]}"
    echo ""
    echo "Domains: ${DOMAINS[*]}"
} > $REPORT_FILE

log "📊 Health report saved to: $REPORT_FILE"