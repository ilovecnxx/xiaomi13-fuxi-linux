"""Compile the actual kernel helper against small control/IO stubs."""
from pathlib import Path
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[2] / "build/linux/sound/soc/soc-ops.c"


class VolumeLimitTest(unittest.TestCase):
    def test_sx_step_count_and_regular_register_ranges(self):
        text = SOURCE.read_text()
        start = text.index("int snd_soc_limit_volume(")
        end = text.index("EXPORT_SYMBOL_GPL(snd_soc_limit_volume);", start)
        helper = text[start:end]
        fixture = r'''
#include <assert.h>
#include <errno.h>
#include <stddef.h>
struct soc_mixer_control { int min, max, platform_max; };
struct snd_kcontrol { unsigned long private_value; void (*info)(void); };
struct snd_soc_card { int dev; };
static struct snd_kcontrol *found;
static int clip_result;
#define unlikely(x) (x)
#define dev_dbg(...) ((void)0)
static void snd_soc_info_volsw_sx(void) {}
static void normal_info(void) {}
static struct snd_kcontrol *snd_soc_card_get_kcontrol(struct snd_soc_card *c, const char *n) { return found; }
static int snd_soc_clip_to_platform_max(struct snd_kcontrol *c) { return clip_result; }
'''
        checks = r'''
int main(void) {
    struct snd_soc_card card = {0};
    struct soc_mixer_control mc = { .min=0x4cf, .max=0x391 };
    struct snd_kcontrol ctl = { .private_value=(unsigned long)&mc, .info=snd_soc_info_volsw_sx };
    found = &ctl;
    assert(snd_soc_limit_volume(&card, "SX", 816) == 0);
    assert(mc.platform_max == 816);
    assert(snd_soc_limit_volume(&card, "SX", 914) == -EINVAL);
    assert(mc.platform_max == 816);
    assert(snd_soc_limit_volume(&card, "SX", 0) == -EINVAL);
    mc.min=10; mc.max=100; mc.platform_max=0; ctl.info=normal_info;
    assert(snd_soc_limit_volume(&card, "normal", 81) == 0);
    assert(mc.platform_max == 81);
    assert(snd_soc_limit_volume(&card, "normal", 91) == -EINVAL);
    clip_result=-ENOMEM;
    assert(snd_soc_limit_volume(&card, "normal", 70) == -ENOMEM);
    found=NULL;
    assert(snd_soc_limit_volume(&card, "missing", 70) == -EINVAL);
    return 0;
}
'''
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "limit.c"
            output = Path(directory) / "limit"
            source.write_text(fixture + helper + checks)
            subprocess.run(["gcc", "-std=c11", "-Wall", "-Wextra", "-Wno-unused-parameter", "-Werror", str(source), "-o", str(output)], check=True, capture_output=True)
            subprocess.run([str(output)], check=True, capture_output=True)


if __name__ == "__main__":
    unittest.main()
