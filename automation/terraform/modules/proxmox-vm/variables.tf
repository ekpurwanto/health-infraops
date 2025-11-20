# Health-InfraOps Proxmox VM Module Variables

# Proxmox Connection
variable "proxmox_api_url" {
  description = "Proxmox API URL"
  type        = string
  default     = "https://10.0.1.10:8006/api2/json"
}

variable "proxmox_token_id" {
  description = "Proxmox API token ID"
  type        = string
  sensitive   = true
}

variable "proxmox_token_secret" {
  description = "Proxmox API token secret"
  type        = string
  sensitive   = true
}

variable "proxmox_tls_insecure" {
  description = "Whether to skip TLS verification"
  type        = bool
  default     = true
}

variable "proxmox_debug" {
  description = "Enable debug mode for Proxmox provider"
  type        = bool
  default     = false
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "pve-01"
}

variable "proxmox_pool" {
  description = "Proxmox resource pool"
  type        = string
  default     = "health-infraops"
}

# VM Configuration
variable "vm_name" {
  description = "Base name for the virtual machine"
  type        = string
}

variable "vm_role" {
  description = "Role of the VM (app, db, lb, mon, etc.)"
  type        = string
  validation {
    condition     = contains(["app", "db", "lb", "mon", "backup", "dns"], var.vm_role)
    error_message = "VM role must be one of: app, db, lb, mon, backup, dns."
  }
}

variable "vm_count" {
  description = "Number of VMs to create"
  type        = number
  default     = 1
}

variable "environment" {
  description = "Environment (production, staging, development)"
  type        = string
  default     = "production"
  validation {
    condition     = contains(["production", "staging", "development"], var.environment)
    error_message = "Environment must be one of: production, staging, development."
  }
}

# VM Specifications
variable "vm_cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 2
}

variable "vm_sockets" {
  description = "Number of CPU sockets"
  type        = number
  default     = 1
}

variable "vm_memory" {
  description = "Memory in MB"
  type        = number
  default     = 4096
}

variable "vm_balloon_memory" {
  description = "Balloon memory in MB"
  type        = number
  default     = 0
}

# Disk Configuration
variable "vm_disk_type" {
  description = "Disk type (scsi, virtio, etc.)"
  type        = string
  default     = "scsi"
}

variable "vm_disk_storage" {
  description = "Storage pool for disk"
  type        = string
  default     = "local-lvm"
}

variable "vm_disk_size" {
  description = "Disk size in GB"
  type        = string
  default     = "32G"
}

variable "vm_disk_format" {
  description = "Disk format (raw, qcow2, etc.)"
  type        = string
  default     = "raw"
}

variable "vm_disk_ssd" {
  description = "Enable SSD emulation"
  type        = bool
  default     = true
}

# Network Configuration
variable "vm_network_bridge" {
  description = "Network bridge to use"
  type        = string
  default     = "vmbr0"
}

variable "vm_vlan_id" {
  description = "VLAN ID for the primary network"
  type        = number
  default     = 10
}

variable "vm_additional_networks" {
  description = "Additional network interfaces"
  type = list(object({
    bridge  = string
    vlan_id = number
  }))
  default = []
}

# Cloud-Init Configuration
variable "vm_user" {
  description = "Default user for cloud-init"
  type        = string
  default     = "admin"
}

variable "vm_password" {
  description = "Default password for cloud-init"
  type        = string
  sensitive   = true
  default     = "HealthInfraOps2023!"
}

variable "vm_domain" {
  description = "Domain for the VM"
  type        = string
  default     = "infokes.co.id"
}

variable "vm_timezone" {
  description = "Timezone for the VM"
  type        = string
  default     = "Asia/Jakarta"
}

variable "ssh_public_key" {
  description = "SSH public key for cloud-init"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key for provisioning"
  type        = string
  default     = "~/.ssh/health-infraops-admin.key"
}

variable "vm_dns_servers" {
  description = "DNS servers for the VM"
  type        = list(string)
  default     = ["8.8.8.8", "1.1.1.1"]
}

variable "vm_packages" {
  description = "Additional packages to install via cloud-init"
  type        = list(string)
  default = [
    "curl",
    "wget",
    "git",
    "vim",
    "htop",
    "net-tools"
  ]
}

# DNS Configuration
variable "dns_server" {
  description = "DNS server to update records"
  type        = string
  default     = "dns-01.infokes.co.id"
}

variable "dns_server_user" {
  description = "User for DNS server access"
  type        = string
  default     = "admin"
}