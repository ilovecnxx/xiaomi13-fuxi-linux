"""Idle auto-suspend must stay off until a wake source for s2idle is verified."""
import configparser
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
OVERRIDE = ROOT / "work/rootfs-overlay/usr/share/glib-2.0/schemas/90-fuxi-power.gschema.override"
SECTION = "org.gnome.settings-daemon.plugins.power"
HOST_SCHEMAS = Path("/usr/share/glib-2.0/schemas")
NEEDED = ("org.gnome.settings-daemon.plugins.power.gschema.xml", "org.gnome.settings-daemon.enums.xml")


class PowerOverrideTest(unittest.TestCase):
    def test_idle_suspend_is_disabled(self):
        config = configparser.ConfigParser(interpolation=None)
        config.read_string(OVERRIDE.read_text())
        self.assertEqual(config[SECTION]["sleep-inactive-ac-type"], "'nothing'")
        self.assertEqual(config[SECTION]["sleep-inactive-battery-type"], "'nothing'")

    @unittest.skipUnless(shutil.which("glib-compile-schemas")
                         and all((HOST_SCHEMAS / n).exists() for n in NEEDED),
                         "host lacks gnome-settings-daemon schemas")
    def test_override_compiles_against_schema(self):
        with tempfile.TemporaryDirectory() as tmp:
            for name in NEEDED:
                shutil.copy(HOST_SCHEMAS / name, tmp)
            shutil.copy(OVERRIDE, tmp)
            subprocess.run(["glib-compile-schemas", "--strict", tmp], check=True, capture_output=True)


if __name__ == "__main__":
    unittest.main()
