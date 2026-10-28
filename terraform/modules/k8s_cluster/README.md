# k8s_cluster

Terraform module that clones a cloud-init template into the VMs of a
disposable Kubernetes cluster on Proxmox VE, with the `bpg/proxmox`
provider. It can spread the VMs across the nodes of a Proxmox cluster and
writes the Ansible inventory fragment that `ansible/site.yml` uses to
install Kubernetes on them.

The module only creates infrastructure. Which Kubernetes distribution ends
up on the VMs is Ansible's job; the module just records it in the
inventory.

## Features

- Control-plane and worker VMs from one `nodes` map, with per-node CPU,
  memory, disk, user and password overrides
- Placement per VM on any node of a Proxmox cluster, with a template and a
  network bridge per Proxmox node
- CPU, memory and disk changes applied in place, without recreating the VM;
  moving a VM to another Proxmox node live-migrates it
- `distribution` (`k3s`, `kubeadm` or `none`) passed to Ansible through the
  inventory
- Writes `inventory.d/10-cluster.ini` and records each VM's SSH host key in
  `~/.ssh/known_hosts`

## Usage

```hcl
module "vm_template" {
  source = "github.com/m0r4a/k8s-in-proxmox//terraform/modules/vm_template?ref=main"

  proxmox_node    = "server01"
  template_vm_id  = 9001
  vm_user         = "mora"
  ssh_public_keys = [trimspace(file(pathexpand("~/.ssh/id_ed25519.pub")))]
}

module "k8s_cluster" {
  source = "github.com/m0r4a/k8s-in-proxmox//terraform/modules/k8s_cluster?ref=main"

  distribution         = "k3s"
  proxmox_node         = "server01"
  template_vm_id       = module.vm_template.template_vm_id
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
    control-plane = { vmid = 201, role = "control-plane", ip = "10.0.0.10", cores = 2, memory = 3072 }
    worker1       = { vmid = 202, role = "worker", ip = "10.0.0.11" }
    worker2       = { vmid = 203, role = "worker", ip = "10.0.0.12" }
  }
}
```

Then run Ansible against the generated inventory:

```bash
cd ansible && ansible-playbook -i inventory.d/ site.yml
```

## Examples

- [single-node](../../examples/single-node): every VM on one Proxmox host
- [multi-node](../../examples/multi-node): two Proxmox nodes, a template
  and bridge per node, a worker on the second node
- [existing-template](../../examples/existing-template): templates created
  by `proxmox_setup.sh --create-template` instead of the `vm_template`
  module

## Prerequisites

- Proxmox VE 8.4 or newer. `vm_template` imports the image from an
  `import` volume.
- An API token and the `tfprov` SSH user on every Proxmox node, both created
  by [`proxmox_setup.sh`](../../scripts/proxmox_setup.sh). The provider
  uploads snippets over SSH.
- A cloud-init template on each Proxmox node that hosts VMs, from the
  `vm_template` module or the script.

## Nodes

The `nodes` map key is the VM hostname. With `cluster_name` set it becomes a
suffix: `cluster_name = "lab"` and key `cp1` gives `lab-cp1`.

| Field | Required | Description |
| --- | --- | --- |
| `vmid` | yes | Proxmox VM ID, unique in the Proxmox cluster |
| `role` | yes | `control-plane` or `worker` |
| `ip` | yes | Static IPv4 address; the prefix length is `network_cidr` |
| `proxmox_node` | no | Proxmox node for the VM. Defaults to `proxmox_node` |
| `cores` | no | CPU cores. Defaults to `cores` |
| `memory` | no | Memory in MB. Defaults to `memory` |
| `disk_size_gb` | no | Boot disk size in GB. Defaults to `disk_size_gb` |
| `user` | no | Cloud-init user. Defaults to `vm_user` |
| `password` | no | Cloud-init password. Defaults to `vm_password` |

The module rejects a map without a control-plane node, duplicated VM IDs or
IPs, invalid hostnames or IPv4 addresses, and out-of-range cores (1 to 128),
memory (512 MB to 1 TB) or disk sizes (20 GB minimum). With
`distribution = "kubeadm"`, control-plane nodes also need at least 2 cores
and 1700 MB, the kubeadm preflight minimum.

## Multiple Proxmox nodes

Set `proxmox_node` on a node to place its VM there. Two things in a
Proxmox cluster are per node and need a map:

- **Templates.** A template on local storage (`local-lvm`) is only visible
  to its own node, so create one per node, each with a VM ID unique in the
  cluster, and pass them as `templates`. A VM on a node missing from
  `templates` clones `template_vm_id` from `proxmox_node`, which only works
  with shared storage.
- **Bridges.** The bridge carrying the VM network can have a different name
  on each node. `network_bridges` overrides `network_bridge` for the nodes
  listed.

```hcl
templates       = { for node, t in module.vm_template : node => t.template_vm_id }
network_bridge  = "vmbr1"
network_bridges = { server02 = "vmbr0" }
```

The [multi-node example](../../examples/multi-node) puts all of this
together.

## Distribution

`distribution` does not change the VMs. It is tagged on each VM and written
to the inventory as `k8s_distribution`, and `site.yml` picks the roles from
it:

| `distribution` | What `site.yml` does |
| --- | --- |
| `k3s` | Prepares the nodes and installs k3s (without kube-proxy), Cilium as CNI and Service proxy, Helm and Flux |
| `none` | Only prepares the nodes (`common`, `k8s_prep`); no Kubernetes |
| `kubeadm` | Fails in the first play on purpose: there are no kubeadm roles yet |

## Ansible integration

