# Troubleshoot playgrounds

Failed creation, restart, stop, persistence, and deletion operations return a nonzero exit status. Remote background steps retry up to three times. A failed command can leave some playgrounds updated; inspect `status`, resolve the error, and rerun the command. If a playground remains in a transitional state for about three minutes, the script exits rather than creating a replacement.

For network errors, inspect `systemctl status tunnel wg-quick@mesh0` and `wg show` through `labctl ssh`. The first VM hosts the tunnel server, so it must be running for traffic between clients. `check` samples reachability from two VMs; it does not verify every pair or Kubernetes workload health.

For K3s administration, SSH to the control plane and run `sudo k3s kubectl get nodes`. Its kubeconfig is root-readable because it grants cluster administration access.

## Read the execution output

Every task heading shows elapsed seconds; detail lines use two-space indentation. A successful command prints its completion heading before the final hub access section, when applicable. If the command fails, inspect the indented diagnostics; a success completion heading is not printed.

Lifecycle commands capture raw CLI progress so parallel operations do not mix terminal rendering with script messages. If deletion fails, the output includes the playground name, ID, and captured error. Resolve the error and rerun `destroy` to remove remaining playgrounds.

Use lowercase `labctl ssh` to connect. The final access command selects the WireGuard hub: `node-01` for 5 VMs or `node-01-vm-01` with `--machine vm-01` for 15 VMs. No additional local proxy process is required.

## Syntax error after an operation

Both scripts validate their full Bash syntax before contacting playgrounds. Command dispatch and completion are parsed together in a function before any long-running operation. If a local copy reports an unexpected token, run `bash -n ./15vm.sh` (or `bash -n ./5vm.sh`) and replace the file with a complete copy of the current script. Replacing a Bash script in place while it runs can cause Bash to read changed text at the old file offset, producing unexpected tokens or stray command names after a long step. Both scripts now keep dispatch and completion in the same parsed function and exit without reading a changed file tail. A regression test replaces the source during execution and verifies successful completion.

If connectivity checks succeeded before the error, keep the existing VMs. After correcting the file, run `check` to verify the network and print the hub access command; provisioning again is unnecessary.

## Playground listing returns HTTP 502

A failed playground-list request prevents the script from discovering existing VMs. Both scripts retry temporary listing failures, including HTTP 429, 500, 502, 503, and 504, up to three attempts with 2- and 4-second delays. Authentication errors are returned immediately.

If all attempts fail, the command exits with the captured error before performing further operations. It does not interpret a failed listing as an empty account or create replacement VMs. Retry the command once the API is responding; existing playgrounds are retained.

`status` returns an error if reading the public URL or inspecting the hub over SSH fails. These failures are not reported as a missing K3s installation or a successful status check.
