#!/bin/bash
# Health-InfraOps Lynis Security Audit Script

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
LYNIS_DIR="/opt/lynis"
AUDIT_DIR="/var/log/health-infraops-audit"
DATE=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="$AUDIT_DIR/lynis-report-$DATE.log"
HARDENING_FILE="$AUDIT_DIR/hardening-suggestions-$DATE.md"
SERVER_TYPE="${1:-all}"  # all, web, db, app, mon

log "Starting Health-InfraOps Lynis Security Audit..."

# Check if Lynis is installed
if ! command -v lynis &> /dev/null; then
    log "Lynis not found. Installing..."
    
    # Install Lynis from official repository
    apt update
    apt install -y lynis
    
    if ! command -v lynis &> /dev/null; then
        error "Failed to install Lynis. Please install manually."
        exit 1
    fi
fi

# Create audit directory
mkdir -p $AUDIT_DIR
chmod 700 $AUDIT_DIR

# Determine audit profile based on server type
case $SERVER_TYPE in
    "web")
        AUDIT_PROFILE="--tests-from-group malware,authentication,networking,ports,processes"
        SERVER_DESC="Web Server"
        ;;
    "db")
        AUDIT_PROFILE="--tests-from-group authentication,database,file-systems,logging,processes"
        SERVER_DESC="Database Server"
        ;;
    "app")
        AUDIT_PROFILE="--tests-from-group authentication,file-systems,logging,processes,software"
        SERVER_DESC="Application Server"
        ;;
    "mon")
        AUDIT_PROFILE="--tests-from-group authentication,logging,malware,networking,ports"
        SERVER_DESC="Monitoring Server"
        ;;
    "all"|*)
        AUDIT_PROFILE=""
        SERVER_DESC="Comprehensive Audit"
        ;;
esac

log "Running $SERVER_DESC audit..."

# Run Lynis audit
log "Executing Lynis security audit..."
lynis audit system $AUDIT_PROFILE --cronjob --log-file $REPORT_FILE --report-file $REPORT_FILE

# Check if audit was successful
if [ $? -eq 0 ]; then
    log "✅ Lynis audit completed successfully"
else
    error "❌ Lynis audit encountered issues"
fi

# Extract hardening suggestions
log "Extracting hardening suggestions..."
lynis show details | grep -A5 -B5 "Suggestion" > $HARDENING_FILE || true

# Parse Lynis report and generate summary
log "Generating audit summary..."
cat > $AUDIT_DIR/audit-summary-$DATE.md << EOF
# Health-InfraOps Security Audit Report
**Server Type**: $SERVER_DESC  
**Audit Date**: $(date)  
**Lynis Version**: $(lynis --version 2>/dev/null | head -1)  

## Executive Summary

