module "vm_template" {
  source = "github.com/m0r4a/k8s-in-proxmox//terraform/modules/vm_template?ref=main"

  vm_user        = var.vm_user
  ssh_public_key = var.ssh_public_key

  proxmox_nodes = {
    server01  = { template_vm_id = 9001, network_bridge = "vmbr1" }
    server02 = { template_vm_id = 9002, network_bridge = "vmbr0" }
  }
}

module "k8s_cluster" {
  source = "github.com/m0r4a/k8s-in-proxmox//terraform/modules/k8s_cluster?ref=main"

  distribution         = "none"
  vm_user              = var.vm_user
  vm_password          = var.vm_password
  ssh_public_key       = var.ssh_public_key
  ssh_private_key_path = var.ssh_private_key_path
  network_gateway      = var.network_gateway

  proxmox_nodes = module.vm_template.proxmox_nodes

  ansible = {
    enabled = true
    path    = "../../../ansible"
  }

  nodes = {
    control-plane = { vmid = 201, role = "control-plane", ip = "10.0.0.10", proxmox_node = "server01", cores = 2, memory = 3072 }
    worker1       = { vmid = 202, role = "worker", ip = "10.0.0.11", proxmox_node = "server01", cores = 8, memory = 12288}
    worker2       = { vmid = 203, role = "worker", ip = "10.0.0.12", proxmox_node = "server02", cores = 6, memory = 6656}
    worker3       = { vmid = 204, role = "worker", ip = "10.0.0.13", proxmox_node = "server02", cores = 6, memory = 6656}
  }
}
