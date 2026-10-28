# Multiple Proxmox nodes

Spreads a k3s cluster across the two nodes of a Proxmox cluster:

| VM | Proxmox node | Template | Bridge |
| --- | --- | --- | --- |
| control-plane (`10.0.0.10`) | `server01` | 9001 | `vmbr1` |
| worker1 (`10.0.0.11`) | `server01` | 9001 | `vmbr1` |
| worker2 (`10.0.0.12`) | `server02` | 9002 | `vmbr0` |

Each Proxmox node gets its own template, because templates on `local-lvm`
are only visible to their node, and `templates` tells `k8s_cluster`
which one to clone for each VM. The VM network sits on a bridge with a
different name on each node, which `network_bridges` maps.

Run `proxmox_setup.sh` first so every node has the `tfprov` SSH user.
To add a worker on `server02` later, add it to `nodes` and apply again;
the existing VMs are left alone.

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars   # fill in your values
terraform init
terraform apply
cd ../../../ansible && ansible-playbook -i inventory.d/ site.yml
```

Run `terraform destroy` when you are done.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.4.0 |
| proxmox | 0.118.1 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| k8s_cluster | ../../modules/k8s_cluster | n/a |
| vm_template | ../../modules/vm_template | n/a |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| network_gateway | IPv4 gateway for the VMs. | `string` | n/a | yes |
| proxmox_api_token | API token in the form "user@realm!tokenid=secret". | `string` | n/a | yes |
| proxmox_endpoint | Proxmox VE API endpoint, e.g. https://192.168.1.2:8006/. | `string` | n/a | yes |
| proxmox_ssh_private_key_path | Private key for proxmox_ssh_user. | `string` | n/a | yes |
| ssh_private_key_path | Private key Ansible uses to reach the VMs. | `string` | n/a | yes |
| ssh_public_key | SSH public key (raw or path to a .pub file) added to each VM. | `string` | n/a | yes |
| vm_password | Cloud-init password for vm_user. | `string` | n/a | yes |
| vm_user | Cloud-init username for the VMs. | `string` | n/a | yes |
| proxmox_insecure | Skip TLS verification of the Proxmox API. | `bool` | `true` | no |
| proxmox_ssh_user | SSH user the provider connects to the Proxmox nodes as. | `string` | `"tfprov"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| control_plane_ip | IP of the control-plane node. |
| node_ips | IPs of the cluster members. |
| vm_ids | Cluster VM IDs by node key. |
<!-- END_TF_DOCS -->
