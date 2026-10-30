"""The overnight display collector must remain read-only and Linux-gated."""
from pathlib import Path
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "fuxi-display-snapshot.sh"


class DisplaySnapshotTest(unittest.TestCase):
    def test_requires_expected_linux_root_before_collecting(self):
        text = SCRIPT.read_text()
        self.assertRegex(text, r"grep -q 'fuxi\.fb=' /proc/cmdline")
        self.assertRegex(text, r'findmnt -n -o SOURCE /.*= /dev/sda33')

    def test_collects_display_touch_and_desktop_evidence(self):
        text = SCRIPT.read_text()
        for evidence in (
            "/sys/class/drm/card*-*",
            "/sys/class/backlight/*",
            "/proc/bus/input/devices",
            "/sys/kernel/debug/dri/*/state",
            "dmesg --color=never",
            "journalctl -b -u phosh -u phoc",
        ):
            with self.subTest(evidence=evidence):
                self.assertIn(evidence, text)

    def test_does_not_mutate_device_or_reboot(self):
        text = SCRIPT.read_text()
        for forbidden in (
            "adb reboot",
            "fastboot flash",
            "systemctl reboot",
            "systemctl restart",
            "brightness=",
            "tee /sys/",
            "dd if=",
        ):
            with self.subTest(command=forbidden):
                self.assertNotIn(forbidden, text)
        self.assertNotRegex(text, r"(?m)^\s*(?:reboot|shutdown\s+-r)\b")


if __name__ == "__main__":
    unittest.main()
