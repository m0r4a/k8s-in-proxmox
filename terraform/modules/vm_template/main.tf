locals {
  vendor_cloud_config = <<-EOF
    #cloud-config
    packages:
      - qemu-guest-agent
    runcmd:
      - systemctl enable --now qemu-guest-agent
  EOF

  # Entries with template_node reuse a template from another entry.
  templates = {
    for key, host in var.proxmox_nodes : key => merge(host, {
      node_name = coalesce(host.proxmox_node_name, key)
    }) if host.template_node == null
  }

  is_public_ssh_key_path = var.ssh_public_key != null && can(regex("^[~./]", var.ssh_public_key))
  ssh_public_keys = var.ssh_public_key == null ? [] : [
    local.is_public_ssh_key_path ? trimspace(file(pathexpand(var.ssh_public_key))) : trimspace(var.ssh_public_key)
  ]
}

resource "proxmox_virtual_environment_file" "vendor_cloud_config" {
  for_each = local.templates

  content_type = "snippets"
  datastore_id = "local"
  node_name    = each.value.node_name

  source_raw {
    data      = local.vendor_cloud_config
    file_name = "${var.template_name}-vendor.yaml"
  }
}

resource "proxmox_download_file" "cloud_image" {
  for_each = var.image_file_id == null ? local.templates : {}

  content_type        = "import"
  datastore_id        = "local"
  node_name           = each.value.node_name
  overwrite           = true
  overwrite_unmanaged = true

  url       = var.image_url
  file_name = "${var.template_name}.qcow2"
}

resource "proxmox_virtual_environment_vm" "template" {
  for_each = local.templates

  vm_id         = each.value.template_vm_id
  name          = var.template_name
  node_name     = each.value.node_name
  tags          = var.tags
  template      = true
  started       = false
  on_boot       = false
  machine       = "q35"
  bios          = "ovmf"
  scsi_hardware = "virtio-scsi-single"
  boot_order    = ["scsi0"]

  cpu {
    cores = var.cores
    type  = "max"
  }

  memory {
    dedicated = var.memory
  }

  efi_disk {
    datastore_id = each.value.datastore_id
    file_format  = "raw"
    type         = "4m"
  }

  disk {
    datastore_id = each.value.datastore_id
    import_from  = var.image_file_id != null ? var.image_file_id : proxmox_download_file.cloud_image[each.key].id
    interface    = "scsi0"
    iothread     = true
    discard      = "on"
    size         = var.disk_size_gb
  }

  initialization {
    datastore_id = each.value.cloudinit_datastore_id
    upgrade      = false

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      username = var.vm_user
      keys     = local.ssh_public_keys
    }

    vendor_data_file_id = proxmox_virtual_environment_file.vendor_cloud_config[each.key].id
  }

  network_device {
    bridge = each.value.network_bridge
    model  = "virtio"
  }

  serial_device {
    device = "socket"
  }

  agent {
    enabled = false
  }
}
