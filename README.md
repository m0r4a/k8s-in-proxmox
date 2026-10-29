# k8s in Proxmox

Terraform and Ansible to provision a disposable Kubernetes cluster on
Proxmox VE, with long-lived SeaweedFS storage next to it. Terraform uses the
`bpg/proxmox` provider and does not care which Kubernetes distribution you
run. Ansible installs k3s today, and kubeadm is planned. The full design is
in [requirements.md](requirements.md) and the security setup in
[security.md](security.md).

## Getting started

### 1. Prerequisites

- Proxmox VE 8.4 or newer with API and SSH access. The template disk is
  imported from an `import` volume, which older versions lack.
- Terraform 1.4 or newer
- Ansible on your workstation
- An SSH key pair (`~/.ssh/id_ed25519`)

### 2. One-time Proxmox setup

Point the setup script at any node of your Proxmox cluster. It logs in as
root over SSH, finds every node of the cluster and sets all of them up:

- a PVE role, API user and API token (once, for the whole cluster)
- the `snippets` and `import` content types on the `local` storage
- `tfprov` on each node, the SSH user Terraform uploads snippets with. Its
  sudo rights cover only that.

Templates are left to the `vm_template` Terraform module unless you pass
`--create-template`, which makes one per node. [security.md](security.md)
explains each step.

```bash
cd terraform/scripts

# Default: PVE role/user/token + tfprov SSH user on every node (template via Terraform)
./proxmox_setup.sh --host 192.168.1.2 --ssh-key ~/.ssh/id_ed25519

# Optional: also create one cloud-init template per node via the script
./proxmox_setup.sh --host 192.168.1.2 --ssh-key ~/.ssh/id_ed25519 --create-template

# A node that joined the cluster later
./proxmox_setup.sh --host 192.168.1.2 --ssh-key ~/.ssh/id_ed25519 --nodes server03
```

Save the token secret from the output. The script also prints the Proxmox
connection block for `terraform.tfvars`. Copy it into the `terraform.tfvars`
of both roots (`terraform/cluster` and `terraform/storage`).

The script does not touch the SSH settings of your Proxmox hosts, so your
root SSH access stays as it was.

### 3. Provision the infrastructure (two roots)

The cluster and the storage node live in separate Terraform roots with
separate state, so destroying the cluster never touches storage.

Storage is long-lived and you apply it once. It clones an existing
template, so create the template first (with the cluster root's
`vm_template` module or `proxmox_setup.sh --create-template`), then:

```bash
cd terraform/storage
cp main.tf.example main.tf                     # edit storage node definitions
cp terraform.tfvars.example terraform.tfvars   # edit with your values
terraform init
terraform apply                                # writes ansible/inventory.d/20-storage.ini
```

The cluster is disposable, so apply and destroy it as often as you like:

```bash
cd ../cluster
cp main.tf.example main.tf                      # edit control-plane/worker nodes
cp terraform.tfvars.example terraform.tfvars    # edit with your values
terraform init
terraform apply                                 # writes ansible/inventory.d/10-cluster.ini
```

Both roots can share the Proxmox connection values through one file:
`terraform apply -var-file=../common.tfvars`.

In `cluster/main.tf`, `distribution` (`k3s`, `kubeadm` or `none`) picks what
Ansible installs. Each node can set `proxmox_node` to run on a specific node
of the Proxmox cluster. Templates and bridge names differ per Proxmox node,
and the `templates` and `network_bridges` maps cover that. The
[k8s_cluster module README](terraform/modules/k8s_cluster/README.md) has the
details and [examples/multi-node](terraform/examples/multi-node) a working
setup.

### 4. Configure with Ansible

`ansible/ansible.cfg` points at `inventory.d/`, so Ansible picks up both
fragments on its own:

```bash
cd ../../ansible
ansible-playbook site.yml
```

With `distribution = "k3s"`, Ansible installs k3s, Cilium, Helm and
SeaweedFS. With `none` it only prepares the nodes (packages, SSH hardening,
swap, kernel modules, sysctl) and leaves installing Kubernetes to you.
There are no kubeadm roles yet, so with `kubeadm` the playbook stops at its
first play with an error.

