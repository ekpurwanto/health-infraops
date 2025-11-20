# Health-InfraOps Storage Module
# Storage Infrastructure Configuration

# NFS Server Configuration
resource "proxmox_virtual_environment_vm" "nfs_server" {
  node_name = var.proxmox_node
  vm_id     = var.nfs_server_id

  name        = "nfs-01.${var.domain}"
  description = "Health-InfraOps NFS Storage Server"

  # Network configuration
  network_device {
    bridge = "vmbr0"
    model  = "virtio"
    tag    = var.storage_vlan_id
  }

  # CPU and Memory
  cpu {
    cores   = 4
    sockets = 1
    type    = "x86-64-v2-AES"
  }

  memory {
    dedicated = 4096
  }

  # Storage - Larger disk for NFS
  disk {
    datastore_id = "local-lvm"
    file_id      = "local:iso/ubuntu-22.04-server-cloudimg-amd64.img"
    interface    = "scsi0"
    size         = 100  # 100GB for NFS storage
  }

  # Additional disk for backups
  disk {
    datastore_id = "local-lvm"
    interface    = "scsi1"
    size         = 500  # 500GB for backups
    file_format  = "raw"
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

# Backup Server Configuration
resource "proxmox_virtual_environment_vm" "backup_server" {
  node_name = var.proxmox_node
  vm_id     = var.backup_server_id

  name        = "backup-01.${var.domain}"
  description = "Health-InfraOps Backup Server"

  # Network configuration
  network_device {
    bridge = "vmbr0"
    model  = "virtio"
    tag    = var.storage_vlan_id
  }

  # Management network
  network_device {
    bridge = "vmbr0"
    model  = "virtio"
    tag    = var.management_vlan_id
  }

  # CPU and Memory
  cpu {
    cores   = 4
    sockets = 1
    type    = "x86-64-v2-AES"
  }

  memory {
    dedicated = 8192  # 8GB for backup operations
  }

  # Large disk for backups
  disk {
    datastore_id = "local-lvm"
    file_id      = "local:iso/ubuntu-22.04-server-cloudimg-amd64.img"
    interface    = "scsi0"
    size         = 100  # 100GB OS disk
  }

  # Backup storage disk
  disk {
    datastore_id = "local-lvm"
    interface    = "scsi1"
    size         = 1000  # 1TB for backups
    file_format  = "raw"
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

# Storage Provisioning
resource "null_resource" "nfs_setup" {
  depends_on = [proxmox_virtual_environment_vm.nfs_server]

  connection {
    type        = "ssh"
    user        = var.vm_user
    private_key = file(var.ssh_private_key_path)
    host        = proxmox_virtual_environment_vm.nfs_server.default_ipv4_address
  }

  provisioner "remote-exec" {
    inline = [
      # Install NFS server
      "sudo apt update",
      "sudo apt install -y nfs-kernel-server nfs-common",
      
      # Create export directories
      "sudo mkdir -p /export/{app-data,backups,media,logs,isos}",
      "sudo chown -R nobody:nogroup /export",
      "sudo chmod -R 755 /export",
      
      # Configure NFS exports
      "echo '/export/app-data 10.0.10.0/24(rw,sync,no_subtree_check)' | sudo tee -a /etc/exports",
      "echo '/export/backups 10.0.50.0/24(rw,sync,no_subtree_check)' | sudo tee -a /etc/exports",
      "echo '/export/media 10.0.10.0/24(rw,sync,no_subtree_check)' | sudo tee -a /etc/exports",
      
      # Start NFS server
      "sudo systemctl enable nfs-server",
      "sudo systemctl start nfs-server",
      "sudo exportfs -ra"
    ]
  }
}

resource "null_resource" "backup_setup" {
  depends_on = [proxmox_virtual_environment_vm.backup_server]

  connection {
    type        = "ssh"
    user        = var.vm_user
    private_key = file(var.ssh_private_key_path)
    host        = proxmox_virtual_environment_vm.backup_server.default_ipv4_address
  }

  provisioner "file" {
    source      = "${path.module}/scripts/backup-setup.sh"
    destination = "/tmp/backup-setup.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/backup-setup.sh",
      "sudo /tmp/backup-setup.sh --domain ${var.domain} --environment ${var.environment}"
    ]
  }
}

# Storage DNS Records
resource "null_resource" "storage_dns" {
  depends_on = [
    proxmox_virtual_environment_vm.nfs_server,
    proxmox_virtual_environment_vm.backup_server
  ]

  provisioner "local-exec" {
    command = <<EOT
      # Add NFS server to DNS
      ssh -i ${var.ssh_private_key_path} ${var.dns_server_user}@${var.dns_server} \
        "/opt/health-infraops/networking/dns/bind9/update-dns.sh add-a nfs-01.${var.domain} ${proxmox_virtual_environment_vm.nfs_server.default_ipv4_address}"
      
      # Add backup server to DNS
      ssh -i ${var.ssh_private_key_path} ${var.dns_server_user}@${var.dns_server} \
        "/opt/health-infraops/networking/dns/bind9/update-dns.sh add-a backup-01.${var.domain} ${proxmox_virtual_environment_vm.backup_server.default_ipv4_address}"
    EOT
  }
}

# Output Storage Information
output "nfs_server_ip" {
  description = "NFS server IP address"
  value       = proxmox_virtual_environment_vm.nfs_server.default_ipv4_address
}

output "backup_server_ip" {
  description = "Backup server IP address"
  value       = proxmox_virtual_environment_vm.backup_server.default_ipv4_address
}

output "storage_export_paths" {
  description = "NFS export paths"
  value = {
    app_data = "/export/app-data"
    backups  = "/export/backups"
    media    = "/export/media"
    logs     = "/export/logs"
  }
}