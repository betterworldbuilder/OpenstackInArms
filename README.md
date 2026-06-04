# ARM OpenStack PoC

**OPENSTACKK BROTHERS and SISTERS in ARM** is a small mission-control style toolkit for proving that OpenStack can run on ARM64 lab hardware.

It gives you two ways to operate:

- **Mission Control Web UI**: a simple neon cockpit with the `OPENSTACKK BROTHERS and SISTERS in ARM` title bar, node editing, and buttons for each PoC stage.
- **CLI scripts**: direct Bash/Python scripts for repeatable terminal-driven deployment.

The target hardware is Raspberry Pi 5 for low-cost lab/demo work and server-grade ARM64 hardware for serious validation.

The goal is to validate:

- ARM64 OpenStack control plane services
- ARM64 Linux VM boot
- Neutron basic networking
- Floating IP / SSH access
- Cinder LVM lab volume
- Serial console as the noVNC workaround

This is not a production SLA deployment.

## Launch Mission Control

Start the local web UI from the repo root:

```bash
cd /home/dzoan/OSPC2FLEX/Openstack-SisandBrotherInArms
python3 scripts/06_mission_control_server.py
```

Open:

```text
http://127.0.0.1:8787
```

The UI is localhost-only and runs an allowlist of PoC steps:

| Stage | Button | What It Runs |
|---|---|---|
| Prereq Scan | Run | `scripts/00_check_prereqs.sh` |
| Bootstrap ARM Nodes | Run | `scripts/01_bootstrap_arm_nodes.sh` |
| Generate Inventory | Run | `scripts/02_generate_inventory.py` |
| Deploy Kolla ARM | Deploy | `scripts/03_deploy_kolla_arm.sh` |
| Validate Cloud | Run | `scripts/04_validate_arm_openstack.sh` |
| Build ARM64 Images | Run | `scripts/05_build_arm64_kolla_images.sh` |

Use the UI for demos and guided operation. Use the CLI commands below when you want exact terminal control.

## Why / What / So What / What Now

### Why

ARM servers are becoming practical for edge, lab, and low-power cloud experiments. This PoC answers one simple question: can we stand up a small OpenStack environment on ARM64 and boot ARM64 cloud workloads safely?

### What

This repo provides scripts and documentation for a Kolla-Ansible based ARM OpenStack PoC. It targets Raspberry Pi 5 for low-cost lab testing and server-grade ARM64 hardware for more serious validation.

### So What

The value is learning the real limits before investing in a larger ARM cloud design:

- Validate ARM64 OpenStack services.
- Boot ARM64 Linux cloud images.
- Test basic Neutron networking.
- Use serial console when noVNC is unreliable.
- Avoid mixing x86 images with ARM compute nodes.

### What Now

Start with the Mission Control UI and the 2-node Raspberry Pi PoC below. If the basics work, move to 3+ nodes or ARM server hardware, then consider phase 2 items such as Ceph, Octavia, and stronger networking.

## Recommended Release

Default:

```bash
OPENSTACK_RELEASE=2025.1
```

Use OpenStack 2025.1 as the default PoC baseline. The deployment script installs Kolla-Ansible from `stable/${OPENSTACK_RELEASE}` by default and allows override with `KOLLA_ANSIBLE_SOURCE`.

## Folder Layout

```text

├── README.md
├── mission-control.html
├── nodes.example.txt
├── scripts/
│   ├── 00_check_prereqs.sh
│   ├── 01_bootstrap_arm_nodes.sh
│   ├── 02_generate_inventory.py
│   ├── 03_deploy_kolla_arm.sh
│   ├── 04_validate_arm_openstack.sh
│   ├── 05_build_arm64_kolla_images.sh
│   ├── 06_mission_control_server.py
│   └── lib/common.sh
└── docs/
    ├── hardware_bom.md
    ├── arm_vs_x86_support_matrix.md
    └── troubleshooting.md
```

## Step 1: Create Node File

You can create `nodes.txt` in Mission Control with the **Save Nodes** button, or create it manually:

Copy the example:

```bash
cd /home/dzoan/OSPC2FLEX/Openstack-SisandBrotherInArms
cp nodes.example.txt nodes.txt
vim nodes.txt
```

Example:

```text
192.168.10.11 pi-os-ctrl controller
192.168.10.12 pi-os-cmp1 compute
192.168.10.13 pi-os-cmp2 compute
```

## Example: 2 Raspberry Pi 5 PoC

This is the smallest useful lab shape:

| Node | Example IP | Role | Purpose |
|---|---|---|---|
| Pi 1 | 192.168.10.11 | controller | API, scheduler, network, Horizon, control services |
| Pi 2 | 192.168.10.12 | compute | Nova compute, ARM64 test VM |

Use this for a first demo, not production. Both Pis should run Ubuntu Server ARM64, use wired Ethernet, and preferably boot from NVMe or USB SSD rather than SD card.

Create `nodes.txt`:

```text
192.168.10.11 pi-os-ctrl controller
192.168.10.12 pi-os-cmp1 compute
```

