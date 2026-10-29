resource "proxmox_virtual_environment_vm" "node" {
  for_each = local.nodes_normalized

  vm_id         = each.value.vmid
  name          = each.value.hostname
  node_name     = each.value.proxmox_node
  migrate       = true
  tags          = each.value.tags
  on_boot       = each.value.on_boot
  started       = true
  machine       = "q35"
  bios          = "ovmf"
  scsi_hardware = "virtio-scsi-single"
  boot_order    = ["scsi0"]

  clone {
    vm_id        = each.value.template_vm_id
    node_name    = each.value.template_node
    datastore_id = each.value.datastore_id
    full         = true
    retries      = 3
  }

  cpu {
    cores = each.value.cores
    type  = "max"
  }

  memory {
    dedicated = each.value.memory
  }

  efi_disk {
    datastore_id = each.value.datastore_id
    file_format  = "raw"
    type         = "4m"
  }

  disk {
    datastore_id = each.value.datastore_id
    interface    = "scsi0"
    iothread     = true
    discard      = "on"
    size         = each.value.disk_size_gb
  }

  initialization {
    datastore_id = each.value.cloudinit_datastore_id
    upgrade      = false

    ip_config {
      ipv4 {
        address = "${each.value.ip}/${var.network_cidr}"
        gateway = var.network_gateway
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      username = each.value.user
      password = each.value.password
      keys     = [local.ssh_public_key_content]
    }
  }

  network_device {
    bridge = each.value.network_bridge
    model  = "virtio"
  }

  serial_device {
    device = "socket"
  }

  agent {
    enabled = true
  }

  hotplug             = "network,disk,usb"
  reboot_after_update = true

  lifecycle {
    ignore_changes = [tags]

    # kubeadm preflight refuses control planes below 2 CPUs / 1700 MB.
    precondition {
      condition     = var.distribution != "kubeadm" || each.value.role != "control-plane" || (each.value.cores >= 2 && each.value.memory >= 1700)
      error_message = "kubeadm control-plane nodes need at least 2 cores and 1700 MB of memory."
    }
  }
}

resource "null_resource" "ssh_keyscan" {
  for_each = local.nodes_normalized

  triggers = {
    vm_id = proxmox_virtual_environment_vm.node[each.key].vm_id
    vm_ip = each.value.ip
  }

  provisioner "local-exec" {
    command = <<-EOT
      ssh-keygen -R ${each.value.ip} 2>/dev/null || true
      for i in $(seq 1 30); do
        KEY=$(ssh-keyscan -H ${each.value.ip} 2>/dev/null)
        if [ -n "$KEY" ]; then
          echo "$KEY" >> ~/.ssh/known_hosts
          exit 0
        fi
        sleep 10
      done
      exit 1
    EOT
  }

  depends_on = [proxmox_virtual_environment_vm.node]
}
