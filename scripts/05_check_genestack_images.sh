#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

GENESTACK_PATH="${GENESTACK_PATH:-/opt/genestack}"
KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"

log "Checking Genestack image signals"
log "Genestack path: $GENESTACK_PATH"
log "Kubeconfig: $KUBECONFIG"

if [[ -d "$GENESTACK_PATH" ]]; then
  log "Image references in Genestack manifests"
  grep -R "image:" "$GENESTACK_PATH" 2>/dev/null | head -80 || warn "No image references found in $GENESTACK_PATH"
else
  warn "Genestack checkout not found at $GENESTACK_PATH"
fi

if command -v kubectl >/dev/null 2>&1 && [[ -f "$KUBECONFIG" ]]; then
  log "Images currently requested by Kubernetes workloads"
  kubectl --kubeconfig "$KUBECONFIG" get pods -A \
    -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{" "}{range .spec.containers[*]}{.image}{" "}{end}{"\n"}{end}' \
    | sort -u

  log "Pods not ready"
  kubectl --kubeconfig "$KUBECONFIG" get pods -A --field-selector=status.phase!=Running || true
else
  warn "kubectl or kubeconfig missing; live workload image check skipped"
fi

cat <<'INFO'
ARM64 image checklist:
  - Confirm every OpenStack service image has a linux/arm64 manifest.
  - Confirm Kubernetes operators, OVN, databases, message bus, and OpenStack-Helm images support ARM64.
  - For private registries, mirror images by digest after ARM64 validation.
INFO

log "Genestack image check complete"
