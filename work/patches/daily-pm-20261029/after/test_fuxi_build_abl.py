"""Build-script regressions; fixtures never connect to or write a phone."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[1] / "fuxi-build-abl.sh"
BASE_CONFIG = "CONFIG_FUXI_FORCE_BUILTIN_DTB=y\n# baseline marker\n"


class BuildTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.kernel = self.root / "build/linux"
        for path in ("scripts", "work/kbuild", "bin", "build/linux/scripts",
                     "build/linux/usr", "build/linux/arch/arm64/boot/dts/qcom",
                     "build/edk2-msm/tools",
                     "build/edk2-msm/Platform/Xiaomi/sm8550/FdtBlob_compat"):
            (self.root / path).mkdir(parents=True, exist_ok=True)
        shutil.copy2(SOURCE, self.root / "scripts/fuxi-build-abl.sh")
        (self.kernel / ".config").write_text(BASE_CONFIG)
        # A stale legacy backup must never replace the current baseline.
        (self.kernel / ".config.fuxi-main").write_text("STALE CONFIG\n")
        self.executable("build/linux/scripts/config", '''#!/usr/bin/env python3
import pathlib, sys
p = pathlib.Path('.config')
with p.open('a') as f:
    for action, key in zip(sys.argv[1::2], sys.argv[2::2]):
        if action == '-e': f.write('CONFIG_' + key + '=y\\n')
''')
        self.executable("bin/make", '''#!/bin/bash
set -eu
case " $* " in
  *" olddefconfig "*)
    printf '# normalized by olddefconfig\\n' >> .config
    [ "${FAIL_STAGE:-}" != config ]; exit $? ;;
  *" Image.gz "*)
    [ "${FAIL_STAGE:-}" != kernel ] || { echo 'error: test build failure'; exit 1; }
    printf 'test kernel' > arch/arm64/boot/Image
    printf 'test compressed kernel' > arch/arm64/boot/Image.gz ;;
  *"qcom/"*)
    target="${!#}"
    printf 'test dtb' > "arch/arm64/boot/dts/$target" ;;
esac
''')
        self.executable("bin/fdtget", "#!/bin/sh\nprintf 'console=tty0\\n'\n")
        self.executable("bin/git", '''#!/bin/sh
case "$*" in *rev-parse*) printf 'test-commit\\n';; *status*) printf ' M file\\n';; esac
''')
        (self.root / "build/edk2-msm/Platform/Xiaomi/sm8550/FdtBlob_compat/fuxi.dtb").write_bytes(b"bait")
        (self.root / "build/edk2-msm/tools/mkbootimg.py").write_text('''import pathlib, sys
out = pathlib.Path(sys.argv[sys.argv.index('-o') + 1])
kernel = pathlib.Path(sys.argv[sys.argv.index('--kernel') + 1])
out.write_bytes(b'ANDROID!' + kernel.read_bytes())
''')
        self.env = {key: value for key, value in os.environ.items()
                    if key not in ("FUXI_PM", "FUXI_DTB", "FAIL_STAGE")}
        self.env["PATH"] = str(self.root / "bin") + os.pathsep + os.environ["PATH"]

    def executable(self, name, content):
        path = self.root / name
        path.write_text(content)
        path.chmod(0o755)

    def run_build(self, *args, **env):
        return subprocess.run(
            ["bash", str(self.root / "scripts/fuxi-build-abl.sh"), "test", *args],
            env={**self.env, **env}, text=True, capture_output=True, timeout=20)

    def assert_restored(self):
        self.assertEqual((self.kernel / ".config").read_text(), BASE_CONFIG)

    def test_default_pm_manifest_and_config_restore(self):
        result = self.run_build()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_restored()
        out = self.root / "work/kbuild/abl-fuxi-test.img"
        config = out.with_suffix(".config").read_text()
        for option in ("CPU_FREQ", "ARM_QCOM_CPUFREQ_HW", "THERMAL", "QCOM_TSENS"):
            self.assertIn(f"CONFIG_{option}=y\n", config)
        record = json.loads(out.with_suffix(".build.json").read_text())
        self.assertTrue(record["power_management_requested"])
        for key, path in (("boot_image", out), ("config", out.with_suffix(".config")),
                          ("builtin_dtb", out.with_suffix(".dtb"))):
            self.assertEqual(record["sha256"][key], hashlib.sha256(path.read_bytes()).hexdigest())

    def test_failed_olddefconfig_restores_config(self):
        result = self.run_build(FAIL_STAGE="config")
        self.assertNotEqual(result.returncode, 0)
        self.assert_restored()

    def test_failed_kernel_restores_config(self):
        result = self.run_build(FAIL_STAGE="kernel")
        self.assertNotEqual(result.returncode, 0)
        self.assert_restored()

    def test_pm_can_be_explicitly_disabled(self):
        result = self.run_build(FUXI_PM="0")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_restored()
        out = self.root / "work/kbuild/abl-fuxi-test.config"
        self.assertNotIn("CONFIG_CPU_FREQ=y", out.read_text())

    def test_lock_prevents_configuration_changes(self):
        with (self.kernel / ".fuxi-build.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.run_build()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("另一个 fuxi 构建", result.stdout)
        self.assert_restored()
        self.assertFalse((self.root / "work/kbuild/abl-fuxi-test.img").exists())

    def test_repack_cannot_leave_stale_provenance(self):
        result = self.run_build()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        out = self.root / "work/kbuild/abl-fuxi-test.img"
        original = out.read_bytes()
        (self.kernel / "arch/arm64/boot/Image.gz").write_bytes(b"different kernel")
        result = self.run_build("--no-kernel")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("不能覆盖有构建记录", result.stdout)
        self.assertEqual(out.read_bytes(), original)
        self.assert_restored()


if __name__ == "__main__":
    unittest.main()
