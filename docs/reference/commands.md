# Command reference

Run the scripts locally with Bash 4.3 or later, standard Unix tools, and `labctl` installed and authenticated to your iximiuz Labs account. Your account must support the requested playground resources and persistence. The VMs need outbound access to Ubuntu package repositories, GitHub releases, and, for K3s, `get.k3s.io` and its downloads.

Both scripts use the playground titles `node-01` through `node-05`. Use one setup at a time in an account: these titles identify the playgrounds the scripts manage. A script can reuse, stop, or delete matching playgrounds created by the other script. Duplicate active titles cause the scripts to stop with an error. Other titles, including `node-06`, are excluded from lifecycle operations.

Run either `playgrounds/scripts/5vm.sh` or `playgrounds/scripts/15vm.sh` with one of these commands. Use `--help` for inline usage.

| Command | Effect |
| --- | --- |
| `up` | Start missing playgrounds, restart stopped ones, configure the network, and check connectivity |
| `up --k3s` | Run `up`, then install K3s |
| `k3s` | Install K3s on existing running VMs |
| `check` | Ping the other VMs from the first and last VM |
| `status` | List playgrounds, the public tunnel URL, and the control plane SSH command |
| `down` | Stop running playgrounds while retaining persistent disks |
| `restart` | Require all five playgrounds to exist, start them, and reconnect the network |
| `destroy` | Delete running and stopped playgrounds and their data |

`up` and `restart` set a 24-hour lifetime and enable persistence. Restarting can change the public tunnel URL; use `restart` to update the clients. Repeating `up` reuses running playgrounds, existing VPN keys, and an existing exposed port.

## Execution output

Steps and per-VM progress go to standard error, with elapsed seconds. For example, `up` reports these stages (times and URLs vary):

```text
[0s] Step: Start or reuse playgrounds
[12s] node-01: Started (<playground-id>)
[15s] Step: Set lifetime to 24h and enable persistence
[17s] Step: Install network tools and collect public keys
[17s] node-01: Executing remote step
[22s] node-01: Remote step completed
[24s] Step: Expose or reuse the tunnel port
[25s] Public URL: https://<public-host>
[25s] Step: Configure the VPN server and clients
[30s] Step: Check connectivity from the first and last VM
[35s] All 5 VMs connected
[35s] Done in 35s
```

Parallel operations can finish in any order. `up --k3s` also reports control plane installation, agent installation, and waiting for Ready nodes. Logging does not print private keys or K3s join tokens.
