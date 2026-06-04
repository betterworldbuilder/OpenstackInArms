# ARM vs x86 OpenStack Support Matrix

| Feature | ARM Raspberry Pi PoC | ARM Server PoC | x86 Production |
|---|---:|---:|---:|
| Keystone | Supported | Supported | Supported |
| Glance | Supported | Supported | Supported |
| Nova API | Supported | Supported | Supported |
| Nova Compute | Partial | Supported with validation | Supported |
| Neutron basic networking | Supported | Supported | Supported |
| Horizon | Supported | Supported | Supported |
| noVNC | Not reliable / do not depend on it | Validate | Supported |
| Serial console | Required workaround | Supported | Supported |
| Cinder LVM | Lab only | Supported | Supported |
| Cinder Ceph RBD | Optional / limited | Recommended | Supported |
| Ceph OSD | Not recommended on SD card | Supported with NVMe | Supported |
| Octavia | Exclude phase 1 | Optional phase 2 | Supported |
| Trove | Exclude | Optional phase 2 | Supported |
| Windows x86 guests | Not practical | Not practical | Supported |
| GPU passthrough | Not practical | Hardware-dependent | Supported with right hardware |
| SR-IOV | Not practical | Hardware-dependent | Supported with right hardware |
| DPDK | Not practical | Hardware-dependent | Supported with right hardware |
| Production SLA | No | Architecture validation only | Yes |

## Rule

ARM OpenStack is for low-cost edge, lab, training, and innovation.

x86 OpenStack remains the production-grade SLA platform.
