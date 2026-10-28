locals {
  ansible_inventory_path = "${var.ansible.path}/inventory.d/10-cluster.ini"
}

resource "local_file" "ansible_inventory" {
  count = var.ansible.enabled ? 1 : 0

  content = templatefile("${path.module}/ansible_templates/inventory.tpl", {
    nodes                = local.nodes_normalized
    ssh_private_key_path = local.ssh_private_key_path
    control_plane_ip     = local.control_plane_ip
    vm_user              = var.vm_user
    distribution         = var.distribution
    cluster_cidr         = var.cluster_cidr
    service_cidr         = var.service_cidr
  })

  filename        = local.ansible_inventory_path
  file_permission = "0644"
}
