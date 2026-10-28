output "vm_ids" {
  description = "Storage VM IDs by node key."
  value       = module.storage_node.vm_ids
}

output "storage_node_ips" {
  description = "IPs of the storage nodes."
  value       = module.storage_node.storage_node_ips
}
