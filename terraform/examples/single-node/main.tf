# One Proxmox host: a template plus one control plane and two workers on it.

module "vm_template" {
  source = "../../modules/vm_template"

  proxmox_node    = "server01"
  template_vm_id  = 9001
  vm_user         = var.vm_user
  ssh_public_keys = [trimspace(file(pathexpand(var.ssh_public_key)))]
}

module "k8s_cluster" {
  source = "../../modules/k8s_cluster"

  distribution         = "k3s"
  vm_user              = var.vm_user
  vm_password          = var.vm_password
  ssh_public_key       = var.ssh_public_key
  ssh_private_key_path = var.ssh_private_key_path
  network_gateway      = var.network_gateway

  # A single Proxmox node, so the VMs below do not need to name it.
  proxmox_nodes = {
    server01 = { template_vm_id = module.vm_template.template_vm_id, network_bridge = "vmbr0" }
  }

  # Writes ../../../ansible/inventory.d/10-cluster.ini for site.yml.
  ansible = {
    enabled = true
    path    = "../../../ansible"
  }

  nodes = {
    control-plane = { vmid = 201, role = "control-plane", ip = "10.0.0.10", cores = 2, memory = 3072 }
    worker1       = { vmid = 202, role = "worker", ip = "10.0.0.11" }
    worker2       = { vmid = 203, role = "worker", ip = "10.0.0.12" }
  }
}
