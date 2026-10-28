# Single Proxmox node

Creates a Rocky Linux 10 template (9001) on `server01` and a k3s cluster
on the same node: one control plane (`10.0.0.10`) and two workers
(`10.0.0.11`, `10.0.0.12`), all on `vmbr0`. Terraform writes
`ansible/inventory.d/10-cluster.ini` and Ansible installs k3s on the VMs.

Edit `main.tf` for your node name, bridge, VM IDs and IPs.

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
