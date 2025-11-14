# 🏗️ System Architecture Overview

**Architecture Layers:**
1. Nginx Web Layer (Docker)
2. PostgreSQL Database Layer
3. Prometheus & Grafana Monitoring Layer
4. Network Bridge (Docker network)
5. Backup Automation (cron job)
6. Security Hardening (firewall, fail2ban)

```mermaid
graph TD
A[Users] --> B[Nginx Container]
B --> C[PostgreSQL DB]
B --> D[Prometheus]
D --> E[Grafana Dashboard]