With `ansible.enabled = true` the module writes
`<ansible.path>/inventory.d/10-cluster.ini`:

```ini
[control_plane]
10.0.0.10 ansible_user=mora cluster_admin_user=mora cluster_admin_home=/home/mora

[worker]
10.0.0.11 ansible_user=mora cluster_admin_user=mora cluster_admin_home=/home/mora
10.0.0.12 ansible_user=mora cluster_admin_user=mora cluster_admin_home=/home/mora

[k8s_cluster:children]
control_plane
worker

[all:vars]
k8s_distribution=k3s
ansible_ssh_private_key_file=~/.ssh/id_ed25519
k8s_control_plane_ip=10.0.0.10
k8s_cluster_cidr=10.42.0.0/16
k8s_service_cidr=10.43.0.0/16
cluster_admin_user=mora
cluster_admin_home=/home/mora
```

The fragment only holds infrastructure facts. Ansible configuration
(versions, install URLs) is in the roles' defaults, overridable in
`ansible/inventory.d/group_vars/`.
Ansible reads every file in `inventory.d/`, so this fragment merges with the
`20-storage.ini` one from the `storage_node` module.

`cluster_cidr` reaches both k3s (`--cluster-cidr`) and Cilium's IPAM pool.

## Lifecycle

- CPU and memory changes are applied in place and the VM reboots
  (`reboot_after_update = true`).
- Disk size changes grow the disk live through `hotplug`. Disks cannot
  shrink.
- Changing a node's `proxmox_node` live-migrates the VM (`migrate = true`).
- VM tags are ignored after creation, so tags edited in the Proxmox UI stay.
- VMs start when their Proxmox node boots (`on_boot = true`).

## Limitations

- One control-plane node. `control_plane_ip` is taken with `one()`, so a
  second control-plane node makes the plan fail; HA control planes are not
  supported yet.
- IPv4 only, static addresses.
- Storage VMs are a separate module, [`storage_node`](../storage_node), run
  from their own root so a cluster destroy never reaches them.

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
| [local_file.ansible_inventory](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [null_resource.ssh_keyscan](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [proxmox_virtual_environment_vm.node](https://registry.terraform.io/providers/bpg/proxmox/0.118.1/docs/resources/virtual_environment_vm) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| network_gateway | IPv4 gateway for the VMs. | `string` | n/a | yes |
| nodes | Cluster nodes. The map key is the hostname suffix (or full hostname when cluster_name is empty). | ```map(object({ vmid = number role = string ip = string proxmox_node = optional(string) user = optional(string) password = optional(string) cores = optional(number) memory = optional(number) disk_size_gb = optional(number) }))``` | n/a | yes |
| proxmox_node | Default Proxmox node for the cluster VMs, and the node holding template_vm_id. Overridable per node. | `string` | n/a | yes |
| ssh_private_key_path | Path to the SSH private key Ansible uses to reach the nodes. | `string` | n/a | yes |
| ssh_public_key | SSH public key (raw or path to a .pub file) added to each VM. | `string` | n/a | yes |
| template_vm_id | VM ID of the cloud-init template to clone. Provide module.vm_template.template_vm_id, or an existing template ID. | `number` | n/a | yes |
| vm_password | Cloud-init password for vm_user. | `string` | n/a | yes |
| vm_user | Default cloud-init username for the VMs. Overridable per node. | `string` | n/a | yes |
| ansible | Ansible integration. When enabled, writes inventory.d/10-cluster.ini to the ansible directory. | ```object({ enabled = bool path = optional(string, "") })``` | ```{ "enabled": false, "path": "" }``` | no |
| clone_datastore_id | Datastore where cloned VM disks are placed. | `string` | `"local-lvm"` | no |
| cloudinit_datastore_id | Datastore used for the per-VM cloud-init drive. | `string` | `"local-lvm"` | no |
| cluster_cidr | Pod CIDR for the cluster. | `string` | `"10.42.0.0/16"` | no |
| cluster_name | Prefix prepended to every VM hostname. Empty keeps the map key as the hostname. | `string` | `""` | no |
| cores | Default CPU cores per VM. Overridable per node. | `number` | `3` | no |
| disk_size_gb | Default boot disk size in GB. Overridable per node. | `number` | `20` | no |
| distribution | Kubernetes distribution Ansible installs on the nodes, or none to only prepare them. Written to the inventory as k8s_distribution. | `string` | `"k3s"` | no |
| dns_servers | DNS servers written to each VM via cloud-init. | `list(string)` | ```[ "1.1.1.1", "8.8.8.8" ]``` | no |
| memory | Default memory (MB) per VM. Overridable per node. | `number` | `4096` | no |
| network_bridge | Default Proxmox bridge the VM network devices attach to. Overridable per Proxmox node with network_bridges. | `string` | `"vmbr0"` | no |
| network_bridges | Bridge per Proxmox node when the VM network is not on network_bridge everywhere (e.g. { server02 = "vmbr0" }). | `map(string)` | `{}` | no |
| network_cidr | Network prefix length used when assigning static IPs. | `number` | `24` | no |
| service_cidr | Service CIDR for the cluster. | `string` | `"10.43.0.0/16"` | no |
| tags | Tags applied to every VM in addition to role/cluster tags. | `list(string)` | `[]` | no |
| templates | Template VM ID per Proxmox node (e.g. { pve2 = 9002 }). Nodes on a Proxmox node not listed here clone template_vm_id from proxmox_node, which requires shared storage. | `map(number)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| control_plane_ip | IP of the control-plane node. |
| node_ips | IPs of the cluster members. |
| vm_ids | Map of node key -> provisioned VM ID. |
<!-- END_TF_DOCS -->
