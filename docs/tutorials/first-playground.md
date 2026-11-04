# Create your first five-VM network

This tutorial starts five Ubuntu VMs, checks their private network, and stops them while preserving their disks.

You need Bash 4.3 or later, standard Unix tools, and an authenticated `labctl` installation. Your iximiuz Labs account must support the requested resources and persistence. See the [prerequisites and setup details](../reference/commands.md).

Both setups manage `node-01` through `node-05`. Use one setup per account and check that those titles are available before starting.

## Start the VMs

From the repository root, run:

```bash
playgrounds/scripts/5vm.sh up
```

Watch the timestamped steps as the script starts playgrounds, enables persistence, installs networking tools, and configures the VPN. Successful completion includes `All 5 VMs connected`.

## Inspect and check the network

```bash
playgrounds/scripts/5vm.sh status
playgrounds/scripts/5vm.sh check
```

`status` shows the playgrounds, public tunnel URL, and an SSH command for the first VM. `check` tests connectivity from the first and last VM to the other VMs. Each VM can reach peers by name, such as `node-03`.

## Stop and resume

Stop the playgrounds while retaining their persistent disks:

```bash
playgrounds/scripts/5vm.sh down
```

When you need them again, run:

```bash
playgrounds/scripts/5vm.sh restart
```

The script reconnects the network using the current public URL.

For a Kubernetes cluster or the 15-VM setup, follow [Manage playgrounds and K3s](../how-to/manage-playgrounds.md). To permanently remove the setup and its data, use the `destroy` command described in the [command reference](../reference/commands.md).
