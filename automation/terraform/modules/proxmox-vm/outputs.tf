# Health-InfraOps Proxmox VM Module Outputs

output "vm_ids" {
  description = "List of created VM IDs"
  value       = proxmox_vm_qemu.health_infraops_vm[*].id
}

output "vm_names" {
  description = "List of created VM names"
  value       = proxmox_vm_qemu.health_infraops_vm[*].name
}

output "vm_ipv4_addresses" {
  description = "List of VM IPv4 addresses"
  value       = proxmox_vm_qemu.health_infraops_vm[*].default_ipv4_address
}

output "vm_mac_addresses" {
  description = "List of VM MAC addresses"
  value       = proxmox_vm_qemu.health_infraops_vm[*].default_ipv4_address
}

output "vm_status" {
  description = "List of VM statuses"
  value       = proxmox_vm_qemu.health_infraops_vm[*].status
}

output "vm_disk_size" {
  description = "List of VM disk sizes"
  value       = proxmox_vm_qemu.health_infraops_vm[*].disk
}

output "inventory" {
  description = "Complete inventory of created VMs"
  value = {
    for vm in proxmox_vm_qemu.health_infraops_vm :
    vm.name => {
      id        = vm.id
      ipv4      = vm.default_ipv4_address
      status    = vm.status
      node      = var.proxmox_node
      role      = var.vm_role
      environment = var.environment
    }
  }
}

output "ssh_connection_strings" {
  description = "SSH connection strings for created VMs"
  value = [
    for vm in proxmox_vm_qemu.health_infraops_vm :
    "ssh -i ${var.ssh_private_key_path} ${var.vm_user}@${vm.default_ipv4_address} -p 22"
  ]
}

output "provisioning_log" {
  description = "Path to provisioning log file"
  value       = "${path.module}/vm-creation.log"
}

output "inventory_csv" {
  description = "Path to inventory CSV file"
  value       = "${path.module}/vm-inventory.csv"
}