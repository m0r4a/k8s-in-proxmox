# Templates already created by `proxmox_setup.sh --create-template`, which makes
# one per node starting at --template-id (9000 on server01, 9001 on server02).
# No vm_template module here.

module "k8s_cluster" {
  source = "github.com/m0r4a/k8s-in-proxmox//terraform/modules/k8s_cluster?ref=main"

  distribution         = "k3s"
  vm_user              = var.vm_user
  vm_password          = var.vm_password
  ssh_public_key       = var.ssh_public_key
  ssh_private_key_path = var.ssh_private_key_path
  network_gateway      = var.network_gateway
  cluster_name         = "lab"

  proxmox_nodes = {
    server01 = { template_vm_id = 9000 }
    server02 = { template_vm_id = 9001 }
  }

  ansible = {
    enabled = true
    path    = "../../../ansible"
  }

  nodes = {
    cp1 = { vmid = 211, role = "control-plane", ip = "10.0.0.20", proxmox_node = "server01", cores = 2, memory = 3072 }
    w1  = { vmid = 212, role = "worker", ip = "10.0.0.21", proxmox_node = "server01" }
    w2  = { vmid = 213, role = "worker", ip = "10.0.0.22", proxmox_node = "server02" }
  }
}
