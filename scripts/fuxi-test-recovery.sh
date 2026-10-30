#!/bin/bash
# 不用 fastboot 的测试流程（fastboot 在这台电脑上 USB 很不稳定）：
#   Android（adb root）把镜像 dd 进 recovery_b → adb reboot recovery → 主线 Linux
#   → [可选] 在 initramfs 串口 shell 执行命令（FUXI_STAY=1，赶在 8 秒自动启动前 touch /tmp/stay）
#     或等 Ubuntu 起来后用 ssh 执行命令 → reboot 回 Android
# 测试镜像起不来时：长按电源 20 秒即回 Android（正常开机不碰 recovery_b）。
# 用法: scripts/fuxi-test-recovery.sh <abl 镜像> [ssh 命令 ...]
#       FUXI_STAY=1 scripts/fuxi-test-recovery.sh <镜像> [initramfs 命令 ...]
#       FUXI_KEEP=1 …：测试后不回 Android
#       FUXI_HOST=<手机无线 IP> …：没接 USB 数据（充电头/无线 adb）时，ssh 检查走 WiFi
# 无线 adb：先在主机 adb pair/connect；adb root 重启 adbd 后端口会变，脚本按 mDNS 自动重连
# 当前已知好镜像：work/patches/abl-recovery-dualboot-20261027/recovery-linux.img
set -u
B="$(cd "$(dirname "$0")/.." && pwd)"
ADB="$B/tools/platform-tools/adb"
IMG="${1:?用法: fuxi-test-recovery.sh <abl 镜像> [命令 ...]}"; shift
RUN="$B/work/claude-logs/rtest-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$RUN"; S="$RUN/summary.txt"
t0=$(date +%s)
log() { echo "$(date +%T) +$(( $(date +%s) - t0 ))s $*" | tee -a "$S"; }
notify() { log "$*"; notify-send -u critical fuxi "$*" 2>/dev/null || true; }
wait_for() { local e=$(( $(date +%s) + $1 )); shift; while [ "$(date +%s)" -lt "$e" ]; do "$@" && return 0; sleep 1; done; return 1; }
adb_up() { timeout 3 "$ADB" devices 2>/dev/null | grep -qw device; }
# 无线调试的连接端口每次 adbd 重启都会变：断开 offline 的旧端口，按 mDNS 连新端口
adb_wifi_reconnect() {
  local s ep
  for s in $(timeout 3 "$ADB" devices 2>/dev/null | awk '$2=="offline" && $1 ~ /:/ {print $1}'); do
    timeout 5 "$ADB" disconnect "$s" >/dev/null 2>&1
  done
  ep=$(timeout 5 "$ADB" mdns services 2>/dev/null | awk '$2 ~ /_adb-tls-connect/ {print $3; exit}')
  [ -n "$ep" ] && timeout 10 "$ADB" connect "$ep" >/dev/null 2>&1
  adb_up
}
adb_up_any() { adb_up || adb_wifi_reconnect; }
SSH_HOST="${FUXI_HOST:-10.42.0.2}"
ssh_up() { timeout 5 bash -c "exec 3<>/dev/tcp/$SSH_HOST/22; timeout 3 head -c 4 <&3 | grep -q SSH" 2>/dev/null; }

log "image $(basename "$IMG") sha256=$(sha256sum "$IMG" | cut -c1-16)"
# 手机正在 Ubuntu（上一个测试留在 Linux）：重启即回 Android（正常开机不走 recovery_b），方便多个测试脚本串起来跑
if ! adb_up_any && ssh_up; then
  log "手机在 Ubuntu，先重启回 Android"
  timeout 15 "$B/scripts/fuxi-ssh.sh" 'systemctl reboot' >/dev/null 2>&1
  wait_for 150 adb_up_any || { notify "150s 内没回到 Android"; exit 1; }
  wait_for 120 sh -c "[ \"\$(timeout 5 '$ADB' shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')\" = 1 ]"
fi
wait_for 60 adb_up_any || { notify "手机不在 Android（adb 不可用）"; exit 1; }
timeout 20 "$ADB" root >/dev/null 2>&1; sleep 2; wait_for 30 adb_up_any || { notify "adb root 后 30s 内没重连上"; exit 1; }
timeout 60 "$ADB" push "$IMG" /data/local/tmp/fuxi-test.img >/dev/null || { log "FAIL push"; exit 1; }
n=$(stat -c %s "$IMG"); want=$(sha256sum "$IMG" | cut -c1-16)
got=$(timeout 60 "$ADB" shell "dd if=/data/local/tmp/fuxi-test.img of=/dev/block/by-name/recovery_b bs=1M conv=fsync 2>/dev/null; sync; rm /data/local/tmp/fuxi-test.img; head -c $n /dev/block/by-name/recovery_b | sha256sum | cut -c1-16" | tr -d '\r')
[ "$got" = "$want" ] || { log "FAIL recovery_b 校验不符 got=$got want=$want"; exit 1; }
log "recovery_b 已写入并校验"
timeout 20 "$ADB" reboot recovery
log "adb reboot recovery"

if [ "${FUXI_STAY:-0}" = 1 ]; then
  wait_for 60 test -c /dev/fuxi-acm || { notify "60s 内没有串口：测试镜像可能没起来，长按电源 20 秒回 Android"; exit 3; }
  log "串口出现"
  python3 "$B/scripts/fuxi_serial.py" /dev/fuxi-acm "$RUN" "$@" 2>&1 | tee -a "$S"
  [ "${FUXI_KEEP:-0}" = 1 ] && { log "FUXI_KEEP=1：留在 initramfs"; exit 0; }
  printf 'reboot -f\n' > /dev/fuxi-acm 2>/dev/null
else
  wait_for 90 ssh_up || { notify "90s 内 ssh 不可用：测试镜像可能没起来，长按电源 20 秒回 Android"; exit 3; }
  log "Ubuntu ssh 可用"
  for c in "$@"; do echo "\$ $c"; timeout 120 "$B/scripts/fuxi-ssh.sh" "$c"; done 2>&1 | tee "$RUN/ssh.txt"
  [ "${FUXI_KEEP:-0}" = 1 ] && { log "FUXI_KEEP=1：留在 Ubuntu"; exit 0; }
  timeout 15 "$B/scripts/fuxi-ssh.sh" 'systemctl reboot' >/dev/null 2>&1
fi
wait_for 90 adb_up_any && log "回到 Android" || notify "90s 未回 Android"
log "dir=$RUN"
