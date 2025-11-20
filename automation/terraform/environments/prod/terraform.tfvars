# Health-InfraOps Production Environment Configuration

# Proxmox Authentication
proxmox_token_id = "terraform@pve!health-infraops-token"
proxmox_token_secret = "your-proxmox-token-secret-here"

# SSH Configuration
ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC... health-infraops-admin"

# VM Configuration
vm_password = "SecurePassword123!"

# Infrastructure Scale
app_server_count = 4
db_server_count = 2
load_balancer_count = 2
monitoring_server_count = 1
dns_server_count = 2

# Resource Sizing
app_server_cores = 4
app_server_memory = 4096
app_server_disk = "50G"

db_server_cores = 4
db_server_memory = 8192
db_server_disk = "100G"

load_balancer_cores = 2
load_balancer_memory = 2048
load_balancer_disk = "32G"

monitoring_server_cores = 4
monitoring_server_memory = 4096
monitoring_server_disk = "100G"

# Network Configuration
production_vlan_id = 10
database_vlan_id = 20
dmz_vlan_id = 30
management_vlan_id = 40
backup_vlan_id = 50

# DNS Configuration
dns_servers = ["8.8.8.8", "1.1.1.1"]
domain = "infokes.co.id"

# Backup Configuration
backup_retention_days = 30
backup_schedule = "0 2 * * *"

# Monitoring Configuration
monitoring_retention_days = 90
alerting_enabled = true

# Security Configuration
firewall_enabled = true
fail2ban_enabled = true
auditd_enabled = true
