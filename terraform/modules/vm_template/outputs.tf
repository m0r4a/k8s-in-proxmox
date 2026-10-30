output "template_vm_ids" {
  description = "Template VM ID per proxmox_nodes key, for the entries that got a template."
  value       = { for key, template in proxmox_virtual_environment_vm.template : key => template.vm_id }
}

output "template_vm_name" {
  description = "Name of the templates."
  value       = var.template_name
}

output "proxmox_nodes" {
  description = "The proxmox_nodes input, available once every template exists. Pass it to k8s_cluster or storage_node so their VMs wait for the templates."
  value       = var.proxmox_nodes
  depends_on  = [proxmox_virtual_environment_vm.template]
}
