# Setup reference

| Setup | Playgrounds | VMs | Resources per VM |
| --- | --- | --- | --- |
| [4 VMs](../../playgrounds/scripts/4vm.sh) | 1 | 4 | `dev-machine`: 1 vCPU, 1 GiB RAM, 30 GiB disk. `node-1`, `node-2`, `node-3`: 3 vCPU, 5 GiB RAM, 70 GiB disk each. One OS disk per VM, no data disk. |
| [5 VMs](../../playgrounds/scripts/5vm.sh) | 5 | 5 | 4 vCPU, 10 GiB RAM, 20 GiB OS disk, 80 GiB data disk |
| [15 VMs](../../playgrounds/scripts/15vm.sh) | 5 | 15 | Two VMs per playground with 4 vCPU and 6 GiB RAM; one with 2 vCPU and 4 GiB RAM. Each has a 20 GiB OS disk and 60 GiB data disk. |

All VMs use Ubuntu 26.04. In the 5 VM and 15 VM setups, every VM mounts a data disk at `/data`.

The 4 VM setup creates one playground titled `4vm` from [4vm.yaml](../../playgrounds/manifests/4vm.yaml). The other two layouts create five playgrounds. Their manifests are [5vm.yaml](../../playgrounds/manifests/5vm.yaml) and [15vm.yaml](../../playgrounds/manifests/15vm.yaml).
