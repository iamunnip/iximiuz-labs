# Manage playgrounds and K3s

Use this guide with `labctl` installed and authenticated. Read the [prerequisites and naming constraints](../reference/commands.md) first.

## Choose a setup

From the repository root, select one script:

```bash
script=playgrounds/scripts/5vm.sh
# For 15 VMs instead:
# script=playgrounds/scripts/15vm.sh
```

The scripts manage the same playground titles. Remove an old setup before switching layouts; `start` reuses existing playgrounds rather than replacing their VM specifications.

## Create a K3s cluster

To start the selected setup and install K3s:

```bash
"$script" start --k3s
```

To add K3s to an already running setup:

```bash
"$script" k3s
```

The script waits for all expected nodes to become Ready. Standalone `k3s` finishes with `Step: Completed installing K3s`; `start --k3s` finishes with `Step: Completed setting up VMs`. The timestamp shows total elapsed seconds. Both print `Step: Access to hub VM` last. Use that SSH command, or the one printed by `status`, then run `sudo k3s kubectl get nodes` on the control plane.

## Resume persistent VMs

```bash
"$script" restart
"$script" check
```

`restart` requires all five playgrounds to exist and refreshes the tunnel configuration after a public URL change.

## Stop or delete a setup

To keep disks for later:

```bash
"$script" stop
```

`stop` retains persistent disks and finishes with a timestamped `Step: Completed stopping playgrounds; disks retained` heading.

To permanently delete the selected playgrounds and their data:

```bash
"$script" destroy
```

Check `"$script" status` before deletion to inspect the matching playground titles.

Successful deletion finishes with `Step: Completed deleting playgrounds and their data`, including the elapsed time. `stop`, and `destroy` do not print a hub access section. Detailed CLI progress is captured; failures are shown as indented diagnostics and do not produce a success completion heading.
