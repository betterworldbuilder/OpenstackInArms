# ARM OpenStack PoC Troubleshooting

## 1. SSH Fails During Bootstrap

Check:

```bash
ssh ubuntu@NODE_IP hostname
```

Fix:

- Confirm IP address.
- Confirm SSH key.
- Confirm user is `ubuntu`, or set `SSH_USER`.

## 2. `/dev/kvm` Missing

Check:

```bash
ls -l /dev/kvm
lscpu
```

Possible causes:

- ARM board firmware does not expose virtualization.
- Kernel module is not loaded.
- Host OS does not support KVM on this board.

Workaround:

- Use ARM server hardware for Nova compute validation.
- Avoid QEMU full emulation for real workloads.

## 3. noVNC Does Not Work

This PoC does not depend on noVNC.

Use:

```bash
openstack console url show arm-test-01 --serial
```

Also use SSH/floating IP access.

## 4. ARM VM Does Not Boot

Check image architecture:

```bash
openstack image show ubuntu-24.04-arm64 -f yaml
```

Required properties:

```text
hw_architecture=aarch64
architecture=aarch64
```

Do not boot x86 images on ARM compute.

## 5. Network Not Reachable

Check:

```bash
openstack network list
openstack subnet list
openstack server list
ip -br addr
ovs-vsctl show
```

For Raspberry Pi PoC, prefer flat/provider networking first.

## 6. Kolla Precheck Fails

Run:

```bash
source ~/kolla-venv/bin/activate
kolla-ansible -i arm-openstack-poc/multinode-arm.ini prechecks
```

Check:

- VIP is unused.
- Network interface name is correct.
- Nodes have passwordless sudo.
- Python 3 is installed.

## 7. Cinder LVM Backend Fails

Kolla's LVM backend expects a usable volume group on the storage host. This bundle installs LVM tooling but does not create a volume group automatically, because that could overwrite disks.

Create the volume group manually only after confirming the target block device:

```bash
sudo pvcreate /dev/NVME_OR_DISK
sudo vgcreate cinder-volumes /dev/NVME_OR_DISK
```

Ceph is intentionally phase 2 only.
