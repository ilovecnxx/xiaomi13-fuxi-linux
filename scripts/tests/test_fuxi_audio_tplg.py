"""Topology failures must not silently reuse a previous output."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "fuxi-audio-tplg.sh"
SOURCE = """SectionManifest.manifest {}
SectionVendorTuples {
	'device16.logger1:tuple0' {
		token1 16
	}
	'device16.i2s_rx1:tuple0' {
		token1 16
		token250 0
		token256 1
	}
	'PRIMARY_MI2S_RX Audio Mixer:tuple0' {
		token1 16
	}
}
'Primary MI2S Playback, , device16.i2s_rx1'
"""


class AudioTopologyTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for directory in ("scripts", "bin", "work/firmware-audio/qcom/sm8550"):
            (self.root / directory).mkdir(parents=True)
        shutil.copy2(SCRIPT, self.root / "scripts/fuxi-audio-tplg.sh")
        self.output = self.root / "work/firmware-audio/qcom/sm8550/Xiaomi-13-tplg.bin"
        self.output.write_bytes(b"previous validated topology")
        self.fixture = self.root / "source.conf"
        self.fixture.write_text(SOURCE)
        for name, source in {
            "zstd": '#!/bin/sh\ncp "$AUDIO_TEST_SOURCE" "$4"\n',
            "alsatplg": '#!/bin/sh\nif [ "$1" = -c ] && [ "${AUDIO_TEST_FAIL:-0}" = 1 ]; then echo "compile failed" >&2; exit 9; fi\ncp "$2" "$4"\n'
        }.items():
            path = self.root / "bin" / name
            path.write_text(source)
            path.chmod(0o755)

    def run_build(self, **env):
        return subprocess.run(["bash", str(self.root / "scripts/fuxi-audio-tplg.sh")],
                              env={**os.environ, "PATH": str(self.root / "bin") + os.pathsep + os.environ["PATH"],
                                   "AUDIO_TEST_SOURCE": str(self.fixture), "SD": "2", **env},
                              capture_output=True, text=True, timeout=10)

    def test_compiler_failure_preserves_previous_topology(self):
        result = self.run_build(AUDIO_TEST_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("compile failed", result.stderr)
        self.assertEqual(self.output.read_bytes(), b"previous validated topology")

    def test_invalid_data_line_preserves_previous_topology(self):
        result = self.run_build(SD="3")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.output.read_bytes(), b"previous validated topology")

    def test_success_rewrites_secondary_interface_and_channel(self):
        result = self.run_build()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        result_text = self.output.read_text()
        self.assertIn("token1 18", result_text)
        self.assertIn("token250 1", result_text)
        self.assertIn("token256 2", result_text)
        self.assertNotIn("Primary MI2S Playback", result_text)


if __name__ == "__main__":
    unittest.main()
