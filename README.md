# k8s in Proxmox

This repository holds the Terraform and Ansible code that provisions a
disposable Kubernetes cluster on Proxmox VE, with long-lived SeaweedFS
storage next to it. Terraform uses the `bpg/proxmox` provider and works with
any Kubernetes distribution, while Ansible installs k3s today and has
kubeadm support planned. [requirements.md](requirements.md) describes the
full design and [security.md](security.md) the security setup.

## Getting started

### 1. Prerequisites

You need Proxmox VE 8.4 or newer with API and SSH access, because the
template disk is imported from an `import` volume that older versions lack.
On your workstation you need Terraform 1.9 or newer, Ansible and an SSH key
pair such as `~/.ssh/id_ed25519`.

### 2. One-time Proxmox setup

Point the setup script at any node of your Proxmox cluster. The script logs
in as root over SSH, finds every node of the cluster and sets all of them
up. It creates a PVE role, an API user and an API token once for the whole
cluster, and it enables the `snippets` and `import` content types on the
`local` storage. On each node it also creates `tfprov`, the SSH user that
Terraform uses to upload snippets, with sudo rights that cover only that
task.

The script leaves the templates to the `vm_template` Terraform module unless
you pass `--create-template`, in which case it creates one template per node, and
[security.md](security.md) explains each step.

```bash
cd terraform/scripts

# Default: PVE role/user/token + tfprov SSH user on every node (template via Terraform)
./proxmox_setup.sh --host 192.168.1.2 --ssh-key ~/.ssh/id_ed25519

# Optional: also create one cloud-init template per node via the script
./proxmox_setup.sh --host 192.168.1.2 --ssh-key ~/.ssh/id_ed25519 --create-template

# A node that joined the cluster later
./proxmox_setup.sh --host 192.168.1.2 --ssh-key ~/.ssh/id_ed25519 --nodes server03
```

Save the token secret from the output, and copy the Proxmox connection block
that the script prints into the `terraform.tfvars` of every root you apply.
With `--create-template` it also prints a `proxmox_nodes` block with the
template ID of each node.

The script does not touch the SSH settings of your Proxmox hosts, so your
root SSH access stays as it was.

### 3. Provision the infrastructure

Each directory in [`terraform/examples/`](terraform/examples) is a
self-contained Terraform root with its own state. The cluster and the
storage node always run from separate roots, so destroying the cluster never
touches storage. Pick the cluster example that fits your Proxmox setup and
edit its `main.tf` for your nodes, IPs and VM IDs.

| Example | What it deploys |
| --- | --- |
| [single-node](terraform/examples/single-node) | It creates a template and a k3s cluster on one Proxmox node. |
| [multi-node](terraform/examples/multi-node) | It creates a template on each of two Proxmox nodes and spreads the cluster across them. |
| [existing-template](terraform/examples/existing-template) | It deploys the cluster from templates made by `proxmox_setup.sh --create-template`. |
| [storage](terraform/examples/storage) | It creates the long-lived SeaweedFS storage VM. |

The cluster is disposable, so you can apply and destroy it as often as you
like.

```bash
cd terraform/examples/multi-node                # or single-node, existing-template
cp terraform.tfvars.example terraform.tfvars    # fill in your values
terraform init
terraform apply                                 # writes ansible/inventory.d/10-cluster.ini
```

Storage is long-lived and you apply it once, after a cluster example or
`proxmox_setup.sh --create-template` has created the template it clones.

```bash
cd ../storage
cp terraform.tfvars.example terraform.tfvars    # fill in your values
terraform init
terraform apply                                 # writes ansible/inventory.d/20-storage.ini
```

Both roots can share the Proxmox connection values through one file if you
pass `-var-file=../common.tfvars` to `terraform apply`.

The `distribution` setting in the `main.tf` of a cluster example (`k3s`,
`kubeadm` or `none`) picks what Ansible installs. Its `proxmox_nodes` map
lists the Proxmox nodes the VMs can run on, together with the template,
bridge and datastores of each one, and when the map has more than one entry
every VM picks its node with `proxmox_node`. The
[k8s_cluster module README](terraform/modules/k8s_cluster/README.md) has the
details.

### 4. Configure with Ansible

`ansible/ansible.cfg` points at `inventory.d/`, so Ansible picks up both
fragments on its own.

```bash
cd ../../../ansible
ansible-playbook site.yml
```

