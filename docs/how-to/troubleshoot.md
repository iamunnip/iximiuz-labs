# Troubleshoot playgrounds

Failed creation, restart, stop, persistence, and deletion operations return a nonzero exit status. Remote background steps retry up to three times. A failed command can leave some playgrounds updated; inspect `status`, resolve the error, and rerun the command. If a playground remains in a transitional state for about three minutes, the script exits rather than creating a replacement.

For network errors, inspect `systemctl status tunnel wg-quick@mesh0` and `wg show` through `labctl ssh`. The first VM hosts the tunnel server, so it must be running for traffic between clients. `check` samples reachability from two VMs; it does not verify every pair or Kubernetes workload health.

For K3s administration, SSH to the control plane and run `sudo k3s kubectl get nodes`. Its kubeconfig is root-readable because it grants cluster administration access.

## Read the execution output

Every task heading shows elapsed seconds; detail lines use two-space indentation. A successful command prints its completion heading before the final hub access section, when applicable. If the command fails, inspect the indented diagnostics; a success completion heading is not printed.

Lifecycle commands capture raw CLI progress so parallel operations do not mix terminal rendering with script messages. If deletion fails, the output includes the playground name, ID, and captured error. Resolve the error and rerun `destroy` to remove remaining playgrounds.

Use lowercase `labctl ssh` to connect. The final access command selects the WireGuard hub: `node-01` for 5 VMs or `node-01-vm-01` with `--machine vm-01` for 15 VMs. No additional local proxy process is required.

## Syntax error after an operation

Both scripts validate their full Bash syntax before contacting playgrounds. If a local copy reports an unexpected token, run `bash -n ./15vm.sh` (or `bash -n ./5vm.sh`) and replace the file with a complete copy of the current script. Keep the script file unchanged while it runs.

If connectivity checks succeeded before the error, keep the existing VMs. After correcting the file, run `check` to verify the network and print the hub access command; provisioning again is unnecessary.
