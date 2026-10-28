variable "proxmox_endpoint" {
  description = "Proxmox VE API endpoint."
  type        = string

  validation {
    condition     = can(regex("^https?://.+", var.proxmox_endpoint))
    error_message = "proxmox_endpoint must be a valid HTTP(S) URL."
  }
}

variable "proxmox_api_token" {
  description = "API token in the form \"user@realm!tokenid=secret\"."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^.+@.+!.+=.+", var.proxmox_api_token))
    error_message = "proxmox_api_token must be in the form \"user@realm!tokenid=secret\"."
  }
}

variable "proxmox_insecure" {
  description = "Skip TLS verification."
  type        = bool
  default     = true
}

variable "proxmox_ssh_user" {
  description = "SSH user the provider connects to the Proxmox node as (snippet uploads). proxmox_setup.sh creates tfprov with the sudo rules it needs."
  type        = string
  default     = "tfprov"

  validation {
    condition     = length(var.proxmox_ssh_user) > 0
    error_message = "proxmox_ssh_user must not be empty."
  }
}

variable "proxmox_ssh_private_key_path" {
  description = "Path to the SSH private key for the Proxmox node."
  type        = string

  validation {
    condition     = can(file(pathexpand(var.proxmox_ssh_private_key_path)))
    error_message = "Proxmox SSH private key file does not exist at the specified path."
  }
}

variable "proxmox_node" {
  description = "Proxmox node where VMs will be created."
  type        = string

  validation {
    condition     = length(var.proxmox_node) > 0
    error_message = "proxmox_node must not be empty."
  }
}

variable "template_vm_id" {
  description = "VM ID of an existing cloud-init template to clone. The storage root does not create the template; set this to the template made by the cluster root's vm_template module (default 9001) or by proxmox_setup.sh."
  type        = number
  default     = 9001

  validation {
    condition     = var.template_vm_id > 0 && var.template_vm_id < 999999999
    error_message = "template_vm_id must be a positive integer."
  }
}

variable "vm_user" {
  description = "Cloud-init username for the VMs."
  type        = string

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]*$", var.vm_user))
    error_message = "vm_user must be a valid Unix username (lowercase, start with letter or underscore)."
  }
}

variable "vm_password" {
  description = "Cloud-init password for vm_user."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.vm_password) > 0
    error_message = "vm_password must not be empty."
  }
}

variable "ssh_public_key" {
  description = "SSH public key (raw or path to a .pub file) added to each VM."
  type        = string

  validation {
    condition     = length(var.ssh_public_key) > 0
    error_message = "ssh_public_key must not be empty."
  }
}

variable "ssh_private_key_path" {
  description = "Path to the SSH private key Ansible uses to reach the nodes."
  type        = string

  validation {
    condition     = can(file(pathexpand(var.ssh_private_key_path)))
    error_message = "SSH private key file does not exist at the specified path."
  }
}

variable "network_bridge" {
  description = "Proxmox bridge the VM network devices attach to."
  type        = string
  default     = "vmbr0"

  validation {
    condition     = can(regex("^vmbr[0-9]+$", var.network_bridge))
    error_message = "network_bridge must be a valid Proxmox bridge name (e.g. vmbr0, vmbr1)."
  }
}

variable "network_gateway" {
  description = "IPv4 gateway for the VMs."
  type        = string

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.network_gateway))
    error_message = "network_gateway must be a valid IPv4 address."
  }
}
