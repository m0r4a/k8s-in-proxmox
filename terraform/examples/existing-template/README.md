# Existing templates

Uses templates made by the setup script instead of the `vm_template`
module:

```bash
./proxmox_setup.sh --host 192.168.1.2 --ssh-key ~/.ssh/id_ed25519 --create-template
```

The script creates one template per node starting at `--template-id`
(default 9000), in node-name order, and prints the map to pass as
`templates`. This example assumes `server01 = 9000` and
`server02 = 9001`, and creates a `lab-` prefixed cluster with a worker
on each node.

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
