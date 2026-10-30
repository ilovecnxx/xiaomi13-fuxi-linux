#!/usr/bin/env python3
import importlib.util
import sys
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "fuxi-panel-cmds.py"
SPEC = importlib.util.spec_from_file_location("fuxi_panel_cmds", SCRIPT)
CONVERTER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = CONVERTER
SPEC.loader.exec_module(CONVERTER)


class PanelCommandConverterTests(unittest.TestCase):
    def test_packet_types_keep_vendor_write_format(self):
        cases = (
            (0x05, [0x29, 0x00], "mipi_dsi_dcs_write_seq_multi", "0x29"),
            (0x15, [0x51, 0x80], "mipi_dsi_dcs_write_seq_multi", "0x51, 0x80"),
            (0x39, [0x92, 0x70], "xiaomi_fuxi_dcs_long_write_seq_multi", "0x92, 0x70"),
            (0x39, [0x9e, 0x01, 0x02], "mipi_dsi_dcs_write_seq_multi", "0x9e, 0x01, 0x02"),
            (0x03, [], "mipi_dsi_generic_write_multi", "NULL, 0"),
            (0x13, [0x01], "mipi_dsi_generic_write_seq_multi", "0x01"),
            (0x23, [0x01, 0x02], "mipi_dsi_generic_write_seq_multi", "0x01, 0x02"),
            (0x29, [0x01, 0x02], "xiaomi_fuxi_generic_long_write_seq_multi", "0x01, 0x02"),
            (0x29, [0x01, 0x02, 0x03], "mipi_dsi_generic_write_seq_multi", "0x01, 0x02, 0x03"),
        )
        for dtype, payload, helper, data in cases:
            with self.subTest(dtype=hex(dtype)):
                output = CONVERTER.emit(dtype, payload)
                self.assertIn(helper, output)
                self.assertIn(data, output)

    def test_rejects_truncated_command_records(self):
        with self.assertRaises(SystemExit):
            CONVERTER.parse("cmd = [39 00 00]", "cmd")
        with self.assertRaises(SystemExit):
            CONVERTER.parse("cmd = [39 00 00 00 00 00 02 92]", "cmd")

    def test_rejects_invalid_short_write_lengths(self):
        for dtype, payload in ((0x03, [0x11]), (0x13, []), (0x23, [0x01])):
            with self.subTest(dtype=hex(dtype)):
                with self.assertRaises(SystemExit):
                    CONVERTER.emit(dtype, payload)


if __name__ == "__main__":
    unittest.main()
