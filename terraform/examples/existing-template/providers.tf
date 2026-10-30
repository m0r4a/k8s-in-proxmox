provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_insecure

  # Snippet uploads go over SSH as the restricted user proxmox_setup.sh creates.
  ssh {
    agent       = false
    username    = var.proxmox_ssh_user
    private_key = file(pathexpand(var.proxmox_ssh_private_key_path))
  }
}
