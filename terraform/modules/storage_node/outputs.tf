output "vm_ids" {
  description = "Map of node key -> provisioned VM ID."
  value       = { for key, node in proxmox_virtual_environment_vm.storage : key => node.vm_id }
}

output "storage_node_ips" {
  description = "IPs of the storage nodes."
  value       = [for _, node in local.nodes_normalized : node.ip]
}
