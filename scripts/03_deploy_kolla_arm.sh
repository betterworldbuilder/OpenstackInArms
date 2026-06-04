#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

OPENSTACK_RELEASE="${OPENSTACK_RELEASE:-2025.1}"
VENV="${VENV:-$HOME/kolla-venv}"
INVENTORY="${INVENTORY:-${SCRIPT_DIR}/../multinode-arm.ini}"

# Must be set by the operator to an unused address on the management network.
VIP="${VIP:-}"

# Raspberry Pi default is usually eth0.
# ARM servers may use eno1, ens3, enp1s0, etc.
EXT_IFACE="${EXT_IFACE:-eth0}"

KOLLA_ANSIBLE_SOURCE="${KOLLA_ANSIBLE_SOURCE:-git+https://opendev.org/openstack/kolla-ansible@stable/${OPENSTACK_RELEASE}}"
UPPER_CONSTRAINTS_FILE="${UPPER_CONSTRAINTS_FILE:-https://releases.openstack.org/constraints/upper/${OPENSTACK_RELEASE}}"

require_file "$INVENTORY"
require_env VIP
need_cmd python3
require_root_or_sudo

log "Installing local Kolla-Ansible deployment dependencies"

run_sudo apt-get update
run_sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
  python3-venv python3-dev libffi-dev gcc libssl-dev git sshpass

log "Creating Python virtual environment at $VENV"
python3 -m venv "$VENV"
# shellcheck disable=SC1091
source "$VENV/bin/activate"

pip install -U pip wheel

log "Installing Kolla-Ansible for OpenStack release $OPENSTACK_RELEASE"
pip install \
  "ansible-core>=2.17,<2.18.99" \
  "$KOLLA_ANSIBLE_SOURCE"

pip install python-openstackclient -c "$UPPER_CONSTRAINTS_FILE"

log "Installing Kolla-Ansible Galaxy dependencies"
kolla-ansible install-deps

log "Preparing /etc/kolla"
run_sudo mkdir -p /etc/kolla
run_sudo chown "$USER:$USER" /etc/kolla

if [[ ! -f /etc/kolla/passwords.yml ]]; then
  cp "$VENV/share/kolla-ansible/etc_examples/kolla/passwords.yml" /etc/kolla/passwords.yml
fi

if [[ ! -f /etc/kolla/globals.yml ]]; then
  cp "$VENV/share/kolla-ansible/etc_examples/kolla/globals.yml" /etc/kolla/globals.yml
fi

log "Generating Kolla passwords"
kolla-genpwd

log "Writing ARM PoC /etc/kolla/globals.yml"

cat >/etc/kolla/globals.yml <<KOLLA
---
kolla_base_distro: "ubuntu"
kolla_install_type: "source"
openstack_release: "$OPENSTACK_RELEASE"

# Internal API VIP. Must be unused and reachable on the management network.
kolla_internal_vip_address: "$VIP"

# Network interfaces.
network_interface: "$EXT_IFACE"
neutron_external_interface: "$EXT_IFACE"

# Basic PoC services.
enable_haproxy: "yes"
enable_horizon: "yes"
enable_cinder: "yes"
enable_cinder_backend_lvm: "yes"
enable_neutron_provider_networks: "yes"

# ARM PoC console strategy:
# Do not rely on noVNC for this PoC. Use serial console and SSH.
nova_compute_virt_type: "kvm"
nova_console: "none"
enable_nova_serialconsole_proxy: "yes"

# Keep phase 1 small.
enable_octavia: "no"
enable_trove: "no"
enable_sahara: "no"
enable_magnum: "no"
KOLLA

log "Kolla globals generated"
cat /etc/kolla/globals.yml

log "Running Kolla bootstrap-servers"
kolla-ansible -i "$INVENTORY" bootstrap-servers

log "Running Kolla prechecks"
kolla-ansible -i "$INVENTORY" prechecks

log "Deploying OpenStack"
kolla-ansible -i "$INVENTORY" deploy

log "Running post-deploy"
kolla-ansible -i "$INVENTORY" post-deploy

log "Deployment complete"
echo "Next:"
echo "  source /etc/kolla/admin-openrc.sh"
echo "  openstack service list"