## Structure

```
terraform/
  cluster/                 Root 1: disposable Kubernetes cluster (own state)
    main.tf.example          Module usage (copy to main.tf, edit nodes)
    versions.tf / providers.tf / variables.tf / terraform.tfvars.example
  storage/                 Root 2: long-lived storage (own state)
    main.tf.example          Module usage (copy to main.tf, edit nodes)
    versions.tf / providers.tf / variables.tf / terraform.tfvars.example
  scripts/
    proxmox_setup.sh       One-time PVE setup for every node of the cluster
  modules/
    vm_template/           Creates a cloud-init template
    k8s_cluster/           Clones template into cluster VMs, writes 10-cluster.ini
    storage_node/          Clones template into storage VMs, writes 20-storage.ini
  examples/                Self-contained roots: single-node, multi-node,
                           existing-template, storage
ansible/
  site.yml                 distribution check, common, k8s_prep, k3s_server, k3s_agent, storage
  README.md                Ansible documentation
  ansible.cfg              Uses inventory.d/ as the default inventory
  inventory.d/             Generated inventory fragments (read as a directory)
    10-cluster.ini           From the cluster root (gitignored)
    20-storage.ini           From the storage root (gitignored)
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

Each module has a README with usage notes and its inputs and outputs:
[vm_template](terraform/modules/vm_template), [k8s_cluster](terraform/modules/k8s_cluster)
and [storage_node](terraform/modules/storage_node). The tables between the
`BEGIN_TF_DOCS` markers come from [terraform-docs](https://terraform-docs.io).
After changing variables or outputs, regenerate them from `terraform/`:

```bash
for d in modules/* examples/*; do terraform-docs -c .terraform-docs.yml "$d"; done
```

## Roles

| Role | Target | Purpose |
| --- | --- | --- |
| `common` | all nodes | Package update, SSH hardening, sudo, reboot |
| `k8s_prep` | `k8s_cluster` (any distribution) | Swap off, kernel modules, sysctl |
| `k3s_server` | control plane (k3s only) | k3s server, Cilium, Helm, Hubble |
| `k3s_agent` | workers (k3s only) | k3s agent join |
| `storage` | storage nodes | Data disk, firewall, Docker, SeaweedFS |

## Terraform and Ansible separation

Each Terraform root writes its own fragment into `ansible/inventory.d/` with
infrastructure facts: IPs, users, SSH key path, distribution, control plane
IP and cluster CIDRs. The cluster root writes `10-cluster.ini` and the
storage root writes `20-storage.ini`. Ansible reads the whole directory and
merges them.

Everything else (versions, install URLs, the Cilium values, reboot policy)
has a default in its role's `defaults/main.yml`, so the playbook runs without
any extra files. To change a setting, put it in
`ansible/inventory.d/group_vars/`. Ansible also runs without Terraform if you
copy the files in `ansible/inventory.examples/` into `ansible/inventory.d/`
and edit them.

## Using it from another repository

Another repository only needs its own Terraform roots and inventory. It
references the modules by a pinned git ref and runs the playbook from a clone
of this repo checked out at the same ref:

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
the rest of that repository's cluster config instead of in this repo.

## Workflow

To replace the cluster and keep storage, run
`cd terraform/cluster && terraform destroy`, edit `main.tf`, run
`terraform apply`, then `cd ../../ansible && ansible-playbook site.yml`.

A cluster `terraform destroy` cannot reach storage, because storage has its
own root and state. The storage VM also sets `prevent_destroy = true` in case
someone destroys the storage root itself by accident.

To reconfigure only storage, run `ansible-playbook site.yml --limit storage`.

To tear storage down on purpose, comment out `prevent_destroy` in
`modules/storage_node/main.tf`, then `cd terraform/storage && terraform destroy`.

## Security

[security.md](security.md) covers:
- Proxmox host SSH setup, the `tfprov` user and lockout protection
- PVE API permissions
- VM SSH hardening and sudo configuration
- The storage node firewall
- Recommendations for production
