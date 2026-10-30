#!/bin/bash
# 找能让上游 WCN7850 固件接受的小米 RF 标定（现在用的是高通参考板 board-id 82 的标定，不是本机天线数据）。
# 每个候选：board-2.bin = 候选标定（改名 board-id=255）+ 上游 regdb → 重启进 Ubuntu → 看固件是否崩溃（RDDM）、
# wlp1s0 是否出现、扫到多少网络。ath12k 半初始化不能 unbind（会卡死整机），所以每个候选都要重启一次。
# 结束时恢复已验证可用的 board-2.bin（work/firmware 里那份）。
# 用法: scripts/fuxi-wifi-bdf-try.sh [候选文件名 ...]   默认 bd_m3.elf bd_m3gl.elf bdwlan.elf（在 work/firmware-src/kiwi/）
# 结果: work/claude-logs/wifi-bdf-try-<时间>.log
set -u
B="$(cd "$(dirname "$0")/.." && pwd)"
IMG="${FUXI_IMG:-$B/work/kbuild/abl-fuxi-wifi12.img}"
K="$B/work/firmware-src/kiwi"
GOOD="$B/work/firmware/ath12k/WCN7850/hw2.0/board-2.bin"
LOG="$B/work/claude-logs/wifi-bdf-try-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
say() { echo "$(date +%T) $*"; }
ssh_() { timeout "${T:-120}" "$B/scripts/fuxi-ssh.sh" "$@"; }
NAME255="bus=pci,vendor=17cb,device=1107,subsystem-vendor=17cb,subsystem-device=1107,qmi-chip-id=2,qmi-board-id=255"
[ -f "$GOOD" ] || "$B/scripts/fuxi-wcn7850-firmware.sh"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
cands=("$@"); [ ${#cands[@]} -gt 0 ] || cands=(bd_m3.elf bd_m3gl.elf bdwlan.elf)

push_board() {  # $1 = board-2.bin
  tar -C "$(dirname "$1")" -cf - "$(basename "$1")" | ssh_ "cd /lib/firmware/ath12k/WCN7850/hw2.0 && tar -xmf - && mv -f '$(basename "$1")' board-2.bin && sync && sha256sum board-2.bin | cut -c1-16"
}

for c in "${cands[@]}"; do
  [ -f "$K/$c" ] || { say "跳过 $c（不存在）"; continue; }
  say "======== 候选 $c"
  python3 -I - "$GOOD" "$K/$c" "$W/board-2.$c.bin" "$NAME255" <<'EOF'
import struct, sys
good, bdf, out, name = sys.argv[1:5]
d = open(good, "rb").read()
magic = b"QCA-ATH12K-BOARD\0"
pad = lambda b: b + b"\0" * (-len(b) % 4)
ie = lambda i, b: struct.pack("<II", i, len(b)) + pad(b)
def ies(buf):
    o = 0
    while o + 8 <= len(buf):
        i, l = struct.unpack_from("<II", buf, o); yield i, buf[o + 8:o + 8 + l]; o += 8 + ((l + 3) & ~3)
regdb = [x for i, x in ies(d[len(pad(magic)):]) if i == 1]
blob = pad(magic) + ie(0, ie(0, name.encode()) + ie(1, open(bdf, "rb").read()))
for r in regdb:
    blob += ie(1, r)
open(out, "wb").write(blob)
EOF
  push_board "$W/board-2.$c.bin" || { say "FAIL 推送失败（手机不在 Ubuntu？）"; break; }
  FUXI_KEEP=1 "$B/scripts/fuxi-test-recovery.sh" "$IMG" 'uname -v' | grep -vE 'pushed' >/dev/null || { say "FAIL 没进 Ubuntu"; break; }
  T=120 ssh_ "sleep 25; echo \"RDDM 次数: \$(dmesg | grep -c MHI_CB_EE_RDDM)\"; echo \"接口: \$(ip -br link | awk '/^wl/{print \$1}')\"
    nmcli dev wifi rescan 2>/dev/null; sleep 8; echo \"可见网络: \$(nmcli -t -f SSID dev wifi list 2>/dev/null | wc -l)\"
    dmesg | grep -E 'ath12k.*(fail|error|RDDM)' | tail -n 3" | sed "s/^/  [$c] /"
done

say "== 恢复已验证的 board-2.bin（参考板标定）"
push_board "$GOOD" && FUXI_KEEP=1 "$B/scripts/fuxi-test-recovery.sh" "$IMG" 'ip -br link | grep -E "^wl"' | tail -n 2
say "完成，日志 $LOG"
