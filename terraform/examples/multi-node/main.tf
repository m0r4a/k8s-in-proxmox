# Two Proxmox nodes in one Proxmox cluster: one template per node (templates on
# local storage are only visible to their own node) and VMs placed per node.

module "vm_template" {
  source = "../../modules/vm_template"

  vm_user        = var.vm_user
  ssh_public_key = var.ssh_public_key

  # Everything that differs between Proxmox nodes. Template VM IDs must be
  # unique across the Proxmox cluster. A key is the Proxmox node name unless
  # proxmox_node_name says otherwise, as for myOtherServer.
  proxmox_nodes = {
    server01      = { template_vm_id = 9001, network_bridge = "vmbr1" }
    myOtherServer = { proxmox_node_name = "server02", template_vm_id = 9002, network_bridge = "vmbr0" }
  }
}

module "k8s_cluster" {
  source = "../../modules/k8s_cluster"

  distribution         = "k3s"
  vm_user              = var.vm_user
  vm_password          = var.vm_password
  ssh_public_key       = var.ssh_public_key
  ssh_private_key_path = var.ssh_private_key_path
  network_gateway      = var.network_gateway

  # The same nodes as the templates, available once those exist.
  proxmox_nodes = module.vm_template.proxmox_nodes

  ansible = {
    enabled = true
    path    = "../../../ansible"
  }

  nodes = {
    control-plane = { vmid = 201, role = "control-plane", ip = "10.0.0.10", proxmox_node = "server01", cores = 2, memory = 3072 }
    worker1       = { vmid = 202, role = "worker", ip = "10.0.0.11", proxmox_node = "server01" }
    worker2       = { vmid = 203, role = "worker", ip = "10.0.0.12", proxmox_node = "myOtherServer" }
  }
}
