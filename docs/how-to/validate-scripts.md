# Validate script changes

Run local checks without provisioning playgrounds:

```bash
bash -n playgrounds/scripts/4vm.sh
bash -n playgrounds/scripts/5vm.sh
bash -n playgrounds/scripts/15vm.sh
shellcheck playgrounds/scripts/*.sh
python3 -m unittest discover -s tests -v
```

`tests/test_4vm.py` covers `4vm.sh` with its own fake `labctl`, including K3s, kubectl setup on `dev-machine`, and keeping the kubeconfig and join token out of the output. `tests/test_scripts.py` executes `5vm.sh` and `15vm.sh` with a fake `labctl` for `start`, `start --k3s`, `k3s`, `check`, `status`, `stop`, `restart`, and `destroy`. They verify timestamped task and completion headings, two-space indentation, hidden raw CLI progress, and hub-only access printed last where applicable. They also cover lifecycle failure handling, command validation, duplicate titles, operation scope, help output, captured exposed-port progress, and rejecting malformed script files before any VM operation. A regression test replaces the script file during execution to ensure the completion block still runs correctly. Temporary playground-list errors are tested for bounded retries; persistent errors must exit without starting replacement VMs. They do not verify remote provisioning or live network connectivity.

When changing script behavior or terminal output, update the README, command reference, and affected guides in the same change. Confirm that examples match both scripts, including the `--machine vm-01` argument for the 15-VM hub.
