#!/bin/bash
# 构建一版测试镜像：内核 Image + fuxi-min.dtb（含内置 initramfs）→ EDK2 固件 → work/kbuild/boot-fuxi-<名字>.img
# 用法: scripts/fuxi-build.sh <名字> [--no-kernel]
#   内核 cmdline 在 FuxiLinuxBoot.c 的 AsciiSPrint 里；只改 cmdline 时可加 --no-kernel
set -euo pipefail
B="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${1:?用法: fuxi-build.sh <名字> [--no-kernel]}"
L="$B/work/claude-logs"; mkdir -p "$L"
FLB="$B/build/edk2-msm/Silicon/Qualcomm/sm8550/Drivers/FuxiLinuxBoot"
if [ "${2:-}" != "--no-kernel" ]; then
  cd "$B/build/linux"
  # initramfs 改动不会触发重新打包，每次都强制重建
  rm -f usr/initramfs_data.cpio usr/initramfs_data.cpio.gz
  echo "[kernel] make（日志 $L/kbuild.log）"
  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)" Image qcom/sm8550-xiaomi-fuxi-min.dtb > "$L/kbuild.log" 2>&1 ||
    { grep -m5 -B2 -A3 'error' "$L/kbuild.log"; exit 1; }
  cp arch/arm64/boot/Image "$FLB/Image.tiano"
fi
cd "$B/build/edk2-msm"
echo "[edk2] build.sh（日志 $L/edk2-build.log）"
PATH="$B/tools/ccwrap:$B/tools:$PATH" ./build.sh --device fuxi --toolchain GCC5 -r DEBUG > "$L/edk2-build.log" 2>&1 ||
  { tail -n 20 "$L/edk2-build.log"; exit 1; }
OUT="$B/work/kbuild/boot-fuxi-$NAME.img"
cp boot-fuxi.img "$OUT"
echo "[ok] $OUT $(stat -c %s "$OUT") bytes"
grep -a -o -m1 'loglevel=[^"]*rdinit=/init' workspace/Build/fuxi/DEBUG_GCC5/AARCH64/FuxiLinuxBoot.efi | sed 's/^/[cmdline] /'
