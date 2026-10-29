# k8s_cluster

This Terraform module clones a cloud-init template into the VMs of a
disposable Kubernetes cluster on Proxmox VE, using the `bpg/proxmox`
provider. It can spread the VMs across the nodes of a Proxmox cluster, and it
writes the Ansible inventory fragment that `ansible/site.yml` uses to install
Kubernetes on them.

The module only creates infrastructure. Installing the Kubernetes
distribution is the job of Ansible, and the module just records the choice
in the inventory.

## Features

- One `nodes` map describes the control-plane and worker VMs, and each VM
  can override its CPU, memory, disk, user and password.
- Each VM can run on any node of a Proxmox cluster, and the `proxmox_nodes`
  map describes the template, bridge and datastores of every Proxmox node in
  one place.
- CPU, memory and disk changes apply in place without recreating the VM,
  and moving a VM to another Proxmox node live-migrates it.
- The `distribution` setting (`k3s`, `kubeadm` or `none`) reaches Ansible
  through the inventory.
- The module writes `inventory.d/10-cluster.ini` and records the SSH host key
  of each VM in `~/.ssh/known_hosts`.

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
  vm_user              = "mora"
  vm_password          = var.vm_password
  ssh_public_key       = "~/.ssh/id_ed25519.pub"
  ssh_private_key_path = "~/.ssh/id_ed25519"
  network_gateway      = "10.0.0.253"

  proxmox_nodes = {
    server01 = { template_vm_id = module.vm_template.template_vm_id, network_bridge = "vmbr1" }
  }

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

After `terraform apply`, run Ansible against the generated inventory.

```bash
cd ansible && ansible-playbook -i inventory.d/ site.yml
```

## Examples

- [single-node](../../examples/single-node) puts every VM on one Proxmox
  host.
- [multi-node](../../examples/multi-node) uses two Proxmox nodes with a
  template and a bridge per node, and it places a worker on the second node.
- [existing-template](../../examples/existing-template) uses templates
  created by `proxmox_setup.sh --create-template` instead of the
  `vm_template` module.

## Prerequisites

- You need Proxmox VE 8.4 or newer, because `vm_template` imports the image
  from an `import` volume.
- [`proxmox_setup.sh`](../../scripts/proxmox_setup.sh) must have created the
  API token and the `tfprov` SSH user on every Proxmox node, because the
  provider uploads snippets over SSH.
- Each Proxmox node that hosts VMs needs a cloud-init template, which you
  create with the `vm_template` module or with the script.

## Nodes

The key of the `nodes` map is the VM hostname. When `cluster_name` is set,
the key becomes a suffix, so `cluster_name = "lab"` and the key `cp1` give
the hostname `lab-cp1`.

| Field | Required | Description |
| --- | --- | --- |
| `vmid` | yes | The Proxmox VM ID must be unique in the Proxmox cluster. |
| `role` | yes | The role must be `control-plane` or `worker`. |
| `ip` | yes | The static IPv4 address uses `network_cidr` as its prefix length. |
| `proxmox_node` | no | The VM runs on this key of `proxmox_nodes`, which is required when the map has more than one entry. |
| `cores` | no | The number of CPU cores defaults to `cores`. |
| `memory` | no | The memory in MB defaults to `memory`. |
| `disk_size_gb` | no | The boot disk size in GB defaults to `disk_size_gb`. |
| `user` | no | The cloud-init user defaults to `vm_user`. |
| `password` | no | The cloud-init password defaults to `vm_password`. |

The module rejects a map without a control-plane node, duplicated VM IDs or
IPs, invalid hostnames or IPv4 addresses, and out-of-range cores (1 to 128),
memory (512 MB to 1 TB) or disk sizes (20 GB minimum). With
`distribution = "kubeadm"`, control-plane nodes also need at least 2 cores
and 1700 MB, which is the kubeadm preflight minimum.

## Proxmox nodes

`proxmox_nodes` lists the Proxmox nodes the VMs can run on and holds
everything that differs between them. The map key is the name that the rest
of the configuration uses for each node.

| Field | Required | Description |
| --- | --- | --- |
| `proxmox_node_name` | no | The node name in Proxmox defaults to the map key. |
| `template_vm_id` | yes | VMs on this node clone the template with this ID. |
| `template_node` | no | When the template lives on another entry, this field holds the key of that entry. It only works with shared storage. |
| `network_bridge` | no | The bridge that carries the VM network on this node defaults to `vmbr0`. |
| `datastore_id` | no | The datastore for the cloned disks defaults to `local-lvm`. |
| `cloudinit_datastore_id` | no | The datastore for the cloud-init drive defaults to `local-lvm`. |

With a single entry, every VM goes to that node without naming it. With more
than one entry, every VM in `nodes` must set `proxmox_node`, and the module
rejects names that are not keys of `proxmox_nodes`.

`nodes[*].proxmox_node` and `template_node` always refer to the map key. If
you set `proxmox_node_name`, you can give a node a key of your own and keep
its Proxmox name out of the rest of the configuration.

```hcl
proxmox_nodes = {
  big-box = { proxmox_node_name = "server01", template_vm_id = 9001 }
}
```

A template on local storage (`local-lvm`) is only visible to its own node,
so a Proxmox cluster usually has one template per node, each with a VM ID
that is unique in the cluster.

```hcl
proxmox_nodes = {
  server01 = { template_vm_id = 9001, network_bridge = "vmbr1" }
  server02 = { template_vm_id = 9002 }
}

nodes = {
  control-plane = { vmid = 201, role = "control-plane", ip = "10.0.0.10", proxmox_node = "server01" }
  worker1       = { vmid = 202, role = "worker", ip = "10.0.0.11", proxmox_node = "server02" }
}
```

