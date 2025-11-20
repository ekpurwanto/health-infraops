# Health-InfraOps Network Module
# VLAN and Network Infrastructure Configuration

# Proxmox Network Configuration
resource "proxmox_virtual_environment_network_linux_bridge" "health_infraops_vlans" {
  for_each = var.vlans

  node_name = var.proxmox_node
  name      = "vmbr0.${each.value.vlan_id}"

  address   = each.value.gateway
  gateway   = each.value.gateway
  autostart = true

  # VLAN configuration
  vlan {
    tag = each.value.vlan_id
  }

  # Bridge configuration
  bridge {
    ports = []
  }
}

# Firewall Rules for VLANs
resource "proxmox_virtual_environment_firewall_rules" "health_infraops_firewall" {
  node_name = var.proxmox_node

  dynamic "rule" {
    for_each = var.firewall_rules
    content {
      type    = rule.value.type
      action  = rule.value.action
      comment = rule.value.comment
      dest    = rule.value.dest
      dport   = rule.value.dport
      proto   = rule.value.proto
      source  = rule.value.source
      sport   = rule.value.sport
    }
  }
}

# IP Sets for Network Groups
resource "proxmox_virtual_environment_firewall_ipset" "health_infraops_ipsets" {
  for_each = var.ip_sets

  node_name = var.proxmox_node
  name      = each.key

  dynamic "cidr" {
    for_each = each.value.cidrs
    content {
      name = cidr.key
      cidr = cidr.value
    }
  }

  comment = each.value.comment
}

# DNS Configuration for Health-InfraOps
resource "null_resource" "dns_configuration" {
  for_each = var.dns_records

  triggers = {
    dns_records = jsonencode(var.dns_records)
  }

  provisioner "local-exec" {
    command = <<EOT
      ssh -i ${var.ssh_private_key_path} ${var.dns_server_user}@${var.dns_server} \
        "/opt/health-infraops/networking/dns/bind9/update-dns.sh add-a ${each.value.hostname} ${each.value.ip_address}"
    EOT
  }
}

# Load Balancer Configuration
resource "proxmox_virtual_environment_vm" "load_balancer" {
  count = var.load_balancer_count

  node_name = var.proxmox_node
  vm_id     = var.load_balancer_start_id + count.index

  # Load Balancer specific configuration
  name        = "lb-${format("%02d", count.index + 1)}.${var.domain}"
  description = "Health-InfraOps Load Balancer ${count.index + 1}"

  # Network configuration for load balancer
  network_device {
    bridge = "vmbr0"
    model  = "virtio"
    tag    = var.dmz_vlan_id
  }

  # Additional management network
  network_device {
    bridge = "vmbr0"
    model  = "virtio"
    tag    = var.management_vlan_id
  }

  # CPU and Memory
  cpu {
    cores   = 2
    sockets = 1
    type    = "x86-64-v2-AES"
  }

  memory {
    dedicated = 2048
  }

  # Disk
  disk {
    datastore_id = "local-lvm"
    file_id      = "local:iso/ubuntu-22.04-server-cloudimg-amd64.img"
    interface    = "scsi0"
    size         = 32
  }

  # Cloud-init
  initialization {
    datastore_id = "local-lvm"

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      username = var.vm_user
      password = var.vm_password
      keys     = [var.ssh_public_key]
    }
  }
}

# Output Load Balancer IPs
resource "null_resource" "load_balancer_dns" {
  count = var.load_balancer_count

  depends_on = [proxmox_virtual_environment_vm.load_balancer]

  provisioner "local-exec" {
    command = <<EOT
      # Wait for VM to get IP
      sleep 30
      
      # Get VM IP (this would need proper implementation with data sources)
      VM_IP=$(pvesh get /nodes/${var.proxmox_node}/qemu/${var.load_balancer_start_id + count.index}/agent/network-get-interfaces | jq -r '.result[] | select(.name=="ens18") | ."ip-addresses"[] | select(."ip-address-type"="ipv4") | ."ip-address"')
      
      # Update DNS
      ssh -i ${var.ssh_private_key_path} ${var.dns_server_user}@${var.dns_server} \
        "/opt/health-infraops/networking/dns/bind9/update-dns.sh add-a lb-${format("%02d", count.index + 1)}.${var.domain} $VM_IP"
    EOT
  }
}