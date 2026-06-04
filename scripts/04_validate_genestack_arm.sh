#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

GENESTACK_PATH="${GENESTACK_PATH:-/opt/genestack}"
KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
OPENRC="${GENESTACK_OPENRC:-${OPENRC:-/etc/genestack/admin-openrc.sh}}"

failures=0

log "Validating Genestack ARM PoC"
log "Genestack path: $GENESTACK_PATH"
log "Kubeconfig: $KUBECONFIG"
log "OpenRC: $OPENRC"

if [[ -d "$GENESTACK_PATH/.git" ]]; then
  log "Genestack checkout"
  git -C "$GENESTACK_PATH" status --short || failures=1
else
  warn "Genestack checkout not found at $GENESTACK_PATH"
  failures=1
fi

if command -v kubectl >/dev/null 2>&1 && [[ -f "$KUBECONFIG" ]]; then
  log "Kubernetes nodes"
  kubectl --kubeconfig "$KUBECONFIG" get nodes -o wide || failures=1

  log "OpenStack / Genestack pods"
  kubectl --kubeconfig "$KUBECONFIG" get pods -A \
    | grep -Ei 'openstack|keystone|nova|neutron|glance|cinder|ovn|mariadb|rabbit|memcached' || true
else
  warn "kubectl or kubeconfig missing; Kubernetes validation skipped"
  failures=1
fi

if command -v helm >/dev/null 2>&1 && [[ -f "$KUBECONFIG" ]]; then
  log "Helm releases"
  helm --kubeconfig "$KUBECONFIG" list -A || true
else
  warn "helm or kubeconfig missing; Helm release validation skipped"
fi

if command -v openstack >/dev/null 2>&1 && [[ -f "$OPENRC" ]]; then
  # shellcheck disable=SC1090
  source "$OPENRC"
  log "OpenStack services"
  openstack service list || failures=1
  log "OpenStack endpoints"
  openstack endpoint list || true
else
  warn "openstack CLI or OpenRC missing; OpenStack API validation skipped"
fi

if [[ "$failures" -ne 0 ]]; then
  warn "Genestack validation found missing prerequisites or failed checks"
  exit 1
fi

log "Genestack validation complete"
