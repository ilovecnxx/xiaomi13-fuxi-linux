#!/bin/bash
# 高频轮询 fastboot（0.3s），一出现立即 fastboot boot；boot 失败则继续等下一次枚举。
# 用法: scripts/auto-boot-tight.sh <image> [wait_s]
B="/home/user/文档/deepseek-harness/default-workspace/linux-android"
FB="$B/tools/platform-tools/fastboot"
IMG="${1:?image}"; WAIT="${2:-1800}"; LOG="$B/logs/auto-tight.log"
t0=$(date +%s); tries=0
echo "$(date '+%F %T') watch $IMG" >> "$LOG"
while [ $(( $(date +%s) - t0 )) -lt "$WAIT" ]; do
  if timeout 2 "$FB" devices 2>/dev/null | grep -q fastboot; then
    tries=$((tries+1))
    echo "$(date '+%F %T') fastboot seen (#$tries), booting" >> "$LOG"
    if timeout 40 "$FB" boot "$IMG" >> "$LOG" 2>&1; then
      echo "$(date '+%F %T') boot OK" >> "$LOG"; exit 0
    fi
    echo "$(date '+%F %T') boot failed, keep waiting" >> "$LOG"
    sleep 1
  fi
  sleep 0.3
done
echo "$(date '+%F %T') timeout" >> "$LOG"; exit 1
