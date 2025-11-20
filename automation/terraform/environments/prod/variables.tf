# Health-InfraOps Production Environment Variables

# Proxmox Configuration
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

# Infrastructure Configuration
variable "domain" {
  description = "Domain name for the infrastructure"
  type        = string
  default     = "infokes.co.id"
}

# VM Configuration
variable "vm_user" {
  description = "Default user for VMs"
  type        = string
  default     = "admin"
}

variable "vm_password" {
  description = "Default password for VMs"
  type        = string
  sensitive   = true
  default     = "HealthInfraOps2023!"
}

# SSH Configuration
variable "ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key"
  type        = string
  default     = "~/.ssh/health-infraops-admin.key"
}

# DNS Configuration
variable "dns_server" {
  description = "DNS server hostname"
  type        = string
  default     = "dns-01.infokes.co.id"
}

variable "dns_server_user" {
  description = "DNS server user"
  type        = string
  default     = "admin"
}

# Environment Specific
variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}