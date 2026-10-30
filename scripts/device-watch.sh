#!/bin/bash
# 持续监测手机状态并写入磁盘日志（供 agent/人自动读取）。
# 判定顺序：adb devices → fastboot devices → USB 有 18d1/05c6 但工具都看不到（unstable）→ none
# 说明：ABL fastboot 可能是 18d1:d00d("Android")；Android 系统可能是 18d1:4ee2("Xiaomi 13"/MTP+debug)，
#       所以不能靠 VID:PID 判断，必须以工具为准。
B="/home/user/文档/deepseek-harness/default-workspace/linux-android"
LOG="$B/logs/usb-state.log"; POLL="$B/logs/usb-poll.log"
mkdir -p "$B/logs"
ADB="$B/tools/platform-tools/adb"; FB="$B/tools/platform-tools/fastboot"
last=""
while :; do
  now=$(date '+%F %T')
  ids=$(lsusb 2>/dev/null | grep -oE '(18d1|05c6):[0-9a-f]{4}' | sort -u | tr '\n' ',')
  state="none"
  if [ -n "$ids" ]; then
    if timeout 6 "$ADB" devices 2>/dev/null | tail -n +2 | grep -q 'device'; then
      state="adb"
    elif timeout 6 "$FB" devices 2>/dev/null | grep -q 'fastboot'; then
      state="fastboot"
    else
      state="unstable"
    fi
  fi
  if [ "$state" != "$last" ]; then
    echo "$now STATE=$state ids=${ids:-none}" >> "$LOG"
    last="$state"
  fi
  echo "$now $state ${ids:-none}" >> "$POLL"
  tail -n 5000 "$POLL" > "$POLL.tmp" 2>/dev/null && mv "$POLL.tmp" "$POLL"
  sleep 2
done
