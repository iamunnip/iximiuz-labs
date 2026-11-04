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

`start` and `restart` set each playground to a 24-hour lifetime and make it persistent, so disks survive a stop. `restart` starts stopped playgrounds and reconnects them. The public URL changes after a restart.

| Script | Manifest | What it builds |
| --- | --- | --- |
| `5vm.sh` | `5vm.yaml` | Five single-VM playgrounds on one private network, with optional K3s |
| `15vm.sh` | `15vm.yaml` | Five three-VM playgrounds, 15 VMs on one private network, with optional K3s |

## 5vm.sh

Five playgrounds, `node-01` to `node-05`, each with Ubuntu 26.04, 4 vCPU, 10 GiB RAM, a 20 GiB OS disk and an 80 GiB disk on `/data`.

```sh
playgrounds/scripts/5vm.sh start          # start and connect the VMs
playgrounds/scripts/5vm.sh start --k3s    # same, and install K3s
playgrounds/scripts/5vm.sh k3s         # add K3s to running VMs
playgrounds/scripts/5vm.sh check       # test the network from the first and last VM
playgrounds/scripts/5vm.sh status      # show the VMs and how to connect to the control plane
playgrounds/scripts/5vm.sh stop        # stop the VMs and keep their disks
playgrounds/scripts/5vm.sh restart     # start stopped VMs and reconnect them
playgrounds/scripts/5vm.sh destroy     # delete the VMs and their data
playgrounds/scripts/5vm.sh --help      # show usage
```

Every operational command prints timestamped task headings, detail lines indented by two spaces, and a final completion heading with total elapsed time. For commands that leave the hub running, its SSH command appears last:

```text
[35s] Step: Completed setting up VMs
  All 5 VMs connected

[35s] Step: Access to hub VM
  node-01: labctl ssh <playground-id>
```

`node-01` is the WireGuard hub and optional K3s control plane. See the [command reference](docs/reference/commands.md) for every option and its completion message.

VMs reach each other by name, for example `ping node-03`, on 10.8.0.1 to 10.8.0.5. Port 8080 is fixed. Re-running is safe: keys, ports and the public URL stay the same.

With K3s, `node-01` has the `control-plane` role and the others have the `node` role. It is a minimal install, without Traefik and ServiceLB. K3s data is kept on `/data/k3s`.

## 15vm.sh

Five playgrounds, `node-01` to `node-05`, each with three Ubuntu 26.04 VMs:

| VM | vCPU | RAM | OS disk | Disk on `/data` |
| --- | --- | --- | --- | --- |
| `vm-01` | 4 | 6 GiB | 20 GiB | 60 GiB |
| `vm-02` | 4 | 6 GiB | 20 GiB | 60 GiB |
| `vm-03` | 2 | 4 GiB | 20 GiB | 60 GiB |

That is the most one playground allows: 10 vCPU, 16 GiB RAM and 240 GiB disk.

It takes the same commands and uses the same output format as `5vm.sh`. Its WireGuard hub is `node-01-vm-01`; the final access command is `labctl ssh <node-01-playground-id> --machine vm-01`. VMs reach each other by name, for example `ping node-03-vm-02`, on 10.8.0.1 to 10.8.0.15. With K3s, `node-01-vm-01` has the `control-plane` role and the others have the `node` role. It is a minimal install, without Traefik and ServiceLB. K3s data is kept on `/data/k3s`.
