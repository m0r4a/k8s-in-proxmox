# storage_node

Terraform module that clones a cloud-init template into one or more
long-lived storage VMs on Proxmox VE, with the `bpg/proxmox` provider, and
writes their Ansible inventory fragment. The Ansible `storage` role turns
them into SeaweedFS nodes that hold the cluster's PVC data.

Storage nodes are not members of the Kubernetes cluster. They are meant to
outlive it.

## Features

- A second SCSI disk (`scsi1`) per VM for data, which the `storage` role
  formats, mounts at `/mnt/data` and hands to SeaweedFS
- `prevent_destroy = true` on the VMs, so even a destroy of the storage root
  itself is refused
- Writes `inventory.d/20-storage.ini` with self-contained connection vars,
  so storage can be configured without the cluster fragment
- CPU, memory and disk changes applied in place, without recreating the VM

## Usage

Run it from its own root and state (`terraform/storage/`), separate from the
cluster root, so a cluster `terraform destroy` never reaches it:

```hcl
module "storage_node" {
  source = "github.com/m0r4a/k8s-in-proxmox//terraform/modules/storage_node?ref=main"

  proxmox_node         = "server01"
  template_vm_id       = 9001
  vm_user              = "mora"
  vm_password          = var.vm_password
  ssh_public_key       = "~/.ssh/id_ed25519.pub"
  ssh_private_key_path = "~/.ssh/id_ed25519"
  network_bridge       = "vmbr1"
  network_gateway      = "10.0.0.253"

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

- [storage](../../examples/storage)

## Prerequisites

The module does not create the template. Create it first with the
[`vm_template`](../vm_template) module (usually from the cluster root) or
with `proxmox_setup.sh --create-template`, then pass its ID as
`template_vm_id`.

## Nodes

The `nodes` map key is the VM hostname, or its suffix when `cluster_name` is
set.

| Field | Required | Description |
| --- | --- | --- |
| `vmid` | yes | Proxmox VM ID, unique in the Proxmox cluster |
| `ip` | yes | Static IPv4 address; the prefix length is `network_cidr` |
| `storage_disk_gb` | no | Data disk size in GB. Defaults to `storage_disk_gb` |
| `cores` | no | CPU cores. Defaults to `cores` |
| `memory` | no | Memory in MB. Defaults to `memory` |
| `disk_size_gb` | no | Boot disk size in GB. Defaults to `disk_size_gb` |
| `user` | no | Cloud-init user. Defaults to `vm_user` |
| `password` | no | Cloud-init password. Defaults to `vm_password` |

## Ansible integration

With `ansible.enabled = true` the module writes
`<ansible.path>/inventory.d/20-storage.ini`:

```ini
[storage]
10.0.0.30 ansible_user=mora cluster_admin_user=mora cluster_admin_home=/home/mora

[storage:vars]
ansible_ssh_private_key_file=~/.ssh/id_ed25519
cluster_admin_user=mora
cluster_admin_home=/home/mora
```

SeaweedFS settings (image, ports, firewall) live in
`ansible/inventory.d/group_vars/storage.yml`.

## Tearing it down

`prevent_destroy` makes Terraform refuse to destroy the VMs. For an
intentional teardown, comment it out in `main.tf` of this module, then run
`terraform destroy` in the storage root. The data disk goes with the VM.

## Limitations

- Every storage VM goes on `proxmox_node`; there is no per-VM Proxmox node
  yet, unlike `k8s_cluster`.
- One network bridge for all storage VMs.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.4.0 |
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
| nodes | Storage nodes. The map key is the hostname suffix (or full hostname when cluster_name is empty). Every node gets an extra data disk sized by storage_disk_gb. | ```map(object({ vmid = number ip = string user = optional(string) password = optional(string) cores = optional(number) memory = optional(number) disk_size_gb = optional(number) storage_disk_gb = optional(number) }))``` | n/a | yes |
| proxmox_node | Proxmox node where the storage VMs will be created. | `string` | n/a | yes |
| ssh_private_key_path | Path to the SSH private key Ansible uses to reach the nodes. | `string` | n/a | yes |
| ssh_public_key | SSH public key (raw or path to a .pub file) added to each VM. | `string` | n/a | yes |
| template_vm_id | VM ID of an existing cloud-init template to clone. The storage root does not create the template; point this at a template made by the cluster root's vm_template module or by proxmox_setup.sh. | `number` | n/a | yes |
| vm_password | Cloud-init password for vm_user. | `string` | n/a | yes |
| vm_user | Default cloud-init username for the VMs. Overridable per node. | `string` | n/a | yes |
| ansible | Ansible integration. When enabled, writes inventory.d/20-storage.ini to the ansible directory. | ```object({ enabled = bool path = optional(string, "") })``` | ```{ "enabled": false, "path": "" }``` | no |
| clone_datastore_id | Datastore where cloned VM disks are placed. | `string` | `"local-lvm"` | no |
| cloudinit_datastore_id | Datastore used for the per-VM cloud-init drive. | `string` | `"local-lvm"` | no |
| cluster_name | Prefix prepended to every VM hostname. Empty keeps the map key as the hostname. | `string` | `""` | no |
| cores | Default CPU cores per VM. Overridable per node. | `number` | `2` | no |
| disk_size_gb | Default boot disk size in GB. Overridable per node. | `number` | `20` | no |
| dns_servers | DNS servers written to each VM via cloud-init. | `list(string)` | ```[ "1.1.1.1", "8.8.8.8" ]``` | no |
| memory | Default memory (MB) per VM. Overridable per node. | `number` | `4096` | no |
| network_bridge | Proxmox bridge the VM network devices attach to. | `string` | `"vmbr0"` | no |
| network_cidr | Network prefix length used when assigning static IPs. | `number` | `24` | no |
| storage_disk_gb | Default size in GB of the extra data disk (scsi1) attached to each storage VM. Overridable per node. | `number` | `50` | no |
| tags | Tags applied to every VM in addition to the storage/cluster tags. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| storage_node_ips | IPs of the storage nodes. |
| vm_ids | Map of node key -> provisioned VM ID. |
<!-- END_TF_DOCS -->
