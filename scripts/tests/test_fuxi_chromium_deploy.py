"""Guard the Chromium isolated-prefix deploy script against unsafe changes.

Chromium is installed as an isolated prefix under /opt/chromium (Debian arm64 .deb) with a
private library dir; it must never touch system dpkg, never reboot/flash the phone, and must
inject the private libs via LD_LIBRARY_PATH before the system ones.
"""
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/fuxi-chromium-deploy.sh"


class ChromiumDeployTest(unittest.TestCase):
    def setUp(self):
        self.text = SCRIPT.read_text()

    def test_script_exists_and_is_shell(self):
        self.assertTrue(SCRIPT.exists())
        self.assertTrue(self.text.startswith("#!/bin/bash"))

    def test_supports_rollback(self):
        self.assertIn("--rollback", self.text)
        self.assertIn("rm -rf /opt/chromium", self.text)

    def test_installs_into_isolated_prefix_not_dpkg(self):
        self.assertIn("/opt/chromium", self.text)
        # Must extract debs, never run a system dpkg/apt install for chromium
        self.assertIn("dpkg-deb -x", self.text)
        self.assertNotRegex(self.text, r"(?m)^\s*dpkg\s+-i\b")
        self.assertNotRegex(self.text, r"(?m)^\s*apt(?:-get)?\s+install\b[^\n]*chromium")

    def test_private_library_path_precedes_system(self):
        # LD_LIBRARY_PATH must place the private dir first.
        self.assertRegex(
            self.text,
            r'LD_LIBRARY_PATH="?\$ROOT/privatelib',
        )

    def test_verifies_sha256_of_downloaded_debs(self):
        self.assertIn("hashlib.sha256", self.text)
        self.assertIn("SHA256 mismatch", self.text)

    def test_never_reboots_or_flashes(self):
        self.assertIsNone(re.search(r"(?m)^\s*(?:reboot|systemctl\s+reboot|shutdown\s+-r)\b", self.text))
        self.assertNotIn("fastboot flash", self.text)

    def test_targets_linux_rootfs_only(self):
        self.assertIn("/dev/sda33", self.text)
        self.assertIn("fuxi.fb=", self.text)


if __name__ == "__main__":
    unittest.main()
