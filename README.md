# ARM OpenStack PoC

This folder contains a small ARM OpenStack PoC deployment bundle for Raspberry Pi 5 and ARM64 server hardware.

The goal is to validate:

- ARM64 OpenStack control plane services
- ARM64 Linux VM boot
- Neutron basic networking
- Floating IP / SSH access
- Cinder LVM lab volume
- Serial console as the noVNC workaround

This is not a production SLA deployment.

## Recommended Release

Default:

```bash
OPENSTACK_RELEASE=2025.1
```

Use OpenStack 2025.1 as the default PoC baseline. The deployment script installs Kolla-Ansible from `stable/${OPENSTACK_RELEASE}` by default and allows override with `KOLLA_ANSIBLE_SOURCE`.

## Folder Layout

```text

├── README.md
├── nodes.example.txt
├── scripts/
│   ├── 00_check_prereqs.sh
│   ├── 01_bootstrap_arm_nodes.sh
│   ├── 02_generate_inventory.py
│   ├── 03_deploy_kolla_arm.sh
│   ├── 04_validate_arm_openstack.sh
│   ├── 05_build_arm64_kolla_images.sh
│   └── lib/common.sh
└── docs/
    ├── hardware_bom.md
    ├── arm_vs_x86_support_matrix.md
    └── troubleshooting.md
```

## Step 1: Create Node File

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
chmod +x scripts/*.sh
```
