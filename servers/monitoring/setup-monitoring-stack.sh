#!/bin/bash
# servers/monitoring/setup-monitoring-stack.sh

echo "📊 Setting up Monitoring Stack"

# Install Zabbix Server
wget https://repo.zabbix.com/zabbix/6.4/ubuntu/pool/main/z/zabbix-release/zabbix-release_6.4-1+ubuntu22.04_all.deb
dpkg -i zabbix-release_6.4-1+ubuntu22.04_all.deb
apt update
apt install -y zabbix-server-pgsql zabbix-frontend-php zabbix-apache-conf zabbix-agent

# Install Grafana
wget -q -O - https://packages.grafana.com/gpg.key | apt-key add -
echo "deb https://packages.grafana.com/oss/deb stable main" | tee -a /etc/apt/sources.list.d/grafana.list
apt update
apt install -y grafana

# Start services
systemctl enable zabbix-server zabbix-agent apache2 grafana-server
systemctl start zabbix-server zabbix-agent apache2 grafana-server

echo "✅ Monitoring stack setup completed!"