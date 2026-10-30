#!/bin/sh
# 一次 fastboot：刷入自编 VT+KEXEC 内核并验证 Ubuntu 完整启动
set -e
B="/home/user/文档/deepseek-harness/default-workspace/linux-android"
FB="$B/tools/platform-tools/fastboot"
cd "$B"
KEY=work/ssh/client_key
echo "== 1) 打包 boot_b =="
python3 build/edk2-msm/tools/mkbootimg.py --kernel work/kbuild/Image-vt-kexec.img \
  --ramdisk build/native/empty-ramdisk --header_version 4 --pagesize 4096 \
  --os_version 17.0.0 --os_patch_level 2026-10 --output work/kbuild/boot_b_vtkexec.img >/dev/null
echo "== 2) 刷入 =="
"$FB" devices | grep -q fastboot || { echo "请先进入 fastboot"; exit 1; }
"$FB" flash boot_b work/kbuild/boot_b_vtkexec.img
"$FB" flash init_boot_b work/initboot/init_boot_ssh_rebuilt.img
"$FB" reboot
echo "== 3) 等待 USB 网络 =="
i=0
while [ $i -lt 30 ]; do
  ip -br addr show enx020000001302 2>/dev/null | grep -q 192.168.77 && break
  sleep 3; i=$((i+1))
done
ip -br addr show enx020000001302 2>/dev/null || { echo "USB 网络未出现"; exit 1; }
echo "== 4) SSH 抓取内核信息 =="
sleep 5
ssh -i "$KEY" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  root@192.168.77.2 'uname -a; echo ---; dmesg | head -40; echo ---; ls /dev/tty0 2>/dev/null; echo ---; cat /proc/cmdline' \
  | tee work/kbuild/vtkexec-dmesg.txt
echo "== 完成，日志见 work/kbuild/vtkexec-dmesg.txt =="
