#!/usr/bin/env python3
"""验证 Mic2 UCM 配置使用 AMIC5→ADC4→SWR_MIC1"""
import unittest

class TestFuxiUCMMic2(unittest.TestCase):
    def test_mic2_uses_adc4_amic5(self):
        """Mic2 device 调用 AnalogMic5EnableSeq + SoundwireMic1EnableSeq，CaptureElem 为 ADC4"""
        from pathlib import Path
        p = Path(__file__).parents[2]/"work/rootfs-overlay/usr/share/alsa/ucm2/Qualcomm/sm8550/Xiaomi-13/HiFi.conf"
        t = p.read_text()
        sec = [s.strip() for s in t.split("SectionDevice") if '"Mic2"' in s]
        self.assertEqual(len(sec), 1, "Mic2 section 未找到或重复")
        m2 = sec[0]
        self.assertIn("/codecs/wcd938x/AnalogMic5EnableSeq.conf", m2, "未启用 AMIC5")
        self.assertIn("/codecs/qcom-lpass/tx-macro/SoundwireMic1EnableSeq.conf", m2, "未连接 SWR_MIC1")
        self.assertIn('CaptureMixerElem "ADC4"', m2, "CaptureMixerElem 应为 ADC4")
        self.assertNotIn("ADC2", m2, "Mic2 不应再使用 ADC2")
        self.assertNotIn("AMIC3", m2, "Mic2 不应再使用 AMIC3")

if __name__=="__main__": unittest.main()
