#!/bin/bash
# 生成主线需要的 WCN7850 固件目录 → work/firmware/{ath12k/WCN7850/hw2.0,qca}/（部署到手机 /lib/firmware/）。
#
# 默认 FUXI_WIFI_FW=upstream（2026-10-28 实机验证可用：固件起来、wlp1s0、扫到 69 个网络）：
#   amss.bin、m3.bin、蓝牙 hmtbtfw20.tlv/hmtnv20.bin 取自本机 linux-firmware（/lib/firmware，不联网），
#   board-2.bin = 上游 board-2.bin 里 17cb:1107 board-id=82（高通参考板）的标定数据改名为本机的 board-id=255
#                 + 上游的 regdb（"bus=pci"）条目。
#   注意：RF 标定来自参考板，不是小米这块板子的天线数据（够用，后面再找兼容的小米标定）。
# 对照实验（10-28，见 docs/目标-M5.md）：
#   - Android 固件（amss20.bin + phy_ucode20.elf + 小米 bd_m3）：QMI 全部走完、M3 也收下，但固件再也不发 ready（静默卡住）；
#   - 上游固件 + 小米 bd_m3：下载标定数据时固件崩溃（RDDM）；
#   - 上游固件 + 参考板标定 + Android regdb.bin：固件 ready 后 set mode 前崩溃（RDDM）——根因是 regdb 格式不配；
#   - 上游固件 + 参考板标定 + 上游 regdb：正常。
# FUXI_WIFI_FW=android：旧做法（Android 固件，只用于对照）。
set -euo pipefail
B="$(cd "$(dirname "$0")/.." && pwd)"
K="$B/work/firmware-src/kiwi"
BT="$B/work/firmware-src/bt"
W="$B/work/firmware/ath12k/WCN7850/hw2.0"
Q="$B/work/firmware/qca"
LF=/lib/firmware
NAME255="bus=pci,vendor=17cb,device=1107,subsystem-vendor=17cb,subsystem-device=1107,qmi-chip-id=2,qmi-board-id=255"
NAME82="bus=pci,vendor=17cb,device=1107,subsystem-vendor=17cb,subsystem-device=1107,qmi-chip-id=2,qmi-board-id=82"
mkdir -p "$W" "$Q"

case "${FUXI_WIFI_FW:-upstream}" in
upstream)
  zstd -dqf "$LF/ath12k/WCN7850/hw2.0/amss.bin.zst" -o "$W/amss.bin"
  zstd -dqf "$LF/ath12k/WCN7850/hw2.0/m3.bin.zst" -o "$W/m3.bin"
  zstd -dqf "$LF/ath12k/WCN7850/hw2.0/board-2.bin.zst" -o "$W/board-2.bin.upstream"
  rm -f "$W/regdb.bin"   # regdb 用 board-2.bin 里的上游条目；Android 的 regdb.bin 会让上游固件崩
  python3 -I - "$W/board-2.bin.upstream" "$W/board-2.bin" "$NAME82" "$NAME255" <<'EOF'
import struct, sys
src, out, name_src, name_dst = sys.argv[1:5]
d = open(src, "rb").read()
magic = b"QCA-ATH12K-BOARD\0"
assert d.startswith(magic)
pad = lambda b: b + b"\0" * (-len(b) % 4)
ie = lambda i, b: struct.pack("<II", i, len(b)) + pad(b)
def ies(buf):
    o = 0
    while o + 8 <= len(buf):
        i, l = struct.unpack_from("<II", buf, o)
        yield i, buf[o + 8:o + 8 + l]
        o += 8 + ((l + 3) & ~3)
top = list(ies(d[len(pad(magic)):]))
bd = [dict(ies(x))[1] for i, x in top if i == 0 and dict(ies(x)).get(0, b"").decode() == name_src]
regdb = [x for i, x in top if i == 1]
assert len(bd) == 1 and regdb, (len(bd), len(regdb))
blob = pad(magic) + ie(0, ie(0, name_dst.encode()) + ie(1, bd[0]))
for r in regdb:
    blob += ie(1, r)
open(out, "wb").write(blob)
print(f"[wifi] board-2.bin {len(blob)} B（{name_src.rsplit(',', 1)[1]} → board-id=255，regdb 条目 {len(regdb)}）")
EOF
  rm -f "$W/board-2.bin.upstream"
  zstd -dqf "$LF/qca/hmtbtfw20.tlv.zst" -o "$Q/hmtbtfw20.tlv"
  zstd -dqf "$LF/qca/hmtnv20.bin.zst" -o "$Q/hmtnv20.bin"
  ;;
android)
  [ -f "$K/amss20.bin" ] || { echo "[wifi] 缺 $K/amss20.bin"; exit 1; }
  cp "$K/amss20.bin" "$W/amss.bin"
  cp "$K/phy_ucode20.elf" "$W/m3.bin"
  cp "$K/regdb.bin" "$W/regdb.bin"
  python3 -I "$B/scripts/fuxi-ath12k-board.py" "$W/board-2.bin" "$NAME255=$K/bd_m3.elf" "bus=pci,qmi-chip-id=2,qmi-board-id=255=$K/bd_m3.elf"
  ls "$BT"/hmt* >/dev/null 2>&1 && cp "$BT"/hmt* "$Q/"
  ;;
*) echo "FUXI_WIFI_FW 只能是 upstream 或 android"; exit 2 ;;
esac
echo "[wifi] $(ls "$W" | tr '\n' ' ')"
echo "[bt] $(ls "$Q" | tr '\n' ' ' | cut -c1-200)"
