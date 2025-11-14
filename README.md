🖥 Health-InfraOps
Healthcare Infrastructure & Operations Simulation for klinik online System

Proyek ini mensimulasikan infrastruktur data center untuk sistem layanan kesehatan berbasis web, seperti klinik atau layanan kesehatan. Tujuan proyek adalah menunjukkan kemampuan System Administrator / InfraOps / DevOps dalam membangun dan mengelola virtual infrastructure, networking, security, monitoring, dan disaster recovery.

🎯 Project Objectives

Membangun simulasi data center menggunakan virtual machine hypervisor

Menjalankan multi-server environment (APP, DB, Proxy, AD, Monitoring)

Menerapkan network security, VLAN segmentation, firewall, dan VPN

Deploy cluster database, load balancing, monitoring, dan backup

Integrasi automation & observability untuk production-grade system

🧱 Tech Stack
Layer	Tools / Technology
Hypervisor	Proxmox VE / VMware / VirtualBox / Hyper-V
OS Server	Ubuntu Server, Debian, Windows Server
Networking	VLAN, DHCP, DNS, VPN, HAProxy, Nginx
Database	PostgreSQL HA Cluster
Monitoring	Zabbix, Prometheus, Grafana
Backup & Storage	Proxmox Backup Server / Ceph
Automation	Ansible, Bash scripting
Security	Firewall IPtables / Fortigate rules
Load Test	k6 / Apache Benchmark
🏗 Infrastructure Topology
                  ┌──────────────┐
                  │  INTERNET     │
                  └──────┬───────┘
                         │
                   ┌─────▼──────┐
                   │  DMZ / LB   │  (HAProxy / Nginx)
                   └─────┬──────┘
      ┌──────────────────┼───────────────────┐
      │                  │                   │
┌─────▼────┐      ┌─────▼──────┐      ┌─────▼─────┐
│  APP-01  │      │  DB-CL-01   │      │ MONITORING │
│ Backend  │      │ PostgreSQL  │      │ Zabbix     │
└──────────┘      └─────────────┘      └────────────┘

VLAN Segmentation
VLAN10 - PROD
VLAN20 - DB
VLAN30 - DMZ
VLAN40 - MGMT
VLAN50 - BACKUP

🗂 Repository Structure
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

⚙️ Virtual Machines Specification
VM	OS	Spesifikasi	Fungsi
VM-APP-01	Ubuntu 22.04	4 vCPU / 8GB RAM	Backend aplikasi
VM-DB-CL-01	Ubuntu	8 vCPU / 32GB	PostgreSQL Cluster
VM-LB-01	Ubuntu	2 vCPU / 4GB	HAProxy / Reverse Proxy
VM-AD-01	Win Server	2 vCPU / 4GB	AD / LDAP
VM-MON-01	Debian	4 vCPU / 8GB	Zabbix + Prometheus + Grafana
📊 Monitoring Dashboard

Uptime Monitoring

CPU/RAM/Storage metrics

Database & service health

SLA monthly report

📦 Key Deliverables
Deliverable	Status
Architecture diagram (.drawio)	✔
VM build & configuration	✔
Monitoring with Zabbix + Grafana	✔
Backup & Disaster Recovery test	✔
Load testing results	✔
Documentation PDF	✔
🧪 Demo & Test
Load Testing Example
k6 run load-test.js

📄 Reports
Report	File
Incident Log	/10-reports/incident-log.xlsx
DR Testing Report	/07-backup-dr/full-dr-test-report.md
SLA Uptime Report	/10-reports/uptime-sla-report.pdf
🚀 How to Use This Project
git clone https://github.com/<username>/health-infraops.git
cd health-infraops


Ikuti step instalasi dalam folder /02-hypervisor-setup

📌 Future Improvements

Kubernetes migration

Zero Trust access control

Implement Ceph distributed storage

🙌 Support & Connect

Jika ingin berkolaborasi atau membutuhkan file full OVF:
📧 Email : ekpurwanto@gmail.com

🔗 LinkedIn : https://linkedin.com/in/
<username>
