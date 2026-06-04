#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

OPENSTACK_RELEASE="${OPENSTACK_RELEASE:-2025.1}"
REGISTRY="${REGISTRY:-localhost:5000}"
NAMESPACE="${NAMESPACE:-kolla-arm64}"
VENV="${VENV:-$HOME/kolla-build-venv}"
KOLLA_SOURCE="${KOLLA_SOURCE:-git+https://opendev.org/openstack/kolla@stable/${OPENSTACK_RELEASE}}"

require_root_or_sudo
need_cmd python3

log "Installing Docker and cross-arch build helpers"
run_sudo apt-get update
run_sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
  python3-venv python3-dev git docker.io qemu-user-static binfmt-support

run_sudo systemctl enable --now docker

log "Creating build virtualenv at $VENV"
python3 -m venv "$VENV"
# shellcheck disable=SC1091
source "$VENV/bin/activate"

pip install -U pip wheel
pip install "$KOLLA_SOURCE"

cat >kolla-build-arm64.conf <<EOF
[DEFAULT]
base = ubuntu
type = source
base_arch = aarch64
namespace = $NAMESPACE
tag = $OPENSTACK_RELEASE-arm64
push = true
registry = $REGISTRY
EOF

log "Building ARM64 Kolla images"
kolla-build \
  --config-file kolla-build-arm64.conf \
  --platform linux/arm64 \
  --base-arch aarch64

log "ARM64 Kolla image build complete"