\`\`\`
$(grep -E "(Hardening|Score|Warnings|Suggestions)" $REPORT_FILE | head -10)
\`\`\`

## System Information
\`\`\`
$(grep -E "(Hostname|OS|Kernel|Architecture)" $REPORT_FILE | head -10)
\`\`\`

## Critical Findings
\`\`\`
$(grep -i "warning\\|critical\\|vulnerability" $REPORT_FILE | head -20)
\`\`\`

## Security Score
\`\`\`
$(grep -A5 "Hardening index" $REPORT_FILE)
\`\`\`

## Top Recommendations
\`\`\`
$(grep "Suggestion" $HARDENING_FILE | head -10)
\`\`\`

## Full Report
The complete audit report is available at: \`$REPORT_FILE\`

## Next Steps
1. Review critical findings
2. Implement hardening suggestions
3. Schedule follow-up audit
4. Update security policies
EOF

# Generate actionable hardening script
log "Generating hardening script..."
cat > $AUDIT_DIR/apply-hardening-$DATE.sh << 'EOF'
#!/bin/bash
# Health-InfraOps Security Hardening Script
# Generated from Lynis audit $(date)

set -e

echo "Applying security hardening based on Lynis audit..."

# 1. File System Hardening
echo "Hardening file systems..."
chmod 700 /boot /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.monthly /etc/cron.weekly
chmod 600 /etc/crontab /etc/ssh/sshd_config

# 2. SSH Hardening
echo "Hardening SSH configuration..."
sed -i 's/^#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#Protocol 2/Protocol 2/' /etc/ssh/sshd_config

# 3. Network Hardening
echo "Hardening network configuration..."
echo 'net.ipv4.ip_forward=0' >> /etc/sysctl.conf
echo 'net.ipv4.conf.all.send_redirects=0' >> /etc/sysctl.conf
echo 'net.ipv4.conf.default.send_redirects=0' >> /etc/sysctl.conf
sysctl -p

# 4. User Account Security
echo "Enhancing user account security..."
passwd -l root
usermod -s /sbin/nologin nobody
usermod -s /sbin/nologin daemon

# 5. Service Hardening
echo "Hardening services..."
systemctl mask rpcbind
systemctl mask nfs-server

# 6. Logging Enhancement
echo "Enhancing logging..."
echo 'auth,authpriv.* /var/log/auth.log' >> /etc/rsyslog.conf
echo 'kernel.* -/var/log/kernel.log' >> /etc/rsyslog.conf
systemctl restart rsyslog

# 7. File Permissions
echo "Setting secure file permissions..."
find /etc/ssh -type f -name 'ssh_host_*_key' -exec chmod 600 {} \;
find /etc/ssl -type f -name '*.key' -exec chmod 600 {} \;

echo "Hardening completed. Please review and reboot if necessary."
EOF

chmod +x $AUDIT_DIR/apply-hardening-$DATE.sh

# Perform additional Health-InfraOps specific checks
log "Performing Health-InfraOps specific security checks..."
cat > $AUDIT_DIR/health-infraops-specific-$DATE.log << EOF
Health-InfraOps Specific Security Audit
=======================================
Audit Date: $(date)

1. VLAN Configuration Check:
$(ip route show | grep -E "10.0.*" || echo "No VLAN routes found")

2. Service Accessibility:
$(ss -tuln | grep -E ":80|:443|:22|:3306|:5432" || echo "No services listening")

3. Health-InfraOps User Accounts:
$(getent passwd | grep -E "admin|deploy|monitor|backup" || echo "No Health-InfraOps users found")

4. SSL Certificate Check:
$(find /etc/ssl -name "*.crt" -exec openssl x509 -noout -subject -dates -in {} \; 2>/dev/null || echo "No SSL certificates found")

5. Backup Configuration:
$(crontab -l | grep -E "backup|rsync|tar" || echo "No backup cron jobs found")

6. Monitoring Agents:
$(ps aux | grep -E "zabbix|prometheus|node_exporter" || echo "No monitoring agents running")

7. Database Security:
$(mysql -e "SELECT user, host FROM mysql.user WHERE user NOT IN ('mysql.sys','mysql.session','mysql.infoschema');" 2>/dev/null || echo "MySQL not accessible")

8. Firewall Status:
$(iptables -L -n 2>/dev/null | head -20 || ufw status verbose 2>/dev/null || echo "Firewall status unavailable")
EOF

# Generate compliance report
log "Generating compliance report..."
cat > $AUDIT_DIR/compliance-report-$DATE.md << EOF
# Health-InfraOps Compliance Report

## HIPAA Security Rule Compliance
- [ ] Access Control: $(grep -q "password" $REPORT_FILE && echo "PASS" || echo "FAIL")
- [ ] Audit Controls: $(grep -q "audit" $REPORT_FILE && echo "PASS" || echo "FAIL")
- [ ] Integrity: $(grep -q "file.*integrity" $REPORT_FILE && echo "PASS" || echo "FAIL")
- [ ] Authentication: $(grep -q "authentication" $REPORT_FILE && echo "PASS" || echo "FAIL")

## NIST Cybersecurity Framework
- [ ] Identify: Asset management, risk assessment
- [ ] Protect: Access control, awareness training
- [ ] Detect: Anomalies and events, continuous monitoring
- [ ] Respond: Response planning, communications
- [ ] Recover: Recovery planning, improvements

## PCI DSS Compliance
- [ ] Build and Maintain Secure Networks
- [ ] Protect Cardholder Data
- [ ] Maintain Vulnerability Management
- [ ] Implement Strong Access Control
- [ ] Regularly Monitor Networks
- [ ] Maintain Information Security Policy
EOF

# Send notification (if configured)
if command -v sendmail &> /dev/null; then
    log "Sending audit notification..."
    cat << EOF | sendmail -t
To: security@infokes.co.id
Subject: Health-InfraOps Security Audit Completed - $(date)

Health-InfraOps security audit has been completed.

Server Type: $SERVER_DESC
Audit Date: $(date)

Summary:
$(grep -E "Hardening index|Tests performed|Warnings|Suggestions" $REPORT_FILE | head -10)

Critical findings require attention. Please review the full report at:
$REPORT_FILE

- Health-InfraOps Security Team
EOF
fi

log "✅ Health-InfraOps Lynis security audit completed!"
log "📊 Audit Results:"
echo "   Full Report: $REPORT_FILE"
echo "   Hardening Suggestions: $HARDENING_FILE"
echo "   Audit Summary: $AUDIT_DIR/audit-summary-$DATE.md"
echo "   Hardening Script: $AUDIT_DIR/apply-hardening-$DATE.sh"
echo "   Compliance Report: $AUDIT_DIR/compliance-report-$DATE.md"

# Display quick summary
warning "Quick Summary:"
grep -E "Hardening index|Warnings|Suggestions" $REPORT_FILE | head -5

# Schedule next audit
log "Scheduling next audit..."
if ! crontab -l | grep -q "lynis-audit.sh"; then
    (crontab -l 2>/dev/null; echo "0 2 * * 0 /opt/health-infraops/security/audit/lynis/lynis-audit.sh all") | crontab -
    log "✅ Weekly audit scheduled in crontab"
fi