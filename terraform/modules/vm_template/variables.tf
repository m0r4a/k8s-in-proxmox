variable "proxmox_nodes" {
  description = "Proxmox nodes to create a template on, in the same shape k8s_cluster and storage_node take. Each entry gets a template with its template_vm_id on its node, except entries with template_node set, which reuse the template of another entry (shared storage)."
  type = map(object({
    proxmox_node_name      = optional(string)
    template_vm_id         = number
    template_node          = optional(string)
    network_bridge         = optional(string, "vmbr0")
    datastore_id           = optional(string, "local-lvm")
    cloudinit_datastore_id = optional(string, "local-lvm")
  }))

  validation {
    condition     = length(var.proxmox_nodes) > 0
    error_message = "At least one Proxmox node is required."
  }

  validation {
    condition     = alltrue([for h in values(var.proxmox_nodes) : length(h.proxmox_node_name) > 0 if h.proxmox_node_name != null])
    error_message = "proxmox_node_name must not be empty."
  }

  validation {
    condition     = alltrue([for h in values(var.proxmox_nodes) : h.template_vm_id > 0 && h.template_vm_id < 999999999])
    error_message = "All template VM IDs must be positive integers."
  }

  validation {
    condition     = alltrue([for h in values(var.proxmox_nodes) : contains(keys(var.proxmox_nodes), h.template_node) if h.template_node != null])
    error_message = "template_node must be one of the keys of proxmox_nodes."
  }

  validation {
    condition     = alltrue([for h in values(var.proxmox_nodes) : can(regex("^vmbr[0-9]+$", h.network_bridge))])
    error_message = "All network_bridge values must be valid Proxmox bridge names (e.g. vmbr0, vmbr1)."
  }

  # The image and the snippet are named after template_name, so two templates
  # on the same Proxmox node would overwrite each other's files.
  validation {
    condition = length(distinct([
      for k, h in var.proxmox_nodes : coalesce(h.proxmox_node_name, k) if h.template_node == null
    ])) == length([for h in values(var.proxmox_nodes) : h if h.template_node == null])
    error_message = "Two entries that create a template point at the same Proxmox node. Give one of them template_node, or use a second module call with another template_name."
  }

  validation {
    condition = length(distinct([
      for h in values(var.proxmox_nodes) : h.template_vm_id if h.template_node == null
    ])) == length([for h in values(var.proxmox_nodes) : h if h.template_node == null])
    error_message = "Template VM IDs must be unique across the Proxmox cluster."
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

variable "tags" {
  description = "Tags applied to the template VM."
  type        = list(string)
  default     = ["template", "rocky10"]
}

variable "ssh_public_key" {
  description = "SSH public key (raw or path to a .pub file) injected into the templates via cloud-init. Clones made by k8s_cluster and storage_node set their own."
  type        = string
  default     = null
}
