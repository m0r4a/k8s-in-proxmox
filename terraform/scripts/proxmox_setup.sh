#!/usr/bin/env bash
# Configures a Proxmox VE node or cluster for Terraform provisioning with the
# bpg provider.
#
# Cluster-wide (stored in /etc/pve, done once): PVE role, user, API token and
# the snippets/import content types on 'local'.
# Per node (done on every node of the cluster): sudo, the restricted SSH user
# for the provider (tfprov, sudo limited to snippet uploads), the snippets and
# import directories and, with --create-template, a cloud-init template.
#
# Nodes are discovered from /cluster/status on --host; a standalone node is a
# one-node cluster. Template creation is off unless --create-template is
# passed; the vm_template Terraform module creates templates by default.

# Usage: ./proxmox_setup.sh --host <IP> [options]

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $*"; }
info() { echo -e "${CYAN}[i]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
die() {
	echo -e "${RED}[✗]${NC} $*" >&2
	exit 1
}
skip() { echo -e "${YELLOW}[~]${NC} $*, skipping"; }

PVE_HOST=""
SSH_USER="root"
SSH_KEY=""
SSH_PASS=""

ROLE_NAME="TerraformProv"
TF_USER="terraform-prov"
TF_REALM="pve"
TF_PASS=""
TOKEN_NAME="mytoken"
SVC_USER="tfprov"
SVC_PUBKEY=""
SKIP_SVC_USER=false

NODES_FILTER=""
UNINSTALL_NODES=""
declare -A NODE_ADDR_OVERRIDE=()

TEMPLATE_ID="9000"
TEMPLATE_NAME="rocky10-cloudinit"
STORAGE="local-lvm"
ROCKY_URL="https://dl.rockylinux.org/pub/rocky/10/images/x86_64/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2"
ROCKY_IMG="/root/rocky10-cloudinit.qcow2"
SNIPPET_NAME="qemu-guest-agent.yml"

SKIP_TEMPLATE=true
SKIP_SNIPPET=true
UNINSTALL=false

ROLE_PRIVS="Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit \
Pool.Allocate Pool.Audit \
Sys.Audit Sys.Console Sys.Modify \
VM.Allocate VM.Audit VM.Clone \
VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk \
VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options \
VM.Migrate VM.PowerMgmt SDN.Use \
Datastore.Allocate \
VM.GuestAgent.Audit VM.GuestAgent.Unrestricted"

usage() {
	cat <<EOF
$(echo -e "${BOLD}proxmox_setup.sh${NC}"): Proxmox Terraform + cloud-init setup

$(echo -e "${BOLD}USAGE${NC}")
  $(basename "$0") --host <IP> [options]

$(echo -e "${BOLD}CONNECTION${NC}")
  --host <IP>            Any node of the cluster          (required)
  --ssh-user <user>      SSH login user                  (default: root)
  --ssh-key <path>       Path to private key             (recommended)
  --ssh-pass <pass>      SSH password (requires sshpass)

$(echo -e "${BOLD}NODES${NC}")
  --nodes <a,b>          Only set up these nodes         (default: all nodes)
  --node-address <n=ip>  Reach node n at ip instead of the address in
                         /cluster/status (repeatable)

$(echo -e "${BOLD}TERRAFORM USER${NC}")
  --tf-user <name>       PVE username                    (default: terraform-prov)
  --tf-pass <pass>       PVE user password               (prompted if the user is new)
  --token-name <name>    API token name                  (default: mytoken)

$(echo -e "${BOLD}PROVIDER SSH USER${NC}")
  --svc-user <name>      SSH user Terraform connects as  (default: tfprov)
  --svc-pubkey <path>    Public key authorized for it    (default: <--ssh-key>.pub)
  --skip-svc-user        Don't create it; Terraform keeps using root over SSH

$(echo -e "${BOLD}TEMPLATE${NC}")
  --template-id <id>     VM ID of the first node's template; the Nth node
                         (sorted by name) gets <id>+N-1 (default: 9000)
  --template-name <name> VM name for the templates       (default: rocky10-cloudinit)
  --storage <pool>       Proxmox storage pool            (default: local-lvm)
  --rocky-url <url>      Override Rocky Linux image URL

  --create-template      Create a cloud-init template and snippet on each node
                         (skipped by default; use the vm_template Terraform
                         module instead)
  --skip-template        Skip template creation (default)
  --skip-snippet         Skip qemu-guest-agent snippet creation (default)

$(echo -e "${BOLD}TEARDOWN${NC}")
  --uninstall            Remove everything this script created, on every node
                         and cluster-wide (role, user, token)
  --uninstall-node <a,b> Remove only the per-node resources of these nodes;
                         the role, user and token stay

$(echo -e "${BOLD}EXAMPLES${NC}")
  # Setup PVE role/user/token + SSH user tfprov on every node:
  $(basename "$0") --host 192.168.1.10 --ssh-key ~/.ssh/id_ed25519

  # Add a node that joined the cluster later:
  $(basename "$0") --host 192.168.1.10 --ssh-key ~/.ssh/id_ed25519 --nodes server03

  # Full setup including one template per node:
  $(basename "$0") --host 192.168.1.10 --ssh-key ~/.ssh/id_ed25519 --create-template

  # Remove a node from the setup before taking it out of the cluster:
  $(basename "$0") --host 192.168.1.10 --ssh-key ~/.ssh/id_ed25519 --uninstall-node server03

  # Tear everything down:
  $(basename "$0") --host 192.168.1.10 --ssh-key ~/.ssh/id_ed25519 --uninstall
EOF
	exit 0
}

# Args

[[ $# -eq 0 ]] && usage

while [[ $# -gt 0 ]]; do
	case "$1" in
	--host)
		PVE_HOST="$2"
		shift 2
		;;
	--ssh-user)
		SSH_USER="$2"
		shift 2
		;;
	--ssh-key)
		SSH_KEY="$2"
		shift 2
		;;
	--ssh-pass)
		SSH_PASS="$2"
		shift 2
		;;
	--nodes)
		NODES_FILTER="$2"
		shift 2
		;;
	--node-address)
		[[ "$2" == *=* ]] || die "--node-address expects <node>=<ip>, got: $2"
		NODE_ADDR_OVERRIDE["${2%%=*}"]="${2#*=}"
		shift 2
		;;
	--tf-user)
		TF_USER="$2"
		shift 2
		;;
	--tf-pass)
		TF_PASS="$2"
		shift 2
		;;
	--token-name)
		TOKEN_NAME="$2"
		shift 2
		;;
	--svc-user)
		SVC_USER="$2"
		shift 2
		;;
	--svc-pubkey)
		SVC_PUBKEY="$2"
		shift 2
		;;
	--skip-svc-user)
		SKIP_SVC_USER=true
		shift
		;;
	--template-id)
		TEMPLATE_ID="$2"
		shift 2
		;;
	--template-name)
		TEMPLATE_NAME="$2"
		shift 2
		;;
	--storage)
		STORAGE="$2"
		shift 2
		;;
	--rocky-url)
		ROCKY_URL="$2"
		shift 2
		;;
	--skip-template)
		SKIP_TEMPLATE=true
		shift
		;;
	--create-template)
		SKIP_TEMPLATE=false
		SKIP_SNIPPET=false
		shift
		;;
	--skip-snippet)
		SKIP_SNIPPET=true
		shift
		;;
	--uninstall)
		UNINSTALL=true
		shift
		;;
	--uninstall-node)
		UNINSTALL_NODES="$2"
		shift 2
		;;
	--help | -h) usage ;;
	*) die "Unknown argument: $1" ;;
	esac
