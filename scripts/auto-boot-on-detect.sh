#!/bin/bash
# 后台等待手机重新枚举为 fastboot，一经检测立即 boot 指定镜像（用于"用户拔插 USB 后自动开跑"）。
# 用法: scripts/auto-boot-on-detect.sh <image> [等待秒数]
B="/home/user/文档/deepseek-harness/default-workspace/linux-android"
IMG="${1:?image required}"; WAIT="${2:-300}"
FB="$B/tools/platform-tools/fastboot"; ADB="$B/tools/platform-tools/adb"
LOG="$B/logs/auto-boot.log"
log(){ echo "$(date '+%F %T') $*" >> "$LOG"; }
log "waiting for fastboot (image=$IMG, timeout=${WAIT}s)"
t0=$(date +%s)
while [ $(( $(date +%s) - t0 )) -lt "$WAIT" ]; do
  if lsusb 2>/dev/null | grep -qE '(18d1|05c6):[0-9a-f]{4}'; then
    if timeout 8 "$FB" devices 2>/dev/null | grep -q fastboot; then
      log "fastboot detected, issuing boot"
      timeout 120 "$FB" boot "$IMG" >> "$LOG" 2>&1
      rc=$?
      log "fastboot boot rc=$rc"
      # 记录返回状态（adb / fastboot / none），持续 10 分钟
      t1=$(date +%s)
      while [ $(( $(date +%s) - t1 )) -lt 600 ]; do
        st="none"
        if timeout 6 "$ADB" devices 2>/dev/null | tail -n +2 | grep -q device; then st="adb"
        elif timeout 6 "$FB" devices 2>/dev/null | grep -q fastboot; then st="fastboot"; fi
        if [ "$st" != "none" ]; then log "returned: $st after $(( $(date +%s) - t0 ))s"; break; fi
        sleep 5
      done
      exit 0
    fi
  fi
  sleep 1
done
log "timeout waiting for fastboot"
exit 1
