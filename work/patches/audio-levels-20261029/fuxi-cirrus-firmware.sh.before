#!/bin/bash
# CS35L41 功放 DSP 固件与调音：从 Android 只读拉取，按主线 wm_adsp 的命名放好。
#   主线文件名：cirrus/cs35l41-dsp1-spk-prot-xiaomi-fuxi-<B|T>.wmfw（DSP 程序）与 .bin（调音/系数）
#   （DTS 里 cirrus,subsystem-id = "xiaomi-fuxi"，sound-name-prefix = B/T；打开 "<B|T> DSP1 Preload Switch" 才加载）
#   厂商文件名不确定（常见 cs35l41-dsp1-spk-prot.wmfw、cs35l41-dsp1-spk-prot-<前缀>.bin、*-music.txt 场景表），
#   所以先把所有候选拉到 work/firmware-src/cirrus/ 并列出，再按下面的规则映射；映射不到的打印出来，人工补。
# 用法: scripts/fuxi-cirrus-firmware.sh（手机在 Android，adb root 可用）
# 产物: work/firmware-audio/cirrus/
set -u
B="$(cd "$(dirname "$0")/.." && pwd)"
ADB="$B/tools/platform-tools/adb"
SRC="$B/work/firmware-src/cirrus"
OUT="$B/work/firmware-audio/cirrus"
mkdir -p "$SRC" "$OUT"

if [ "$(timeout 5 "$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; then
  timeout 20 "$ADB" root >/dev/null 2>&1; sleep 2; timeout 30 "$ADB" wait-for-device
  files=$(timeout 60 "$ADB" shell 'for d in /vendor/firmware /vendor/firmware_mnt/image /odm/firmware /odm/etc /vendor/etc /mnt/vendor/persist/audio; do
    [ -d $d ] && find $d -maxdepth 2 \( -iname "*cs35l41*" -o -iname "*.wmfw" -o -iname "[BT]-*.txt" -o -iname "*cirrus*" \) 2>/dev/null; done' | tr -d '\r' | sort -u)
  for f in $files; do
    [ -f "$SRC/$(basename "$f")" ] || timeout 60 "$ADB" pull "$f" "$SRC/" >/dev/null && echo "pulled $f"
  done
else
  echo "手机不在 Android，只用已拉取的 $SRC"
fi
echo "--- 候选（$SRC）"; ls -l "$SRC"

pick() {  # 第一个存在的文件
  for c in "$@"; do [ -f "$SRC/$c" ] && { echo "$SRC/$c"; return 0; }; done; return 1
}
for p in B T; do
  w=$(pick "cs35l41-dsp1-spk-prot-$p.wmfw" "cs35l41-dsp1-spk-prot.wmfw" "cs35l41.wmfw" "$(cd "$SRC" && ls *.wmfw 2>/dev/null | head -n 1)") &&
    cp "$w" "$OUT/cs35l41-dsp1-spk-prot-xiaomi-fuxi-$p.wmfw" && echo "$p wmfw ← $(basename "$w")" || echo "$p 没有 wmfw"
  b=$(pick "cs35l41-dsp1-spk-prot-$p.bin" "cs35l41-$p.bin" "$p.bin" "cs35l41-dsp1-spk-prot.bin") &&
    cp "$b" "$OUT/cs35l41-dsp1-spk-prot-xiaomi-fuxi-$p.bin" && echo "$p bin  ← $(basename "$b")" || echo "$p 没有调音 bin（DSP 可以只跑 wmfw 默认参数）"
done
ls -l "$OUT"
