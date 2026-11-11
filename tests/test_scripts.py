"""Exercise orchestration with a fake labctl; never contact real playgrounds."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = [ROOT / "playgrounds/scripts" / name for name in ("15vm.sh", "5vm.sh")]  # multi-playground VPN setups
MOCK = r'''#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
case "$1 $2" in
  'playground list')
    if [[ $SCENARIO == file_replaced && ! -e ${CALLS}.replaced ]]; then
      cp "$REPLACEMENT" "$SCRIPT_SOURCE"
      touch "${CALLS}.replaced"
    fi
    if [[ $SCENARIO == list_502 || ( $SCENARIO == list_transient && $(wc -l < "$CALLS") == 1 ) ]]; then
      echo 'labctl: request failed with status 502: error code: 502' >&2
      exit 1
    fi
    if [[ $SCENARIO == list_401 ]]; then
      echo 'labctl: request failed with status 401' >&2
      exit 1
    fi
    echo 'ID TEMPLATE TITLE STATUS'
    case "$SCENARIO" in
      empty|start_failure) ;;
      duplicate)
        echo 'id1 flexbox node-01 RUNNING'
        echo 'id2 flexbox node-01 STOPPED' ;;
      running|persist_failure|expose_new|list_transient|file_replaced)
        for i in {1..5}; do printf 'id%s flexbox node-%02d RUNNING\n' "$i" "$i"; done ;;
      *)
        echo 'id1 flexbox node-01 RUNNING'
        echo 'id2 flexbox node-02 STOPPED'
        echo 'other flexbox node-06 RUNNING' ;;
    esac ;;
  'playground start') echo 'Simulated creation failure' >&2; exit 1 ;;
  'playground destroy')
    if [[ $SCENARIO == destroy_failure ]]; then
      echo 'Simulated deletion failure' >&2; exit 1
    fi
    printf '\033]11;rgb:1111/1414/1616\033\\' >&2
    echo 'Destroying playground (raw progress)'
    echo 'Waiting for playground to be destroyed... Done.' >&2 ;;
  'playground lifetime') echo 'Setting lifetime (raw progress)' >&2 ;;
  'playground persist')
    if [[ $SCENARIO == persist_failure ]]; then
      echo 'Simulated persistence failure' >&2; exit 1
    fi
    echo 'Persisting playground (raw progress)' >&2 ;;
  'playground stop'|'playground restart') echo 'Lifecycle raw progress' >&2 ;;
  'ssh '*)
    if [[ $SCENARIO == status_ssh_failure ]]; then echo 'Simulated SSH failure' >&2; exit 1; fi
    script=$(cat)
    bash -n <<<"$script" || exit 1
    echo "$script" >> "$REMOTE"
    if [[ $script == *'wg pubkey'* ]]; then
      printf '%s\n' 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
    elif [[ $script == *'cat /data/k3s/server/node-token'* ]]; then
      echo 'mock-join-token'
    fi ;;
  'expose list')
    if [[ $SCENARIO == status_url_failure ]]; then echo 'Simulated expose-list failure' >&2; exit 1; fi
    [[ $SCENARIO != expose_new ]] || exit 0
    echo 'port http://vm:8080 https://example.test';
    echo 'port http://vm-01:8080 https://example.test' ;;
  'expose port') echo 'HTTP port exposed (raw progress)' >&2; echo 'https://example.test' ;;
  *) echo "Unexpected labctl command: $*" >&2; exit 2 ;;
esac
'''


class ScriptTests(unittest.TestCase):
    def run_script(self, script, scenario, *args):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            mock = base / "labctl"
            mock.write_text(MOCK)
            mock.chmod(0o755)
            sleep = base / "sleep"
            sleep.write_text("#!/usr/bin/env bash\nexit 0\n")
            sleep.chmod(0o755)
            calls, remote = base / "calls", base / "remote"
            env = dict(os.environ, PATH=f"{base}:{os.environ['PATH']}",
                       SCENARIO=scenario, CALLS=str(calls), REMOTE=str(remote))
            if scenario == "file_replaced":
                source = script.read_text()
                script = base / script.name
                script.write_text(source)
                replacement = base / "replacement.sh"
                replacement.write_text("# updated revision\n" * 2000 + source)
                env.update(SCRIPT_SOURCE=str(script), REPLACEMENT=str(replacement))
            result = subprocess.run(["bash", str(script), *args], env=env,
                                    text=True, capture_output=True, timeout=15)
            return result, calls.read_text() if calls.exists() else ""

    def test_help_and_argument_validation(self):
        for script in SCRIPTS:
            with self.subTest(script=script.name):
                result, calls = self.run_script(script, "empty", "--help")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("Usage:", result.stdout)
                self.assertEqual(calls, "")
                result, calls = self.run_script(script, "empty", "stop", "x", "y")
                self.assertEqual(result.returncode, 2)
                self.assertEqual(calls, "")

    def test_failed_creation_is_not_success(self):
        for script in SCRIPTS:
            with self.subTest(script=script.name):
                result, calls = self.run_script(script, "start_failure", "start")
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn(": Started", result.stderr)
                self.assertIn("  Simulated creation failure", result.stderr)
                self.assertNotIn("ssh ", calls)
                self.assertIn("Step: Start", result.stderr)

    def test_destroy_failure_propagates(self):
        for script in SCRIPTS:
            with self.subTest(script=script.name):
                result, calls = self.run_script(script, "destroy_failure", "destroy")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Simulated deletion failure", result.stderr)
                self.assertNotIn("destroy other", calls)
                self.assertNotIn("Completed deleting", result.stderr)

    def test_destroy_includes_stopped_and_excludes_unrelated(self):
        for script in SCRIPTS:
            with self.subTest(script=script.name):
                result, calls = self.run_script(script, "normal", "destroy")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("playground destroy id1", calls)
                self.assertIn("playground destroy id2", calls)
                self.assertEqual(result.stdout, "")
                self.assertNotIn("\x1b", result.stderr)
                self.assertNotIn("raw progress", result.stderr)
                self.assertNotIn("Waiting for playground", result.stderr)
                self.assertIn("  node-01: Destroyed (id1)", result.stderr)
                self.assertIn("  node-02: Destroyed (id2)", result.stderr)
                self.assertRegex(result.stderr, r"\n\[\d+s\] Step: Completed deleting playgrounds and their data\n$")
                self.assertNotIn("destroy other", calls)

    def test_empty_destroy_succeeds(self):
        for script in SCRIPTS:
            with self.subTest(script=script.name):
                result, _ = self.run_script(script, "empty", "destroy")
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_duplicate_names_prevent_mutation(self):
        for script in SCRIPTS:
            with self.subTest(script=script.name):
                result, calls = self.run_script(script, "duplicate", "stop")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Duplicate playground title", result.stderr)
                self.assertNotIn("playground stop", calls)

    def test_stop_only_stops_running_setup_members(self):
        for script in SCRIPTS:
            with self.subTest(script=script.name):
                result, calls = self.run_script(script, "normal", "stop")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("playground stop id1", calls)
                self.assertNotIn("playground stop id2", calls)
                self.assertNotIn("playground stop other", calls)

    def test_start_with_k3s_generates_valid_remote_scripts(self):
        for script in SCRIPTS:
            with self.subTest(script=script.name):
                result, calls = self.run_script(script, "running", "start", "--k3s")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("Step: Configure the VPN server and clients", result.stderr)
                self.assertIn("Step: Wait for all K3s nodes", result.stderr)
                self.assertRegex(result.stderr, r"\n\[\d+s\] Step: Completed setting up VMs\n  All (5|15) VMs connected\n\n\[\d+s\] Step: Access to hub VM\n  node-01(?:-vm-01)?: labctl ssh id1(?: --machine vm-01)?\n$")
                self.assertNotIn("mock-join-token", result.stderr)
                self.assertIn("playground persist id5", calls)
                self.assertNotIn("raw progress", result.stderr)
                self.assertIn("node-01: Lifetime 24h; persistent", result.stderr)
                self.assertIn("\n\n[", result.stderr)
                timed_lines = [line for line in result.stderr.splitlines() if line.startswith("[") and "Step: " in line]
                step_lines = [line for line in result.stderr.splitlines() if "Step: " in line]
                self.assertEqual(timed_lines, step_lines)
                self.assertGreater(len(timed_lines), 1)
                for line in timed_lines:
                    self.assertRegex(line, r"^\[\d+s\] Step: ")
                for line in result.stderr.splitlines():
                    if line.strip() and not line.startswith("["):
                        self.assertTrue(line.startswith("  "), line)
                self.assertIn("Step: Start or reuse playgrounds", timed_lines[0])
                self.assertIn("Step: Access to hub VM", result.stderr)
                if script.stem == "15vm":
                    self.assertIn("labctl ssh id1 --machine vm-01", result.stderr)
                    self.assertNotIn("labctl ssh id5", result.stderr)
                    self.assertIn("node-01-vm-01: labctl ssh", result.stderr)
                else:
                    self.assertIn("labctl ssh id1\n", result.stderr)
                    self.assertNotIn("labctl ssh id5", result.stderr)
                ssh_calls = [line for line in calls.splitlines() if line.startswith("ssh ")]
                node_count = 15 if script.stem == "15vm" else 5
                self.assertEqual(len(ssh_calls), 3 * node_count + 3)
                self.assertTrue(all(" -- sudo bash -s" in line for line in ssh_calls))
                self.assertNotIn("ssh-proxy", calls)
                if node_count == 15:
                    self.assertTrue(all(" --machine vm-" in line for line in ssh_calls))

    def test_every_operational_option_has_completion_and_consistent_format(self):
        options = [
            (("start",), "Completed setting up VMs", True),
            (("start", "--k3s"), "Completed setting up VMs", True),
            (("restart",), "Completed setting up VMs", True),
            (("check",), "Completed connectivity check", True),
            (("k3s",), "Completed installing K3s", True),
            (("status",), "Completed checking playground status", True),
            (("stop",), "Completed stopping playgrounds; disks retained", False),
            (("destroy",), "Completed deleting playgrounds and their data", False),
        ]
        for script in SCRIPTS:
            for args, completion, access in options:
                with self.subTest(script=script.name, args=args):
                    result, _ = self.run_script(script, "running", *args)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout, "")
                    self.assertNotIn("raw progress", result.stderr)
                    self.assertNotIn("\x1b", result.stderr)
                    self.assertIn("Step: " + completion, result.stderr)
                    for line in result.stderr.splitlines():
                        if not line.strip():
                            continue
                        if line.startswith("["):
                            self.assertRegex(line, r"^\[\d+s\] Step: ")
                        else:
                            self.assertTrue(line.startswith("  "), line)
                    if access:
                        self.assertLess(result.stderr.index(completion), result.stderr.index("Step: Access to hub VM"))
                        self.assertEqual(result.stderr.count("Step: Access to hub VM"), 1)
                        self.assertRegex(result.stderr.splitlines()[-1], r"^  node-01(?:-vm-01)?: labctl ssh id1(?: --machine vm-01)?$")
                    else:
                        self.assertNotIn("Step: Access", result.stderr)
                        self.assertTrue(result.stderr.rstrip().endswith(completion))

    def test_status_does_not_hide_api_or_ssh_failures(self):
        for script in SCRIPTS:
            for scenario, error in (("status_url_failure", "Simulated expose-list failure"),
                                    ("status_ssh_failure", "Simulated SSH failure")):
                with self.subTest(script=script.name, scenario=scenario):
                    result, _ = self.run_script(script, scenario, "status")
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(error, result.stderr)
                    self.assertNotIn("Completed checking", result.stderr)
                    self.assertNotIn("Not installed", result.stderr)

    def test_replacing_source_during_execution_does_not_break_completion(self):
        for script in SCRIPTS:
            with self.subTest(script=script.name):
                result, _ = self.run_script(script, "file_replaced", "start")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("Step: Completed setting up VMs", result.stderr)
                self.assertIn("Step: Access to hub VM", result.stderr)

    def test_list_retries_transient_failure(self):
        for script in SCRIPTS:
            with self.subTest(script=script.name):
                result, calls = self.run_script(script, "list_transient", "start")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("retrying in 2s", result.stderr)
                self.assertIn("Completed setting up VMs", result.stderr)
                self.assertNotIn("playground start", calls)

    def test_list_failure_does_not_mutate_playgrounds(self):
        for script in SCRIPTS:
            for scenario, attempts in (("list_502", 3), ("list_401", 1)):
                with self.subTest(script=script.name, scenario=scenario):
                    result, calls = self.run_script(script, scenario, "start")
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(calls.splitlines(), ["playground list"] * attempts)
                    self.assertIn("no further operations will run", result.stderr)
                    self.assertNotIn("Completed setting up", result.stderr)

    def test_new_exposure_progress_is_captured(self):
        for script in SCRIPTS:
            with self.subTest(script=script.name):
                result, calls = self.run_script(script, "expose_new", "start")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("expose port id1", calls)
                self.assertNotIn("raw progress", result.stderr)
                self.assertIn("  Public URL: https://example.test", result.stderr)
                self.assertIn("Step: Completed setting up VMs", result.stderr)

    def test_invalid_file_is_rejected_before_labctl(self):
        with tempfile.TemporaryDirectory() as directory:
            invalid = Path(directory) / "invalid.sh"
            invalid.write_text(SCRIPTS[0].read_text() + "\n;;\n")
            result, calls = self.run_script(invalid, "running", "start")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("syntax error", result.stderr)
            self.assertEqual(calls, "")

    def test_mock_rejects_uppercase_ssh(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            mock = base / "labctl"
            mock.write_text(MOCK)
            result = subprocess.run(
                ["bash", str(mock), "SSH", "id1"],
                env=dict(os.environ, CALLS=str(base / "calls")),
                text=True, capture_output=True, timeout=5,
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn("Unexpected labctl command: SSH", result.stderr)

    def test_persistence_error_remains_visible(self):
        for script in SCRIPTS:
            with self.subTest(script=script.name):
                result, calls = self.run_script(script, "persist_failure", "start")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Simulated persistence failure", result.stderr)
                self.assertIn("Failed to set lifetime or persistence", result.stderr)
                self.assertNotIn("ssh ", calls)

    def test_status_shows_only_hub_connection(self):
        for script in SCRIPTS:
            with self.subTest(script=script.name):
                result, _ = self.run_script(script, "normal", "status")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("labctl ssh id1", result.stderr)
                self.assertNotIn("labctl ssh id2", result.stderr)
                self.assertNotIn("labctl ssh other", result.stderr)


if __name__ == "__main__":
    unittest.main()
