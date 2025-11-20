# Health-InfraOps Network Module Variables

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "pve-01"
}

variable "vlans" {
  description = "VLAN configuration"
  type = map(object({
    vlan_id  = number
    gateway  = string
    subnet   = string
  }))
  default = {
    production = {
      vlan_id = 10
      gateway = "10.0.10.1/24"
      subnet  = "10.0.10.0/24"
    }
    database = {
      vlan_id = 20
      gateway = "10.0.20.1/24"
      subnet  = "10.0.20.0/24"
    }
    dmz = {
      vlan_id = 30
      gateway = "10.0.30.1/24"
      subnet  = "10.0.30.0/24"
    }
    management = {
      vlan_id = 40
      gateway = "10.0.40.1/24"
      subnet  = "10.0.40.0/24"
    }
    backup = {
      vlan_id = 50
      gateway = "10.0.50.1/24"
      subnet  = "10.0.50.0/24"
    }
  }
}

variable "firewall_rules" {
  description = "Firewall rules for VLANs"
  type = list(object({
    type    = string
    action  = string
    comment = string
    dest    = string
    dport   = string
    proto   = string
    source  = string
    sport   = string
  }))
  default = [
    {
      type    = "in"
      action  = "ACCEPT"
      comment = "SSH from management"
      dest    = ""
      dport   = "2222"
      proto   = "tcp"
      source  = "10.0.40.0/24"
      sport   = ""
    },
    {
      type    = "in"
      action  = "ACCEPT"
      comment = "App from load balancer"
      dest    = "10.0.10.0/24"
      dport   = "3000"
      proto   = "tcp"
      source  = "10.0.30.0/24"
      sport   = ""
    }
  ]
}

variable "ip_sets" {
  description = "IP sets for network groups"
  type = map(object({
    cidrs   = map(string)
    comment = string
  }))
  default = {
    app_servers = {
      cidrs = {
        "app-01" = "10.0.10.11/32"
        "app-02" = "10.0.10.12/32"
        "app-03" = "10.0.10.13/32"
      }
      comment = "Application servers"
    }
    db_servers = {
      cidrs = {
        "db-mysql-01" = "10.0.20.21/32"
        "db-mysql-02" = "10.0.20.22/32"
      }
      comment = "Database servers"
    }
  }
}

variable "dns_records" {
  description = "DNS records to create"
  type = map(object({
    hostname  = string
    ip_address = string
  }))
  default = {
    "infokes.co.id" = {
      hostname  = "infokes.co.id"
      ip_address = "10.0.30.10"
    }
    "www.infokes.co.id" = {
      hostname  = "www.infokes.co.id"
      ip_address = "10.0.30.10"
    }
  }
}

variable "domain" {
  description = "Domain name for the infrastructure"
  type        = string
  default     = "infokes.co.id"
}

variable "load_balancer_count" {
  description = "Number of load balancers to create"
  type        = number
  default     = 2
}

variable "load_balancer_start_id" {
  description = "Starting VM ID for load balancers"
  type        = number
  default     = 100
}

variable "dmz_vlan_id" {
  description = "VLAN ID for DMZ"
  type        = number
  default     = 30
}

variable "management_vlan_id" {
  description = "VLAN ID for management"
  type        = number
  default     = 40
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key"
  type        = string
  default     = "~/.ssh/health-infraops-admin.key"
}

variable "ssh_public_key" {
  description = "SSH public key"
  type        = string
}

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

variable "vm_user" {
  description = "VM default user"
  type        = string
  default     = "admin"
}

variable "vm_password" {
  description = "VM default password"
  type        = string
  sensitive   = true
  default     = "HealthInfraOps2023!"
}