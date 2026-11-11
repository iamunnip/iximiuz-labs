"""Exercise 4vm.sh with a fake labctl; never contact real playgrounds."""
import base64
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "playgrounds/scripts/4vm.sh"
KUBECONFIG = base64.b64encode(b"server: https://127.0.0.1:6443\nclient-key-data: secret-key\n").decode()
MOCK = r'''#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
case "$1 $2" in
  'playground list')
    if [[ $SCENARIO == list_502 || ( $SCENARIO == list_transient && $(wc -l < "$CALLS") == 1 ) ]]; then
      echo 'labctl: request failed with status 502: error code: 502' >&2
      exit 1
    fi
    if [[ $SCENARIO == list_401 ]]; then echo 'labctl: request failed with status 401' >&2; exit 1; fi
    echo 'ID TEMPLATE TITLE STATUS'
    case "$SCENARIO" in
      empty|start_failure) ;;
      created) if [[ -e ${CALLS}.created ]]; then echo 'id1 flexbox 4vm RUNNING'; fi ;;
      duplicate) echo 'id1 flexbox 4vm RUNNING'; echo 'id2 flexbox 4vm STOPPED' ;;
      stopped) echo 'id1 flexbox 4vm STOPPED'; echo 'other flexbox node-01 RUNNING' ;;
      *) echo 'id1 flexbox 4vm RUNNING'; echo 'other flexbox node-01 RUNNING' ;;
    esac ;;
  'playground start')
    [[ $SCENARIO == created ]] || { echo 'Simulated creation failure' >&2; exit 1; }
    touch "${CALLS}.created"; echo 'Creating (raw progress)' >&2; echo id1 ;;
  'playground destroy')
    [[ $SCENARIO != destroy_failure ]] || { echo 'Simulated deletion failure' >&2; exit 1; }
    echo 'Destroying playground (raw progress)' ;;
  'playground lifetime') echo 'Setting lifetime (raw progress)' >&2 ;;
  'playground persist')
    [[ $SCENARIO != persist_failure ]] || { echo 'Simulated persistence failure' >&2; exit 1; }
    echo 'Persisting playground (raw progress)' >&2 ;;
  'playground stop'|'playground restart') echo 'Lifecycle raw progress' >&2 ;;
  'ssh '*)
    [[ $SCENARIO != status_ssh_failure ]] || { echo 'Simulated SSH failure' >&2; exit 1; }
    script=$(cat)
    bash -n <<<"$script" || exit 1
    printf '%s\n---\n' "$*" >> "$REMOTE"
    echo "$script" >> "$REMOTE"
    if [[ $script == *'cat /var/lib/rancher/k3s/server/node-token'* ]]; then
      echo "Created symlink '/etc/systemd/system/k3s.service'." >&2
      echo 'mock-join-token'
    elif [[ $script == *'k3s --version'* ]]; then
      echo v1.33.5; echo "$KUBECONFIG_B64"
    elif [[ $script == *'command -v k3s'* && $SCENARIO != no_k3s ]]; then
      echo /usr/local/bin/k3s
    fi ;;
  *) echo "Unexpected labctl command: $*" >&2; exit 2 ;;
esac
'''


