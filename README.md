# OPENARMS X LAB

**OPENARMS X LAB** is an ARM OpenStack PoC toolkit for Raspberry Pi 5 and ARM64 server hardware.

It has two ways to run:

- **Automatic Web UI Mode**: a local neon Mission Control interface that scans the LAN, lets you choose ARM nodes, and runs each PoC stage with buttons.
- **Manual Mode**: direct CLI commands for users who want terminal-only control.

This is a PoC, not a production SLA deployment.

## Goal

Validate a small ARM64 OpenStack environment:

- ARM64 OpenStack control plane services
- ARM64 Linux VM boot
- Neutron basic networking
- Floating IP / SSH access
- Cinder LVM lab volume
- Serial console as the noVNC workaround

## Automatic Web UI Mode

Start the local web UI from the repo root:

```bash
cd /home/dzoan/OSPC2FLEX/Openstack-SisandBrotherInArms
./Openarm.sh
```

Alternative direct launch:

```bash
python3 scripts/06_mission_control_server.py
```

Open:

```text
http://127.0.0.1:8787
```

The UI is localhost-only. It runs an allowlist of PoC actions and does not expose arbitrary shell command execution.

### Web UI Stages

| Stage | Button | Purpose |
|---|---|---|
| 01 LAN Scout | Scan | Scan a CIDR, discover reachable IPs, probe SSH, and detect ARM candidates |
| 02 Prereq Scan | Run | Check local tools, node file format, and SSH reachability |
| 03 Bootstrap Cloud Nodes | Run | Install base packages and check KVM/Open vSwitch readiness on ARM/x86 nodes |
| 04 Generate Inventory | Run | Generate `multinode-arm.ini` for Kolla-Ansible |
| 05 Deploy Kolla ARM | Deploy | Run Kolla bootstrap, prechecks, deploy, and post-deploy |
| 06 Validate Cloud | Run | Upload ARM64 image, create flavor/network, boot VM, show serial console |
| 07 Build ARM64 Images | Run | Optional private ARM64 Kolla image build |

### LAN Scout

1. Enter a LAN range, for example `192.168.10.0/24`.
2. Click **Scan LAN**.
3. Review the detected hosts table.
4. Tick the ARM Raspberry Pi or ARM server IPs you want to use.
5. Assign each selected host a role: `controller`, `compute`, `storage`, or `all`.
6. Click **Use Selected** to draft `nodes.txt`.
7. Click **Save Nodes**.

### OpenStack Release Picker

The Web UI lets the user choose the release before deployment.

| Release | Name | Notes |
|---|---|---|
| `2025.1` | Epoxy | Default PoC baseline |
| `2024.2` | Dalmatian | Fallback for older Kolla-Ansible testing |
| `2024.1` | Caracal | Older validation target |

The selected release is passed to deployment, and the Web UI also shows the actual source URL used by the deploy script:

```bash
OPENSTACK_RELEASE=<selected-release>
KOLLA_ANSIBLE_SOURCE=git+https://opendev.org/openstack/kolla-ansible@stable/<selected-release>
```

## Manual Mode

Use Manual Mode when you want exact terminal control.

## Recommended Release

Default:

```bash
OPENSTACK_RELEASE=2025.1
```

The deployment script installs Kolla-Ansible from `stable/${OPENSTACK_RELEASE}` by default and allows override with `KOLLA_ANSIBLE_SOURCE`.

## Folder Layout

```text
├── README.md
├── Openarm.sh
├── mission-control.html
├── nodes.example.txt
├── scripts/
│   ├── 00_check_prereqs.sh
│   ├── 01_bootstrap_cloud_nodes.sh
│   ├── 01_bootstrap_arm_nodes.sh      # legacy wrapper
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

## Manual Step 1: Create Node File

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

## Manual Step 2: Check Prerequisites

```bash
cd /home/dzoan/OSPC2FLEX/Openstack-SisandBrotherInArms
chmod +x scripts/*.sh
NODE_LIST=nodes.txt SSH_USER=ubuntu scripts/00_check_prereqs.sh
```

## Manual Step 3: Bootstrap Cloud Nodes

```bash
NODE_LIST=nodes.txt SSH_USER=ubuntu scripts/01_bootstrap_cloud_nodes.sh
```

Reboot nodes after bootstrap:

```bash
ssh ubuntu@192.168.10.11 sudo reboot
ssh ubuntu@192.168.10.12 sudo reboot
ssh ubuntu@192.168.10.13 sudo reboot
```

## Manual Step 4: Generate Kolla Inventory

```bash
python3 scripts/02_generate_inventory.py \
  --nodes nodes.txt \
  --output multinode-arm.ini \
  --ansible-user ubuntu
```

## Manual Step 5: Deploy OpenStack

Set an unused VIP in the same management network and choose the OpenStack release.

Default:

```bash
OPENSTACK_RELEASE=2025.1 \
VIP=192.168.10.250 \
EXT_IFACE=eth0 \
INVENTORY=multinode-arm.ini \
scripts/03_deploy_kolla_arm.sh
```

Different release example:

```bash
OPENSTACK_RELEASE=2024.2 \
VIP=192.168.10.250 \
EXT_IFACE=eth0 \
INVENTORY=multinode-arm.ini \
scripts/03_deploy_kolla_arm.sh
```

## Manual Step 6: Validate ARM OpenStack

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

## 2 Raspberry Pi 5 PoC Example

Smallest useful lab shape:

| Node | Example IP | Role | Purpose |
|---|---|---|---|
| Pi 1 | 192.168.10.11 | controller | API, scheduler, network, Horizon, control services |
| Pi 2 | 192.168.10.12 | compute | Nova compute, ARM64 test VM |

Example `nodes.txt`:

```text
192.168.10.11 pi-os-ctrl controller
192.168.10.12 pi-os-cmp1 compute
```

Use wired Ethernet. Prefer NVMe or USB SSD over SD card.

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
