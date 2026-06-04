#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

OPENRC="${OPENRC:-/etc/kolla/admin-openrc.sh}"

IMG_URL="${IMG_URL:-https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-arm64.img}"
IMG_NAME="${IMG_NAME:-ubuntu-24.04-arm64}"

FLAVOR="${FLAVOR:-m1.arm.tiny}"

NET="${NET:-public1}"
SUBNET="${SUBNET:-public1-subnet}"

CIDR="${CIDR:-}"
GW="${GW:-}"
POOL_START="${POOL_START:-}"
POOL_END="${POOL_END:-}"

SERVER_NAME="${SERVER_NAME:-arm-test-01}"

require_file "$OPENRC"
require_env CIDR
require_env GW
require_env POOL_START
require_env POOL_END
need_cmd curl
need_cmd openstack

# shellcheck disable=SC1090
source "$OPENRC"

log "Checking OpenStack services"
openstack service list

log "Checking hypervisors"
openstack hypervisor list || true

log "Checking compute services"
openstack compute service list || true

if ! openstack image show "$IMG_NAME" >/dev/null 2>&1; then
  log "Downloading ARM64 Ubuntu cloud image"
  curl -L "$IMG_URL" -o /tmp/arm64-cloud.img

  log "Creating ARM64 Glance image: $IMG_NAME"
  openstack image create "$IMG_NAME" \
    --disk-format qcow2 \
    --container-format bare \
    --property hw_architecture=aarch64 \
    --property architecture=aarch64 \
    --file /tmp/arm64-cloud.img
else
  log "Image already exists: $IMG_NAME"
fi

if ! openstack flavor show "$FLAVOR" >/dev/null 2>&1; then
  log "Creating flavor: $FLAVOR"
  openstack flavor create "$FLAVOR" \
    --ram 1024 \
    --disk 5 \
    --vcpus 1
else
  log "Flavor already exists: $FLAVOR"
fi

if ! openstack network show "$NET" >/dev/null 2>&1; then
  log "Creating provider external network: $NET"
  openstack network create \
    --external \
    --provider-network-type flat \
    --provider-physical-network physnet1 \
    "$NET"
else
  log "Network already exists: $NET"
fi

if ! openstack subnet show "$SUBNET" >/dev/null 2>&1; then
  log "Creating subnet: $SUBNET"
  openstack subnet create "$SUBNET" \
    --network "$NET" \
    --subnet-range "$CIDR" \
    --gateway "$GW" \
    --allocation-pool start="$POOL_START",end="$POOL_END" \
    --no-dhcp
else
  log "Subnet already exists: $SUBNET"
fi

if ! openstack server show "$SERVER_NAME" >/dev/null 2>&1; then
  log "Booting ARM test VM: $SERVER_NAME"
  openstack server create "$SERVER_NAME" \
    --image "$IMG_NAME" \
    --flavor "$FLAVOR" \
    --network "$NET" \
    --wait
else
  log "Server already exists: $SERVER_NAME"
fi

log "Server list"
openstack server list

log "Serial console URL"
openstack console url show "$SERVER_NAME" --serial || warn "Serial console URL not available yet"

log "Validation complete"
