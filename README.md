# k3s in Proxmox

Provision a disposable Kubernetes cluster on Proxmox VE with persistent
SeaweedFS storage. Built on the `bpg/proxmox` provider. The Terraform
modules are distribution-agnostic; Ansible currently installs k3s, with
kubeadm planned. See [requirements.md](requirements.md) for full
documentation and [security.md](security.md) for security measures.

## Getting started

### 1. Prerequisites

- Proxmox VE 8.4 or newer with API + SSH access (the template disk is
  imported from an `import` volume)
- Terraform >= 1.4
- Ansible on your workstation
- An SSH key pair (`~/.ssh/id_ed25519`)

### 2. One-time Proxmox setup

Run the setup script against the PVE host. It connects as root over SSH and
creates a PVE role, an API user and an API token, enables the `snippets` and
`import` content types on `local`, and creates `tfprov`, the restricted SSH
user Terraform uses for snippet uploads. It does not create the
template unless you pass `--create-template`; by default the `vm_template`
Terraform module does that. See [security.md](security.md) for details.

```bash
cd terraform/scripts

# Default: PVE role/user/token + tfprov SSH user (template via Terraform)
./proxmox_setup.sh --host 192.168.1.2 --ssh-key ~/.ssh/id_ed25519

# Optional: also create the cloud-init template via the script
./proxmox_setup.sh --host 192.168.1.2 --ssh-key ~/.ssh/id_ed25519 --create-template
```

Save the token secret from the output. The script also prints the Proxmox
connection block for `terraform.tfvars`; copy it into the `terraform.tfvars`
of both roots (`terraform/cluster` and `terraform/storage`).

The script does not modify SSH settings on your PVE host. Your root SSH
access is left untouched.

### 3. Provision the infrastructure (two roots)

The cluster and the storage node live in separate Terraform roots with
separate state, so a cluster `terraform destroy` never touches storage.

Storage is long-lived: apply it once. It clones an existing template, so
create the template first (with the cluster root's `vm_template` module or
`proxmox_setup.sh --create-template`), then:

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

The shared Proxmox connection values can live in one file passed to both
roots with `terraform apply -var-file=../common.tfvars`.

In `cluster/main.tf`, `distribution` (`k3s`, `kubeadm` or `none`) picks what
Ansible installs, and each node can set `proxmox_node` to land on a specific node of
the Proxmox cluster. See the
[k8s_cluster module README](terraform/modules/k8s_cluster/README.md).

### 4. Configure with Ansible

Point Ansible at the `inventory.d/` directory and it merges both fragments:

```bash
cd ../../ansible
ansible-playbook -i inventory.d/ site.yml
```

With `distribution = "k3s"`, Ansible installs k3s, Cilium, Helm, Flux, and
SeaweedFS. With `none` it only prepares the nodes (packages, SSH hardening,
swap, kernel modules, sysctl) and installs no Kubernetes, so you can install
it yourself. `kubeadm` has no roles yet, so the playbook stops at the first
play with an error.

## Structure

```
terraform/
  cluster/                 ROOT #1 - disposable Kubernetes cluster (own state)
    main.tf.example          Module usage (copy to main.tf, edit nodes)
    versions.tf / providers.tf / variables.tf / terraform.tfvars.example
  storage/                 ROOT #2 - long-lived storage (own state)
    main.tf.example          Module usage (copy to main.tf, edit nodes)
    versions.tf / providers.tf / variables.tf / terraform.tfvars.example
  scripts/
    proxmox_setup.sh       One-time PVE setup
  modules/
    vm_template/           Creates a cloud-init template
    k8s_cluster/           Clones template into cluster VMs, writes 10-cluster.ini
    storage_node/          Clones template into storage VMs, writes 20-storage.ini
  examples/                Self-contained roots: single-node, multi-node,
                           existing-template, storage
ansible/
  site.yml                 distribution check -> common -> k8s_prep -> k3s_server -> k3s_agent -> storage
  README.md                Ansible documentation
  ansible.cfg              Uses inventory.d/ as the default inventory
  inventory.d/             Generated inventory fragments (read as a directory)
    10-cluster.ini           From the cluster root (gitignored)
    20-storage.ini           From the storage root (gitignored)
    group_vars/              Your overrides of the role defaults (gitignored)
  inventory.examples/      Example fragments and group_vars to copy into inventory.d/
  roles/
    common/                Package update, SSH hardening, sudo
    k8s_prep/              Swap, kernel modules, sysctl for any Kubernetes
    k3s_server/            k3s server, Cilium, Helm, Flux
    k3s_agent/             k3s agent join
    storage/               Data disk, firewall, Docker, SeaweedFS
```

