# ARM OpenStack PoC Hardware BOM

## Option A: Low-Cost Raspberry Pi 5 Lab

| Item | Recommended |
|---|---|
| Nodes | 3 x Raspberry Pi 5 8GB |
| Storage | 3 x NVMe SSD, 256GB minimum, 500GB preferred |
| Adapter | 3 x Raspberry Pi 5 NVMe PCIe HAT |
| Network | 1 x 8-port 1GbE switch |
| Power | Official Raspberry Pi 5 PSU or PoE+ HAT |
| Cooling | Active cooler required |
| OS | Ubuntu Server ARM64 |
| Use case | Lab, demo, training, edge concept |
| Not for | Production SLA, Windows x86 workloads, DPDK, SR-IOV, GPU passthrough |

## Option B: Fully Compliant ARM Server Validation

| Item | Recommended |
|---|---|
| Server | Ampere Altra / AmpereOne ARM64 server |
| CPU | 32+ ARM64 cores |
| RAM | 128GB minimum |
| Storage | Enterprise NVMe |
| Network | 10GbE or 25GbE |
| OS | Ubuntu Server ARM64 |
| Use case | Serious ARM64 OpenStack validation |
| Not for | Blind migration of x86 workloads to ARM |

## Hardware Positioning

| Platform | Positioning |
|---|---|
| Raspberry Pi 5 | Cheapest ARM edge/lab OpenStack validation |
| Ampere ARM64 server | Realistic ARM cloud validation |
| x86 server | Production-grade OpenStack platform |
