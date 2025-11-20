# Health-InfraOps Proxmox VM Module
# Infrastructure as Code for Virtual Machines

terraform {
  required_version = ">= 1.0"
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "2.9.11"
    }
  }
}

# Proxmox Provider Configuration
provider "proxmox" {
  pm_api_url          = var.proxmox_api_url
  pm_api_token_id     = var.proxmox_token_id
  pm_api_token_secret = var.proxmox_token_secret
  pm_tls_insecure     = var.proxmox_tls_insecure
  pm_debug            = var.proxmox_debug
}

# Cloud-Init Configuration
data "template_file" "cloud_init_user_data" {
  template = file("${path.module}/templates/cloud-init.yaml")
  vars = {
    hostname        = var.vm_name
    domain          = var.vm_domain
    ssh_public_key  = var.ssh_public_key
    user            = var.vm_user
    password        = var.vm_password
    timezone        = var.vm_timezone
    dns_servers     = jsonencode(var.vm_dns_servers)
    packages        = jsonencode(var.vm_packages)
  }
}

# Proxmox VM Resource
resource "proxmox_vm_qemu" "health_infraops_vm" {
  count = var.vm_count

  # Basic Configuration
  name        = "${var.vm_name}-${format("%02d", count.index + 1)}"
  desc        = "Health-InfraOps ${var.vm_role} - ${var.environment}"
  target_node = var.proxmox_node
  pool        = var.proxmox_pool
  tags        = "health-infraops,${var.vm_role},${var.environment}"

  # VM Specifications
  agent     = 1
  cores     = var.vm_cores
  sockets   = var.vm_sockets
  memory    = var.vm_memory
  balloon   = var.vm_balloon_memory
  cpu       = "x86-64-v2-AES"
  scsihw    = "virtio-scsi-single"

  # Disk Configuration
  disk {
    type    = var.vm_disk_type
    storage = var.vm_disk_storage
    size    = var.vm_disk_size
    format  = var.vm_disk_format
    ssd     = var.vm_disk_ssd
    discard = "on"
  }

  # Network Configuration
  network {
    model  = "virtio"
    bridge = var.vm_network_bridge
    tag    = var.vm_vlan_id
  }

  # Additional Network Interfaces
  dynamic "network" {
    for_each = var.vm_additional_networks
    content {
      model  = "virtio"
      bridge = network.value.bridge
      tag    = network.value.vlan_id
    }
  }

  # Cloud-Init Configuration
  cicustom = "user=local:snippets/cloud-init-${var.vm_name}-${format("%02d", count.index + 1)}.yaml"

  # OS Configuration
  os_type   = "cloud-init"
  cloudinit_cdrom_storage = "local"

  # Boot Configuration
  bootdisk = "scsi0"
  boot     = "order=scsi0;ide2;net0"

  # Serial Console
  serial {
    id   = 0
    type = "socket"
  }

  # Lifecycle Configuration
  lifecycle {
    ignore_changes = [
      network,
      disk,
      desc
    ]
    create_before_destroy = true
  }

  # Connection for Provisioners
  connection {
    type        = "ssh"
    user        = var.vm_user
    private_key = file(var.ssh_private_key_path)
    host        = self.default_ipv4_address
    timeout     = "10m"
  }

  # Provisioning - Base Configuration
  provisioner "remote-exec" {
    inline = [
      "sudo hostnamectl set-hostname ${self.name}",
      "echo '${self.name}' | sudo tee /etc/hostname",
      "sudo systemctl restart systemd-hostname"
    ]
  }

  # Provisioning - Health-InfraOps Specific
  provisioner "file" {
    source      = "${path.module}/scripts/health-infraops-bootstrap.sh"
    destination = "/tmp/health-infraops-bootstrap.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/health-infraops-bootstrap.sh",
      "sudo /tmp/health-infraops-bootstrap.sh --role ${var.vm_role} --environment ${var.environment}"
    ]
  }
}

# Cloud-Init Snippet Resource
resource "proxmox_vm_qemu" "cloud_init_snippet" {
  count = var.vm_count

  provisioner "file" {
    content     = data.template_file.cloud_init_user_data.rendered
    destination = "/var/lib/vz/snippets/cloud-init-${var.vm_name}-${format("%02d", count.index + 1)}.yaml"
  }
}

# IP Address Management
resource "null_resource" "ip_configuration" {
  count = var.vm_count

  triggers = {
    vm_id = proxmox_vm_qemu.health_infraops_vm[count.index].id
  }

  provisioner "local-exec" {
    command = <<EOT
      echo "VM ${proxmox_vm_qemu.health_infraops_vm[count.index].name} created with IP: ${proxmox_vm_qemu.health_infraops_vm[count.index].default_ipv4_address}" >> ${path.module}/vm-creation.log
      echo "${proxmox_vm_qemu.health_infraops_vm[count.index].name},${proxmox_vm_qemu.health_infraops_vm[count.index].default_ipv4_address},${var.vm_role}" >> ${path.module}/vm-inventory.csv
    EOT
  }
}

# DNS Registration
resource "null_resource" "dns_registration" {
  count = var.vm_count

  triggers = {
    vm_ip = proxmox_vm_qemu.health_infraops_vm[count.index].default_ipv4_address
  }

  provisioner "local-exec" {
    command = <<EOT
      # Update DNS records for the new VM
      ssh -i ${var.ssh_private_key_path} ${var.dns_server_user}@${var.dns_server} \
        "/opt/health-infraops/networking/dns/bind9/update-dns.sh add-a ${proxmox_vm_qemu.health_infraops_vm[count.index].name} ${proxmox_vm_qemu.health_infraops_vm[count.index].default_ipv4_address}"
    EOT
  }

  depends_on = [proxmox_vm_qemu.health_infraops_vm]
}