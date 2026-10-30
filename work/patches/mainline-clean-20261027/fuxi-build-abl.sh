#!/bin/bash
# ABL 直接引导的 boot 镜像（不经过自制 UEFI）：
#   boot.img header v1，kernel 字段 = Image.gz + 厂商 fuxi DTB（"诱饵"）
#   - ABL 按 msm-id/board-id 挑 DTB，并把 dtbo 分区的 overlay 叠上去；叠到主线 DTB 上会卡死
#     （2026-10-27 实测：附主线 DTB 时 ABL 回 Booting OKAY 后黑屏卡住，附厂商 DTB 则正常跳转）
#   - 内核开了 CONFIG_FUXI_FORCE_BUILTIN_DTB，忽略 ABL 传入的 DTB，改用编进内核的主线 DTB
#     （arch/arm64/kernel/fuxi_dtb.S），cmdline 也来自它的 /chosen/bootargs
#   initramfs 内建在内核里（CONFIG_INITRAMFS_SOURCE），ramdisk 字段为空
# 用法: scripts/fuxi-build-abl.sh <名字> [--no-kernel]
# 产物: work/kbuild/abl-fuxi-<名字>.img
set -euo pipefail
B="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${1:?用法: fuxi-build-abl.sh <名字> [--no-kernel]}"
L="$B/work/claude-logs"; mkdir -p "$L"
K="$B/build/linux"
DTB="$K/arch/arm64/boot/dts/qcom/sm8550-xiaomi-fuxi-min.dtb"
BAIT_DTB="$B/build/edk2-msm/Platform/Xiaomi/sm8550/FdtBlob_compat/fuxi.dtb"
MAKE=(make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)")

if [ "${2:-}" != "--no-kernel" ]; then
  cd "$K"
  # initramfs 改动不会触发重新打包，每次都强制重建
  rm -f usr/initramfs_data.cpio usr/initramfs_data.cpio.gz
  echo "[kernel] make dtb → Image.gz（日志 $L/kbuild.log）"
  # 先单独编 DTB：内核用 .incbin 把它嵌进去
  { "${MAKE[@]}" qcom/sm8550-xiaomi-fuxi-min.dtb && "${MAKE[@]}" Image.gz; } > "$L/kbuild.log" 2>&1 ||
    { grep -m5 -B2 -A3 'error' "$L/kbuild.log"; exit 1; }
  grep -q '^CONFIG_FUXI_FORCE_BUILTIN_DTB=y' .config || { echo "需要 CONFIG_FUXI_FORCE_BUILTIN_DTB=y"; exit 1; }
fi

# 镜像头里的 cmdline 只是记录（不生效），和内建 DTB 保持一致
CMDLINE=$(fdtget "$DTB" /chosen bootargs | sed 's/ *$//')
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
cat "$K/arch/arm64/boot/Image.gz" "$BAIT_DTB" > "$W/kernel-dtb"
: > "$W/ramdisk"
OUT="$B/work/kbuild/abl-fuxi-$NAME.img"
python3 "$B/build/edk2-msm/tools/mkbootimg.py" \
  --header_version 1 --os_version 13.0.0 --os_patch_level 2022-11 \
  --kernel "$W/kernel-dtb" --ramdisk "$W/ramdisk" \
  --base 0x0 --kernel_offset 0x00000000 --ramdisk_offset 0x01000000 --tags_offset 0x00000100 \
  --pagesize 4096 --cmdline "${CMDLINE:0:500}" -o "$OUT"
echo "[ok] $OUT $(stat -c %s "$OUT") bytes; Image $(stat -c %s "$K/arch/arm64/boot/Image") bytes"
echo "[cmdline] $CMDLINE"
