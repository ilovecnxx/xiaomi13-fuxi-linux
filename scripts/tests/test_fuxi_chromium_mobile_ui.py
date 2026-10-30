"""Guard the Chromium mobile-UI layer: overlay is self-contained (no mandatory bridge for
navigation), the shell is a self-healing CDP supervisor, and the deploy script never
reboots/flashes or touches system dpkg."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SHELL = ROOT / "work/chromium-mobile/fuxi-mobile-shell.py"
OVERLAY = ROOT / "work/chromium-mobile/mobile-chrome.js"
DEPLOY = ROOT / "scripts/fuxi-chromium-mobile-ui.sh"
CDP = ROOT / "work/chromium-mobile/cdp.py"


class ChromiumMobileUiTest(unittest.TestCase):
    def test_files_exist(self):
        for p in (SHELL, OVERLAY, DEPLOY, CDP):
            self.assertTrue(p.exists(), str(p))

    def test_overlay_navigates_without_bridge(self):
        js = OVERLAY.read_text()
        # toolbar actions must use history/location APIs, not a required HTTP bridge
        self.assertIn("history.back()", js)
        self.assertIn("history.forward()", js)
        self.assertIn("location.reload()", js)
        self.assertIn("location.href", js)
        # must build the two bars Android-Chrome style
        self.assertIn("fx-top", js)
        self.assertIn("fx-bottom", js)

    def test_shell_is_supervisor_with_lock(self):
        s = SHELL.read_text()
        self.assertIn("_lock = threading.Lock()", s)
        self.assertIn("def supervisor", s)
        self.assertIn("addScriptToEvaluateOnNewDocument", s)
        # must reconnect, not crash, on CDP loss
        self.assertIn("CDP(port=DEBUG_PORT", s)

    def test_deploy_never_reboots_or_flashes_or_dpkg(self):
        s = DEPLOY.read_text()
        self.assertNotRegex(s, r"(?m)^\s*(?:reboot|systemctl\s+reboot|shutdown\s+-r)\b")
        self.assertNotIn("fastboot flash", s)
        self.assertNotRegex(s, r"dpkg\s+-i\b")
        self.assertNotRegex(s, r"apt(?:-get)?\s+install\b")
        self.assertIn("/dev/sda33", s)

    def test_deploy_supports_rollback(self):
        self.assertIn("--rollback", DEPLOY.read_text())


if __name__ == "__main__":
    unittest.main()
