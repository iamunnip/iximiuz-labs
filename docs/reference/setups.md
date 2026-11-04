# Setup reference

| Setup | Playgrounds | VMs | Resources per VM |
| --- | --- | --- | --- |
| [5 VMs](../../playgrounds/scripts/5vm.sh) | 5 | 5 | 4 vCPU, 10 GiB RAM, 20 GiB OS disk, 80 GiB data disk |
| [15 VMs](../../playgrounds/scripts/15vm.sh) | 5 | 15 | Two VMs per playground with 4 vCPU and 6 GiB RAM; one with 2 vCPU and 4 GiB RAM. Each has a 20 GiB OS disk and 60 GiB data disk. |

All VMs use Ubuntu 26.04 and mount their data disk at `/data`.

Both layouts create five playgrounds. Their manifests are [5vm.yaml](../../playgrounds/manifests/5vm.yaml) and [15vm.yaml](../../playgrounds/manifests/15vm.yaml).
