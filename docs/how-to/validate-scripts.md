# Validate script changes

Run local checks without provisioning playgrounds:

```bash
bash -n playgrounds/scripts/5vm.sh
bash -n playgrounds/scripts/15vm.sh
shellcheck playgrounds/scripts/*.sh
python3 -m unittest discover -s tests -v
```

The tests substitute a fake `labctl` and cover lifecycle failure handling, command validation, duplicate titles, and operation scope. They do not verify remote provisioning or live network connectivity.
