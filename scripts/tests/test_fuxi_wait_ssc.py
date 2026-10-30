"""Exercise readiness against missing, failed, and delayed QRTR discovery."""
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / "work/rootfs-overlay/usr/local/libexec/fuxi-wait-ssc"


class WaitSSCTest(unittest.TestCase):
    def run_wait(self, lookup, seconds="1"):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            command = root / "qrtr-lookup"
            command.write_text("#!/bin/sh\n" + lookup)
            command.chmod(0o755)
            return subprocess.run(
                ["bash", str(SCRIPT), seconds], capture_output=True, text=True,
                timeout=8, env={**os.environ, "PATH": directory + os.pathsep + os.environ["PATH"],
                                "SSC_TEST_STATE": str(root / "called")})

    def test_other_services_do_not_count_as_ssc(self):
        result = self.run_wait("echo '1400 1 0 5 20 Different service'\n")
        self.assertEqual(result.returncode, 1)
        self.assertIn("unavailable", result.stderr)

    def test_failed_lookup_does_not_count_even_with_a_matching_line(self):
        result = self.run_wait("echo '400 1 0 5 20 SSC'\nexit 1\n")
        self.assertEqual(result.returncode, 1)

    def test_delayed_service_is_accepted(self):
        result = self.run_wait('if [ -f "$SSC_TEST_STATE" ]; then echo "400 1 0 5 20 SSC"; else touch "$SSC_TEST_STATE"; fi\n', "4")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("service 400 ready", result.stdout)

    def test_hung_discovery_is_bounded(self):
        start = time.monotonic()
        result = self.run_wait("sleep 30\n")
        self.assertEqual(result.returncode, 1)
        self.assertLess(time.monotonic() - start, 6)

    def test_invalid_deadline_is_rejected(self):
        result = self.run_wait("exit 0\n", "0")
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
