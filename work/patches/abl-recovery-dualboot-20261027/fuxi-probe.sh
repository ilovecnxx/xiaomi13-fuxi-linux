#!/bin/bash
# fuxi.die=N 打点探针：fastboot boot 一个"到达打点 N 就 PSCI 复位"的镜像，测手机多久回到 Android。
#   回来得快（< T_BACK 秒）= 内核跑到了打点 N；超时 = 没跑到（手机卡住，需要长按电源）
# 用法: scripts/fuxi-probe.sh <镜像> [T_BACK 秒，默认 45]
set -u
B="$(cd "$(dirname "$0")/.." && pwd)"
ADB="$B/tools/platform-tools/adb"; FB="$B/tools/platform-tools/fastboot"
IMG="${1:?用法: fuxi-probe.sh <镜像> [T_BACK]}"; T_BACK="${2:-45}"
say() { echo "$(date +%T) $*"; }
notify() { say "$*"; notify-send -u critical fuxi "$*" 2>/dev/null || true; }
adb_up() { timeout 3 "$ADB" devices 2>/dev/null | grep -qw device; }
fb_up()  { timeout 3 "$FB" devices 2>/dev/null | grep -q fastboot; }
wait_for() { local e=$(( $(date +%s) + $1 )); shift; while [ "$(date +%s)" -lt "$e" ]; do "$@" && return 0; sleep 1; done; return 1; }

# 进入一个"干净"的 fastboot 会话（ABL 在一次失败启动后会拒绝同一会话里的后续镜像）
if adb_up; then
  timeout 20 "$ADB" reboot bootloader >/dev/null 2>&1
elif fb_up; then
  timeout 15 "$FB" reboot bootloader >/dev/null 2>&1; sleep 3
else
  notify "手机不在 Android/fastboot：请长按电源 20 秒重启"; wait_for 120 adb_up || exit 1
  timeout 20 "$ADB" reboot bootloader >/dev/null 2>&1
fi
wait_for 25 fb_up || { notify "没认到 fastboot：请拔插 USB 线"; wait_for 60 fb_up || exit 1; }
timeout 30 "$FB" boot "$IMG" 2>&1 | grep -E 'Booting|FAILED' | sed "s/^/$(date +%T) /"
t0=$(date +%s)
if wait_for "$T_BACK" adb_up; then
  say "RESULT=BACK $(basename "$IMG") $(( $(date +%s) - t0 ))s 回到 Android（内核到达了该打点）"
else
  notify "RESULT=STUCK $(basename "$IMG") ${T_BACK}s 未回 Android（没到该打点）：请长按电源 20 秒"
  exit 2
fi
