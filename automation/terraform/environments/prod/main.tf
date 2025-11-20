# Health-InfraOps Production Environment
# Infokes Healthcare System - Production Infrastructure

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "2.9.11"
    }
  }

  backend "s3" {
    bucket = "health-infraops-tfstate"
    key    = "production/terraform.tfstate"
    region = "ap-southeast-1"
    
    # For Proxmox backend (alternative)
    # backend "http" {
    #   address = "https://pve-01.infokes.co.id:8006/api2/json/terraform/state"
    #   lock_address = "https://pve-01.infokes.co.id:8006/api2/json/terraform/lock"
    #   username = "terraform@pve"
    #   password = var.proxmox_password
    # }
  }
}

# Provider Configuration
provider "proxmox" {
  pm_api_url          = var.proxmox_api_url
  pm_api_token_id     = var.proxmox_token_id
  pm_api_token_secret = var.proxmox_token_secret
  pm_tls_insecure     = var.proxmox_tls_insecure
  pm_debug            = var.proxmox_debug
}

# Network Infrastructure
module "network" {
  source = "../../modules/network"

  proxmox_node        = var.proxmox_node
  domain              = var.domain
  ssh_public_key      = var.ssh_public_key
  ssh_private_key_path = var.ssh_private_key_path
  dns_server          = var.dns_server
  dns_server_user     = var.dns_server_user

  load_balancer_count    = 2
  load_balancer_start_id = 100
}

# Storage Infrastructure
module "storage" {
  source = "../../modules/storage"

  proxmox_node        = var.proxmox_node
  domain              = var.domain
  ssh_public_key      = var.ssh_public_key
  ssh_private_key_path = var.ssh_private_key_path
  dns_server          = var.dns_server
  dns_server_user     = var.dns_server_user

  nfs_server_id     = 110
  backup_server_id  = 111
  storage_vlan_id   = 50
  management_vlan_id = 40
  environment       = "production"
}

# Load Balancer VMs
module "load_balancers" {
  source = "../../modules/proxmox-vm"

  proxmox_api_url      = var.proxmox_api_url
  proxmox_token_id     = var.proxmox_token_id
  proxmox_token_secret = var.proxmox_token_secret
  proxmox_node         = var.proxmox_node

  vm_name     = "lb"
  vm_role     = "lb"
  vm_count    = 2
  environment = "production"

  vm_cores    = 2
  vm_memory   = 2048
  vm_disk_size = "32G"
  vm_vlan_id  = 30  # DMZ VLAN

  vm_user              = var.vm_user
  vm_password          = var.vm_password
  ssh_public_key       = var.ssh_public_key
  ssh_private_key_path = var.ssh_private_key_path
  dns_server           = var.dns_server
  dns_server_user      = var.dns_server_user
}

# Application Servers
module "app_servers" {
  source = "../../modules/proxmox-vm"

  proxmox_api_url      = var.proxmox_api_url
  proxmox_token_id     = var.proxmox_token_id
  proxmox_token_secret = var.proxmox_token_secret
  proxmox_node         = var.proxmox_node

  vm_name     = "app"
  vm_role     = "app"
  vm_count    = 4
  environment = "production"

  vm_cores    = 4
  vm_memory   = 4096
  vm_disk_size = "50G"
  vm_vlan_id  = 10  # Production VLAN

  vm_user              = var.vm_user
  vm_password          = var.vm_password
  ssh_public_key       = var.ssh_public_key
  ssh_private_key_path = var.ssh_private_key_path
  dns_server           = var.dns_server
  dns_server_user      = var.dns_server_user

  # Additional management network
  vm_additional_networks = [
    {
      bridge  = "vmbr0"
      vlan_id = 40
    }
  ]
}

# Database Servers
module "database_servers" {
  source = "../../modules/proxmox-vm"

  proxmox_api_url      = var.proxmox_api_url
  proxmox_token_id     = var.proxmox_token_id
  proxmox_token_secret = var.proxmox_token_secret
  proxmox_node         = var.proxmox_node

  vm_name     = "db-mysql"
  vm_role     = "db"
  vm_count    = 2
  environment = "production"

