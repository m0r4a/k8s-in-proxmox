output "template_vm_id" {
  description = "VM ID of the created template. Pass this to k8s_cluster.template_vm_id."
  value       = proxmox_virtual_environment_vm.template.vm_id
}

output "template_vm_name" {
  description = "Name of the created template."
  value       = proxmox_virtual_environment_vm.template.name
}