## Module documentation

Each module has a README with usage, notes and its inputs and outputs:
[vm_template](terraform/modules/vm_template), [k8s_cluster](terraform/modules/k8s_cluster),
[storage_node](terraform/modules/storage_node). The tables between the
`BEGIN_TF_DOCS` markers are generated by [terraform-docs](https://terraform-docs.io);
after changing variables or outputs, regenerate them from `terraform/`:

```bash
for d in modules/* examples/*; do terraform-docs -c .terraform-docs.yml "$d"; done
```

## Roles

| Role | Target | Purpose |
| --- | --- | --- |
| `common` | all nodes | Package update, SSH hardening, sudo, reboot |
| `k8s_prep` | `k8s_cluster` (any distribution) | Swap off, kernel modules, sysctl |
| `k3s_server` | control plane (k3s only) | k3s server, Cilium, Helm, Flux |
| `k3s_agent` | workers (k3s only) | k3s agent join |
| `storage` | storage nodes | Data disk, firewall, Docker, SeaweedFS |

## Terraform and Ansible separation

Each Terraform root writes its own fragment into `ansible/inventory.d/`
with infrastructure facts (IPs, users, SSH key path, distribution, control
plane IP, cluster CIDRs): the cluster root writes `10-cluster.ini`, the
storage root writes `20-storage.ini`. Ansible reads the whole directory and
merges them. Ansible configuration (versions, install URLs, the Cilium
values, reboot policy) is in each role's `defaults/main.yml`, so the
playbook works with no extra files; override any of it in
`ansible/inventory.d/group_vars/`. Ansible can run standalone with manual
fragments (copy the files in `ansible/inventory.examples/` into
`ansible/inventory.d/`).

## Using it from another repository

The repo is self-contained, so another repository can pin it as a git
submodule and keep only its own inventory and overrides:

```
my-infra/
  k3s-in-proxmox/            git submodule add https://github.com/m0r4a/k3s-in-proxmox.git
  terraform/cluster/main.tf  source = "../../k3s-in-proxmox/terraform/modules/k8s_cluster"
  ansible/
    ansible.cfg              inventory = inventory.d
    site.yml                 - ansible.builtin.import_playbook: ../k3s-in-proxmox/ansible/site.yml
    inventory.d/group_vars/  overrides, e.g. cilium_values_file
```

Update it with `git submodule update --remote k3s-in-proxmox`, or pin a tag with
`git -C k3s-in-proxmox checkout <tag>`.

## Workflow

To swap clusters without touching storage, run
`cd terraform/cluster && terraform destroy`, edit `main.tf`, run
`terraform apply`, then `cd ../../ansible && ansible-playbook -i inventory.d/ site.yml`.

Storage is a separate root with its own state, so a cluster
`terraform destroy` cannot reach it. The storage VM also sets
`prevent_destroy = true` in case the storage root itself is destroyed by
accident.

To reconfigure only storage, run
`ansible-playbook -i inventory.d/ site.yml --limit storage`.

To tear storage down on purpose, comment out `prevent_destroy` in
`modules/storage_node/main.tf`, then `cd terraform/storage && terraform destroy`.

## Security

[security.md](security.md) covers:
- Proxmox host SSH setup and lockout protection
- PVE API permissions
- VM SSH hardening and sudo configuration
- Storage node firewall
- Production recommendations
