🖥 Health-InfraOps
Healthcare Infrastructure & Operations Simulation for e-Clinic / e-Puskesmas System
<p align="center"> <img src="https://img.shields.io/badge/Status-In_Progress-blue" /> <img src="https://img.shields.io/badge/Infrastructure-Virtualization-orange" /> <img src="https://img.shields.io/badge/Monitoring-Zabbix%20%7C%20Grafana-green" /> <img src="https://img.shields.io/badge/Environment-Production%20Simulation-red" /> </p> <p align="center"> <img src="https://img.shields.io/github/stars/username/health-infraops?style=social" /> <img src="https://img.shields.io/github/forks/username/health-infraops?style=social" /> </p>
🩺 Project Overview

Health-InfraOps adalah proyek simulasi data center dan infrastruktur operasional untuk layanan kesehatan digital seperti eClinic dan ePuskesmas, dirancang sebagai portofolio profesional System Administrator / InfraOps / DevOps Engineer.
Fokus proyek ini meliputi virtualisasi server, keamanan jaringan, cluster database, monitoring, backup, disaster recovery, dan automation.

🧱 Tech Stack
Layer	Technology
Hypervisor	Proxmox VE / VMware / VirtualBox
OS Server	Ubuntu Server, Debian, Windows Server
Network Services	DHCP, DNS, VPN, VLAN, HAProxy, Nginx
Database	PostgreSQL High-Availability Cluster
Monitoring	Zabbix, Prometheus, Grafana
Backup	Proxmox Backup Server / Ceph
Automation	Ansible, Bash
Security	IPtables, Fail2Ban, LDAP / AD
Testing	k6, Apache Benchmark
🖧 Architecture Diagram

Simulasi arsitektur data center skala enterprise

<p align="center"> <img src="https://raw.githubusercontent.com/ekpurwanto/health-infraops/main/00-docs/architecture-diagram.png" width="720"/> </p>
                  ┌──────────────┐
                  │   INTERNET    │
                  └───────┬───────┘
                          │
                     ┌────▼─────┐
                     │  LB / DMZ │   (HAProxy / Proxy)
                     └────┬─────┘
    ┌─────────────────────┼──────────────────────┐
    │                     │                      │
┌───▼───────┐      ┌──────▼────────┐     ┌──────▼─────────┐
│ APP-01    │      │ DB-CLUSTER     │     │ MONITORING      │
│ Backend   │      │ PostgreSQL HA  │     │ Zabbix + Grafana │
└───────────┘      └────────────────┘     └──────────────────┘

Network Segmentation
VLAN10 - PROD
VLAN20 - DB
VLAN30 - DMZ
VLAN40 - MGMT
VLAN50 - BACKUP

📂 Repository Structure
health-infraops/
├── 00-docs/
├── 01-lab-design/
├── 02-hypervisor-setup/
├── 03-vm-configuration/
├── 04-networking-security/
├── 05-services-setup/
├── 06-monitoring-observability/
├── 07-backup-dr/
├── 08-ci-cd-devops/
├── 09-health-app-simulation/
└── 10-reports/

⚙️ Virtual Machines Setup
VM	OS	Spec	Role
VM-LB-01	Ubuntu	2 CPU / 4GB	Load Balancer
VM-APP-01	Ubuntu	4 CPU / 8GB	Backend App
VM-DB-CL-01	Ubuntu	8 CPU / 32GB	HA PostgreSQL
VM-MON-01	Debian	4 CPU / 8GB	Zabbix + Grafana
VM-AD-01	Win Server	2 CPU / 4GB	LDAP / AD Domain
📦 Features

✔ Multi-server deployment
✔ VLAN & network segmentation
✔ Load balancing & reverse proxy
✔ High-Availability PostgreSQL cluster
✔ Centralized monitoring
✔ Backup & Disaster Recovery test
✔ Automated server provisioning

🧪 Testing & Benchmark
k6 run load-test.js

📄 Reports Included
Report	File
Monthly SLA	/10-reports/uptime-sla-report.pdf
Incident Log	/10-reports/incident-log.xlsx
Disaster Recovery Report	/07-backup-dr/full-dr-test-report.md
🚀 Getting Started
git clone https://github.com/ekpurwanto/health-infraops.git
cd health-infraops


Install VM sesuai panduan pada folder:

/02-hypervisor-setup

🔗 Connect & Collaboration

📧 Email : your.email@example.com

🔗 LinkedIn : https://linkedin.com/in/ekopurwanto
📦 GitHub : https://github.com/ekpurwanto
