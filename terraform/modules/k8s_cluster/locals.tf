locals {
  node_hosts = { for key, value in var.nodes : key => coalesce(value.proxmox_node, var.proxmox_node) }

  nodes_normalized = {
    for key, value in var.nodes : key => {
      vmid         = value.vmid
      role         = value.role
      proxmox_node = local.node_hosts[key]
      hostname     = var.cluster_name != "" ? "${var.cluster_name}-${key}" : key
      user         = coalesce(value.user, var.vm_user)
      password     = coalesce(value.password, var.vm_password)
      cores        = coalesce(value.cores, var.cores)
      memory       = coalesce(value.memory, var.memory)
      disk_size_gb = coalesce(value.disk_size_gb, var.disk_size_gb)
      ip           = value.ip
      tags         = distinct(concat(var.tags, [var.distribution, value.role], var.cluster_name != "" ? [var.cluster_name] : []))
      on_boot      = true

      # Template local to the VM's Proxmox node when listed in var.templates,
      # otherwise template_vm_id on var.proxmox_node (needs shared storage).
      template_vm_id = lookup(var.templates, local.node_hosts[key], var.template_vm_id)
      template_node  = contains(keys(var.templates), local.node_hosts[key]) ? local.node_hosts[key] : var.proxmox_node
      network_bridge = lookup(var.network_bridges, local.node_hosts[key], var.network_bridge)
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
