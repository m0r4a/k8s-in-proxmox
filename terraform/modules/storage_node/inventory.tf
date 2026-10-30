locals {
  storage_inventory_path = "${var.ansible.path}/inventory.d/20-storage.ini"
}

resource "local_file" "storage_inventory" {
  count = var.ansible.enabled ? 1 : 0

  content = templatefile("${path.module}/ansible_templates/storage_inventory.tpl", {
    nodes                = local.nodes_normalized
    ssh_private_key_path = local.ssh_private_key_path
    vm_user              = var.vm_user
  })

  filename        = local.storage_inventory_path
  file_permission = "0644"
}
