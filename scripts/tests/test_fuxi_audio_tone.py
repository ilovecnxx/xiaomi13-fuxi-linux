"""Verify the actual shell-embedded audible fixture stays bounded and isolated."""
import array
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
import wave


class AudioToneTest(unittest.TestCase):
    def test_faded_half_scale_stereo_fixture(self):
        script = (Path(__file__).resolve().parents[1] / "fuxi-audio-smoke.sh").read_text()
        generator = re.findall(r'python3 - "\$wave" <<\x27PY\x27\n(.*?)\nPY', script, re.S)[-1]
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "tone.wav"
            subprocess.run([sys.executable, "-", str(target)], input=generator, text=True, check=True, timeout=10)
            with wave.open(str(target)) as stream:
                self.assertEqual((stream.getnchannels(), stream.getsampwidth(), stream.getframerate(), stream.getnframes()), (2, 2, 48000, 240000))
                values = array.array('h', stream.readframes(stream.getnframes()))
            self.assertLessEqual(max(abs(v) for v in values), 16384)
            for pulse, channel in enumerate((0, 0, 1, 1)):
                start = pulse * 120000
                block = values[start:start + 120000]
                self.assertTrue(any(block[channel::2]))
                self.assertFalse(any(block[1 - channel::2]))
                self.assertEqual(block[:2], array.array('h', [0, 0]))
                self.assertFalse(any(block[72000:]))


if __name__ == "__main__":
    unittest.main()
