# vm_template

This Terraform module creates a Rocky Linux 10 cloud-init template on one
Proxmox VE node, using the `bpg/proxmox` provider. A vendor cloud-init
snippet installs and starts qemu-guest-agent, so VMs cloned from the
template boot with the agent running.

Templates on local storage are only visible to their own node, so in a
Proxmox cluster you call the module once per node with `for_each`.

## Features

- The module downloads the cloud image as an `import` volume and imports it
  through the Proxmox API (`import_from`), so the SSH user of the provider
  needs no `qm` rights.
- It can also use an image that is already on the node (`image_file_id`).
- It uploads the vendor snippet that installs qemu-guest-agent.
- The template uses UEFI (OVMF), the q35 machine type, CPU type `max`,
  VirtIO SCSI single and DHCP.

## Usage

```hcl
module "vm_template" {
  source = "github.com/m0r4a/k8s-in-proxmox//terraform/modules/vm_template?ref=main"

  proxmox_node    = "server01"
  template_vm_id  = 9001
  vm_user         = "mora"
  ssh_public_keys = [trimspace(file(pathexpand("~/.ssh/id_ed25519.pub")))]
}
```

For one template per node of a Proxmox cluster, iterate over the same map
that `k8s_cluster` takes as `proxmox_nodes`.

```hcl
locals {
  proxmox_nodes = {
    server01 = { template_vm_id = 9001, network_bridge = "vmbr1" }
    server02 = { template_vm_id = 9002, network_bridge = "vmbr0" }
  }
}

module "vm_template" {
  for_each = local.proxmox_nodes
  source   = "github.com/m0r4a/k8s-in-proxmox//terraform/modules/vm_template?ref=main"

  proxmox_node    = lookup(each.value, "proxmox_node_name", each.key)
  template_vm_id  = each.value.template_vm_id
  network_bridge  = each.value.network_bridge
  vm_user         = "mora"
  ssh_public_keys = [trimspace(file(pathexpand("~/.ssh/id_ed25519.pub")))]
}

# k8s_cluster:
#   proxmox_nodes = {
#     for name, t in module.vm_template : name => merge(local.proxmox_nodes[name], { template_vm_id = t.template_vm_id })
#   }
```

The [`k8s_cluster`](../k8s_cluster) and [`storage_node`](../storage_node)
modules receive the template IDs through `proxmox_nodes` and clone whatever
template sits at each ID.

## Examples

- [single-node](../../examples/single-node) creates one template.
- [multi-node](../../examples/multi-node) creates one template per Proxmox
  node.

## Prerequisites

- You need Proxmox VE 8.4 or newer for the `import` content type.
- The node needs the `snippets` and `import` content types on the `local`
  storage and the `tfprov` SSH user, and
  [`proxmox_setup.sh`](../../scripts/proxmox_setup.sh) sets up both.

## Ways to get a template

1. By default, this module downloads the Rocky 10 image from `image_url`.
2. With `image_url = null` and `image_file_id` set, this module uses an
   image that is already on the node. The image must be an import volume
   such as `local:import/rocky10.qcow2`.
3. `proxmox_setup.sh --create-template` creates one template per node with
   shell commands, which keeps the templates out of Terraform state. In that
   case you skip this module and paste the `proxmox_nodes` block that the
   script prints. The
   [existing-template example](../../examples/existing-template) shows this
   setup.

## Notes

- `template_vm_id` must be unique across the whole Proxmox cluster, not only
  on its node.
- `vm_user`, `ssh_public_keys`, `cores`, `memory` and the bridge only
  configure the template itself, because `k8s_cluster` and `storage_node`
  set their own values on every clone.
- Clones can grow the boot disk beyond `disk_size_gb`, but they can never
  shrink it.
- The downloaded image and the snippet are named after `template_name`, so
  each template on the same node needs a different name.

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
