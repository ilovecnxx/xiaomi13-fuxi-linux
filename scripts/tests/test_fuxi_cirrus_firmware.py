"""Firmware staging must retain channel identity and reject incomplete inputs."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "fuxi-cirrus-firmware.sh"


class CirrusFirmwareTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        (root / "scripts").mkdir()
        self.script = root / "scripts" / SCRIPT.name
        shutil.copy2(SCRIPT, self.script)
        self.source = root / "work/firmware-src/cirrus"
        self.output = root / "work/firmware-audio/cirrus"
        self.source.mkdir(parents=True)
        self.output.mkdir(parents=True)
        (self.source / "cs35l41-dsp1-spk-prot.wmfw").write_bytes(b"WMFW" + bytes(16))
        for channel in ("B", "T"):
            (self.source / f"{channel}-cs35l41-dsp1-spk-prot.bin").write_bytes(b"WMDR" + channel.encode() * 16)
        self.old = self.output / "cs35l41-dsp1-spk-prot-xiaomi-fuxi-b.wmfw"
        self.old.write_bytes(b"previous validated artifact")

    def run_stage(self):
        return subprocess.run(["bash", str(self.script), "--local-only"], capture_output=True, text=True, timeout=10)

    def test_real_vendor_prefixes_map_to_lowercase_channel_names(self):
        result = self.run_stage()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for channel in ("B", "T"):
            target = self.output / f"cs35l41-dsp1-spk-prot-xiaomi-fuxi-{channel.lower()}.bin"
            self.assertEqual(target.read_bytes(), b"WMDR" + channel.encode() * 16)
        manifest = json.loads((self.output / "manifest.json").read_text())
        self.assertEqual(len(manifest["files"]), 4)
        self.assertFalse(manifest["deployed"])
        self.assertFalse(manifest["speaker_protection_validated"])

    def test_missing_top_coefficients_do_not_partially_replace_outputs(self):
        (self.source / "T-cs35l41-dsp1-spk-prot.bin").unlink()
        self.assertNotEqual(self.run_stage().returncode, 0)
        self.assertEqual(self.old.read_bytes(), b"previous validated artifact")
        self.assertEqual(list(self.output.iterdir()), [self.old])

    def test_calibration_firmware_is_not_used_as_protection_fallback(self):
        (self.source / "cs35l41-dsp1-spk-prot.wmfw").rename(self.source / "cs35l41-dsp1-spk-cali.wmfw")
        self.assertNotEqual(self.run_stage().returncode, 0)
        self.assertEqual(self.old.read_bytes(), b"previous validated artifact")

    def test_bad_coefficient_header_keeps_existing_artifacts(self):
        (self.source / "T-cs35l41-dsp1-spk-prot.bin").write_bytes(b"not a coefficient file")
        self.assertNotEqual(self.run_stage().returncode, 0)
        self.assertEqual(self.old.read_bytes(), b"previous validated artifact")


if __name__ == "__main__":
    unittest.main()
