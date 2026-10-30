#!/bin/bash
# 通过 adb(root) 从 Android 直接 kexec 启动主线内核（不写分区、不依赖 fastboot）。
# 用法: scripts/kexec-mainline-adb.sh <Image> <dtb> [cmdline]
# 之后主线内核会把 printk 写进 Android 的 ramoops 区域(0xa7000000)；
# 内核卡死后（或加了自复位）回到 Android 即可从 /sys/fs/pstore 读日志。
B="/home/user/文档/deepseek-harness/default-workspace/linux-android"
ADB="$B/tools/platform-tools/adb"
IMG="${1:?usage: $0 <Image> <dtb> [cmdline]}"; DTB="${2:?}"; CMD="${3:-console=tty0 loglevel=7 rdinit=/init}"
T=/data/local/tmp/fuxi
set -e
"$ADB" root >/dev/null 2>&1 || true; sleep 2; "$ADB" wait-for-device
"$ADB" shell "mkdir -p $T"
"$ADB" push "$B/work/kbuild/kexec-static" "$T/kexec" >/dev/null
"$ADB" push "$IMG" "$T/Image" >/dev/null
"$ADB" push "$DTB" "$T/fuxi.dtb" >/dev/null
"$ADB" shell "chmod 755 $T/kexec"
echo "== kexec load =="
"$ADB" shell "$T/kexec -l $T/Image --dtb=$T/fuxi.dtb --command-line='$CMD'"
echo "== kexec -e =="
"$ADB" shell "$T/kexec -e" || true
