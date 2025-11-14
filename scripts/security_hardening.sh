#!/bin/bash
echo "🔒 Starting security hardening..."

# Disable root SSH login
sudo sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# Enable firewall
sudo ufw allow 22,80,443/tcp
sudo ufw --force enable

# Install Fail2Ban
sudo apt update && sudo apt install fail2ban -y
sudo systemctl enable fail2ban --now

echo "✅ Security hardening complete!"
