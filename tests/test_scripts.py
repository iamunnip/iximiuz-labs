"""Exercise orchestration with a fake labctl; never contact real playgrounds."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = sorted((ROOT / "playgrounds/scripts").glob("*.sh"))
MOCK = r'''#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
case "$1 $2" in
  'playground list')
    echo 'ID TEMPLATE TITLE STATUS'
    case "$SCENARIO" in
      empty|start_failure) ;;
      duplicate)
        echo 'id1 flexbox node-01 RUNNING'
        echo 'id2 flexbox node-01 STOPPED' ;;
      running)
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
    fi ;;
  'ssh '*)
    script=$(cat)
    bash -n <<<"$script" || exit 1
    echo "$script" >> "$REMOTE"
    if [[ $script == *'wg pubkey'* ]]; then
      printf '%s\n' 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
    elif [[ $script == *'cat /data/k3s/server/node-token'* ]]; then
      echo 'mock-join-token'
    fi ;;
  'expose list') echo 'port http://vm:8080 https://example.test';
    echo 'port http://vm-01:8080 https://example.test' ;;
esac
'''


class ScriptTests(unittest.TestCase):
    def run_script(self, script, scenario, *args):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            mock = base / "labctl"
            mock.write_text(MOCK)
            mock.chmod(0o755)
            calls, remote = base / "calls", base / "remote"
            env = dict(os.environ, PATH=f"{base}:{os.environ['PATH']}",
                       SCENARIO=scenario, CALLS=str(calls), REMOTE=str(remote))
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
                result, calls = self.run_script(script, "empty", "down", "x", "y")
                self.assertEqual(result.returncode, 2)
                self.assertEqual(calls, "")

    def test_failed_creation_is_not_success(self):
        for script in SCRIPTS:
            with self.subTest(script=script.name):
                result, calls = self.run_script(script, "start_failure", "up")
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn(": Started", result.stderr)
                self.assertNotIn("ssh ", calls)
                self.assertIn("Step: Start", result.stderr)

    def test_destroy_failure_propagates(self):
        for script in SCRIPTS:
            with self.subTest(script=script.name):
                result, calls = self.run_script(script, "destroy_failure", "destroy")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Simulated deletion failure", result.stderr)
                self.assertNotIn("destroy other", calls)

    def test_destroy_includes_stopped_and_excludes_unrelated(self):
        for script in SCRIPTS:
            with self.subTest(script=script.name):
                result, calls = self.run_script(script, "normal", "destroy")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("playground destroy id1", calls)
                self.assertIn("playground destroy id2", calls)
                self.assertNotIn("destroy other", calls)

    def test_empty_destroy_succeeds(self):
        for script in SCRIPTS:
            with self.subTest(script=script.name):
                result, _ = self.run_script(script, "empty", "destroy")
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_duplicate_names_prevent_mutation(self):
        for script in SCRIPTS:
            with self.subTest(script=script.name):
                result, calls = self.run_script(script, "duplicate", "down")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Duplicate playground title", result.stderr)
                self.assertNotIn("playground stop", calls)

    def test_down_only_stops_running_setup_members(self):
        for script in SCRIPTS:
            with self.subTest(script=script.name):
                result, calls = self.run_script(script, "normal", "down")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("playground stop id1", calls)
                self.assertNotIn("playground stop id2", calls)
                self.assertNotIn("playground stop other", calls)

    def test_up_with_k3s_generates_valid_remote_scripts(self):
        for script in SCRIPTS:
            with self.subTest(script=script.name):
                result, calls = self.run_script(script, "running", "up", "--k3s")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("Step: Configure the VPN server and clients", result.stderr)
                self.assertIn("Step: Wait for all K3s nodes", result.stderr)
                self.assertIn("Done in", result.stderr)
                self.assertNotIn("mock-join-token", result.stderr)
                self.assertIn("playground persist id5", calls)


if __name__ == "__main__":
    unittest.main()
