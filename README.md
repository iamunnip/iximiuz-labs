# iximiuz-labs

Scripts for iximiuz Labs playgrounds.

See [docs/](docs/README.md) for prerequisites, execution steps, architecture, and troubleshooting. Both setups use the same playground titles; use one setup at a time per account.

```
playgrounds/
  manifests/   5vm.yaml and 15vm.yaml
  scripts/     5vm.sh and 15vm.sh
docs/          Tutorials, how-to guides, reference, and explanation
tests/         Local script regression checks using a fake labctl
```

Every script sets each playground to a 24 hour lifetime and makes it persistent, so disks survive a stop. `restart` starts stopped playgrounds and reconnects them. The public URL changes after a restart.

| Script | Manifest | What it builds |
| --- | --- | --- |
| `5vm.sh` | `5vm.yaml` | Five single-VM playgrounds on one private network, with optional k3s |
| `15vm.sh` | `15vm.yaml` | Five three-VM playgrounds, 15 VMs on one private network, with optional k3s |

## 5vm.sh

Five playgrounds, `node-01` to `node-05`, each with Ubuntu 26.04, 4 vCPU, 10 GiB RAM, a 20 GiB OS disk and an 80 GiB disk on `/data`.

```sh
playgrounds/scripts/5vm.sh up          # start and connect the VMs
playgrounds/scripts/5vm.sh up --k3s    # same, and install k3s
playgrounds/scripts/5vm.sh k3s         # add k3s to running VMs
playgrounds/scripts/5vm.sh check       # test the network from the first and last VM
playgrounds/scripts/5vm.sh status      # show the VMs and how to connect to the control plane
playgrounds/scripts/5vm.sh down        # stop the VMs and keep their disks
playgrounds/scripts/5vm.sh restart     # start stopped VMs and reconnect them
playgrounds/scripts/5vm.sh destroy     # delete the VMs and their data
```

VMs reach each other by name, for example `ping node-03`, on 10.8.0.1 to 10.8.0.5. Port 8080 is fixed. Re-running is safe: keys, ports and the public URL stay the same.

With k3s, `node-01` has the `control-plane` role and the others have the `node` role. It is a minimal install, without Traefik and ServiceLB. k3s data is kept on `/data/k3s`.

## 15vm.sh

Five playgrounds, `node-01` to `node-05`, each with three Ubuntu 26.04 VMs:

| VM | vCPU | RAM | OS disk | Disk on `/data` |
| --- | --- | --- | --- | --- |
| `vm-01` | 4 | 6 GiB | 20 GiB | 60 GiB |
| `vm-02` | 4 | 6 GiB | 20 GiB | 60 GiB |
| `vm-03` | 2 | 4 GiB | 20 GiB | 60 GiB |

That is the most one playground allows: 10 vCPU, 16 GiB RAM and 240 GiB disk.

It takes the same commands as the script above. VMs reach each other by name, for example `ping node-03-vm-02`, on 10.8.0.1 to 10.8.0.15. With k3s, `node-01-vm-01` has the `control-plane` role and the others have the `node` role. It is a minimal install, without Traefik and ServiceLB. k3s data is kept on `/data/k3s`.
