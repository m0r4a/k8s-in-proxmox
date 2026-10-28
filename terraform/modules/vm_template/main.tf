locals {
  vendor_cloud_config = <<-EOF
    #cloud-config
    packages:
      - qemu-guest-agent
    runcmd:
      - systemctl enable --now qemu-guest-agent
  EOF

  image_file_id = var.image_file_id != null ? var.image_file_id : proxmox_download_file.cloud_image[0].id
}

resource "proxmox_virtual_environment_file" "vendor_cloud_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node

  source_raw {
    data      = local.vendor_cloud_config
    file_name = "${var.template_name}-vendor.yaml"
  }
}

resource "proxmox_download_file" "cloud_image" {
  count = var.image_file_id == null ? 1 : 0

  content_type        = "import"
  datastore_id        = "local"
  node_name           = var.proxmox_node
  overwrite           = true
  overwrite_unmanaged = true

  url       = var.image_url
  file_name = "${var.template_name}.qcow2"
}

resource "proxmox_virtual_environment_vm" "template" {
  vm_id         = var.template_vm_id
  name          = var.template_name
  node_name     = var.proxmox_node
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
    datastore_id = var.datastore_id
    file_format  = "raw"
    type         = "4m"
  }

  disk {
    datastore_id = var.datastore_id
    import_from  = local.image_file_id
    interface    = "scsi0"
    iothread     = true
    discard      = "on"
    size         = var.disk_size_gb
  }

  initialization {
    datastore_id = var.datastore_id
    upgrade      = false

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      username = var.vm_user
      keys     = var.ssh_public_keys
    }

    vendor_data_file_id = proxmox_virtual_environment_file.vendor_cloud_config.id
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  serial_device {
    device = "socket"
  }

  agent {
    enabled = false
  }
}
