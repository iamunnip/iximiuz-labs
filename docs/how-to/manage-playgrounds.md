# Manage playgrounds and K3s

Use this guide with `labctl` installed and authenticated. Read the [prerequisites and naming constraints](../reference/commands.md) first.

## Choose a setup

From the repository root, select one script:

```bash
script=playgrounds/scripts/5vm.sh
# For 15 VMs instead:
# script=playgrounds/scripts/15vm.sh
```

The scripts manage the same playground titles. Remove an old setup before switching layouts; `up` reuses existing playgrounds rather than replacing their VM specifications.

## Create a K3s cluster

To start the selected setup and install K3s:

```bash
"$script" up --k3s
```

To add K3s to an already running setup:

```bash
"$script" k3s
```

The script waits for all expected nodes to become Ready. Use the SSH command printed by `status`, then run `sudo k3s kubectl get nodes` on the control plane.

## Resume persistent VMs

```bash
"$script" restart
"$script" check
```

`restart` requires all five playgrounds to exist and refreshes the tunnel configuration after a public URL change.

## Stop or delete a setup

To keep disks for later:

```bash
"$script" down
```

To permanently delete the selected playgrounds and their data:

```bash
"$script" destroy
```

Check `"$script" status` before deletion to inspect the matching playground titles.
