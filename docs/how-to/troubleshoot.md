# Troubleshoot playgrounds

Failed creation, restart, stop, persistence, and deletion operations return a nonzero exit status. Remote background steps retry up to three times. A failed command can leave some playgrounds updated; inspect `status`, resolve the error, and rerun the command. If a playground remains in a transitional state for about three minutes, the script exits rather than creating a replacement.

For network errors, inspect `systemctl status tunnel wg-quick@mesh0` and `wg show` through `labctl ssh`. The first VM hosts the tunnel server, so it must be running for traffic between clients. `check` samples reachability from two VMs; it does not verify every pair or Kubernetes workload health.

For K3s administration, SSH to the control plane and run `sudo k3s kubectl get nodes`. Its kubeconfig is root-readable because it grants cluster administration access.
