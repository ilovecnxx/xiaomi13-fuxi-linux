#!/bin/bash
# 把手机带回 fastboot：Android(adb) → adb reboot bootloader；已 fastboot 则直接返回。
B="/home/user/文档/deepseek-harness/default-workspace/linux-android"
ADB="$B/tools/platform-tools/adb"; FB="$B/tools/platform-tools/fastboot"
t0=$(date +%s)
while [ $(( $(date +%s) - t0 )) -lt 120 ]; do
  if timeout 6 "$FB" devices 2>/dev/null | grep -q fastboot; then echo "fastboot ready"; exit 0; fi
  if timeout 6 "$ADB" devices 2>/dev/null | tail -n +2 | grep -q 'device'; then
    echo "$(date '+%T') adb -> reboot bootloader"
    timeout 20 "$ADB" reboot bootloader >/dev/null 2>&1
    sleep 6
    continue
  fi
  sleep 2
done
echo "无法自动回到 fastboot（设备未枚举）"; exit 1
