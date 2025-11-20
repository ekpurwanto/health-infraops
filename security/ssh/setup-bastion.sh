#!/bin/bash
# security/ssh/setup-bastion.sh

echo "🔒 Setting up Bastion Host Security"

# Update SSH configuration
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

cat > /etc/ssh/sshd_config << EOF
Port 2222
Protocol 2
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AllowUsers deploy admin
ClientAliveInterval 300
ClientAliveCountMax 2
MaxAuthTries 3
EOF

# Configure fail2ban
apt install -y fail2ban

cat > /etc/fail2ban/jail.local << EOF
[sshd]
enabled = true
port = 2222
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF

# Restart services
systemctl restart ssh
systemctl enable fail2ban
systemctl start fail2ban

echo "✅ Bastion host security configured!"