  vm_cores    = 4
  vm_memory   = 8192
  vm_disk_size = "100G"
  vm_vlan_id  = 20  # Database VLAN

  vm_user              = var.vm_user
  vm_password          = var.vm_password
  ssh_public_key       = var.ssh_public_key
  ssh_private_key_path = var.ssh_private_key_path
  dns_server           = var.dns_server
  dns_server_user      = var.dns_server_user
}

# Monitoring Servers
module "monitoring_servers" {
  source = "../../modules/proxmox-vm"

  proxmox_api_url      = var.proxmox_api_url
  proxmox_token_id     = var.proxmox_token_id
  proxmox_token_secret = var.proxmox_token_secret
  proxmox_node         = var.proxmox_node

  vm_name     = "mon"
  vm_role     = "mon"
  vm_count    = 1
  environment = "production"

  vm_cores    = 4
  vm_memory   = 4096
  vm_disk_size = "100G"
  vm_vlan_id  = 40  # Management VLAN

  vm_user              = var.vm_user
  vm_password          = var.vm_password
  ssh_public_key       = var.ssh_public_key
  ssh_private_key_path = var.ssh_private_key_path
  dns_server           = var.dns_server
  dns_server_user      = var.dns_server_user
}

# DNS Servers
module "dns_servers" {
  source = "../../modules/proxmox-vm"

  proxmox_api_url      = var.proxmox_api_url
  proxmox_token_id     = var.proxmox_token_id
  proxmox_token_secret = var.proxmox_token_secret
  proxmox_node         = var.proxmox_node

  vm_name     = "dns"
  vm_role     = "dns"
  vm_count    = 2
  environment = "production"

  vm_cores    = 2
  vm_memory   = 2048
  vm_disk_size = "32G"
  vm_vlan_id  = 40  # Management VLAN

  vm_user              = var.vm_user
  vm_password          = var.vm_password
  ssh_public_key       = var.ssh_public_key
  ssh_private_key_path = var.ssh_private_key_path
  dns_server           = var.dns_server
  dns_server_user      = var.dns_server_user
}

# Outputs for Ansible Inventory
output "load_balancer_ips" {
  description = "Load balancer IP addresses"
  value       = module.load_balancers.vm_ipv4_addresses
}

output "app_server_ips" {
  description = "Application server IP addresses"
  value       = module.app_servers.vm_ipv4_addresses
}

output "database_server_ips" {
  description = "Database server IP addresses"
  value       = module.database_servers.vm_ipv4_addresses
}

output "monitoring_server_ips" {
  description = "Monitoring server IP addresses"
  value       = module.monitoring_servers.vm_ipv4_addresses
}

output "dns_server_ips" {
  description = "DNS server IP addresses"
  value       = module.dns_servers.vm_ipv4_addresses
}

output "nfs_server_ip" {
  description = "NFS server IP address"
  value       = module.storage.nfs_server_ip
}

output "backup_server_ip" {
  description = "Backup server IP address"
  value       = module.storage.backup_server_ip
}

# Generate Ansible Inventory
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/inventory.tpl", {
    load_balancers = module.load_balancers.vm_ipv4_addresses
    app_servers    = module.app_servers.vm_ipv4_addresses
    db_servers     = module.database_servers.vm_ipv4_addresses
    mon_servers    = module.monitoring_servers.vm_ipv4_addresses
    dns_servers    = module.dns_servers.vm_ipv4_addresses
    nfs_server     = module.storage.nfs_server_ip
    backup_server  = module.storage.backup_server_ip
    domain         = var.domain
  })
  filename = "${path.module}/../../ansible/inventory/production.generated"
}

# Generate Infrastructure Documentation
resource "local_file" "infrastructure_docs" {
  content = templatefile("${path.module}/templates/infrastructure.md.tpl", {
    load_balancers = module.load_balancers.inventory
    app_servers    = module.app_servers.inventory
    db_servers     = module.database_servers.inventory
    mon_servers    = module.monitoring_servers.inventory
    dns_servers    = module.dns_servers.inventory
    nfs_server     = module.storage.nfs_server_ip
    backup_server  = module.storage.backup_server_ip
    created_at     = timestamp()
  })
  filename = "${path.module}/infrastructure-${timestamp()}.md"
}