The [multi-node example](../../examples/multi-node) creates the templates
with `vm_template` from the same map it passes as `proxmox_nodes`, and it
uses `depends_on = [module.vm_template]` so that the VMs wait for their
templates.

## Distribution

`distribution` does not change the VMs. The module tags each VM with it and
writes it to the inventory as `k8s_distribution`, and `site.yml` picks the
roles from it.

| `distribution` | What `site.yml` does |
| --- | --- |
| `k3s` | It prepares the nodes and installs k3s without kube-proxy, with Cilium as the CNI and Service proxy, plus Helm and Hubble. |
| `none` | It only prepares the nodes with `common` and `k8s_prep` and installs no Kubernetes. |
| `kubeadm` | The first play fails on purpose, because there are no kubeadm roles yet. |

## Ansible integration

With `ansible.enabled = true`, the module writes
`<ansible.path>/inventory.d/10-cluster.ini`. For the usage example above,
the file looks like this.

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

The fragment only holds infrastructure facts. Ansible configuration such as
versions and install URLs lives in the role defaults, and you can override
it in `ansible/inventory.d/group_vars/`. Ansible reads every file in
`inventory.d/`, so this fragment merges with the `20-storage.ini` fragment
that the `storage_node` module writes.

`cluster_cidr` reaches both k3s (`--cluster-cidr`) and the IPAM pool of
Cilium.

## Lifecycle

- CPU and memory changes apply in place, and the VM reboots afterwards
  (`reboot_after_update = true`).
- Disk size changes grow the disk live through `hotplug`, and disks can
  never shrink.
- Changing the `proxmox_node` of a VM live-migrates it (`migrate = true`).
- Terraform ignores VM tags after creation, so the tags you edit in the
  Proxmox UI stay.
- VMs start when their Proxmox node boots (`on_boot = true`).

## Limitations

- The module supports a single control-plane node. It reads
  `control_plane_ip` with `one()`, so a second control-plane node makes the
  plan fail, and HA control planes are not supported yet.
- The module only supports static IPv4 addresses.
- Storage VMs come from a separate module, [`storage_node`](../storage_node),
  which runs from its own root so that destroying the cluster never reaches
  them.

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
| [local_file.ansible_inventory](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [null_resource.ssh_keyscan](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [proxmox_virtual_environment_vm.node](https://registry.terraform.io/providers/bpg/proxmox/0.118.1/docs/resources/virtual_environment_vm) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| network_gateway | IPv4 gateway for the VMs. | `string` | n/a | yes |
| nodes | Cluster nodes. The map key is the hostname suffix (or full hostname when cluster_name is empty). proxmox_node is required when proxmox_nodes has more than one entry. | ```map(object({ vmid = number role = string ip = string proxmox_node = optional(string) user = optional(string) password = optional(string) cores = optional(number) memory = optional(number) disk_size_gb = optional(number) }))``` | n/a | yes |
| proxmox_nodes | Proxmox nodes the VMs can run on. The key is the name nodes[*].proxmox_node and template_node refer to, and the Proxmox node name unless proxmox_node_name is set. template_vm_id is the template cloned for VMs there; set template_node when it lives on another entry (shared storage). | ```map(object({ proxmox_node_name = optional(string) template_vm_id = number template_node = optional(string) network_bridge = optional(string, "vmbr0") datastore_id = optional(string, "local-lvm") cloudinit_datastore_id = optional(string, "local-lvm") }))``` | n/a | yes |
| ssh_private_key_path | Path to the SSH private key Ansible uses to reach the nodes. | `string` | n/a | yes |
| ssh_public_key | SSH public key (raw or path to a .pub file) added to each VM. | `string` | n/a | yes |
| vm_password | Cloud-init password for vm_user. | `string` | n/a | yes |
| vm_user | Default cloud-init username for the VMs. Overridable per node. | `string` | n/a | yes |
| ansible | Ansible integration. When enabled, writes inventory.d/10-cluster.ini to the ansible directory. | ```object({ enabled = bool path = optional(string, "") })``` | ```{ "enabled": false, "path": "" }``` | no |
| cluster_cidr | Pod CIDR for the cluster. | `string` | `"10.42.0.0/16"` | no |
| cluster_name | Prefix prepended to every VM hostname. Empty keeps the map key as the hostname. | `string` | `""` | no |
| cores | Default CPU cores per VM. Overridable per node. | `number` | `3` | no |
| disk_size_gb | Default boot disk size in GB. Overridable per node. | `number` | `20` | no |
| distribution | Kubernetes distribution Ansible installs on the nodes, or none to only prepare them. Written to the inventory as k8s_distribution. | `string` | `"k3s"` | no |
| dns_servers | DNS servers written to each VM via cloud-init. | `list(string)` | ```[ "1.1.1.1", "8.8.8.8" ]``` | no |
| memory | Default memory (MB) per VM. Overridable per node. | `number` | `4096` | no |
| network_cidr | Network prefix length used when assigning static IPs. | `number` | `24` | no |
| service_cidr | Service CIDR for the cluster. | `string` | `"10.43.0.0/16"` | no |
| tags | Tags applied to every VM in addition to role/cluster tags. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| control_plane_ip | IP of the control-plane node. |
| node_ips | IPs of the cluster members. |
| vm_ids | Map of node key -> provisioned VM ID. |
<!-- END_TF_DOCS -->
