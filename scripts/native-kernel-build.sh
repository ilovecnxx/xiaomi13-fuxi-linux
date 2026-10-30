#!/usr/bin/env bash
# Build a temporary fuxi Linux kernel probe and legacy fastboot boot image.
# This only writes workspace build artifacts; it never invokes adb or fastboot.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
KERNEL="$ROOT/build/linux"
OUT="$ROOT/build/native"
DTS_SOURCE="$ROOT/build/fuxi-min.dts"
DTS_NAME=sm8550-xiaomi-fuxi-min
CROSS_COMPILE=${CROSS_COMPILE:-aarch64-linux-gnu-}
JOBS=${JOBS:-$(nproc)}

DTC=${DTC:-$(command -v dtc || true)}
if [[ -z "$DTC" && -x "$KERNEL/scripts/dtc/dtc" ]]; then
  DTC="$KERNEL/scripts/dtc/dtc"
fi
for tool in "${CROSS_COMPILE}gcc" "${CROSS_COMPILE}ld" python3; do
  command -v "$tool" >/dev/null || { echo "Missing build tool: $tool" >&2; exit 1; }
done
[[ -x "$DTC" ]] || { echo "Missing build tool: dtc (build/linux/scripts/dtc/dtc is also accepted)" >&2; exit 1; }
[[ -d "$KERNEL" && -f "$KERNEL/Makefile" ]] || { echo "Missing kernel tree: $KERNEL" >&2; exit 1; }
[[ -f "$KERNEL/.config" ]] || { echo "Missing kernel .config; initialize the kernel config first." >&2; exit 1; }
[[ -x "$ROOT/build/initramfs/init" && -x "$ROOT/build/initramfs/bin/busybox" ]] || {
  echo "Missing executable initramfs files under build/initramfs." >&2; exit 1;
}

mkdir -p "$OUT"
LOG="$OUT/build.log"
exec > >(tee "$LOG") 2>&1
echo "== fuxi native probe build =="
echo "Kernel: $(git -C "$KERNEL" describe --always 2>/dev/null || echo unknown)"
echo "Jobs: $JOBS"

cp "$DTS_SOURCE" "$KERNEL/arch/arm64/boot/dts/qcom/$DTS_NAME.dts"

cd "$KERNEL"
./scripts/config \
  --enable ARCH_QCOM \
  --enable COMMON_CLK \
  --enable COMMON_CLK_QCOM \
  --enable QCOM_RPMH \
  --enable QCOM_RPMHPD \
  --enable QCOM_COMMAND_DB \
  --enable QCOM_SMEM \
  --enable QCOM_SCM \
  --enable REGULATOR \
  --enable REGULATOR_FIXED_VOLTAGE \
  --enable REGULATOR_QCOM_RPMH \
  --enable INTERCONNECT \
  --enable INTERCONNECT_QCOM \
  --enable INTERCONNECT_QCOM_SM8550 \
  --enable IOMMU_SUPPORT \
  --enable IOMMU_DMA \
  --enable ARM_SMMU \
  --enable ARM_SMMU_V3 \
  --enable GENERIC_PHY \
  --enable PHY_SNPS_EUSB2 \
  --enable PHY_QCOM_EUSB2_REPEATER \
  --enable PHY_QCOM_QMP \
  --enable PHY_QCOM_QMP_COMBO \
  --enable PHY_QCOM_QMP_USB \
  --enable USB_SUPPORT \
  --enable USB_DWC3 \
  --enable USB_DWC3_QCOM \
  --enable USB_GADGET \
  --enable USB_G_SERIAL \
  --enable U_SERIAL_CONSOLE \
  --enable DEVTMPFS \
  --enable DEVTMPFS_MOUNT \
  --enable PROC_FS \
  --enable SYSFS \
  --enable TMPFS \
  --enable BLK_DEV_INITRD \
  --enable RD_GZIP \
  --enable BINFMT_ELF \
  --enable BINFMT_SCRIPT \
  --enable EFI \
  --enable EFI_STUB \
  --disable ARM64_VA_BITS_52 \
  --enable ARM64_VA_BITS_48 \
  --disable ARM64_PA_BITS_52 \
  --enable ARM64_PA_BITS_48 \
  --disable ARM64_LPA2 \
  --set-str INITRAMFS_SOURCE "$ROOT/build/initramfs" \
  --enable CMDLINE_BOOL \
  --enable CMDLINE_FORCE \
  --set-str CMDLINE "console=ttyGS0,115200n8 loglevel=8 ignore_loglevel rdinit=/init"

make ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" DTC="$DTC" olddefconfig

for option in ARCH_QCOM INTERCONNECT_QCOM_SM8550 PHY_SNPS_EUSB2 \
    USB_DWC3_QCOM USB_G_SERIAL U_SERIAL_CONSOLE EFI_STUB CMDLINE_FORCE; do
  if ! grep -qx "CONFIG_${option}=y" .config; then
    echo "Required kernel option did not resolve: CONFIG_${option}" >&2
    exit 1
  fi
done
grep -E '^CONFIG_(ARM64_VA_BITS|ARM64_PA_BITS)=' .config

make ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" DTC="$DTC" -j"$JOBS" \
  Image "qcom/$DTS_NAME.dtb"

IMAGE="$KERNEL/arch/arm64/boot/Image"
DTB="$KERNEL/arch/arm64/boot/dts/qcom/$DTS_NAME.dtb"
RAMDISK="$OUT/initramfs.cpio.gz"
gzip -n -c "$KERNEL/usr/initramfs_data.cpio" > "$RAMDISK"
BOOTIMG_TOOL="$ROOT/build/edk2-msm/tools/mkbootimg.py"

python3 "$BOOTIMG_TOOL" \
  --kernel "$IMAGE" \
  --ramdisk "$RAMDISK" \
  --dtb "$DTB" \
  --header_version 2 \
  --pagesize 4096 \
  --base 0x80000000 \
  --kernel_offset 0 \
  --dtb_offset 0x01f00000 \
  --cmdline "console=ttyGS0,115200n8 loglevel=8 ignore_loglevel rdinit=/init" \
  --output "$OUT/boot-fuxi-mainline-test.img"

file "$IMAGE" "$DTB" "$OUT/boot-fuxi-mainline-test.img"
stat -c '%n %s bytes' "$IMAGE" "$DTB" "$RAMDISK" "$OUT/boot-fuxi-mainline-test.img"
echo "Built only. No device command was run."
