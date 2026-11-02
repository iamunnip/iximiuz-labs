# iximiuz-labs

Scripts for iximiuz Labs playgrounds.

```
playgrounds/
  manifests/   one file per setup, named after the VM count and spec
  scripts/     one script per setup, named like its manifest: <total VMs>vm-<OS>-<spec>
```

Every script sets each playground to a 24 hour lifetime and makes it persistent, so disks survive a stop. Running `up` again restarts stopped playgrounds and reconnects them. The public URL changes after a restart.

| Script | Manifest | What it builds |
| --- | --- | --- |
| `5vm-ubuntu26-4c-10g-os20g-data80g.sh` | `5vm-ubuntu26-4c-10g-os20g-data80g.yaml` | Five single-VM playgrounds on one private network, with optional k3s |
| `15vm-ubuntu26-4c6g-4c6g-2c4g-os20g-data60g.sh` | `15vm-ubuntu26-4c6g-4c6g-2c4g-os20g-data60g.yaml` | Five three-VM playgrounds, 15 VMs on one private network, with optional k3s |

## 5vm-ubuntu26-4c-10g-os20g-data80g.sh

Five playgrounds, `node-01` to `node-05`, each with Ubuntu 26.04, 4 vCPU, 10 GiB RAM, a 20 GiB OS disk and an 80 GiB disk on `/data`.

```sh
playgrounds/scripts/5vm-ubuntu26-4c-10g-os20g-data80g.sh up          # start and connect the VMs
playgrounds/scripts/5vm-ubuntu26-4c-10g-os20g-data80g.sh up --k3s    # same, and install k3s
playgrounds/scripts/5vm-ubuntu26-4c-10g-os20g-data80g.sh k3s         # add k3s to running VMs
playgrounds/scripts/5vm-ubuntu26-4c-10g-os20g-data80g.sh check       # test the network from the first and last VM
playgrounds/scripts/5vm-ubuntu26-4c-10g-os20g-data80g.sh status      # list VMs and the public URL
playgrounds/scripts/5vm-ubuntu26-4c-10g-os20g-data80g.sh down        # destroy the VMs and their data
```

VMs reach each other by name, for example `ping node-03`, on 10.8.0.1 to 10.8.0.5. Port 8080 is fixed. Re-running is safe: keys, ports and the public URL stay the same.

With k3s, `node-01` is the server and the others are agents. It is a minimal install, without Traefik and ServiceLB. k3s data is kept on `/data/k3s`.

## 15vm-ubuntu26-4c6g-4c6g-2c4g-os20g-data60g.sh

Five playgrounds, `node-01` to `node-05`, each with three Ubuntu 26.04 VMs:

| VM | vCPU | RAM | OS disk | Disk on `/data` |
| --- | --- | --- | --- | --- |
| `vm-01` | 4 | 6 GiB | 20 GiB | 60 GiB |
| `vm-02` | 4 | 6 GiB | 20 GiB | 60 GiB |
| `vm-03` | 2 | 4 GiB | 20 GiB | 60 GiB |

That is the most one playground allows: 10 vCPU, 16 GiB RAM and 240 GiB disk.

It takes the same commands as the script above. VMs reach each other by name, for example `ping node-03-vm-02`, on 10.8.0.1 to 10.8.0.15. With k3s, `node-01-vm-01` is the server and the others are agents. It is a minimal install, without Traefik and ServiceLB. k3s data is kept on `/data/k3s`.