With `distribution = "k3s"`, Ansible installs k3s, Cilium, Helm and
SeaweedFS. With `none` it only prepares the nodes (packages, SSH hardening,
swap, kernel modules and sysctl) and leaves the Kubernetes install to you.
There are no kubeadm roles yet, so with `kubeadm` the playbook stops with an
error in its first play.

## Structure

```
terraform/
  scripts/
    proxmox_setup.sh       One-time PVE setup for every node of the cluster
  modules/
    vm_template/           Creates cloud-init templates
    k8s_cluster/           Clones templates into cluster VMs, writes 10-cluster.ini
    storage_node/          Clones templates into storage VMs, writes 20-storage.ini
  examples/                Self-contained roots, each with its own state
    single-node/           Disposable cluster on one Proxmox node
    multi-node/            Disposable cluster across two Proxmox nodes
    existing-template/     Cluster from templates made by proxmox_setup.sh
    storage/               Long-lived storage VM
ansible/
  site.yml                 distribution check, common, k8s_prep, k3s_server, k3s_agent, storage
  README.md                Ansible documentation
  ansible.cfg              Uses inventory.d/ as the default inventory
  inventory.d/             Generated inventory fragments (read as a directory)
    10-cluster.ini           From a cluster example (gitignored)
    20-storage.ini           From the storage example (gitignored)
    group_vars/              Your overrides of the role defaults (gitignored)
  inventory.examples/      Example fragments and group_vars to copy into inventory.d/
  roles/
    common/                Package update, SSH hardening, sudo, reboot
    k8s_prep/              Swap, kernel modules, sysctl for any Kubernetes
    k3s_server/            k3s server, Cilium (bundled values), Helm, Hubble
    k3s_agent/             k3s agent join
    storage/               Data disk, firewall, Docker, SeaweedFS
```

## Module documentation

Each module ([vm_template](terraform/modules/vm_template),
[k8s_cluster](terraform/modules/k8s_cluster) and
[storage_node](terraform/modules/storage_node)) has a README with usage
notes and a table of its inputs and outputs. The tables between the
`BEGIN_TF_DOCS` markers come from [terraform-docs](https://terraform-docs.io),
so regenerate them from `terraform/` after you change variables or outputs.

```bash
for d in modules/* examples/*; do terraform-docs -c .terraform-docs.yml "$d"; done
```

## Roles

| Role | Target | Purpose |
| --- | --- | --- |
| `common` | all nodes | It updates packages, hardens SSH, configures sudo and reboots when anything changed. |
| `k8s_prep` | `k8s_cluster` (any distribution) | It turns swap off and sets up kernel modules and sysctl. |
| `k3s_server` | control plane (k3s only) | It installs the k3s server, Cilium, Helm and Hubble. |
| `k3s_agent` | workers (k3s only) | It joins the workers to the cluster as k3s agents. |
| `storage` | storage nodes | It sets up the data disk, the firewall, Docker and SeaweedFS. |

## Terraform and Ansible separation

Each Terraform root writes its own fragment into `ansible/inventory.d/` with
infrastructure facts such as IPs, users, the SSH key path, the distribution,
the control plane IP and the cluster CIDRs. The cluster root writes
`10-cluster.ini`, the storage root writes `20-storage.ini`, and Ansible reads
the whole directory and merges them.

Everything else (versions, install URLs, the Cilium values and the reboot
policy) has a default in the `defaults/main.yml` of its role, so the
playbook runs without any extra files, and you change a setting by putting
it in `ansible/inventory.d/group_vars/`. Ansible also runs without Terraform
if you copy the files in `ansible/inventory.examples/` into
`ansible/inventory.d/` and edit them.

## Using it from another repository

Another repository only needs its own Terraform roots and inventory. It
references the modules by a pinned git ref and runs the playbook from a
clone of this repository checked out at the same ref, with a layout like
the one below.

```
my-infra/
  terraform/cluster/main.tf  source = "git::https://github.com/m0r4a/k8s-in-proxmox.git//terraform/modules/k8s_cluster?ref=<tag>"
  ansible/inventory.d/       fragments written by Terraform (ansible = { path = "../../ansible" })
    group_vars/all.yml       overrides, e.g. cilium_values_file or cilium_values_url
```

```bash
cd k8s-in-proxmox/ansible
ansible-playbook -i ../../my-infra/ansible/inventory.d site.yml
```

`cilium_values_file` and `cilium_values_url` let the Cilium values live with
the rest of the cluster configuration of that repository instead of in this
one.
