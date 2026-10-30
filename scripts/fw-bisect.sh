#!/bin/bash
# 自动跑 STAGE1-5 固件二分：每个镜像自带 30s 看门狗，测试后应自动回 fastboot
B="/home/user/文档/deepseek-harness/default-workspace/linux-android"
FB="$B/tools/platform-tools/fastboot"
cd "$B"
LOG="$B/work/fw-bisect.log"; : > "$LOG"
wait_fb() { local t=0; while [ $t -lt 120 ]; do timeout 2 "$FB" devices 2>/dev/null | grep -q fastboot && return 0; sleep 2; t=$((t+2)); done; return 1; }
for st in 1 2 3 4 5; do
  img="$B/work/kbuild/boot-fuxi-stage$st.img"
  [ -f "$img" ] || { echo "STAGE$st image missing" | tee -a "$LOG"; continue; }
  wait_fb || { echo "STAGE$st: wait fastboot timeout" | tee -a "$LOG"; break; }
  timeout 60 "$FB" flash boot_b "$img" >/dev/null 2>&1
  t0=$(date +%s)
  timeout 20 "$FB" reboot >/dev/null 2>&1
  # 观察是否回 fastboot（看门狗 30s → 预期 35~70s 回来）
  back="none"
  for i in $(seq 1 40); do
    sleep 2
    if timeout 2 "$FB" devices 2>/dev/null | grep -q fastboot; then back="yes"; break; fi
  done
  dt=$(( $(date +%s) - t0 ))
  echo "STAGE$st: fastboot_back=$back after ${dt}s" | tee -a "$LOG"
  [ "$back" = "no" ] && { echo "STAGE$st 没有自动回 fastboot（可能稳定/挂死），停止" | tee -a "$LOG"; break; }
done
echo "=== 恢复原厂 boot_b ===" | tee -a "$LOG"
wait_fb && timeout 60 "$FB" flash boot_b "$B/backups/20261024-172623/boot_b.img" >/dev/null 2>&1
timeout 20 "$FB" reboot >/dev/null 2>&1
echo "done" | tee -a "$LOG"
