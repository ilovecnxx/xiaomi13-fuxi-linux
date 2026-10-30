"""Do not mistake a running PCM or stale IRQ bits for a healthy speaker path."""
import copy
import importlib.util
import os
from pathlib import Path
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "fuxi-audio-diagnose.py"
spec = importlib.util.spec_from_file_location("audio_diagnose", SCRIPT)
diag = importlib.util.module_from_spec(spec)
spec.loader.exec_module(diag)


def live_sample():
    # Reduced real audio-probe4 snapshot; IRQ status3 retains old unlock events.
    registers = dict(zip(diag.REGISTERS.values(), (
        1, 33, 0x370, 3, 0x10000, 0x10180200, 0x101, 16, 8, 0xB880, 0xA0,
        0x400000, 0x2000003F, 0x41406000, 0x2000000F,
    )))
    result = {"pcm_status": "state: RUNNING\nhw_ptr      : 4319", "amplifiers": {}}
    for prefix in ("B", "T"):
        result["amplifiers"][prefix] = {
            "registers": copy.copy(registers), "cache_only": "N",
            "dapm": f"{prefix} Main AMP: On  in 1 out 1",
        }
    result["amplifiers"]["T"]["registers"]["rx_slots"] = 0x100
    return result


class AudioDiagnoseTest(unittest.TestCase):
    def failures(self, sample):
        return [c["check"] for c in diag.playback_checks(sample) if not c["passed"]]

    def test_live_configuration_passes_despite_old_latched_unlock(self):
        self.assertEqual(self.failures(live_sample()), [])

    def test_live_unlock_cannot_hide_behind_old_lock_event(self):
        sample = live_sample()
        sample["amplifiers"]["B"]["registers"]["raw_status3"] = 0x20000010
        self.assertIn("B live PLL locked without unlock", self.failures(sample))

    def test_missing_raw_status_is_not_assumed_zero_or_healthy(self):
        sample = live_sample()
        del sample["amplifiers"]["T"]["registers"]["raw_status1"]
        self.assertIn("T all diagnostic registers readable", self.failures(sample))

    def test_cache_only_cannot_prove_hardware_health(self):
        sample = live_sample()
        sample["amplifiers"]["B"]["cache_only"] = "Y"
        self.assertIn("B volatile status is not cache-only", self.failures(sample))

    def test_each_short_boost_and_thermal_fault_is_rejected(self):
        for bit in (6, 7, 8, 15, 17, 31):
            with self.subTest(bit=bit):
                sample = live_sample()
                sample["amplifiers"]["B"]["registers"]["raw_status1"] |= 1 << bit
                self.assertIn("B no live thermal/boost/short fault", self.failures(sample))

    def test_duplicate_channel_slot_is_rejected(self):
        sample = live_sample()
        sample["amplifiers"]["B"]["registers"]["rx_slots"] = 0x100
        self.assertIn("B receives configured slot 1", self.failures(sample))

    def test_running_pcm_alone_does_not_prove_amplifier_is_enabled(self):
        sample = live_sample()
        sample["amplifiers"]["B"]["registers"]["power1"] = 0
        self.assertIn("B GLOBAL_EN and AMP_EN set", self.failures(sample))

    def test_muted_or_raised_gain_fails_conservative_check(self):
        for value in (0x4CF << 3, 0):
            with self.subTest(value=value):
                sample = live_sample()
                sample["amplifiers"]["T"]["registers"]["digital_volume"] = value
                self.assertIn("T digital gain remains conservative (-30 dB)", self.failures(sample))

    def test_closed_pcm_has_no_valid_pointer(self):
        sample = live_sample()
        sample["pcm_status"] = "closed"
        self.assertIn("ALSA PCM is RUNNING", self.failures(sample))
        self.assertIsNone(diag.hw_pointer(sample))
        self.assertEqual(diag.hw_pointer(live_sample()), 4319)

    def test_parser_stops_before_dsp_memory_and_preserves_missing_reads(self):
        def lines():
            yield "0002014: 00000001\n"
            yield "0002018: XXXXXXXX\n"
            yield "0010098: 2000000f\n"
            yield "001009c: 82000002\n"
            raise AssertionError("must not scan into DSP memory")
        self.assertEqual(diag.parse_registers(lines()), {"power1": 1, "raw_status3": 0x2000000F})

    def test_realtime_requires_an_actual_realtime_data_loop(self):
        for name, scheduler, priority, expected in (
            ("data-loop.0", os.SCHED_RR, 20, True),
            ("data-loop.0", os.SCHED_RR | 0x40000000, 20, True),
            ("data-loop.0", os.SCHED_FIFO, 20, True),
            ("data-loop.0", os.SCHED_OTHER, 0, False),
            ("data-loop.0", os.SCHED_OTHER | 0x40000000, 0, False),
            ("pipewire", os.SCHED_RR, 20, False),
        ):
            with self.subTest(name=name, scheduler=scheduler):
                state = {"threads": [{"name": name, "scheduler": scheduler, "priority": priority}]}
                self.assertEqual(diag.has_realtime_data_loop(state), expected)


if __name__ == "__main__":
    unittest.main()
