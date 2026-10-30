#!/bin/bash
# M3：主线内核从 UFS linux 分区（sda33）启动 Ubuntu（systemd）的一轮完整实验
#   1. 等手机出现（adb/fastboot，最长 $WAIT 秒，默认 60）→ fastboot boot 镜像，留在 initramfs 串口 shell
#   2. 依次执行 prep 命令（可选，例如读写挂载 /mnt/r 修改 rootfs）；最后自动 umount /mnt/r
#   3. touch /tmp/do_switch; exit → init 读写挂载 sda33、switch_root 进 systemd
#   4. 抓串口启动输出到 <run>/switch-raw.log，等到 root shell 后执行 verify 命令
# 用法: scripts/fuxi-m3-switch.sh <boot.img> [prep-cmd ...] -- [verify-cmd ...]
# 手机最终留在 Ubuntu；initramfs 的 sysrq 安全网 900 秒后重启回 Android，
# 取消：scripts/fuxi_sh.py 'kill $(cat /dev/fuxi-safety.pid)'
set -u
B="$(cd "$(dirname "$0")/.." && pwd)"
ADB="$B/tools/platform-tools/adb"; FB="$B/tools/platform-tools/fastboot"
IMG="${1:?用法: fuxi-m3-switch.sh <boot.img> [prep ...] -- [verify ...]}"; shift
PREP=(); VERIFY=()
while [ $# -gt 0 ] && [ "$1" != "--" ]; do PREP+=("$1"); shift; done
[ "${1:-}" = "--" ] && shift
VERIFY=("$@")
WAIT="${WAIT:-60}"

e=$(( $(date +%s) + WAIT ))
until timeout 3 "$ADB" devices 2>/dev/null | grep -qw device || timeout 3 "$FB" devices 2>/dev/null | grep -q fastboot; do
  [ "$(date +%s)" -lt "$e" ] || { echo "$(date +%T) FAIL ${WAIT}s 内手机未出现"; notify-send -u critical fuxi "${WAIT}s 内手机未出现：请进 FASTBOOT 并拔插 USB 线" 2>/dev/null; exit 1; }
  sleep 2
done

FUXI_STAY=1 "$B/scripts/fuxi-run.sh" "$IMG" 'uname -v' | tail -n 3
RUN=$(ls -td "$B"/work/claude-logs/run-* | head -1)
grep -q 'FUXI_STAY=1' "$RUN/summary.txt" || { echo "FAIL 没进 initramfs shell，见 $RUN"; exit 1; }

if [ ${#PREP[@]} -gt 0 ]; then
  python3 "$B/scripts/fuxi_sh.py" -t 120 "${PREP[@]}" | tee "$RUN/prep.txt" || { echo "FAIL prep"; exit 1; }
fi
python3 "$B/scripts/fuxi_sh.py" 'umount /mnt/r 2>/dev/null; sync; echo SYNC_OK' >/dev/null
python3 "$B/scripts/fuxi_sh.py" --send 'touch /tmp/do_switch; exit' >/dev/null
echo "$(date +%T) switch_root 已触发，抓串口"

# 等 root shell 出现（autologin 后 bash 提示符含 "root@"）
python3 - "$RUN/switch-raw.log" <<'EOF'
import re, sys, time, serial
end = time.time() + 60; buf = b""; p = None
while time.time() < end:
    try:
        if p is None:
            p = serial.Serial("/dev/fuxi-acm", 115200, timeout=0.5)
        c = p.read(4096)
        if c:
            buf += c
            if re.search(rb"root@[^\s]*:[^\n]*# ?$", buf[-300:]):
                break
    except Exception:
        p = None; time.sleep(1)
open(sys.argv[1], "wb").write(buf)
t = re.sub(r"\x1b\[[0-9;:?]*[A-Za-z]", "", buf.decode(errors="replace")).replace("\r", "")
fails = [l for l in t.split("\n") if re.search(r"FAILED|TIME \]|DEPEND\]", l)]
print("\n".join(sorted(set(fails))) or "(无 FAILED/超时)")
print("ROOT_SHELL" if "root@" in t else "NO_ROOT_SHELL")
EOF

if [ ${#VERIFY[@]} -gt 0 ]; then
  python3 "$B/scripts/fuxi_sh.py" -t 60 "${VERIFY[@]}" | tee "$RUN/verify.txt"
fi
echo "dir=$RUN"
