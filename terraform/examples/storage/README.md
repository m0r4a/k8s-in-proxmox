# Storage node

Creates one long-lived SeaweedFS VM (`storage1`, `10.0.0.30`) with a
200 GB data disk, and writes `ansible/inventory.d/20-storage.ini`.

It clones an existing template (9001), so create that first, from the
cluster root's `vm_template` module or with `proxmox_setup.sh
--create-template`. Keep this in its own root and state, away from the
cluster, so destroying the cluster never touches storage. The VM has
`prevent_destroy`, so `terraform destroy` here is refused until you
comment it out in the module.

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
| storage_node | ../../modules/storage_node | n/a |

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
| storage_node_ips | IPs of the storage nodes. |
| vm_ids | Storage VM IDs by node key. |
<!-- END_TF_DOCS -->
