# Requirements

Provision a disposable Kubernetes cluster on Proxmox VE with persistent
SeaweedFS storage for PVCs. The cluster is rebuilt with a single
`terraform destroy` + `terraform apply` + a GitOps target change.

## Goals

1. Migrate from telmate/proxmox to bpg/proxmox provider.
2. Terraform modules: `vm_template` (creates a cloud-init template),
   `k8s_cluster` (clones that template into the cluster VMs), and
   `storage_node` (clones it into the long-lived storage VMs). The cluster
   and storage modules accept a `template_vm_id` so they work with either
   the template module or a pre-existing template (e.g. one created by
   `proxmox_setup.sh`). The cluster and storage modules run from separate
   Terraform roots with separate state (`terraform/cluster`,
   `terraform/storage`) so a cluster destroy cannot touch storage.
3. Fix lifecycle management: changing CPU or RAM on a VM must not
   recreate it. The bpg provider updates `cpu.cores` and `memory.dedicated`
   in-place and reboots via `reboot_after_update = true`.
4. Add a `storage` role for a VM that runs SeaweedFS in Docker to manage
   PVCs. This VM is outside the Kubernetes cluster.
5. The end goal: the cluster is one `terraform destroy` away, and a new
   cluster can be spun up by changing where the GitOps tool points and running
   `terraform apply`.
6. Keep the Terraform side independent of the Kubernetes distribution.
   `k8s_cluster` takes a `distribution` (`k3s`, `kubeadm` or `none`) and
   only passes it to Ansible, which picks the roles. Only k3s roles exist so
   far; `none` prepares the nodes without installing Kubernetes.
7. Spread cluster VMs across the nodes of a Proxmox cluster, chosen per VM.

## Architecture

```
.
├── terraform/
│   ├── cluster/                # ROOT #1: disposable Kubernetes cluster (own state)
│   │   ├── main.tf             #   How you use the modules (edit this)
│   │   ├── versions.tf / providers.tf / variables.tf / terraform.tfvars.example
│   ├── storage/                # ROOT #2: long-lived storage (own state)
│   │   ├── main.tf             #   How you use the storage module (edit this)
│   │   ├── versions.tf / providers.tf / variables.tf / terraform.tfvars.example
│   ├── scripts/
│   │   └── proxmox_setup.sh    # One-time PVE setup (role, user, token, template)
│   └── modules/
│       ├── vm_template/        # Creates a cloud-init template
│       ├── k8s_cluster/        # Clones template into cluster VMs, writes 10-cluster.ini
│       └── storage_node/       # Clones template into storage VMs, writes 20-storage.ini
└── ansible/
    ├── site.yml                # Orchestrates all roles
    ├── README.md               # Ansible documentation
    ├── ansible.cfg             # inventory = inventory.d
    ├── inventory.d/            # Generated inventory fragments, read as a directory
    │   ├── 10-cluster.ini      #   From the cluster root (gitignored)
    │   ├── 20-storage.ini      #   From the storage root (gitignored)
    │   └── group_vars/         #   Overrides of the role defaults (gitignored)
    ├── inventory.examples/     # Example fragments and group_vars (committed, kept
    │                           #   out of inventory.d so Ansible doesn't load them)
    └── roles/
        ├── common/             # Package update, base packages, reboot
        ├── k8s_prep/           # Swap, kernel modules, sysctl for any Kubernetes
        ├── k3s_server/         # k3s server, Cilium, Helm, Hubble
        ├── k3s_agent/          # k3s agent join
        └── storage/            # Data disk, Docker, SeaweedFS
```

## Terraform and Ansible separation

Terraform owns infrastructure (VMs, IPs, networks). Ansible owns
configuration (packages, Kubernetes, cilium, seaweedfs).

The connection point is the `inventory.d/` directory. Each Terraform root
writes one fragment (`10-cluster.ini`, `20-storage.ini`) with
infrastructure facts only: IPs, users, SSH key path, distribution, control
plane IP, cluster CIDRs. Ansible reads the directory and merges the
fragments. Ansible configuration (versions, install URLs, the Cilium
values, reboot policy) is in each role's `defaults/main.yml` and can be
overridden in `ansible/inventory.d/group_vars/`.

Ansible can run standalone with manual fragments. It does not depend on
Terraform at runtime, only on the inventory fragment format.

## Roles

| Role            | Ansible group   | In cluster | Extra disk | Purpose                                  |
| --------------- | --------------- | ---------- | ---------- | ---------------------------------------- |
| `control-plane` | `control_plane` | yes        | no         | Runs the control plane. At least one.    |
| `worker`        | `worker`        | yes        | no         | Schedules workloads.                     |
| `storage`       | `storage`       | no         | scsi1      | Hosts SeaweedFS for PVCs.                |

