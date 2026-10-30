#!/bin/sh
# 一键恢复 fuxi 到 stock 分区状态（Android/LineageOS 可正常启动）
set -e
B="/home/user/文档/deepseek-harness/default-workspace/linux-android"
FB="$B/tools/platform-tools/fastboot"
cd "$B"
echo "== 进入 fastboot（如未在）=="
"$FB" devices | grep -q fastboot || { echo "请先进入 fastboot"; exit 1; }
"$FB" set_active b || true
for p in boot_b init_boot_b vendor_boot_b dtbo_b; do
  [ -f "backups/20261024-172623/$p.img" ] && "$FB" flash "$p" "backups/20261024-172623/$p.img"
done
"$FB" reboot
