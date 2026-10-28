output "vm_ids" {
  description = "Cluster VM IDs by node key."
  value       = module.k8s_cluster.vm_ids
}

output "control_plane_ip" {
  description = "IP of the control-plane node."
  value       = module.k8s_cluster.control_plane_ip
}

output "node_ips" {
  description = "IPs of the cluster members."
  value       = module.k8s_cluster.node_ips
}
