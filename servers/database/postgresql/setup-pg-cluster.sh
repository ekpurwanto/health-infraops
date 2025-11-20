#!/bin/bash
# servers/database/postgresql/setup-pg-cluster.sh

echo "🗄️ Setting up PostgreSQL HA Cluster"

# Install PostgreSQL
sudo apt install -y postgresql postgresql-contrib

# Create cluster configuration
sudo -u postgres pg_createcluster 14 main

# Configure replication
cat > /etc/postgresql/14/main/postgresql.conf << EOF
listen_addresses = '*'
port = 5432
max_connections = 200
shared_buffers = 1GB
wal_level = replica
max_wal_senders = 3
hot_standby = on
EOF

# Configure replication access
echo "host replication replicator 10.0.20.0/24 md5" >> /etc/postgresql/14/main/pg_hba.conf

# Restart PostgreSQL
systemctl restart postgresql

echo "✅ PostgreSQL HA Cluster setup completed!"