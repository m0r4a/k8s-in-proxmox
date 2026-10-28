variable "proxmox_node" {
  description = "Proxmox node where the template will be created."
  type        = string

  validation {
    condition     = length(var.proxmox_node) > 0
    error_message = "proxmox_node must not be empty."
  }
}

variable "template_vm_id" {
  description = "VM ID to assign to the template. Must be unique in the Proxmox cluster."
  type        = number

  validation {
    condition     = var.template_vm_id > 0 && var.template_vm_id < 999999999
    error_message = "template_vm_id must be a positive integer."
  }
}

variable "template_name" {
  description = "Name shown in Proxmox for the template VM."
  type        = string
  default     = "rocky10-cloudinit"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.template_name))
    error_message = "template_name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "datastore_id" {
  description = "Datastore used for the template boot disk."
  type        = string
  default     = "local-lvm"

  validation {
    condition     = length(var.datastore_id) > 0
    error_message = "datastore_id must not be empty."
  }
}

variable "image_url" {
  description = "URL of a cloud image to download. Set to null to use an existing image via image_file_id."
  type        = string
  default     = "https://dl.rockylinux.org/pub/rocky/10/images/x86_64/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2"

  validation {
    condition     = var.image_url == null || can(regex("^https?://", var.image_url))
    error_message = "image_url must be a valid HTTP(S) URL or null."
  }
}

variable "image_file_id" {
  description = "File ID of an existing cloud image in a storage with the import content type (e.g. \"local:import/rocky10.qcow2\"). Set image_url to null to use this."
  type        = string
  default     = null

  validation {
    condition     = var.image_file_id == null || can(regex("^[a-zA-Z0-9_-]+:import/.+", var.image_file_id))
    error_message = "image_file_id must be an import volume, \"datastore:import/file\" (e.g. \"local:import/rocky10.qcow2\"), or null."
  }
}

variable "cores" {
  description = "CPU cores for the template. Cloned VMs override this."
  type        = number
  default     = 2

  validation {
    condition     = var.cores >= 1 && var.cores <= 128
    error_message = "cores must be between 1 and 128."
  }
}

variable "memory" {
  description = "Memory (MB) for the template. Cloned VMs override this."
  type        = number
  default     = 2048

  validation {
    condition     = var.memory >= 512 && var.memory <= 1048576
    error_message = "memory must be between 512 MB and 1024 GB."
  }
}

variable "disk_size_gb" {
  description = "Boot disk size in GB. Cloned VMs can only grow this."
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size_gb >= 20
    error_message = "Disk size must be at least 20 GB."
  }
}

variable "vm_user" {
  description = "Cloud-init username on the template. Clones made by k8s_cluster and storage_node set their own."
  type        = string

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]*$", var.vm_user))
    error_message = "vm_user must be a valid Unix username (lowercase, start with letter or underscore)."
  }
}

variable "ssh_public_keys" {
  description = "List of SSH public keys injected into the template via cloud-init."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for k in var.ssh_public_keys : can(regex("^(ssh-rsa|ssh-ed25519|ssh-dss|ecdsa-sha2-nistp) ", k))])
    error_message = "All ssh_public_keys entries must be valid SSH public keys (ssh-rsa, ssh-ed25519, etc.)."
  }
}

variable "tags" {
  description = "Tags applied to the template VM."
  type        = list(string)
  default     = ["template", "rocky10"]
}

variable "network_bridge" {
  description = "Proxmox bridge the template network device attaches to."
  type        = string
  default     = "vmbr0"

  validation {
    condition     = can(regex("^vmbr[0-9]+$", var.network_bridge))
    error_message = "network_bridge must be a valid Proxmox bridge name (e.g. vmbr0, vmbr1)."
  }
}