Run the flow:

```bash
cd /home/dzoan/OSPC2FLEX/Openstack-SisandBrotherInArms

NODE_LIST=nodes.txt SSH_USER=ubuntu scripts/00_check_prereqs.sh
NODE_LIST=nodes.txt SSH_USER=ubuntu scripts/01_bootstrap_arm_nodes.sh

ssh ubuntu@192.168.10.11 sudo reboot
ssh ubuntu@192.168.10.12 sudo reboot

python3 scripts/02_generate_inventory.py \
  --nodes nodes.txt \
  --output multinode-arm.ini \
  --ansible-user ubuntu

OPENSTACK_RELEASE=2025.1 \
VIP=192.168.10.250 \
EXT_IFACE=eth0 \
INVENTORY=multinode-arm.ini \
scripts/03_deploy_kolla_arm.sh
```

Validate with an ARM64 image:

```bash
OPENRC=/etc/kolla/admin-openrc.sh \
CIDR=192.168.100.0/24 \
GW=192.168.100.1 \
POOL_START=192.168.100.100 \
POOL_END=192.168.100.200 \
scripts/04_validate_arm_openstack.sh
```

Expected proof:

```bash
openstack server list
openstack console url show arm-test-01 --serial
```

## Step 2: Check Prerequisites

```bash
cd /home/dzoan/OSPC2FLEX/Openstack-SisandBrotherInArms
chmod +x scripts/*.sh
NODE_LIST=nodes.txt SSH_USER=ubuntu scripts/00_check_prereqs.sh
```

## Step 3: Bootstrap ARM Nodes

```bash
NODE_LIST=nodes.txt SSH_USER=ubuntu scripts/01_bootstrap_arm_nodes.sh
```

Reboot nodes after bootstrap:

```bash
ssh ubuntu@192.168.10.11 sudo reboot
ssh ubuntu@192.168.10.12 sudo reboot
ssh ubuntu@192.168.10.13 sudo reboot
```

## Step 4: Generate Kolla Inventory

```bash
python3 scripts/02_generate_inventory.py \
  --nodes nodes.txt \
  --output multinode-arm.ini \
  --ansible-user ubuntu
```

## Step 5: Deploy OpenStack

Set an unused VIP in the same management network.

```bash
OPENSTACK_RELEASE=2025.1 \
VIP=192.168.10.250 \
EXT_IFACE=eth0 \
INVENTORY=multinode-arm.ini \
scripts/03_deploy_kolla_arm.sh
```

## Step 6: Validate ARM OpenStack

Set provider network values that match your lab network before creating a test VM:

```bash
OPENRC=/etc/kolla/admin-openrc.sh \
CIDR=192.168.100.0/24 \
GW=192.168.100.1 \
POOL_START=192.168.100.100 \
POOL_END=192.168.100.200 \
scripts/04_validate_arm_openstack.sh
```

Expected result:

```bash
openstack server list
openstack console url show arm-test-01 --serial
```

## Optional: Build ARM64 Kolla Images

Only use this if prebuilt ARM64 images are missing or you need a private registry.

```bash
OPENSTACK_RELEASE=2025.1 \
REGISTRY=localhost:5000 \
NAMESPACE=kolla-arm64 \
scripts/05_build_arm64_kolla_images.sh
```

## What Is Included

| Component | Status |
|---|---|
| Keystone | Included |
| Glance | Included |
| Nova | Included |
| Neutron | Included |
| Horizon | Included |
| Cinder LVM | Included |
| Serial console | Included |
| noVNC | Not required |
| Ceph | Phase 2 |
| Octavia | Phase 2 |
| Trove | Excluded |
| GPU / SR-IOV / DPDK | Excluded |

## Validation Commands

```bash
source /etc/kolla/admin-openrc.sh
openstack service list
openstack endpoint list
openstack hypervisor list
openstack compute service list
openstack image list
openstack network list
openstack server list
openstack console url show arm-test-01 --serial
```

## Safety Rule

Do not schedule x86 images to ARM compute nodes.

Use ARM64 images only:

```text
hw_architecture=aarch64
architecture=aarch64
```

## Positioning

| Platform | Positioning |
|---|---|
| Raspberry Pi 5 ARM OpenStack | Lab, edge, demo, training |
| ARM server OpenStack | Serious ARM64 validation |
| x86 OpenStack | Production SLA workloads |

## Phase 2 Notes

Ceph is intentionally excluded from phase 1. Add Ceph only after the basic Kolla-Ansible deployment, Nova compute validation, provider networking, and ARM64 VM boot path are working. Raspberry Pi 5 nodes should use NVMe storage for any Ceph experiment; SD cards are not appropriate for OSDs.

## Local Syntax Checks

Run from the repository root:

```bash
find scripts -type f -name "*.sh" -print0 | xargs -0 -I{} bash -n {}
python3 -m py_compile scripts/02_generate_inventory.py
python3 -m py_compile scripts/06_mission_control_server.py
chmod +x scripts/*.sh
```
