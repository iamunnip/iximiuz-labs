# Command reference

Run the scripts locally with Bash 4.3 or later, standard Unix tools, and `labctl` installed and authenticated to your iximiuz Labs account. Your account must support the requested playground resources and persistence. The VMs need outbound access to Ubuntu package repositories, GitHub releases, and, for K3s, `get.k3s.io` and its downloads.

Both scripts use the playground titles `node-01` through `node-05`. Use one setup at a time in an account: these titles identify the playgrounds the scripts manage. A script can reuse, stop, or delete matching playgrounds created by the other script. Duplicate active titles cause the scripts to stop with an error. Other titles, including `node-06`, are excluded from lifecycle operations.

Run either `playgrounds/scripts/5vm.sh` or `playgrounds/scripts/15vm.sh` with one of these commands. Use `--help` for inline usage.

| Command | Effect |
| --- | --- |
| `start` | Start missing playgrounds, restart stopped ones, configure the network, and check connectivity |
| `start --k3s` | Run `start`, then install K3s |
| `k3s` | Install K3s on existing running VMs |
| `check` | Ping the other VMs from the first and last VM |
| `status` | List playgrounds, the public tunnel URL, and the WireGuard hub SSH command |
| `stop` | Stop running playgrounds while retaining persistent disks |
| `restart` | Require all five playgrounds to exist, start them, and reconnect the network |
| `destroy` | Delete running and stopped playgrounds and their data |

`start` and `restart` set a 24-hour lifetime and enable persistence. Restarting can change the public tunnel URL; use `restart` to update the clients. Repeating `start` reuses running playgrounds, existing VPN keys, and an existing exposed port.

## 4vm.sh

`4vm.sh` takes the same commands and uses the same output format, for one playground titled `4vm`. Other titles are left alone. Differences:

- There is no VPN or public port. The VMs reach each other by name through the `/etc/hosts` entries that iximiuz Labs writes.
- `check` pings `node-1`, `node-2` and `node-3` from `dev-machine`.
- `start --k3s` and `k3s` add a final K3s step, `Set up kubectl on dev-machine`, which installs the `kubectl` version that matches K3s and copies the kubeconfig to `laborant`. The kubeconfig is never printed.
- `status` shows the one playground and whether K3s is installed on `node-1`, the control plane.
- The access section is `Step: Access to dev-machine`, with `labctl ssh <playground-id> --machine dev-machine`.
- `stop` and `destroy` finish with `Completed stopping the playground; disks retained` and `Completed deleting the playground and its data`.

## Execution output

Steps and per-VM progress go to standard error, with a blank line between tasks. Every step header shows the elapsed time. Detail lines are indented by two spaces and have no timestamp. The timer continues running internally and the completion header reports the total setup duration. Lifetime and persistence commands produce one result per playground; their detailed output is printed if an operation fails. Deletion also captures each command’s output and shows one indented result per playground, preserving diagnostics on failure. Successful deletion ends with a timestamped `Step: Completed deleting playgrounds and their data` header showing the total elapsed time. For example, `start` reports these stages (times and URLs vary):

```text
[0s] Step: Start or reuse playgrounds
  node-01: Started (<playground-id>)

[15s] Step: Set lifetime to 24h and enable persistence
  node-01: Lifetime 24h; persistent
  ...
  All playgrounds: lifetime 24h, persistent

[17s] Step: Install network tools and collect public keys
  node-01: Executing remote step
  node-01: Remote step completed

[24s] Step: Expose or reuse the tunnel port
  Public URL: https://<public-host>

[25s] Step: Configure the VPN server and clients

[30s] Step: Check connectivity from the first and last VM

[35s] Step: Completed setting up VMs
  All 5 VMs connected

[35s] Step: Access to hub VM
  node-01: labctl ssh <node-01-playground-id>
```

Parallel operations can finish in any order. `start --k3s` also reports control plane installation, agent installation, and waiting for Ready nodes. Logging does not print private keys or K3s join tokens.

`start` and `restart` print the hub connection command last, after the setup completion summary. `status` also shows the hub command when it is running. The hub is `node-01` for 5 VMs and `node-01-vm-01` for 15 VMs. The latter uses `labctl ssh <node-01-playground-id> --machine vm-01`.

## Output for all commands

Every successful operational command ends with a timestamped completion heading:

| Command | Completion heading |
| --- | --- |
| `start`, `start --k3s`, `restart` | Completed setting up VMs |
| `check` | Completed connectivity check |
| `k3s` | Completed installing K3s |
| `status` | Completed checking playground status |
| `stop` | Completed stopping playgrounds; disks retained |
| `destroy` | Completed deleting playgrounds and their data |

When the hub is running, `start`, `restart`, `check`, `k3s`, and `status` finish with `Step: Access to hub VM` after the completion summary. Only the hub SSH command is printed. `stop`, and `destroy` have no access section. A failed command exits without a success completion heading.

Lifecycle progress from `labctl` is captured per playground so parallel commands do not mix terminal rendering or progress messages. Errors remain visible as indented details. `status` lists the five expected playgrounds in order, including missing and stopped ones. Help displays usage without running operational steps.

Use `start --k3s` to provision VMs and install K3s, or `k3s` to install it on running VMs. `--k3s` is a flag for `start`, rather than a standalone command.