done

FULL_USER="${TF_USER}@${TF_REALM}"
SETUP=true
[[ "$UNINSTALL" == true || -n "$UNINSTALL_NODES" ]] && SETUP=false

[[ -z "$PVE_HOST" ]] && die "--host is required"
[[ -n "$SSH_KEY" && ! -f "$SSH_KEY" ]] && die "SSH key not found: $SSH_KEY"
[[ -z "$SSH_KEY" && -z "$SSH_PASS" ]] && die "Provide either --ssh-key or --ssh-pass"
[[ "$UNINSTALL" == true && -n "$UNINSTALL_NODES" ]] && die "Use either --uninstall or --uninstall-node, not both"
[[ "$UNINSTALL" == true && -n "$NODES_FILTER" ]] && die "--uninstall always covers every node; use --uninstall-node <a,b> for some of them"
[[ "$TEMPLATE_ID" =~ ^[0-9]+$ ]] || die "--template-id must be a number"
[[ "$SVC_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "Invalid --svc-user: ${SVC_USER}"

if [[ "$SETUP" == true && "$SKIP_SVC_USER" == false ]]; then
	[[ -z "$SVC_PUBKEY" && -n "$SSH_KEY" ]] && SVC_PUBKEY="${SSH_KEY}.pub"
	[[ -z "$SVC_PUBKEY" ]] && die "Pass --svc-pubkey <path> (or --ssh-key) to authorize the ${SVC_USER} SSH user, or --skip-svc-user"
	[[ -f "$SVC_PUBKEY" ]] || die "Public key not found: ${SVC_PUBKEY}"
fi

if [[ -n "$SSH_PASS" ]] && ! command -v sshpass &>/dev/null; then
	die "'sshpass' is not installed. Use --ssh-key or install sshpass."
fi

# SSH
# ControlMaster opens one connection per host; later calls reuse its socket.

SSH_SOCKET_DIR=$(mktemp -d "${TMPDIR:-/tmp}/proxmox-setup.XXXXXX")
# -n: nothing here reads stdin, and without it ssh swallows input meant for read.
SSH_OPTS=(
	-n
	-o StrictHostKeyChecking=no
	-o ConnectTimeout=10
	-o LogLevel=ERROR
	-o ControlMaster=auto
	-o ControlPath="${SSH_SOCKET_DIR}/%C"
	-o ControlPersist=120
)
[[ -n "$SSH_KEY" ]] && SSH_OPTS+=(-i "$SSH_KEY")

declare -A CONTACTED=()

ssh_close() {
	local host
	for host in "${!CONTACTED[@]}"; do
		ssh -o ControlPath="${SSH_SOCKET_DIR}/%C" -O exit "${SSH_USER}@${host}" 2>/dev/null || true
	done
	rm -rf "${SSH_SOCKET_DIR}"
}
trap ssh_close EXIT

# host_exec <host> <command>
host_exec() {
	CONTACTED["$1"]=1
	if [[ -n "$SSH_PASS" ]]; then
		sshpass -p "$SSH_PASS" ssh "${SSH_OPTS[@]}" "${SSH_USER}@$1" "$2"
	else
		ssh "${SSH_OPTS[@]}" "${SSH_USER}@$1" "$2"
	fi
}

# Cluster-wide state lives in /etc/pve, so any node answers for it.
pve_exec() { host_exec "$PVE_HOST" "$1"; }
pve_check() { pve_exec "$1" &>/dev/null; }

# Per-node commands go to the node in NODE_NAME / NODE_ADDR (set by for_nodes).
node_exec() { host_exec "$NODE_ADDR" "$1"; }
node_check() { node_exec "$1" &>/dev/null; }

# Connectivity

info "Connecting to ${PVE_HOST}..."
pve_check "pvesh get /version" || die "Cannot reach Proxmox at ${PVE_HOST}. Check host and credentials."

PVE_VERSION=$(pve_exec "pvesh get /version --output-format json 2>/dev/null \
  | python3 -c \"import sys,json; print(json.load(sys.stdin)['version'])\"")
log "Proxmox VE ${PVE_VERSION}"

# Nodes

# One "name address online local" line per node, sorted by name.
mapfile -t CLUSTER_NODES < <(pve_exec "pvesh get /cluster/status --output-format json | python3 -c \
  \"import sys,json
nodes = [n for n in json.load(sys.stdin) if n['type'] == 'node']
for n in sorted(nodes, key=lambda n: n['name']):
    print(n['name'], n.get('ip') or '-', int(n.get('online', 1)), int(n.get('local', 0)))\"")
[[ ${#CLUSTER_NODES[@]} -gt 0 ]] || die "Could not list nodes from /cluster/status on ${PVE_HOST}"

declare -A NODE_ADDRS=() NODE_ONLINE=() NODE_INDEX=()
ALL_NODES=()
for line in "${CLUSTER_NODES[@]}"; do
	read -r name addr online is_local <<<"$line"
	# The node --host points at is reached through --host, not its cluster IP.
	[[ "$is_local" == 1 ]] && addr="$PVE_HOST"
	[[ -n "${NODE_ADDR_OVERRIDE[$name]:-}" ]] && addr="${NODE_ADDR_OVERRIDE[$name]}"
	NODE_INDEX["$name"]=${#ALL_NODES[@]}
	NODE_ADDRS["$name"]="$addr"
	NODE_ONLINE["$name"]="$online"
	ALL_NODES+=("$name")
done

for name in "${!NODE_ADDR_OVERRIDE[@]}"; do
	[[ -n "${NODE_ADDRS[$name]:-}" ]] || die "--node-address: '${name}' is not a node of this cluster (nodes: ${ALL_NODES[*]})"
done

# select_nodes <comma list or empty for all>: prints the chosen node names.
select_nodes() {
	local wanted name
	if [[ -z "$1" ]]; then
		printf '%s\n' "${ALL_NODES[@]}"
		return
	fi
	IFS=',' read -ra wanted <<<"$1"
	for name in "${wanted[@]}"; do
		[[ -n "${NODE_ADDRS[$name]:-}" ]] || die "'${name}' is not a node of this cluster (nodes: ${ALL_NODES[*]})"
		echo "$name"
	done
}

if [[ -n "$UNINSTALL_NODES" ]]; then
	mapfile -t TARGET_NODES < <(select_nodes "$UNINSTALL_NODES")
else
	mapfile -t TARGET_NODES < <(select_nodes "$NODES_FILTER")
fi

for name in "${TARGET_NODES[@]}"; do
	[[ "${NODE_ONLINE[$name]}" == 1 ]] || die "Node '${name}' is offline. Bring it up or leave it out with --nodes."
	[[ "${NODE_ADDRS[$name]}" != "-" ]] || die "No address for node '${name}'; pass --node-address ${name}=<ip>"
done

if [[ ${#ALL_NODES[@]} -gt 1 ]]; then
	log "Cluster nodes: ${ALL_NODES[*]}"
fi
log "Working on: ${TARGET_NODES[*]}"

# for_nodes <function>: runs it once per target node with NODE_NAME/NODE_ADDR set.
for_nodes() {
	local fn=$1
	for NODE_NAME in "${TARGET_NODES[@]}"; do
		NODE_ADDR="${NODE_ADDRS[$NODE_NAME]}"
		echo
		echo -e "${BOLD}== ${NODE_NAME} (${NODE_ADDR}) ==${NC}"
		node_check "true" || die "Cannot reach node '${NODE_NAME}' at ${NODE_ADDR}. Pass --node-address ${NODE_NAME}=<ip> or leave it out with --nodes."
		"$fn"
	done
}

LOCAL_PATH=$(pve_exec "pvesh get /storage/local --output-format json | python3 -c \
  \"import sys,json; print(json.load(sys.stdin).get('path','/var/lib/vz'))\"")
SNIPPET_PATH="${LOCAL_PATH}/snippets/${SNIPPET_NAME}"

# Templates

node_template_id() { echo $((TEMPLATE_ID + NODE_INDEX[$NODE_NAME])); }

# vm_lookup <vmid>: prints "node template name" for that VM anywhere in the
# cluster, or nothing if the ID is free. qm only sees VMs on its own node.
vm_lookup() {
	pve_exec "pvesh get /cluster/resources --type vm --output-format json | python3 -c \
  \"import sys,json
for r in json.load(sys.stdin):
    if r.get('vmid') == $1:
        print(r['node'], int(r.get('template', 0)), r.get('name', '-'))\""
}

# Per-node setup

node_setup() {
	# bpg streams snippets with 'sudo tee', which does not create the directory.
	node_exec "mkdir -p '${LOCAL_PATH}/snippets' '${LOCAL_PATH}/import'"

	[[ "$SKIP_SVC_USER" == true ]] && return

	info "- SSH User -"

	# Minimal rules from the bpg provider docs: pvesm apiinfo is required for any
	# SSH feature, tee is limited to snippet files. Never grant all of qm/pvesm,
	# both are root-equivalent. Regex rules need sudo >= 1.9.10 (PVE 8+).
	local sudoers="${SVC_USER} ALL=(root) NOPASSWD: /usr/sbin/pvesm apiinfo
${SVC_USER} ALL=(root) NOPASSWD: /usr/bin/tee ^${LOCAL_PATH}/snippets/[a-zA-Z0-9_][a-zA-Z0-9_.-]*\$"

	if ! node_check "command -v sudo"; then
		log "Installing sudo..."
		node_exec "apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq sudo >/dev/null 2>&1" ||
			die "Could not install sudo on ${NODE_NAME}"
	fi

	if node_check "id '${SVC_USER}'"; then
		skip "SSH user '${SVC_USER}' already exists"
	else
		log "Creating SSH user '${SVC_USER}'..."
		node_exec "useradd -m -s /bin/bash '${SVC_USER}'"
	fi

	log "Authorizing $(basename "${SVC_PUBKEY}") for '${SVC_USER}'..."
	node_exec "install -d -m 700 -o '${SVC_USER}' -g '${SVC_USER}' ~${SVC_USER}/.ssh && \
    printf '%s\n' '$(cat "${SVC_PUBKEY}")' > ~${SVC_USER}/.ssh/authorized_keys && \
    chown '${SVC_USER}:${SVC_USER}' ~${SVC_USER}/.ssh/authorized_keys && \
    chmod 600 ~${SVC_USER}/.ssh/authorized_keys"

	log "Writing /etc/sudoers.d/${SVC_USER}..."
	node_exec "printf '%s\n' '${sudoers}' > /tmp/sudoers.${SVC_USER} && \
    visudo -cf /tmp/sudoers.${SVC_USER} >/dev/null && \
    install -m 440 /tmp/sudoers.${SVC_USER} /etc/sudoers.d/${SVC_USER}; \
    rc=\$?; rm -f /tmp/sudoers.${SVC_USER}; exit \$rc" ||
		die "Sudoers file for ${SVC_USER} failed validation on ${NODE_NAME}"

	log "SSH user ready"
}

node_snippet() {
	info "- Snippet -"

	if node_check "test -f '${SNIPPET_PATH}'"; then
		skip "Snippet already exists at ${SNIPPET_PATH}"
		return
	fi

	log "Writing ${SNIPPET_PATH}..."
	node_exec "tee '${SNIPPET_PATH}' > /dev/null <<'EOF'
#cloud-config
runcmd:
  - dnf clean all
  - rpm --rebuilddb
  - dnf makecache
  - dnf update -y
  - dnf install -y qemu-guest-agent
  - systemctl enable --now qemu-guest-agent
EOF"
	log "Snippet written"
}

node_template() {
	local vmid existing owner is_template name
	vmid=$(node_template_id)
	info "- Cloud-init Template ${vmid} -"

	existing=$(vm_lookup "$vmid")
	if [[ -n "$existing" ]]; then
		read -r owner is_template name <<<"$existing"
		if [[ "$owner" == "$NODE_NAME" && "$is_template" == 1 && "$name" == "$TEMPLATE_NAME" ]]; then
			skip "Template ${vmid} (${name}) already exists on ${NODE_NAME}"
			return
		fi
		die "VM ID ${vmid} is already used by '${name}' on ${owner}. Pick a free range with --template-id."
	fi

	if node_check "test -f '${ROCKY_IMG}'"; then
		log "Image already present at ${ROCKY_IMG}, skipping download"
	else
		log "Downloading Rocky Linux 10 image to ${NODE_NAME} (this may take a while)..."
		node_exec "wget -q -O '${ROCKY_IMG}' '${ROCKY_URL}'" ||
			die "Image download failed on ${NODE_NAME}"
	fi

	log "Creating VM ${vmid} (${TEMPLATE_NAME})..."
	node_exec "qm create ${vmid} --name '${TEMPLATE_NAME}' --memory 2048 --net0 virtio,bridge=vmbr0"

	log "Importing disk to '${STORAGE}'..."
	node_exec "qm set ${vmid} --scsi0 ${STORAGE}:0,import-from='${ROCKY_IMG}'"

	log "Configuring cloud-init drive and boot order..."
	node_exec "qm set ${vmid} \
      --ide2 ${STORAGE}:cloudinit \
      --boot order=scsi0 \
      --serial0 socket \
      --vga serial0 \
      --agent enabled=1 \
      --cicustom 'vendor=local:snippets/${SNIPPET_NAME}'"

	log "Converting to template..."
	node_exec "qm template ${vmid}"

	log "Cleaning up downloaded image..."
	node_exec "rm -f '${ROCKY_IMG}'"

	log "Template ${vmid} ready on ${NODE_NAME}"
}

node_all() {
	node_setup
	[[ "$SKIP_SNIPPET" == false ]] && node_snippet
	[[ "$SKIP_TEMPLATE" == false ]] && node_template
	return 0
}

# Per-node teardown

node_uninstall() {
	local vmid existing owner is_template name
	info "- SSH User -"
	if node_check "id '${SVC_USER}'"; then
		log "Removing SSH user '${SVC_USER}' and its sudoers file..."
		node_exec "rm -f '/etc/sudoers.d/${SVC_USER}' && userdel -r '${SVC_USER}' 2>/dev/null"
		log "SSH user removed"
	else
		skip "SSH user '${SVC_USER}' not found"
	fi

	info "- Snippet -"
	if node_check "test -f '${SNIPPET_PATH}'"; then
		log "Removing snippet..."
		node_exec "rm -f '${SNIPPET_PATH}'"
		log "Snippet removed"
	else
		skip "Snippet not found at ${SNIPPET_PATH}"
	fi

	vmid=$(node_template_id)
	info "- Cloud-init Template ${vmid} -"
	existing=$(vm_lookup "$vmid")
	if [[ -z "$existing" ]]; then
		skip "VM ${vmid} not found"
		return
	fi
	read -r owner is_template name <<<"$existing"
	if [[ "$owner" == "$NODE_NAME" && "$is_template" == 1 && "$name" == "$TEMPLATE_NAME" ]]; then
		log "Destroying template ${vmid} (--purge removes disk)..."
		node_exec "qm destroy ${vmid} --purge"
		log "Template destroyed"
	else
		warn "VM ${vmid} is '${name}' on ${owner}, not this script's template on ${NODE_NAME}; leaving it alone"
	fi
}

# Cluster-wide setup and teardown

cluster_setup() {
	echo
	echo -e "${BOLD}== cluster ==${NC}"
	info "- Role -"
	if pve_check "pveum role list --output-format json | python3 -c \
  \"import sys,json; roles=[r['roleid'] for r in json.load(sys.stdin)]; exit(0 if '${ROLE_NAME}' in roles else 1)\""; then
		skip "Role '${ROLE_NAME}' already exists"
	else
		log "Creating role '${ROLE_NAME}'..."
		pve_exec "pveum role add '${ROLE_NAME}' -privs '${ROLE_PRIVS}'"
		log "Role created"
	fi

	info "- User -"
	if pve_check "pveum user list --output-format json | python3 -c \
  \"import sys,json; users=[u['userid'] for u in json.load(sys.stdin)]; exit(0 if '${FULL_USER}' in users else 1)\""; then
		skip "User '${FULL_USER}' already exists"
	else
		if [[ -z "$TF_PASS" ]]; then
			read -rsp "Password for ${FULL_USER} (terraform user in proxmox): " TF_PASS
			echo
			[[ -z "$TF_PASS" ]] && die "Password cannot be empty"
		fi
		log "Creating user '${FULL_USER}'..."
		pve_exec "pveum user add '${FULL_USER}' --password '${TF_PASS}'"
		log "User created"
	fi

	log "Assigning role '${ROLE_NAME}' to '${FULL_USER}' on /..."
	pve_exec "pveum aclmod / -user '${FULL_USER}' -role '${ROLE_NAME}'"

	info "- API Token -"
	if pve_check "pveum user token list '${FULL_USER}' --output-format json | python3 -c \
  \"import sys,json; tokens=[t['tokenid'] for t in json.load(sys.stdin)]; exit(0 if '${TOKEN_NAME}' in tokens else 1)\""; then
		warn "Token '${TOKEN_NAME}' already exists. The secret is not recoverable."
		warn "To regenerate it, delete the token and re-run:"
		warn "  pveum user token remove '${FULL_USER}' '${TOKEN_NAME}'"
	else
		log "Generating token '${TOKEN_NAME}' (privilege separation disabled)..."
		TOKEN_OUTPUT=$(pve_exec "pveum user token add '${FULL_USER}' '${TOKEN_NAME}' --privsep 0")
		log "Token generated"
	fi

	info "- Storage content types -"
	# The vm_template module uploads a snippet and downloads the cloud image as an
	# import volume (disk import_from), so 'local' needs both content types.
	local current new ct
	current=$(pve_exec "pvesh get /storage/local --output-format json | python3 -c \
  \"import sys,json; print(json.load(sys.stdin).get('content',''))\"")
	new="${current}"
	for ct in snippets import; do
		[[ ",${new}," == *",${ct},"* ]] || new="${new:+${new},}${ct}"
	done

	if [[ "$new" == "$current" ]]; then
		skip "'local' already allows snippets and import"
	else
		log "Setting 'local' content to ${new}..."
		pve_exec "pvesm set local --content '${new}'" ||
			die "Could not enable snippets/import on 'local' (the import content type needs Proxmox VE 8.4 or newer)"
	fi
}

cluster_uninstall() {
	echo
	echo -e "${BOLD}== cluster ==${NC}"
	info "- API Token -"
	if pve_check "pveum user token list '${FULL_USER}' --output-format json | python3 -c \
    \"import sys,json; tokens=[t['tokenid'] for t in json.load(sys.stdin)]; exit(0 if '${TOKEN_NAME}' in tokens else 1)\""; then
		log "Removing token '${TOKEN_NAME}'..."
		pve_exec "pveum user token remove '${FULL_USER}' '${TOKEN_NAME}'"
		log "Token removed"
	else
		skip "Token '${TOKEN_NAME}' not found"
	fi

	info "- User -"
	if pve_check "pveum user list --output-format json | python3 -c \
    \"import sys,json; users=[u['userid'] for u in json.load(sys.stdin)]; exit(0 if '${FULL_USER}' in users else 1)\""; then
		log "Removing user '${FULL_USER}' (ACL removed automatically)..."
		pve_exec "pveum user delete '${FULL_USER}'"
		log "User removed"
	else
		skip "User '${FULL_USER}' not found"
	fi

	info "- Role -"
	if pve_check "pveum role list --output-format json | python3 -c \
    \"import sys,json; roles=[r['roleid'] for r in json.load(sys.stdin)]; exit(0 if '${ROLE_NAME}' in roles else 1)\""; then
		log "Removing role '${ROLE_NAME}'..."
		pve_exec "pveum role delete '${ROLE_NAME}'"
		log "Role removed"
	else
		skip "Role '${ROLE_NAME}' not found"
	fi

	info "The snippets/import content types on 'local' are left enabled."
}

# Uninstall

if [[ "$SETUP" == false ]]; then
	echo
	if [[ "$UNINSTALL" == true ]]; then
		warn "This removes ${SVC_USER}, the snippet and the templates on ${TARGET_NODES[*]},"
		warn "and the cluster-wide role, user and token (Terraform loses API access)."
	else
		warn "This removes ${SVC_USER}, the snippet and the template on ${TARGET_NODES[*]}."
		warn "The role, user and token stay, so the other nodes keep working."
	fi
	read -rp "  Continue? [y/N] " confirm
	[[ "${confirm,,}" != "y" ]] && die "Aborted"

	for_nodes node_uninstall
	[[ "$UNINSTALL" == true ]] && cluster_uninstall

	echo
	echo -e "${GREEN}  Uninstall complete${NC}"
	echo
	exit 0
fi

# Setup

# Check every template ID before changing anything, so a collision on a later
# node does not leave the earlier ones half done.
if [[ "$SKIP_TEMPLATE" == false ]]; then
	for NODE_NAME in "${TARGET_NODES[@]}"; do
		vmid=$(node_template_id)
		existing=$(vm_lookup "$vmid")
		[[ -z "$existing" ]] && continue
		read -r owner is_template name <<<"$existing"
		[[ "$owner" == "$NODE_NAME" && "$is_template" == 1 && "$name" == "$TEMPLATE_NAME" ]] && continue
		die "VM ID ${vmid} (template for ${NODE_NAME}) is already used by '${name}' on ${owner}. Pick a free range with --template-id."
	done
fi

TOKEN_OUTPUT=""
cluster_setup
for_nodes node_all

if [[ "$SKIP_SVC_USER" == false ]]; then
	TF_SSH_USER="${SVC_USER}"
	TF_SSH_KEY="${SVC_PUBKEY%.pub}"
else
	TF_SSH_USER="root"
	TF_SSH_KEY="${SSH_KEY:-~/.ssh/id_ed25519}"
fi

echo
echo -e "${GREEN}  Done${NC}"

if [[ ${#TARGET_NODES[@]} -lt ${#ALL_NODES[@]} ]]; then
	untouched=()
	for name in "${ALL_NODES[@]}"; do
		[[ " ${TARGET_NODES[*]} " == *" ${name} "* ]] || untouched+=("$name")
	done
	echo
	warn "Not touched (--nodes): ${untouched[*]}. bpg needs ${TF_SSH_USER} on every node it"
	warn "uploads snippets to; run without --nodes if any of them lacks it."
fi

if [[ "$SKIP_TEMPLATE" == false ]]; then
	echo
	info "Templates (add network_bridge where the VM network is not on vmbr0):"
	echo "proxmox_nodes = {"
	for NODE_NAME in "${TARGET_NODES[@]}"; do
		echo "  ${NODE_NAME} = { template_vm_id = $(node_template_id) }"
	done
	echo "}"
fi

if [[ -n "${TOKEN_OUTPUT}" ]]; then
	echo
	warn "Save this token secret, it will not be shown again:"
	echo
	echo -e "${YELLOW}${TOKEN_OUTPUT}${NC}"

	TOKEN_SECRET=$(echo "${TOKEN_OUTPUT}" | grep '^│ value' | sed 's/.*│ //' | sed 's/ │//')
fi

echo
info "terraform.tfvars (copy into every root you apply, e.g. terraform/examples/*):"
echo
cat <<EOF
proxmox_endpoint             = "https://${PVE_HOST}:8006/"
proxmox_api_token            = "${FULL_USER}!${TOKEN_NAME}=${TOKEN_SECRET:-<token secret above>}"
proxmox_insecure             = true
proxmox_ssh_user             = "${TF_SSH_USER}"
proxmox_ssh_private_key_path = "${TF_SSH_KEY}"
EOF
echo

info "Security notes:"
echo
cat <<EOF
- The script does NOT modify SSH settings on your PVE hosts.
- PVE API user '${FULL_USER}' has the TerraformProv role with limited privileges.
- The API token has privilege separation disabled (full user permissions via API).
- Terraform connects over SSH as '${TF_SSH_USER}'. Unless you passed --skip-svc-user,
  that user can only run 'pvesm apiinfo' and write snippets through sudo.
- VM SSH hardening (disable root, key-only auth) is applied by Ansible on the VMs, not the PVE host.
EOF
echo