class FourVmTests(unittest.TestCase):
    def run_script(self, scenario, *args):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            for name, body in (("labctl", MOCK), ("sleep", "#!/usr/bin/env bash\nexit 0\n")):
                path = base / name
                path.write_text(body)
                path.chmod(0o755)
            calls, remote = base / "calls", base / "remote"
            env = dict(os.environ, PATH=f"{base}:{os.environ['PATH']}", SCENARIO=scenario,
                       CALLS=str(calls), REMOTE=str(remote), KUBECONFIG_B64=KUBECONFIG)
            result = subprocess.run(["bash", str(SCRIPT), *args], env=env,
                                    text=True, capture_output=True, timeout=15)
            read = lambda p: p.read_text() if p.exists() else ""
            return result, read(calls), read(remote)

    def assert_format(self, stderr):
        for line in stderr.splitlines():
            if line.strip():
                if line.startswith("["):
                    self.assertRegex(line, r"^\[\d+s\] Step: ")
                else:
                    self.assertTrue(line.startswith("  "), line)
        self.assertNotIn("raw progress", stderr)

    def test_help_and_argument_validation(self):
        result, calls, _ = self.run_script("empty", "--help")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Usage:", result.stdout)
        self.assertEqual(calls, "")
        result, calls, _ = self.run_script("empty", "stop", "x", "y")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(calls, "")

    def test_start_creates_playground_from_manifest(self):
        result, calls, remote = self.run_script("created", "start")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertRegex(calls, r"playground start flexbox -f \S+/4vm\.yaml --title 4vm --quiet")
        self.assertIn("  4vm: Started (id1)", result.stderr)
        self.assertIn("playground persist id1", calls)
        self.assertRegex(result.stderr, r"\n\[\d+s\] Step: Completed setting up VMs\n  All 4 VMs connected\n\n"
                                        r"\[\d+s\] Step: Access to dev-machine\n  dev-machine: labctl ssh id1 --machine dev-machine\n$")
        self.assert_format(result.stderr)

    def test_start_with_k3s(self):
        result, calls, remote = self.run_script("running", "start", "--k3s")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("playground start", calls)
        for step in ("Check connectivity from dev-machine",
                     "Install K3s on control-plane", "Install K3s agents", "Wait for all K3s nodes",
                     "Set up kubectl on dev-machine", "Completed setting up VMs"):
            self.assertIn("Step: " + step, result.stderr)
        self.assertIn("K3S_URL=https://control-plane:6443", remote)
        self.assertIn("INSTALL_K3S_TYPE=exec", remote)
        self.assertIn("dl.k8s.io/release/v1.33.5", remote)
        self.assertNotIn("mock-join-token", result.stderr)
        self.assertIn("\n  Created symlink", result.stderr)
        self.assertNotIn(KUBECONFIG, result.stderr)
        self.assertNotIn("secret-key", result.stderr)
        ssh_calls = [line for line in calls.splitlines() if line.startswith("ssh ")]
        # 1 check, 1 server, 2 agents, 1 ready, 1 kubeconfig, 1 kubectl
        self.assertEqual(len(ssh_calls), 7)
        self.assertTrue(all(line.startswith("ssh id1 --machine ") and line.endswith(" -- sudo bash -s") for line in ssh_calls))
        self.assert_format(result.stderr)

    def test_every_command_completes(self):
        options = [
            (("start",), "Completed setting up VMs", True),
            (("restart",), "Completed setting up VMs", True),
            (("check",), "Completed connectivity check", True),
            (("k3s",), "Completed installing K3s", True),
            (("status",), "Completed checking playground status", True),
            (("stop",), "Completed stopping the playground; disks retained", False),
            (("destroy",), "Completed deleting the playground and its data", False),
        ]
        for args, completion, access in options:
            with self.subTest(args=args):
                result, _, _ = self.run_script("running", *args)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "")
                self.assertIn("Step: " + completion, result.stderr)
                self.assert_format(result.stderr)
                if access:
                    self.assertEqual(result.stderr.splitlines()[-1], "  dev-machine: labctl ssh id1 --machine dev-machine")
                else:
                    self.assertNotIn("Step: Access", result.stderr)

    def test_restart_restarts_stopped_playground(self):
        result, calls, _ = self.run_script("stopped", "restart")
        self.assertNotEqual(result.returncode, 0)  # the mock never reports it running again
        self.assertIn("playground restart id1", calls)
        self.assertNotIn("other", calls)

    def test_failures_are_not_success(self):
        for scenario, args, error in (("start_failure", ("start",), "Simulated creation failure"),
                                      ("persist_failure", ("start",), "Simulated persistence failure"),
                                      ("destroy_failure", ("destroy",), "Simulated deletion failure"),
                                      ("status_ssh_failure", ("status",), "Simulated SSH failure")):
            with self.subTest(scenario=scenario):
                result, calls, _ = self.run_script(scenario, *args)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(error, result.stderr)
                self.assertNotIn("Step: Completed", result.stderr)
                if scenario != "status_ssh_failure":
                    self.assertNotIn("ssh ", calls)

    def test_duplicate_title_prevents_mutation(self):
        result, calls, _ = self.run_script("duplicate", "stop")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Duplicate playground title", result.stderr)
        self.assertNotIn("playground stop", calls)

    def test_other_playgrounds_are_untouched(self):
        for args in (("stop",), ("destroy",)):
            with self.subTest(args=args):
                result, calls, _ = self.run_script("running", *args)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(f"playground {args[0]} id1", calls)
                self.assertNotIn("other", calls)

    def test_empty_commands(self):
        result, _, _ = self.run_script("empty", "destroy")
        self.assertEqual(result.returncode, 0, result.stderr)
        result, _, _ = self.run_script("empty", "check")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("4vm is not running", result.stderr)
        result, _, _ = self.run_script("empty", "status")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("4vm: Not created", result.stderr)

    def test_status_reports_k3s(self):
        result, _, _ = self.run_script("running", "status")
        self.assertIn("K3s: labctl ssh id1 --machine dev-machine -- kubectl get nodes", result.stderr)
        result, _, _ = self.run_script("no_k3s", "status")
        self.assertIn("K3s: Not installed", result.stderr)

    def test_list_retries_and_failures(self):
        result, calls, _ = self.run_script("list_transient", "start")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("retrying in 2s", result.stderr)
        for scenario, attempts in (("list_502", 3), ("list_401", 1)):
            with self.subTest(scenario=scenario):
                result, calls, _ = self.run_script(scenario, "start")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(calls.splitlines(), ["playground list"] * attempts)


if __name__ == "__main__":
    unittest.main()
