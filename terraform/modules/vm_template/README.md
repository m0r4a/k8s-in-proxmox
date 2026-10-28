# vm_template

Terraform module that creates a Rocky Linux 10 cloud-init template on one
Proxmox VE node, with the `bpg/proxmox` provider. A vendor cloud-init
snippet installs and starts qemu-guest-agent, so VMs cloned from the
template boot with the agent running.

Templates on local storage are only visible to their own node. In a Proxmox
cluster, call the module once per node with `for_each`.

## Features

- Downloads the cloud image as an `import` volume and imports it through
  the Proxmox API (`import_from`), so the provider's SSH user needs no
  `qm` rights
- Or uses an image that is already on the node (`image_file_id`)
- Uploads the qemu-guest-agent vendor snippet
- UEFI (OVMF), q35, CPU type `max`, VirtIO SCSI single, DHCP on the template

## Usage

```hcl
module "vm_template" {
  source = "github.com/m0r4a/k3s-in-proxmox//terraform/modules/vm_template?ref=main"

  proxmox_node    = "server01"
  template_vm_id  = 9001
  vm_user         = "mora"
  ssh_public_keys = [trimspace(file(pathexpand("~/.ssh/id_ed25519.pub")))]
}
```

One template per node of a Proxmox cluster:

```hcl
module "vm_template" {
  for_each = { server01 = 9001, server02 = 9002 }
  source   = "github.com/m0r4a/k3s-in-proxmox//terraform/modules/vm_template?ref=main"

  proxmox_node    = each.key
  template_vm_id  = each.value
  vm_user         = "mora"
  ssh_public_keys = [trimspace(file(pathexpand("~/.ssh/id_ed25519.pub")))]
}

# k8s_cluster: templates = { for node, t in module.vm_template : node => t.template_vm_id }
```

Pass `template_vm_id` (or the `templates` map) to the
[`k8s_cluster`](../k8s_cluster) and [`storage_node`](../storage_node)
modules. They clone whatever template sits at that ID.

## Examples

- [single-node](../../examples/single-node)
- [multi-node](../../examples/multi-node): one template per Proxmox node

## Prerequisites

- Proxmox VE 8.4 or newer, for the `import` content type.
- The `snippets` and `import` content types on the `local` storage and the
  `tfprov` SSH user on the node. [`proxmox_setup.sh`](../../scripts/proxmox_setup.sh)
  sets up both.

## Ways to get a template

1. This module, by default, downloads the Rocky 10 image from `image_url`.
2. This module with `image_url = null` and `image_file_id` set uses an
   image already on the node. It must be an import volume, e.g.
   `local:import/rocky10.qcow2`.
3. `proxmox_setup.sh --create-template` creates one template per node with
   shell commands, if you'd rather keep templates out of Terraform state.
   Skip this module and pass the IDs it prints to `k8s_cluster`. See the
   [existing-template example](../../examples/existing-template).

## Notes

- `template_vm_id` must be unique across the Proxmox cluster, not just the
  node.
- `vm_user`, `ssh_public_keys`, `cores`, `memory` and the bridge only
  configure the template itself; `k8s_cluster` and `storage_node` set their
  own on every clone.
- Clones can grow the boot disk beyond `disk_size_gb`, never shrink it.
- The downloaded image and the snippet are named after `template_name`, so
  give each template on the same node a different name.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.4.0 |
| proxmox | 0.118.1 |

## Providers

| Name | Version |
| ---- | ------- |
| proxmox | 0.118.1 |

## Resources

| Name | Type |
| ---- | ---- |
| [proxmox_download_file.cloud_image](https://registry.terraform.io/providers/bpg/proxmox/0.118.1/docs/resources/download_file) | resource |
| [proxmox_virtual_environment_file.vendor_cloud_config](https://registry.terraform.io/providers/bpg/proxmox/0.118.1/docs/resources/virtual_environment_file) | resource |
| [proxmox_virtual_environment_vm.template](https://registry.terraform.io/providers/bpg/proxmox/0.118.1/docs/resources/virtual_environment_vm) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| proxmox_node | Proxmox node where the template will be created. | `string` | n/a | yes |
| template_vm_id | VM ID to assign to the template. Must be unique in the Proxmox cluster. | `number` | n/a | yes |
| vm_user | Cloud-init username on the template. Clones made by k8s_cluster and storage_node set their own. | `string` | n/a | yes |
| cores | CPU cores for the template. Cloned VMs override this. | `number` | `2` | no |
| datastore_id | Datastore used for the template boot disk. | `string` | `"local-lvm"` | no |
| disk_size_gb | Boot disk size in GB. Cloned VMs can only grow this. | `number` | `20` | no |
| image_file_id | File ID of an existing cloud image in a storage with the import content type (e.g. "local:import/rocky10.qcow2"). Set image_url to null to use this. | `string` | `null` | no |
| image_url | URL of a cloud image to download. Set to null to use an existing image via image_file_id. | `string` | `"https://dl.rockylinux.org/pub/rocky/10/images/x86_64/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2"` | no |
| memory | Memory (MB) for the template. Cloned VMs override this. | `number` | `2048` | no |
| network_bridge | Proxmox bridge the template network device attaches to. | `string` | `"vmbr0"` | no |
| ssh_public_keys | List of SSH public keys injected into the template via cloud-init. | `list(string)` | `[]` | no |
| tags | Tags applied to the template VM. | `list(string)` | ```[ "template", "rocky10" ]``` | no |
| template_name | Name shown in Proxmox for the template VM. | `string` | `"rocky10-cloudinit"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| template_vm_id | VM ID of the created template. Pass this to k8s_cluster.template_vm_id. |
| template_vm_name | Name of the created template. |
<!-- END_TF_DOCS -->
