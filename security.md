# Security

This document covers the security measures applied by the project, the
permissions required for each component, and how to avoid lockout
scenarios.

## Proxmox host

### Getting started (one-time setup)

The `proxmox_setup.sh` script requires root SSH access to the PVE host
because it runs `pveum`, `qm`, `pvesm` and `useradd`. After setup,
Terraform uses the API token for VM management and the restricted
`tfprov` SSH user for snippet uploads.

```bash
# Default: PVE role/user/token + tfprov SSH user (template via Terraform module)
cd terraform/scripts
./proxmox_setup.sh --host 192.168.1.2 --ssh-key ~/.ssh/id_ed25519

# Optional: also create the cloud-init template via the script
./proxmox_setup.sh --host 192.168.1.2 --ssh-key ~/.ssh/id_ed25519 --create-template
```

The script:
1. Creates a PVE role (`TerraformProv`) with minimum VM management privileges
2. Creates a PVE user (`terraform-prov@pve`) with that role
3. Generates an API token for the user
4. Adds the `snippets` and `import` content types to the `local` storage,
   keeping the ones it already has, and creates their directories (the
   provider's `sudo tee` upload does not create them)
5. Creates the `tfprov` SSH user with your public key and a limited
   sudoers file (skip with `--skip-svc-user`)
6. Optionally (with `--create-template`): downloads Rocky 10, creates the
   template VM, and creates the qemu-guest-agent snippet

The script does not modify SSH settings on your PVE host. Your root SSH
access, password authentication settings, and sshd_config are left
untouched.

### The tfprov SSH user

The Proxmox API cannot upload snippets, so the bpg provider writes the
`vm_template` cloud-init snippet over SSH. Everything else (create, clone,
start, stop, configure, image download, disk import through `import_from`)
goes through the API token.

Terraform connects as `tfprov` (`proxmox_ssh_user`, the default in both
roots). When its SSH user is not root, the provider runs commands with
`sudo`, so the script writes `/etc/sudoers.d/tfprov` with the minimal rules
from the bpg docs:

```
tfprov ALL=(root) NOPASSWD: /usr/sbin/pvesm apiinfo
tfprov ALL=(root) NOPASSWD: /usr/bin/tee ^/var/lib/vz/snippets/[a-zA-Z0-9_][a-zA-Z0-9_.-]*$
```

`tfprov` can only report the storage API version and write files directly
inside the snippets directory. It does not get `qm` or `pvesm` in general,
which would be equivalent to root. The regex rule needs sudo 1.9.10 or newer
(PVE 8 ships it), and the script installs `sudo` if the host lacks it. The
file is checked with `visudo -cf` before it is installed. To check it by
hand:

```bash
ssh tfprov@<pve-host> sudo pvesm apiinfo   # prints APIVER, no password prompt
```

With `--skip-svc-user` no user is created and you must set
`proxmox_ssh_user = "root"`. In a multi-node Proxmox cluster, run the script
against every node so each one has `tfprov`.

### PVE API permissions

The `TerraformProv` role has these privileges:

```
Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Datastore.Allocate
Pool.Allocate Pool.Audit
Sys.Audit Sys.Console Sys.Modify
VM.Allocate VM.Audit VM.Clone
VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk
VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options
VM.Migrate VM.PowerMgmt SDN.Use
VM.GuestAgent.Audit VM.GuestAgent.Unrestricted
```

These are the minimum required for the bpg provider to manage VMs. The
token has privilege separation disabled (`--privsep 0`) so it inherits
all user permissions.

## VMs (cluster nodes and storage)

### SSH hardening

Applied by the `common` ansible role on all VMs (not the PVE host).
Controlled by `ssh_hardening_enabled: true` (default). Set to `false` in
`ansible/inventory.d/group_vars/all.yml` to disable.

| Setting | Default | Why |
| --- | --- | --- |
| PermitRootLogin | `no` | No direct root SSH to VMs |
| PasswordAuthentication | `no` | Key-based auth only on VMs |
| MaxAuthTries | `3` | Brute-force limit |
| LoginGraceTime | `30` | Drop slow connections |

### Lockout protection on VMs

SSH hardening only runs after the `common` role has established a
working SSH connection (ansible connects via the cloud-init user's SSH
key). The `sshd -t` validation in the task prevents malformed config
from being written. The `restart sshd` handler runs at the end of the
play, not immediately, so all other tasks complete first.

If SSH hardening locks you out of a VM:
- Use the Proxmox web console to access the VM
- Log in with the cloud-init password (still works on the console)
- Fix `/etc/ssh/sshd_config` and run `systemctl restart sshd`

To disable SSH hardening entirely:
```yaml
# ansible/inventory.d/group_vars/all.yml
ssh_hardening_enabled: false
```

### Sudo

The cloud-init user has `NOPASSWD: ALL` sudo via a dedicated file in
`/etc/sudoers.d/<user>`. This is required for Ansible to run privileged
tasks without interactive password prompts. The file is validated with
`visudo -cf` before being written. Cloud-init's default wildcard
sudoers file (`90-cloud-init-users`) is removed to prevent duplicates.

### Storage node firewall

Optional, disabled by default. To enable:

```yaml
# ansible/inventory.d/group_vars/storage.yml
seaweedfs_firewall_enabled: true
seaweedfs_allowed_cidr: "10.0.0.0/24"  # your cluster subnet
```

When enabled, uses `firewalld` (Rocky 10 native) to restrict SeaweedFS
ports to the specified CIDR:

| Port | Service | Access |
| --- | --- | --- |
| 22 | SSH | Any (key-based only) |
| 8333 | SeaweedFS S3 | `seaweedfs_allowed_cidr` only |
| 9333, 19333 | SeaweedFS Master (HTTP, gRPC) | `seaweedfs_allowed_cidr` only |
| 8888, 18888 | SeaweedFS Filer (HTTP, gRPC) | `seaweedfs_allowed_cidr` only |
| 8080, 18080 | SeaweedFS Volume (HTTP, gRPC) | `seaweedfs_allowed_cidr` only |
| anything else | | Rejected by the zone |

SeaweedFS runs with host networking. Ports published by Docker are DNATed
through the FORWARD chain and never reach the zone's rules, so with
published ports these restrictions would not apply. With host networking
the ports are ordinary host ports and firewalld filters them. The master
advertises the VM's own address (`seaweedfs_advertise_ip`, the default IPv4
address) so clients outside the VM can reach the volume server.

With the firewall disabled every SeaweedFS port is reachable from anywhere.

Set `seaweedfs_allowed_cidr` to your actual cluster subnet. With the
firewall disabled (the default) its empty default is never used. With the
firewall enabled, the role checks the value before touching firewalld and
stops with an error naming the variable if it is empty or not an IPv4 CIDR.

## Recommendations for production

- Rotate the PVE API token periodically
- Use a VPN or jump host instead of exposing the PVE API to the internet
- Pin the SeaweedFS image to a specific version instead of `latest`
- Set `seaweedfs_allowed_cidr` to the exact cluster CIDR
- Consider adding `fail2ban` on the PVE host for SSH brute-force protection
- Consider using Proxmox API token privilege separation for finer control
- Review the sudoers file periodically: `visudo -c`
