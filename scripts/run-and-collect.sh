#!/bin/bash
# 跑一张实验镜像，然后从 Android 的 pstore 里自动回收主线内核日志。
# 用法: scripts/run-and-collect.sh <image.img>
# 流程: adb reboot bootloader → fastboot boot image → 等回到 Android(adb)
#       → adb root → 读取 /sys/fs/pstore/* 保存到 logs/run-<ts>/
B="/home/user/文档/deepseek-harness/default-workspace/linux-android"
ADB="$B/tools/platform-tools/adb"; FB="$B/tools/platform-tools/fastboot"
IMG="${1:?usage: $0 <image.img>}"
TS=$(date +%Y%m%d-%H%M%S); OUT="$B/logs/run-$TS"; mkdir -p "$OUT"
LOG="$OUT/run.log"
log(){ echo "$(date '+%F %T') $*" | tee -a "$LOG"; }

wait_adb(){ # wait_adb <timeout_s>
  local t="$1" t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt "$t" ]; do
    timeout 6 "$ADB" devices 2>/dev/null | tail -n +2 | grep -q device && { timeout 6 "$ADB" devices 2>/dev/null | tail -n +2 | grep -q device; return 0; }
    sleep 2
  done
  return 1
}
wait_fastboot(){
  local t="$1" t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt "$t" ]; do
    timeout 6 "$FB" devices 2>/dev/null | grep -q fastboot && return 0
    sleep 2
  done
  return 1
}

log "=== run image=$IMG ==="
log "md5=$(md5sum "$IMG" | cut -d' ' -f1)"

# 1) 进入 fastboot
if ! wait_fastboot 3; then
  if wait_adb 3; then
    log "adb -> reboot bootloader"
    timeout 20 "$ADB" reboot bootloader >/dev/null 2>&1
    if ! wait_fastboot 90; then
      log "ERROR: fastboot 未枚举（需要物理拔插 USB 或重启手机）"
      exit 2
    fi
  else
    log "ERROR: 既不在 adb 也不在 fastboot"
    exit 2
  fi
fi
log "fastboot ready"

# 2) 启动镜像（不写分区）
timeout 120 "$FB" boot "$IMG" >> "$LOG" 2>&1
rc=$?
log "fastboot boot rc=$rc"
[ $rc -ne 0 ] && exit 3

# 3) 等设备回到 Android
log "waiting for Android/adb (up to 600s) ..."
if ! wait_adb 600; then
  log "ERROR: 600s 内没回到 adb（可能卡死）"
  exit 4
fi
log "Android back in adb"

# 4) 取 pstore
timeout 20 "$ADB" root >/dev/null 2>&1
sleep 3
timeout 20 "$ADB" wait-for-device
log "pstore listing:"
timeout 20 "$ADB" shell 'ls -la /sys/fs/pstore 2>/dev/null' >> "$LOG" 2>&1
for f in console-ramoops-0 dmesg-ramoops-0 pmsg-ramoops-0 console-ramoops dmesg-ramoops; do
  timeout 30 "$ADB" shell "cat /sys/fs/pstore/$f 2>/dev/null" > "$OUT/$f.txt" 2>/dev/null
  n=$(wc -c < "$OUT/$f.txt" 2>/dev/null || echo 0)
  log "pulled $f: $n bytes"
done
timeout 20 "$ADB" shell 'cat /proc/device-tree/reserved-memory/ramoops@0xa7000000/reg | xxd -p' >> "$LOG" 2>&1
log "saved to $OUT"
ls -la "$OUT"
