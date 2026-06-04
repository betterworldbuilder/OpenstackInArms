#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

NODE_LIST="${NODE_LIST:-${SCRIPT_DIR}/../nodes.example.txt}"
SSH_USER="${SSH_USER:-ubuntu}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa}"

require_file "$NODE_LIST"
need_cmd ssh

log "Bootstrapping ARM nodes from $NODE_LIST"

while read -r IP HOST ROLE EXTRA; do
  [[ -z "${IP:-}" || "${IP:0:1}" == "#" ]] && continue

  [[ -z "${HOST:-}" ]] && die "Invalid line, missing hostname: $IP"
  [[ -z "${ROLE:-}" ]] && die "Invalid line, missing role: $IP $HOST"
  [[ -n "${EXTRA:-}" ]] && warn "Extra fields ignored on line: $IP $HOST $ROLE $EXTRA"

  case "$ROLE" in
    controller|compute|storage|all) ;;
    *) die "Invalid role '$ROLE' for $HOST" ;;
  esac

  log "Bootstrapping $HOST [$ROLE] at $IP"

  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new "$SSH_USER@$IP" "sudo bash -s" <<REMOTE
set -Eeuo pipefail

hostnamectl set-hostname "$HOST"

apt-get update

DEBIAN_FRONTEND=noninteractive apt-get install -y \
  python3 python3-pip python3-venv python3-dev \
  git curl jq vim htop chrony lvm2 thin-provisioning-tools \
  qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils \
  openvswitch-switch iperf3 net-tools ca-certificates gnupg \
  ethtool iproute2

systemctl enable --now chrony

systemctl enable --now openvswitch-switch || true

modprobe kvm || true
modprobe kvm_arm || true

if [[ -e /dev/kvm ]]; then
  chmod 666 /dev/kvm || true
fi

echo "Architecture:"
uname -m

echo "CPU:"
lscpu | egrep 'Architecture|Model name|CPU\\(s\\)' || true

echo "KVM device:"
ls -l /dev/kvm || true

echo "Network interfaces:"
ip -br link || true
REMOTE
done < "$NODE_LIST"

log "Bootstrap complete. Reboot nodes before deploying OpenStack."
