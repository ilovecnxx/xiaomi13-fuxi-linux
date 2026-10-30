"""Keep the Phosh portal routing consistent across deployment entry points."""
import configparser
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
CANONICAL = ROOT / "work/rootfs-overlay/etc/xdg/xdg-desktop-portal/phosh-portals.conf"
# 只校验源脚本；发布树（work/gh-publish、旧 fuxi-publish*）由 scripts/publish-progress.sh 生成，
# 不应作为独立副本参与测试（2026-10-31 删除旧发布暂存目录后同步修正）。
DEPLOYMENT_SCRIPTS = (
    ROOT / "scripts/fuxi-basic-desktop.sh",
    ROOT / "scripts/fuxi-portal-gtk.sh",
)


def portal_config_blocks(path):
    text = path.read_text()
    return re.findall(r"(?m)^[^\n]*<<'PORTALCONF'\s*\n(.*?)^PORTALCONF\s*$", text, re.S)


def parse_config(text):
    config = configparser.ConfigParser(interpolation=None, delimiters=("=",), strict=True)
    config.read_string(text)
    return config


class PortalConfigTest(unittest.TestCase):
    def test_deployment_paths_match_the_canonical_overlay(self):
        canonical = CANONICAL.read_text()
        for path in DEPLOYMENT_SCRIPTS:
            with self.subTest(script=path):
                expected = [canonical, canonical] if path.name == "fuxi-portal-gtk.sh" else [canonical]
                self.assertEqual(portal_config_blocks(path), expected)

    def test_gtk_file_chooser_is_preferred_without_changing_other_routes(self):
        config = parse_config(CANONICAL.read_text())
        self.assertEqual(config["preferred"]["default"], "phrosh;phosh;gtk;")
        self.assertEqual(config["preferred"]["org.freedesktop.impl.portal.FileChooser"], "gtk;phrosh;")
        self.assertEqual(config["preferred"]["org.freedesktop.impl.portal.Access"], "phosh-shell;")
        self.assertEqual(config["preferred"]["org.freedesktop.impl.portal.ScreenCast"], "wlr;")
        self.assertEqual(config["preferred"]["org.freedesktop.impl.portal.Screenshot"], "gtk;wlr;")
        for interface in ("Background", "Clipboard", "GlobalShortcuts", "InputCapture", "RemoteDesktop"):
            self.assertEqual(config["preferred"][f"org.freedesktop.impl.portal.{interface}"], "none;")

    def test_deployments_restart_only_the_portal_frontend(self):
        for path in DEPLOYMENT_SCRIPTS:
            with self.subTest(script=path.name):
                text = path.read_text()
                self.assertEqual(text.count("systemctl --user restart xdg-desktop-portal.service"), 1)
                self.assertNotRegex(text, r"(?m)^\s*(?:reboot|systemctl\s+reboot|shutdown\s+-r)\b")
                self.assertNotIn("fastboot flash", text)

    def test_portal_package_install_cannot_upgrade_or_remove_existing_packages(self):
        for path in DEPLOYMENT_SCRIPTS:
            if path.name != "fuxi-portal-gtk.sh":
                continue
            with self.subTest(script=path):
                text = path.read_text()
                self.assertIn(
                    "apt-get -s install --no-install-recommends --no-upgrade --no-remove xdg-desktop-portal-gtk",
                    text,
                )
                self.assertIn(
                    "apt-get install -y --no-install-recommends --no-upgrade --no-remove xdg-desktop-portal-gtk",
                    text,
                )


if __name__ == "__main__":
    unittest.main()
