# Health-InfraOps Infrastructure Overview

## Executive Summary
Health-InfraOps adalah platform infrastruktur terintegrasi untuk layanan kesehatan yang menyediakan environment development, staging, dan production dengan high availability dan security compliance.

## Architecture Principles
- **High Availability**: Multi-zone deployment dengan load balancing
- **Security First**: Zero-trust architecture dengan encrypted communication
- **Scalability**: Horizontal scaling capabilities untuk semua komponen
- **Disaster Recovery**: Automated backup dan cross-region replication
- **Compliance**: Memenuhi standar HIPAA dan GDPR untuk data kesehatan

## Infrastructure Components

### 1. Virtualization Layer
Proxmox VE Cluster (3 nodes)
├── pve-01.infokes.co.id (Master)
├── pve-02.infokes.co.id (Worker)
└── pve-03.infokes.co.id (Worker)


### 2. Network Architecture
Network Segments:

DMZ Network (192.168.10.0/24) - Public facing services

Application Network (192.168.20.0/24) - Internal applications

Database Network (192.168.30.0/24) - Database servers

Management Network (192.168.40.0/24) - Administration


### 3. Server Components

#### Web Servers
- **Nginx Load Balancers** (2 instances)
  - SSL termination
  - Load balancing dengan health checks
  - WAF (Web Application Firewall)

- **Apache Application Servers** (3 instances)
  - ModSecurity enabled
  - PHP-FPM dengan opcode caching
  - Static content delivery

#### Application Servers
- **Node.js Microservices** (4 instances)
  - PM2 process management
  - Cluster mode enabled
  - Health check endpoints

- **Python API Services** (2 instances)
  - Gunicorn WSGI server
  - Redis caching layer
  - Celery task queue

#### Database Layer
- **MySQL Primary** (Galera Cluster - 3 nodes)
  - Synchronous replication
  - Automated failover
  - Daily backups dengan point-in-time recovery

- **MongoDB Replica Set** (3 nodes)
  - Document storage untuk unstructured data
  - Automated sharding
  - Oplog untuk real-time replication

#### Monitoring Stack
- **Prometheus** - Metrics collection dan alerting
- **Grafana** - Dashboard dan visualization
- **ELK Stack** - Centralized logging
- **Zabbix** - Infrastructure monitoring

### 4. Storage Architecture

#### Ceph Cluster

Ceph Storage (3 nodes)
├── mon-01 - Monitor node
├── osd-01 - Object Storage Daemon (4TB)
├── osd-02 - Object Storage Daemon (4TB)
└── osd-03 - Object Storage Daemon (4TB)


#### NFS Shares
- `/shared/backups` - Backup storage
- `/shared/appdata` - Application data
- `/shared/logs` - Centralized logs

## High Availability Design

### Load Balancing Strategy

web_servers:
  algorithm: least_connections
  health_check: /health
  sticky_sessions: true
  timeout: 30s

app_servers:
  algorithm: round_robin
  health_check: /api/health
  timeout: 60s

## Database High Availability
-- MySQL Galera Cluster Configuration
wsrep_cluster_name="health_infraops"
wsrep_cluster_address="gcomm://192.168.30.11,192.168.30.12,192.168.30.13"
wsrep_sst_method=rsync

## Security Architecture
## Network Security
Firewall Rules: iptables dengan default deny policy

VPN Access: OpenVPN untuk administrative access

Bastion Host: Jump server untuk SSH access

Network Segmentation: Strict separation antara tiers

Application Security
SSL/TLS: End-to-end encryption dengan Let's Encrypt

WAF: ModSecurity rules untuk threat protection

Authentication: JWT tokens dengan refresh mechanism

API Security: Rate limiting dan API keys

Monitoring dan Alerting
Key Metrics

infrastructure:
  - cpu_usage: 85%
  - memory_usage: 90%
  - disk_usage: 80%
  - network_throughput: 1Gbps

applications:
  - response_time: 200ms
  - error_rate: 1%
  - throughput: 1000 req/sec
  - availability: 99.9%


Alert Channels
Slack: Real-time notifications

Email: Daily summary reports

SMS: Critical alerts only

PagerDuty: On-call escalation

## Backup dan Disaster Recovery
## Backup Strategy
full_backup:
  schedule: "0 2 * * 0"  # Every Sunday at 2 AM
  retention: 30 days
  location: "/backups/full"

incremental_backup:
  schedule: "0 2 * * 1-6" # Monday-Saturday at 2 AM
  retention: 7 days
  location: "/backups/incremental"

database_backup:
  schedule: "0 1 * * *"   # Daily at 1 AM
  retention: 14 days
  location: "/backups/database"
