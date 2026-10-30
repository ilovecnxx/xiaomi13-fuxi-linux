#!/bin/bash
# 不碰串口的完整往返：fastboot boot → Ubuntu → ssh 可达（计时）→ reboot bootloader → fastboot（计时）
# 用法: scripts/fuxi-roundtrip.sh <abl 镜像>
set -u
B="$(cd "$(dirname "$0")/.." && pwd)"
ADB="$B/tools/platform-tools/adb"; FB="$B/tools/platform-tools/fastboot"
IMG="${1:?用法: fuxi-roundtrip.sh <abl 镜像>}"
say() { echo "$(date +%T) $*"; }
fb_up()  { timeout 3 "$FB" devices 2>/dev/null | grep -q fastboot; }
adb_up() { timeout 3 "$ADB" devices 2>/dev/null | grep -qw device; }
ssh_banner() { timeout 5 bash -c 'exec 3<>/dev/tcp/10.42.0.2/22; timeout 3 head -c 4 <&3 | grep -q SSH' 2>/dev/null; }
wait_for() { local e=$(( $(date +%s) + $1 )); shift; while [ "$(date +%s)" -lt "$e" ]; do "$@" && return 0; sleep 1; done; return 1; }

say "等手机进 Android 或 fastboot（最长 180s）"
wait_for 180 sh -c "timeout 3 '$FB' devices 2>/dev/null | grep -q fastboot || timeout 3 '$ADB' devices 2>/dev/null | grep -qw device" || { say "FAIL 无设备"; exit 1; }
if ! fb_up; then timeout 20 "$ADB" reboot bootloader >/dev/null 2>&1; wait_for 30 fb_up || { say "FAIL 没进 fastboot"; exit 1; }; fi
timeout 30 "$FB" boot "$IMG" 2>&1 | grep -E 'Booting|FAIL' | sed "s/^/$(date +%T) /"
t1=$(date +%s)
if wait_for 180 ssh_banner; then say "BOOT fastboot boot → ssh 可用: $(( $(date +%s) - t1 ))s"; else say "FAIL 180s 内 ssh 不可用"; exit 2; fi
"$B/scripts/fuxi-ssh.sh" 'systemd-analyze | head -1; systemctl is-system-running; grep -o "console=[^ ]*" /proc/cmdline'
t2=$(date +%s)
timeout 15 "$B/scripts/fuxi-ssh.sh" 'systemctl reboot --reboot-argument=bootloader' >/dev/null 2>&1
if wait_for 150 fb_up; then say "SHUTDOWN reboot bootloader → fastboot: $(( $(date +%s) - t2 ))s"; else say "FAIL 150s 内没回到 fastboot"; exit 3; fi