`control_plane` and `worker` are children of the `k8s_cluster` group.

## Lifecycle (no recreation on CPU/RAM change)

The bpg provider's `proxmox_virtual_environment_vm` updates `cpu.cores`
and `memory.dedicated` in-place. With `reboot_after_update = true` it
reboots the VM automatically. Disk size changes grow the disk live via
`hotplug = "network,disk,usb"`. All VMs start with their Proxmox node
(`on_boot = true`). Cluster VMs set `migrate = true`, so
changing a node's `proxmox_node` migrates the VM. None of these recreate
the VM.

## Multiple Proxmox nodes

Each entry in the `k8s_cluster` `nodes` map can set `proxmox_node`; it
defaults to the module's `proxmox_node`. A template on local storage is only
visible to its own node, so create one template per Proxmox node (each with
a VM ID unique across the Proxmox cluster) and pass them to `k8s_cluster` as
`templates`. A VM on a node missing from `templates` clones `template_vm_id`
from the module's `proxmox_node`, which needs shared storage. Bridges are
per node as well: `network_bridges` maps a Proxmox node to its bridge when
it differs from `network_bridge`. The `storage_node` module still places
every storage VM on a single `proxmox_node`.

## Template design

The template is a Rocky Linux 10 cloud-init image converted to a Proxmox
template with qemu-guest-agent pre-installed.

There are three ways to create it:

1. The `vm_template` module, by default, downloads a cloud image and
   creates a template VM with a vendor cloud-init snippet that installs
   qemu-guest-agent. This is the recommended path because the template is
   managed in Terraform state.
2. The `vm_template` module with `image_url = null` and `image_file_id` set
   uses an image already on the Proxmox node, as an import volume
   (`local:import/<file>.qcow2`).
3. `proxmox_setup.sh --create-template` creates the template with shell
   commands on the Proxmox node. It is off by default; without the flag the
   script only creates the PVE role, user, token and the `tfprov` SSH user.

The `k8s_cluster` module accepts `template_vm_id` (or one per Proxmox node
through `templates`) and clones whatever template is at that ID. It does not
care how the template was created.

## VM configuration

- BIOS: OVMF (UEFI)
- Machine: q35
- CPU type: max
- EFI disk: 4m, raw format
- SCSI hardware: virtio-scsi-single
- Boot order: scsi0
- Agent: enabled on clones (template has qemu-guest-agent pre-installed)
- Hotplug: network, disk, usb (live disk/NIC changes)

## bpg provider mapping (telmate -> bpg)

| telmate | bpg | Notes |
| --- | --- | --- |
| `proxmox_vm_qemu` | `proxmox_virtual_environment_vm` | |
| `clone = "name"` | `clone { vm_id = 9000 }` | bpg clones by VM ID |
| `scsihw = "virtio-scsi-single"` | `scsi_hardware = "virtio-scsi-single"` | |
| `boot = "order=scsi0"` | `boot_order = ["scsi0"]` | |
| `agent = 1` | `agent { enabled = true }` | |
| `cicustom = "vendor=..."` | `initialization { vendor_data_file_id = ... }` | |
| `ipconfig0 = "ip=..."` | `initialization { ip_config { ipv4 { address = ... } } }` | |
| `ciuser`, `cipassword`, `sshkeys` | `initialization { user_account { ... } }` | |
| `disks { scsi { scsi0 { ... } } }` | `disk { datastore_id, interface, size }` | |
| `network { bridge, model }` | `network_device { bridge, model }` | |
| `serial { id = 0 }` | `serial_device { device = "socket" }` | |
| `vm_state = "running"` | `started = true` | |
| `automatic_reboot = true` | `reboot_after_update = true` | |

## Cluster swap workflow

1. `cd terraform/cluster && terraform destroy`. Storage lives in a separate
   root and state, so it is untouched.
2. Edit node IPs, counts or `distribution` in `cluster/main.tf`, and point
   the GitOps tool at the new cluster.
3. `cd terraform/cluster && terraform apply` brings the new cluster up.
4. `cd ../../ansible && ansible-playbook -i inventory.d/ site.yml`

## Prerequisites

- Proxmox VE 8.4 or newer with API + SSH access.
- Terraform >= 1.4.
- Ansible on your workstation.
- SSH key pair for the Proxmox node and the VMs.
- A PVE API user + token (created by `proxmox_setup.sh` or manually).
- The `snippets` and `import` content types enabled on the `local` storage
  (`proxmox_setup.sh` does this).
