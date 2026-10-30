#!/bin/bash
# 全自动一轮实验（不刷写任何分区）：
#   Android --adb reboot bootloader--> fastboot --fastboot boot IMG--> 主线内核
#   --/dev/fuxi-acm 串口执行命令、收 dmesg--> reboot -f --> 回到 Android（boot_b 为 stock）
#
# 用法: scripts/fuxi-run.sh <boot.img> [手机上要执行的命令 ...]
# 产物: work/claude-logs/run-<时间>/{summary.txt,acm-raw.log,dmesg.txt,cmd-NN.txt}
# 退出码: 0 串口 shell 成功; 2 串口在但 shell 无响应; 3 120s 无串口; 4 提前复位回 Android; 1 前置步骤失败
# FUXI_STAY=1：命令跑完后不重启，手机留在 Linux，之后用 scripts/fuxi_sh.py 继续操作
set -u
B="$(cd "$(dirname "$0")/.." && pwd)"
FB="$B/tools/platform-tools/fastboot"
ADB="$B/tools/platform-tools/adb"
ACM=/dev/fuxi-acm
IMG="${1:?用法: fuxi-run.sh <boot.img> [cmd ...]}"; shift
[ -f "$IMG" ] || { echo "镜像不存在: $IMG"; exit 1; }
RUN="$B/work/claude-logs/run-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RUN"
S="$RUN/summary.txt"
t0=$(date +%s)
log() { echo "$(date +%T) +$(( $(date +%s) - t0 ))s $*" | tee -a "$S"; }
# 需要人手介入时弹桌面通知（超时一律快速失败，不长时间空等）
notify() { log "$*"; notify-send -u critical "fuxi" "$*" 2>/dev/null || true; }
# 超时（实测正常值：重启→fastboot 11-14s；fastboot boot→串口 12-13s；Linux 重启→adb 约 15s）
T_FB=${T_FB:-20}; T_ACM=${T_ACM:-30}; T_ANDROID=${T_ANDROID:-40}; T_NODEV=${T_NODEV:-60}

fb_present()  { timeout 3 "$FB" devices 2>/dev/null | grep -q fastboot; }
adb_present() { timeout 3 "$ADB" devices 2>/dev/null | grep -qw device; }

# 等待条件成立，最长 $1 秒
wait_for() { local n=$1; shift; local e=$(( $(date +%s) + n ))
  while [ "$(date +%s)" -lt "$e" ]; do "$@" && return 0; sleep 0.5; done; return 1; }

log "image $(basename "$IMG") sha256=$(sha256sum "$IMG" | cut -c1-16)"

# 1. 进 fastboot
if fb_present; then
  log "已在 fastboot"
elif adb_present; then
  log "adb reboot bootloader"
  timeout 20 "$ADB" reboot bootloader >/dev/null 2>&1
  wait_for "$T_FB" fb_present || { notify "FAIL ${T_FB}s 内电脑没认到 fastboot：请拔插 USB 线"; exit 1; }
else
  notify "等待 adb/fastboot 出现（最长 ${T_NODEV}s）：手机不在 Android/fastboot，或 USB 没连上"
  wait_for "$T_NODEV" sh -c "timeout 3 '$FB' devices 2>/dev/null | grep -q fastboot || timeout 3 '$ADB' devices 2>/dev/null | grep -qw device" ||
    { notify "FAIL 无设备：请让手机进 FASTBOOT 并拔插 USB 线"; exit 1; }
  exec "$0" "$IMG" "$@"
fi

# 2. fastboot boot（ABL 枚举可能只稳定 1-2 秒，失败重试）
ok=0
for i in 1 2 3 4 5; do
  if timeout 40 "$FB" boot "$IMG" >>"$RUN/fastboot.log" 2>&1; then ok=1; break; fi
  log "fastboot boot 第 $i 次失败，重试"; wait_for 10 fb_present
done
[ $ok = 1 ] || { notify "FAIL fastboot boot 失败：请拔插 USB 线"; exit 1; }
log "fastboot boot OK"

# 3. 等串口（init 最多等 30s ttyGS0，再加内核启动时间）；adb 先回来说明内核提前复位了
tb=$(date +%s)
acm_or_adb() { test -c "$ACM" || adb_present; }
wait_for "$T_ACM" acm_or_adb
if [ -c "$ACM" ]; then
  log "ACM 出现: $(readlink -f $ACM)"
  sleep 1
  python3 "$B/scripts/fuxi_serial.py" "$ACM" "$RUN" "$@" 2>&1 | tee -a "$S"
  rc=${PIPESTATUS[0]}
  log "fuxi_serial rc=$rc"
  if [ "$rc" = 0 ] && [ "${FUXI_STAY:-0}" = 1 ]; then
    # 留在 Linux 继续交互（scripts/fuxi_sh.py）；init 的 180s 安全重启已被 /tmp/keep 取消
    log "FUXI_STAY=1：手机留在 Linux，串口 $ACM"
    log "RESULT=0 dir=$RUN"
    exit 0
  elif [ "$rc" = 0 ]; then
    # 回 Android（initramfs 里没有 reboot 到 bootloader 的保证，统一 reboot -f）
    printf 'reboot -f\n' > "$ACM" 2>/dev/null
    result=0
  else
    result=2
  fi
elif adb_present; then
  log "EARLY_RESET boot 后 $(( $(date +%s) - tb ))s 就回到 Android，未出现串口（内核卡死被看门狗复位？）"
  result=4
else
  notify "NO_ACM ${T_ACM}s 内未出现串口：看屏幕 DEFER 行（init 会自动回 Android）"
  result=3
fi

# 4. 等回 Android
if wait_for "$T_ANDROID" adb_present; then
  log "回到 Android"
else
  notify "WARN ${T_ANDROID}s 未回 Android：看一下手机，必要时长按电源 20s"
fi
log "RESULT=$result dir=$RUN"
exit $result
