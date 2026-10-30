#!/bin/bash
# 尽快把手机弄回 Android：轮询 fastboot（0.3s），一出现立即 fastboot reboot；已在 adb 则退出。
B="/home/user/文档/deepseek-harness/default-workspace/linux-android"
ADB="$B/tools/platform-tools/adb"; FB="$B/tools/platform-tools/fastboot"
LOG="$B/logs/back-to-android.log"
t0=$(date +%s)
while [ $(( $(date +%s) - t0 )) -lt 900 ]; do
  if timeout 3 "$ADB" devices 2>/dev/null | tail -n +2 | grep -q device; then
    echo "$(date '+%F %T') already adb" >> "$LOG"; exit 0
  fi
  if timeout 3 "$FB" devices 2>/dev/null | grep -q fastboot; then
    echo "$(date '+%F %T') fastboot seen -> fastboot reboot" >> "$LOG"
    timeout 25 "$FB" reboot >> "$LOG" 2>&1
    sleep 5
    continue
  fi
  sleep 0.3
done
echo "$(date '+%F %T') give up" >> "$LOG"; exit 1
