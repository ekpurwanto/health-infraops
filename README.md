# 🏥 Health InfraOps — eHealth Infrastructure Optimization

This project simulates a real-world **System Administrator / DevOps** environment for healthcare SaaS systems such as **eClinic** and **ePuskesmas**.  
It demonstrates infrastructure setup, monitoring, CI/CD, backup automation, and security hardening.

---

## 🚀 Features
- Dockerized infrastructure (App + DB + Monitoring)
- Prometheus + Grafana monitoring stack
- Automated backups to local or S3
- CI/CD deployment with GitHub Actions
- Linux security hardening (firewall, fail2ban, SSH key)
- Disaster recovery simulation
- Infrastructure documentation and diagrams

---

## ⚙️ Stack
| Layer | Tools |
|--------|--------|
| OS | Ubuntu 22.04 |
| Web Server | Nginx |
| Database | PostgreSQL |
| Monitoring | Prometheus + Grafana |
| Logging | ELK Stack (optional) |
| CI/CD | GitHub Actions |
| Backup | Bash + Cron + S3 |
| Security | UFW, Fail2Ban, SSH Key |

---

## 🧩 Quick Start
```bash
git clone https://github.com/<username>/health-infraops.git
cd health-infraops/infrastructure
docker-compose up -d
