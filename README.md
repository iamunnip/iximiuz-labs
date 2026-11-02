# iximiuz-labs

Scripts for iximiuz Labs playgrounds.

```
playgrounds/
  manifests/   one file per VM spec, named after the spec
  scripts/     one script per use case, named like its manifest
```

| Script | Manifest | What it builds |
| --- | --- | --- |
| `ubuntu26-4c-10g-os20g-data80g.sh` | `ubuntu26-4c-10g-os20g-data80g.yaml` | Five single-VM playgrounds on one private network, with optional k3s |

## ubuntu26-4c-10g-os20g-data80g.sh

Five playgrounds, `cluster-01` to `cluster-05`, each with Ubuntu 26.04, 4 vCPU, 10 GiB RAM, a 20 GiB OS disk and an 80 GiB disk on `/data`.

```sh
playgrounds/scripts/ubuntu26-4c-10g-os20g-data80g.sh up          # start and connect the VMs
playgrounds/scripts/ubuntu26-4c-10g-os20g-data80g.sh up --k3s    # same, and install k3s
playgrounds/scripts/ubuntu26-4c-10g-os20g-data80g.sh k3s         # add k3s to running VMs
playgrounds/scripts/ubuntu26-4c-10g-os20g-data80g.sh check       # test every VM against every other
playgrounds/scripts/ubuntu26-4c-10g-os20g-data80g.sh status      # list VMs and the public URL
playgrounds/scripts/ubuntu26-4c-10g-os20g-data80g.sh down        # destroy the VMs and their data
```

VMs reach each other by name, for example `ping cluster-03`, on 10.8.0.1 to 10.8.0.5. Port 8080 is fixed. Re-running is safe: keys, ports and the public URL stay the same.

With k3s, `cluster-01` is the server and the others are agents. k3s data is kept on `/data/k3s`.
