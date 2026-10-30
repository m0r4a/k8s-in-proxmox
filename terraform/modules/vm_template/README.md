# vm_template

This Terraform module creates Rocky Linux 10 cloud-init templates on the
nodes of a Proxmox VE cluster, using the `bpg/proxmox` provider. A vendor
cloud-init snippet installs and starts qemu-guest-agent, so VMs cloned from
the templates boot with the agent running.

The module takes the same `proxmox_nodes` map as `k8s_cluster` and
`storage_node`, and it creates one template on each entry. Templates on
local storage are only visible to their own node, which is why every node
that hosts VMs needs its own.

## Features

- The module downloads the cloud image as an `import` volume and imports it
  through the Proxmox API (`import_from`), so the SSH user of the provider
  needs no `qm` rights.
- It can also use an image that is already on each node (`image_file_id`).
- It uploads the vendor snippet that installs qemu-guest-agent.
- The templates use UEFI (OVMF), the q35 machine type, CPU type `max`,
  VirtIO SCSI single and DHCP.
- Entries with `template_node` set reuse the template of another entry,
  which only works with shared storage, so the module creates nothing for
  them.

## Usage

```hcl
module "vm_template" {
  source = "github.com/m0r4a/k8s-in-proxmox//terraform/modules/vm_template?ref=main"

  vm_user        = "mora"
  ssh_public_key = "~/.ssh/id_ed25519.pub"

  proxmox_nodes = {
    server01      = { template_vm_id = 9001, network_bridge = "vmbr1" }
    myOtherServer = { proxmox_node_name = "server02", template_vm_id = 9002 }
  }
}

module "k8s_cluster" {
  # ...
  proxmox_nodes = module.vm_template.proxmox_nodes
}
```

The `proxmox_nodes` output returns the input map once every template
exists. When you pass it to [`k8s_cluster`](../k8s_cluster) or
[`storage_node`](../storage_node), their VMs wait for the templates without
a `depends_on`.

## Examples

- [single-node](../../examples/single-node) creates one template.
- [multi-node](../../examples/multi-node) creates a template on each of two
  Proxmox nodes.

## Prerequisites

- You need Proxmox VE 8.4 or newer for the `import` content type.
- The node needs the `snippets` and `import` content types on the `local`
  storage and the `tfprov` SSH user, and
  [`proxmox_setup.sh`](../../scripts/proxmox_setup.sh) sets up both.

## Ways to get a template

1. By default, this module downloads the Rocky 10 image from `image_url`.
2. With `image_url = null` and `image_file_id` set, this module uses an
   image that is already on the node, which must be an import volume such as
   `local:import/rocky10.qcow2`.
3. `proxmox_setup.sh --create-template` creates one template per node with
   shell commands and keeps the templates out of Terraform state, in which
   case you skip this module and paste the `proxmox_nodes` block that the
   script prints, as the [existing-template
   example](../../examples/existing-template) does.

## Notes

- Each `template_vm_id` must be unique across the whole Proxmox cluster, not
  only on its node, and the module rejects duplicates.
- `vm_user`, `ssh_public_key`, `cores`, `memory` and the bridge only
  configure the templates themselves, because `k8s_cluster` and
  `storage_node` set their own values on every clone.
- Clones can grow the boot disk beyond `disk_size_gb`, but they can never
  shrink it.
- The downloaded image and the snippet are named after `template_name`, so
  the module rejects two entries that would create a template on the same
  Proxmox node. For a second template on a node, call the module again with
  another `template_name`.

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
| proxmox_nodes | Proxmox nodes to create a template on, in the same shape k8s_cluster and storage_node take. Each entry gets a template with its template_vm_id on its node, except entries with template_node set, which reuse the template of another entry (shared storage). | ```map(object({ proxmox_node_name = optional(string) template_vm_id = number template_node = optional(string) network_bridge = optional(string, "vmbr0") datastore_id = optional(string, "local-lvm") cloudinit_datastore_id = optional(string, "local-lvm") }))``` | n/a | yes |
| vm_user | Cloud-init username on the template. Clones made by k8s_cluster and storage_node set their own. | `string` | n/a | yes |
| cores | CPU cores for the template. Cloned VMs override this. | `number` | `2` | no |
| disk_size_gb | Boot disk size in GB. Cloned VMs can only grow this. | `number` | `20` | no |
| image_file_id | File ID of an existing cloud image in a storage with the import content type (e.g. "local:import/rocky10.qcow2"). Set image_url to null to use this. | `string` | `null` | no |
| image_url | URL of a cloud image to download. Set to null to use an existing image via image_file_id. | `string` | `"https://dl.rockylinux.org/pub/rocky/10/images/x86_64/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2"` | no |
| memory | Memory (MB) for the template. Cloned VMs override this. | `number` | `2048` | no |
| ssh_public_key | SSH public key (raw or path to a .pub file) injected into the templates via cloud-init. Clones made by k8s_cluster and storage_node set their own. | `string` | `null` | no |
| tags | Tags applied to the template VM. | `list(string)` | ```[ "template", "rocky10" ]``` | no |
| template_name | Name shown in Proxmox for the template VM. | `string` | `"rocky10-cloudinit"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| proxmox_nodes | The proxmox_nodes input, available once every template exists. Pass it to k8s_cluster or storage_node so their VMs wait for the templates. |
| template_vm_ids | Template VM ID per proxmox_nodes key, for the entries that got a template. |
| template_vm_name | Name of the templates. |
<!-- END_TF_DOCS -->