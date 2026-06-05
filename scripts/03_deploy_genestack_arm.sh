#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

GENESTACK_REPO="${GENESTACK_REPO:-https://github.com/rackerlabs/genestack}"
GENESTACK_REF="${GENESTACK_REF:-release-2026.1}"
GENESTACK_PATH="${GENESTACK_PATH:-/opt/genestack}"
GENESTACK_MODE="${GENESTACK_MODE:-aio}"
GENESTACK_CONFIRM_DEPLOY="${GENESTACK_CONFIRM_DEPLOY:-no}"
OPENSTACK_RELEASE="${OPENSTACK_RELEASE:-2025.1}"
VIP="${VIP:-192.168.10.250}"
EXT_IFACE="${EXT_IFACE:-eth0}"
INVENTORY="${INVENTORY:-${SCRIPT_DIR}/../multinode-arm.ini}"

require_file "$INVENTORY"
need_cmd git
require_root_or_sudo

log "Genestack ARM PoC deployment path"
log "Repository: $GENESTACK_REPO"
log "Git ref: $GENESTACK_REF"
log "Path: $GENESTACK_PATH"
log "Mode: $GENESTACK_MODE"
log "OpenStack release target: $OPENSTACK_RELEASE"
log "VIP: $VIP"
log "External interface: $EXT_IFACE"

cat <<'INFO'
Genestack is a Kubernetes + OpenStack deployment ecosystem.
This path is intended for ARM server PoC validation first.

Expected before full deploy:
  - ARM64 Linux hosts with SSH and sudo working
  - Kubernetes-ready node plan
  - Kube-OVN design
  - Persistent storage design
  - ARM64 container/image validation

Set GENESTACK_CONFIRM_DEPLOY=yes to let this script clone/update Genestack
and run its bootstrap step. Without that flag this script is a safe preflight.
INFO

if [[ "$GENESTACK_CONFIRM_DEPLOY" != "yes" ]]; then
  log "Preflight complete. Genestack deploy not started because GENESTACK_CONFIRM_DEPLOY is not yes."
  echo "Next command when ready:"
  echo "  GENESTACK_CONFIRM_DEPLOY=yes GENESTACK_MODE=$GENESTACK_MODE scripts/03_deploy_genestack_arm.sh"
  exit 0
fi

if [[ ! -d "$GENESTACK_PATH/.git" ]]; then
  log "Cloning Genestack"
  run_sudo mkdir -p "$(dirname "$GENESTACK_PATH")"
  run_sudo git clone --recurse-submodules -j4 "$GENESTACK_REPO" "$GENESTACK_PATH"
else
  log "Updating existing Genestack checkout"
  run_sudo git -C "$GENESTACK_PATH" fetch --tags origin
fi

log "Checking out Genestack ref $GENESTACK_REF"
run_sudo git -C "$GENESTACK_PATH" checkout "$GENESTACK_REF"
if [[ "$(git -C "$GENESTACK_PATH" rev-parse --abbrev-ref HEAD)" != "HEAD" ]]; then
  run_sudo git -C "$GENESTACK_PATH" pull --ff-only origin "$GENESTACK_REF" || true
fi
run_sudo git -C "$GENESTACK_PATH" submodule update --init --recursive

log "Running Genestack bootstrap"
run_sudo env GENESTACK_MODE="$GENESTACK_MODE" "$GENESTACK_PATH/bootstrap.sh"

log "Genestack bootstrap complete"
echo "Review /etc/genestack/provider and /etc/genestack/inventory before Kubernetes/OpenStack deployment steps."
