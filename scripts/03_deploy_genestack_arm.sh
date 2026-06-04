#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

GENESTACK_REPO="${GENESTACK_REPO:-https://github.com/rackerlabs/genestack}"
GENESTACK_PATH="${GENESTACK_PATH:-/opt/genestack}"
GENESTACK_MODE="${GENESTACK_MODE:-aio}"
GENESTACK_CONFIRM_DEPLOY="${GENESTACK_CONFIRM_DEPLOY:-no}"
INVENTORY="${INVENTORY:-${SCRIPT_DIR}/../multinode-arm.ini}"

require_file "$INVENTORY"
need_cmd git
require_root_or_sudo

log "Genestack ARM PoC deployment path"
log "Repository: $GENESTACK_REPO"
log "Path: $GENESTACK_PATH"
log "Mode: $GENESTACK_MODE"

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
  run_sudo git -C "$GENESTACK_PATH" pull --ff-only
  run_sudo git -C "$GENESTACK_PATH" submodule update --init --recursive
fi

log "Running Genestack bootstrap"
run_sudo env GENESTACK_MODE="$GENESTACK_MODE" "$GENESTACK_PATH/bootstrap.sh"

log "Genestack bootstrap complete"
echo "Review /etc/genestack/provider and /etc/genestack/inventory before Kubernetes/OpenStack deployment steps."
