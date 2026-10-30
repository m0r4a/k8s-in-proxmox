locals {
  # With a single Proxmox node, VMs that do not name one go there.
  node_hosts = {
    for key, value in var.nodes : key => value.proxmox_node != null ? value.proxmox_node : one(keys(var.proxmox_nodes))
  }

  # proxmox_nodes keys are names for use in this config; Proxmox sees proxmox_node_name.
  proxmox_node_names = { for key, host in var.proxmox_nodes : key => coalesce(host.proxmox_node_name, key) }

  nodes_normalized = {
    for key, value in var.nodes : key => {
      vmid         = value.vmid
      role         = value.role
      proxmox_node = local.proxmox_node_names[local.node_hosts[key]]
      hostname     = var.cluster_name != "" ? "${var.cluster_name}-${key}" : key
      user         = coalesce(value.user, var.vm_user)
      password     = coalesce(value.password, var.vm_password)
      cores        = coalesce(value.cores, var.cores)
      memory       = coalesce(value.memory, var.memory)
      disk_size_gb = coalesce(value.disk_size_gb, var.disk_size_gb)
      ip           = value.ip
      tags         = distinct(concat(var.tags, [var.distribution, value.role], var.cluster_name != "" ? [var.cluster_name] : []))
      on_boot      = true

      template_vm_id         = var.proxmox_nodes[local.node_hosts[key]].template_vm_id
      template_node          = local.proxmox_node_names[coalesce(var.proxmox_nodes[local.node_hosts[key]].template_node, local.node_hosts[key])]
      network_bridge         = var.proxmox_nodes[local.node_hosts[key]].network_bridge
      datastore_id           = var.proxmox_nodes[local.node_hosts[key]].datastore_id
      cloudinit_datastore_id = var.proxmox_nodes[local.node_hosts[key]].cloudinit_datastore_id
    }
  }

  control_plane_ip = one([
    for _, node in local.nodes_normalized : node.ip
    if node.role == "control-plane"
  ])

  is_public_ssh_key_path = can(regex("^[~./]", var.ssh_public_key))
  ssh_public_key_content = local.is_public_ssh_key_path ? trimspace(file(pathexpand(var.ssh_public_key))) : trimspace(var.ssh_public_key)
  ssh_private_key_path   = replace(var.ssh_private_key_path, ".pub", "")
}
