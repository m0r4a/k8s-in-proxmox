# Storage node

This example creates one long-lived SeaweedFS VM (`storage1` at
`10.0.0.30`) with a 200 GB data disk and writes
`ansible/inventory.d/20-storage.ini`.

The VM clones an existing template (9001), so create that template first
with the `vm_template` module of the cluster root or with
`proxmox_setup.sh --create-template`. Keep this example in its own root and
state, away from the cluster, so that destroying the cluster never touches
storage.

## Usage

The example pulls the modules from the `main` branch on GitHub, so it does
not pick up local changes to `terraform/modules/`, but it still writes the
Ansible inventory into the `ansible/` directory of this clone.

```bash
cp terraform.tfvars.example terraform.tfvars   # fill in your values
terraform init
terraform apply
cd ../../../ansible && ansible-playbook -i inventory.d/ site.yml
```

The VM has `prevent_destroy`, so Terraform refuses `terraform destroy` here.
To remove the VM, comment out `prevent_destroy` in the `storage_node`
module first and then run `terraform destroy`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.9.0 |
| proxmox | 0.118.1 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| storage_node | github.com/m0r4a/k8s-in-proxmox//terraform/modules/storage_node | main |

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
