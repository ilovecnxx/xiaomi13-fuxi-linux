#!/bin/bash
# CS35L41 功放 DSP 固件与调音：从 Android 只读拉取，按主线 wm_adsp 的命名放好。
#   主线文件名：cirrus/cs35l41-dsp1-spk-prot-xiaomi-fuxi-<b|t>.wmfw（DSP 程序）与 .bin（调音/系数）
#   （DTS 里 cirrus,subsystem-id = "xiaomi-fuxi"，sound-name-prefix = B/T；打开 "<B|T> DSP1 Preload Switch" 才加载）
#   厂商文件名不确定（常见 cs35l41-dsp1-spk-prot.wmfw、cs35l41-dsp1-spk-prot-<前缀>.bin、*-music.txt 场景表），
#   所以先把所有候选拉到 work/firmware-src/cirrus/ 并列出，再按下面的规则映射；映射不到的打印出来，人工补。
# 用法: scripts/fuxi-cirrus-firmware.sh [--local-only]（只整理主机文件，不部署或加载 DSP）
# 产物: work/firmware-audio/cirrus/
set -euo pipefail
B="$(cd "$(dirname "$0")/.." && pwd)"
ADB="$B/tools/platform-tools/adb"
SRC="$B/work/firmware-src/cirrus"
OUT="$B/work/firmware-audio/cirrus"
mkdir -p "$SRC" "$OUT"
case "${1:-}" in '') local_only=0;; --local-only) local_only=1;; *) echo "用法: $0 [--local-only]" >&2; exit 2;; esac
[ "$#" -le 1 ] || exit 2

if [ "$local_only" = 0 ] && [ "$(timeout 5 "$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; then
  timeout 20 "$ADB" root >/dev/null 2>&1; sleep 2; timeout 30 "$ADB" wait-for-device
  files=$(timeout 60 "$ADB" shell 'for d in /vendor/firmware /vendor/firmware_mnt/image /odm/firmware; do
    if [ -d "$d" ]; then find "$d" -maxdepth 2 -type f \( -iname "*cs35l41*" -o -iname "[BT]-*.txt" \) 2>/dev/null; fi; done' | tr -d '\r' | sort -u)
  for f in $files; do
    if [ ! -f "$SRC/$(basename "$f")" ]; then
      timeout 60 "$ADB" pull "$f" "$SRC/" >/dev/null
      echo "pulled $f"
    fi
  done
else
  echo "只用已拉取的 $SRC"
fi
echo "--- 候选（$SRC）"; ls -l "$SRC"

pick() {  # 第一个存在的文件
  for c in "$@"; do [ -f "$SRC/$c" ] && { echo "$SRC/$c"; return 0; }; done; return 1
}
STAGE=$(mktemp -d "$OUT/.stage.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
for p in B T; do
  w=$(pick "$p-cs35l41-dsp1-spk-prot.wmfw" "cs35l41-dsp1-spk-prot-$p.wmfw" "cs35l41-dsp1-spk-prot.wmfw") || { echo "缺少 $p 保护固件，保留旧产物" >&2; exit 1; }
  b=$(pick "$p-cs35l41-dsp1-spk-prot.bin" "cs35l41-dsp1-spk-prot-$p.bin") || { echo "缺少 $p 专用系数，保留旧产物" >&2; exit 1; }
  python3 - "$w" "$b" <<'PY'
from pathlib import Path
import sys
for name, magic in zip(sys.argv[1:], (b'WMFW', b'WMDR')):
    data = Path(name).read_bytes()
    if len(data) < 16 or data[:4] != magic:
        raise SystemExit('Invalid firmware header: ' + name)
PY
  # wm_adsp_request_firmware_file lowercases both the system name and prefix.
  stem="cs35l41-dsp1-spk-prot-xiaomi-fuxi-${p,,}"
  cp "$w" "$STAGE/$stem.wmfw"
  cp "$b" "$STAGE/$stem.bin"
  printf '%s\t%s\n' "$stem.wmfw" "$(basename "$w")" "$stem.bin" "$(basename "$b")" >> "$STAGE/sources.tsv"
done
python3 - "$STAGE" <<'PY'
import hashlib, json, sys
from pathlib import Path
stage = Path(sys.argv[1])
records = []
for line in (stage / 'sources.tsv').read_text().splitlines():
    output, source = line.split('\t')
    data = (stage / output).read_bytes()
    records.append({'file': output, 'source': source, 'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)})
(stage / 'manifest.json').write_text(json.dumps({'deployed': False, 'speaker_protection_validated': False, 'files': records}, indent=2) + '\n')
PY
for file in "$STAGE"/*.wmfw "$STAGE"/*.bin "$STAGE/manifest.json"; do mv "$file" "$OUT/"; done
echo "已整理两颗功放的固件和独立系数；未部署、未加载，文件头校验不代表保护/标定通过。"
