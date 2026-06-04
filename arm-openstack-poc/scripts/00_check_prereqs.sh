#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

NODE_LIST="${NODE_LIST:-${SCRIPT_DIR}/../nodes.example.txt}"
SSH_USER="${SSH_USER:-ubuntu}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa}"

log "Checking local prerequisites"
need_cmd ssh
need_cmd scp
need_cmd python3

if [[ ! -f "$SSH_KEY" ]]; then
  warn "SSH key not found at $SSH_KEY. Set SSH_KEY=/path/to/key if needed."
fi

require_file "$NODE_LIST"

log "Checking node file format: $NODE_LIST"

while read -r IP HOST ROLE EXTRA; do
  [[ -z "${IP:-}" || "${IP:0:1}" == "#" ]] && continue

  [[ -z "${HOST:-}" ]] && die "Invalid line, missing hostname: $IP"
  [[ -z "${ROLE:-}" ]] && die "Invalid line, missing role: $IP $HOST"
  [[ -n "${EXTRA:-}" ]] && warn "Extra fields ignored on line: $IP $HOST $ROLE $EXTRA"

  case "$ROLE" in
    controller|compute|storage|all) ;;
    *) die "Invalid role '$ROLE' for host '$HOST'. Allowed: controller, compute, storage, all" ;;
  esac

  log "Checking SSH to $HOST at $IP"
  ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
    "$SSH_USER@$IP" "uname -m && hostname" || warn "SSH check failed for $HOST at $IP"
done < "$NODE_LIST"

log "Prerequisite check completed"
