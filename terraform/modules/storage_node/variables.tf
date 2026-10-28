variable "proxmox_node" {
  description = "Proxmox node where the storage VMs will be created."
  type        = string

  validation {
    condition     = length(var.proxmox_node) > 0
    error_message = "proxmox_node must not be empty."
  }
}

variable "template_vm_id" {
  description = "VM ID of an existing cloud-init template to clone. The storage root does not create the template; point this at a template made by the cluster root's vm_template module or by proxmox_setup.sh."
  type        = number

  validation {
    condition     = var.template_vm_id > 0 && var.template_vm_id < 999999999
    error_message = "template_vm_id must be a positive integer."
  }
}

variable "clone_datastore_id" {
  description = "Datastore where cloned VM disks are placed."
  type        = string
  default     = "local-lvm"

  validation {
    condition     = length(var.clone_datastore_id) > 0
    error_message = "clone_datastore_id must not be empty."
  }
}

variable "cloudinit_datastore_id" {
  description = "Datastore used for the per-VM cloud-init drive."
  type        = string
  default     = "local-lvm"

  validation {
    condition     = length(var.cloudinit_datastore_id) > 0
    error_message = "cloudinit_datastore_id must not be empty."
  }
}

variable "cluster_name" {
  description = "Prefix prepended to every VM hostname. Empty keeps the map key as the hostname."
  type        = string
  default     = ""

  validation {
    condition     = var.cluster_name == "" || can(regex("^[a-z][a-z0-9-]*$", var.cluster_name))
    error_message = "cluster_name must start with a lowercase letter and contain only lowercase letters, digits, and hyphens."
  }
}

variable "vm_user" {
  description = "Default cloud-init username for the VMs. Overridable per node."
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

variable "nodes" {
  description = "Storage nodes. The map key is the hostname suffix (or full hostname when cluster_name is empty). Every node gets an extra data disk sized by storage_disk_gb."
  type = map(object({
    vmid            = number
    ip              = string
    user            = optional(string)
    password        = optional(string)
    cores           = optional(number)
    memory          = optional(number)
    disk_size_gb    = optional(number)
    storage_disk_gb = optional(number)
  }))

  validation {
    condition     = length(var.nodes) > 0
    error_message = "At least one storage node is required."
  }

  validation {
    condition     = length(var.nodes) == length(distinct([for n in var.nodes : n.vmid]))
    error_message = "All VM IDs must be unique across nodes."
  }

  validation {
    condition     = length(var.nodes) == length(distinct([for n in var.nodes : n.ip]))
    error_message = "All IP addresses must be unique across nodes."
  }

  validation {
    condition     = alltrue([for n in var.nodes : can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", n.ip))])
    error_message = "All node IPs must be valid IPv4 addresses."
  }

  validation {
    condition     = alltrue([for n in var.nodes : n.vmid > 0 && n.vmid < 999999999])
    error_message = "All VM IDs must be positive integers."
  }

  validation {
    condition     = alltrue([for k, n in var.nodes : can(regex("^[a-z][a-z0-9-]*$", k))])
    error_message = "Node map keys must be valid hostnames (lowercase, start with letter, alphanumeric and hyphens only)."
  }

  validation {
    condition     = alltrue([for n in var.nodes : n.cores == null || (n.cores >= 1 && n.cores <= 128)])
    error_message = "Per-node cores must be between 1 and 128."
  }

  validation {
    condition     = alltrue([for n in var.nodes : n.memory == null || (n.memory >= 512 && n.memory <= 1048576)])
    error_message = "Per-node memory must be between 512 MB and 1024 GB."
  }

  validation {
    condition     = alltrue([for n in var.nodes : n.disk_size_gb == null || n.disk_size_gb >= 20])
    error_message = "Per-node disk_size_gb must be at least 20 GB."
  }

  validation {
    condition     = alltrue([for n in var.nodes : n.storage_disk_gb == null || n.storage_disk_gb >= 10])
    error_message = "Per-node storage_disk_gb must be at least 10 GB."
  }
}

variable "cores" {
  description = "Default CPU cores per VM. Overridable per node."
  type        = number
  default     = 2

  validation {
    condition     = var.cores >= 1 && var.cores <= 128
    error_message = "cores must be between 1 and 128."
  }
}

variable "memory" {
  description = "Default memory (MB) per VM. Overridable per node."
  type        = number
  default     = 4096

  validation {
    condition     = var.memory >= 512 && var.memory <= 1048576
    error_message = "memory must be between 512 MB and 1024 GB."
  }
}

variable "disk_size_gb" {
  description = "Default boot disk size in GB. Overridable per node."
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size_gb >= 20
    error_message = "disk_size_gb must be at least 20 GB."
  }
}

variable "storage_disk_gb" {
  description = "Default size in GB of the extra data disk (scsi1) attached to each storage VM. Overridable per node."
  type        = number
  default     = 50

  validation {
    condition     = var.storage_disk_gb >= 10
    error_message = "storage_disk_gb must be at least 10 GB."
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

variable "network_cidr" {
  description = "Network prefix length used when assigning static IPs."
  type        = number
  default     = 24

  validation {
    condition     = var.network_cidr >= 8 && var.network_cidr <= 32
    error_message = "network_cidr must be between 8 and 32."
  }
}

variable "dns_servers" {
  description = "DNS servers written to each VM via cloud-init."
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]

  validation {
    condition     = length(var.dns_servers) > 0
    error_message = "At least one DNS server is required."
  }

  validation {
    condition     = alltrue([for s in var.dns_servers : can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", s))])
    error_message = "All DNS servers must be valid IPv4 addresses."
  }
}

variable "ansible" {
  description = "Ansible integration. When enabled, writes inventory.d/20-storage.ini to the ansible directory."
  type = object({
    enabled = bool
    path    = optional(string, "")
  })
  default = {
    enabled = false
    path    = ""
  }

  validation {
    condition     = !var.ansible.enabled || var.ansible.path != ""
    error_message = "ansible.path is required when ansible.enabled is true."
  }
}

variable "tags" {
  description = "Tags applied to every VM in addition to the storage/cluster tags."
  type        = list(string)
  default     = []
}
