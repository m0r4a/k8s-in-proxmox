# A long-lived SeaweedFS storage VM, meant for its own root and state so a
# cluster `terraform destroy` never reaches it. It clones an existing template.

module "storage_node" {
  source = "../../modules/storage_node"

  vm_user              = var.vm_user
  vm_password          = var.vm_password
  ssh_public_key       = var.ssh_public_key
  ssh_private_key_path = var.ssh_private_key_path
  network_gateway      = var.network_gateway

  proxmox_nodes = {
    server01 = { template_vm_id = 9001, network_bridge = "vmbr0" }
  }

  # Writes ../../../ansible/inventory.d/20-storage.ini.
  ansible = {
    enabled = true
    path    = "../../../ansible"
  }

  nodes = {
    storage1 = { vmid = 301, ip = "10.0.0.30", storage_disk_gb = 200 }
  }
}
