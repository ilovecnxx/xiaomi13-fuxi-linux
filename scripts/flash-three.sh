#!/bin/sh
# 逐条刷入并带超时看护，避免 fastboot 卡死
B="/home/user/文档/deepseek-harness/default-workspace/linux-android"
FB="$B/tools/platform-tools/fastboot"
cd "$B"
run() { timeout -k 2 "$1" $FB "${@:2}"; }
echo "== 设备 =="; run 10 devices
echo "== 清 ABL 状态 =="; run 20 reboot bootloader; sleep 6
run 10 devices
echo "== boot_b =="; run 120 flash boot_b work/kbuild/boot_b_kexec.img
echo "== init_boot_b =="; run 60 flash init_boot_b work/initboot/init_boot_patched.img
echo "== vendor_boot_b =="; run 180 flash vendor_boot_b work/kbuild/vendor_boot_b_patched.img
echo "== 重启 =="; run 20 reboot
