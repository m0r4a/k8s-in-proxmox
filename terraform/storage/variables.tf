variable "proxmox_endpoint" {
  description = "Proxmox VE API endpoint, e.g. https://192.168.1.2:8006/."
  type        = string
}

variable "proxmox_api_token" {
  description = "API token in the form \"user@realm!tokenid=secret\"."
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip TLS verification of the Proxmox API."
  type        = bool
  default     = true
}

variable "proxmox_ssh_user" {
  description = "SSH user the provider connects to the Proxmox nodes as."
  type        = string
  default     = "tfprov"
}

variable "proxmox_ssh_private_key_path" {
  description = "Private key for proxmox_ssh_user."
  type        = string
}

variable "vm_user" {
  description = "Cloud-init username for the VMs."
  type        = string
}

variable "vm_password" {
  description = "Cloud-init password for vm_user."
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key (raw or path to a .pub file) added to each VM."
  type        = string
}

variable "ssh_private_key_path" {
  description = "Private key Ansible uses to reach the VMs."
  type        = string
}

variable "network_gateway" {
  description = "IPv4 gateway for the VMs."
  type        = string
}
