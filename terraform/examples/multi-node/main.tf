# Two Proxmox nodes in one Proxmox cluster: one template per node (templates on
# local storage are only visible to their own node) and VMs placed per node.

locals {
  # Proxmox node => template VM ID (unique across the Proxmox cluster).
  proxmox_nodes = {
    server01 = 9001
    server02 = 9002
  }
}

module "vm_template" {
  for_each = local.proxmox_nodes
  source   = "../../modules/vm_template"

  proxmox_node    = each.key
  template_vm_id  = each.value
  vm_user         = var.vm_user
  ssh_public_keys = [trimspace(file(pathexpand(var.ssh_public_key)))]
}

module "k8s_cluster" {
  source = "../../modules/k8s_cluster"

  distribution         = "k3s"
  proxmox_node         = "server01"
  template_vm_id       = module.vm_template["server01"].template_vm_id
  templates            = { for node, t in module.vm_template : node => t.template_vm_id }
  vm_user              = var.vm_user
  vm_password          = var.vm_password
  ssh_public_key       = var.ssh_public_key
  ssh_private_key_path = var.ssh_private_key_path
  network_gateway      = var.network_gateway

  # The VM network is vmbr1 on server01 but vmbr0 on server02.
  network_bridge  = "vmbr1"
  network_bridges = { server02 = "vmbr0" }

  ansible = {
    enabled = true
    path    = "../../../ansible"
  }

  nodes = {
    control-plane = { vmid = 201, role = "control-plane", ip = "10.0.0.10", cores = 2, memory = 3072 }
    worker1       = { vmid = 202, role = "worker", ip = "10.0.0.11" }
    worker2       = { vmid = 203, role = "worker", ip = "10.0.0.12", proxmox_node = "server02" }
  }
}
