# Validate script changes

Run local checks without provisioning playgrounds:

```bash
bash -n playgrounds/scripts/5vm.sh
bash -n playgrounds/scripts/15vm.sh
shellcheck playgrounds/scripts/*.sh
python3 -m unittest discover -s tests -v
```

The tests execute both scripts with a fake `labctl` for `start`, `start --k3s`, `k3s`, `check`, `status`, `stop`, `restart`, and `destroy`. They verify timestamped task and completion headings, two-space indentation, hidden raw CLI progress, and hub-only access printed last where applicable. They also cover lifecycle failure handling, command validation, duplicate titles, operation scope, and help output. They do not verify remote provisioning or live network connectivity.

When changing script behavior or terminal output, update the README, command reference, and affected guides in the same change. Confirm that examples match both scripts, including the `--machine vm-01` argument for the 15-VM hub.
