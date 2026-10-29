# storage_node

This Terraform module clones a cloud-init template into one or more
long-lived storage VMs on Proxmox VE, using the `bpg/proxmox` provider, and
writes their Ansible inventory fragment. The Ansible `storage` role then
turns them into SeaweedFS nodes that hold the PVC data of the cluster.

Storage nodes are not members of the Kubernetes cluster, and they are meant
to outlive it.

## Features

- Each VM gets a second SCSI disk (`scsi1`) for data, which the `storage`
  role formats, mounts at `/mnt/data` and hands to SeaweedFS.
- The VMs have `prevent_destroy = true`, so Terraform refuses to destroy them
  even from the storage root.
- The module writes `inventory.d/20-storage.ini` with its own connection
  variables, so you can configure storage without the cluster fragment.
- CPU, memory and disk changes apply in place without recreating the VM,
  and moving a VM to another Proxmox node live-migrates it.
- The module places VMs across a Proxmox cluster with the same
  `proxmox_nodes` map as [`k8s_cluster`](../k8s_cluster#proxmox-nodes).

## Usage

Run the module from its own root and state (`terraform/storage/`), separate
from the cluster root, so that a `terraform destroy` of the cluster never
reaches it.

```hcl
module "storage_node" {
  source = "github.com/m0r4a/k8s-in-proxmox//terraform/modules/storage_node?ref=main"

  vm_user              = "mora"
  vm_password          = var.vm_password
  ssh_public_key       = "~/.ssh/id_ed25519.pub"
  ssh_private_key_path = "~/.ssh/id_ed25519"
  network_gateway      = "10.0.0.253"

  proxmox_nodes = {
    server01 = { template_vm_id = 9001, network_bridge = "vmbr1" }
  }

  ansible = {
    enabled = true
    path    = "../../ansible"
  }

  nodes = {
    storage1 = { vmid = 301, ip = "10.0.0.30", storage_disk_gb = 200 }
  }
}
```

## Examples

The [storage](../../examples/storage) example creates one storage VM.

## Prerequisites

The module does not create the template, so create it first with the
[`vm_template`](../vm_template) module (usually from the cluster root) or
with `proxmox_setup.sh --create-template`, and then set its ID as the
`template_vm_id` of its node in `proxmox_nodes`.

## Nodes

The key of the `nodes` map is the VM hostname, or its suffix when
`cluster_name` is set.

| Field | Required | Description |
| --- | --- | --- |
| `vmid` | yes | The Proxmox VM ID must be unique in the Proxmox cluster. |
| `ip` | yes | The static IPv4 address uses `network_cidr` as its prefix length. |
| `proxmox_node` | no | The VM runs on this key of `proxmox_nodes`, which is required when the map has more than one entry. |
| `storage_disk_gb` | no | The data disk size in GB defaults to `storage_disk_gb`. |
| `cores` | no | The number of CPU cores defaults to `cores`. |
| `memory` | no | The memory in MB defaults to `memory`. |
| `disk_size_gb` | no | The boot disk size in GB defaults to `disk_size_gb`. |
| `user` | no | The cloud-init user defaults to `vm_user`. |
| `password` | no | The cloud-init password defaults to `vm_password`. |

## Ansible integration

With `ansible.enabled = true`, the module writes
`<ansible.path>/inventory.d/20-storage.ini`, which looks like this.

```ini
[storage]
10.0.0.30 ansible_user=mora cluster_admin_user=mora cluster_admin_home=/home/mora

[storage:vars]
ansible_ssh_private_key_file=~/.ssh/id_ed25519
cluster_admin_user=mora
cluster_admin_home=/home/mora
```

The SeaweedFS settings, such as the image, the ports and the firewall, live
in `ansible/inventory.d/group_vars/storage.yml`.

## Tearing it down

`prevent_destroy` makes Terraform refuse to destroy the VMs, so for an
intentional teardown you comment it out in the `main.tf` of this module
and run `terraform destroy` in the storage root, which deletes the data disk
together with the VM.

## Limitations

The module only supports static IPv4 addresses.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.9.0 |
| local | >= 2.0.0 |
| null | >= 3.0.0 |
| proxmox | 0.118.1 |

## Providers

| Name | Version |
| ---- | ------- |
| local | >= 2.0.0 |
| null | >= 3.0.0 |
| proxmox | 0.118.1 |

## Resources

| Name | Type |
| ---- | ---- |
| [local_file.storage_inventory](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [null_resource.ssh_keyscan](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [proxmox_virtual_environment_vm.storage](https://registry.terraform.io/providers/bpg/proxmox/0.118.1/docs/resources/virtual_environment_vm) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| network_gateway | IPv4 gateway for the VMs. | `string` | n/a | yes |
| nodes | Storage nodes. The map key is the hostname suffix (or full hostname when cluster_name is empty). Every node gets an extra data disk sized by storage_disk_gb. proxmox_node is required when proxmox_nodes has more than one entry. | ```map(object({ vmid = number ip = string proxmox_node = optional(string) user = optional(string) password = optional(string) cores = optional(number) memory = optional(number) disk_size_gb = optional(number) storage_disk_gb = optional(number) }))``` | n/a | yes |
| proxmox_nodes | Proxmox nodes the VMs can run on. The key is the name nodes[*].proxmox_node and template_node refer to, and the Proxmox node name unless proxmox_node_name is set. template_vm_id is the template cloned for VMs there; set template_node when it lives on another entry (shared storage). | ```map(object({ proxmox_node_name = optional(string) template_vm_id = number template_node = optional(string) network_bridge = optional(string, "vmbr0") datastore_id = optional(string, "local-lvm") cloudinit_datastore_id = optional(string, "local-lvm") }))``` | n/a | yes |
| ssh_private_key_path | Path to the SSH private key Ansible uses to reach the nodes. | `string` | n/a | yes |
| ssh_public_key | SSH public key (raw or path to a .pub file) added to each VM. | `string` | n/a | yes |
| vm_password | Cloud-init password for vm_user. | `string` | n/a | yes |
| vm_user | Default cloud-init username for the VMs. Overridable per node. | `string` | n/a | yes |
| ansible | Ansible integration. When enabled, writes inventory.d/20-storage.ini to the ansible directory. | ```object({ enabled = bool path = optional(string, "") })``` | ```{ "enabled": false, "path": "" }``` | no |
| cluster_name | Prefix prepended to every VM hostname. Empty keeps the map key as the hostname. | `string` | `""` | no |
| cores | Default CPU cores per VM. Overridable per node. | `number` | `2` | no |
| disk_size_gb | Default boot disk size in GB. Overridable per node. | `number` | `20` | no |
| dns_servers | DNS servers written to each VM via cloud-init. | `list(string)` | ```[ "1.1.1.1", "8.8.8.8" ]``` | no |
| memory | Default memory (MB) per VM. Overridable per node. | `number` | `4096` | no |
| network_cidr | Network prefix length used when assigning static IPs. | `number` | `24` | no |
| storage_disk_gb | Default size in GB of the extra data disk (scsi1) attached to each storage VM. Overridable per node. | `number` | `50` | no |
| tags | Tags applied to every VM in addition to the storage/cluster tags. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| storage_node_ips | IPs of the storage nodes. |
| vm_ids | Map of node key -> provisioned VM ID. |
<!-- END_TF_DOCS -->
