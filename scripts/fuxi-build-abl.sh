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
FUXI_DTB="${FUXI_DTB:-sm8550-xiaomi-fuxi-min}"   # 例：FUXI_DTB=sm8550-xiaomi-fuxi-disp（原生显示驱动变体）
# pm2 已实机验证；日常镜像默认带 CPU 调频/温控。FUXI_PM=0 仅用于对照诊断。
FUXI_PM="${FUXI_PM:-1}"
DTB="$K/arch/arm64/boot/dts/qcom/$FUXI_DTB.dtb"
BAIT_DTB="$B/build/edk2-msm/Platform/Xiaomi/sm8550/FdtBlob_compat/fuxi.dtb"
MAKE=(make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)")

# 同一个内核树的配置和内建 DTB 不能被两个构建同时修改。
exec 9>"$K/.fuxi-build.lock"
flock -n 9 || { echo "另一个 fuxi 构建正在使用 $K"; exit 1; }
W=$(mktemp -d)
cleanup() {
  if [ -f "$W/main.config" ]; then
    cp "$W/main.config" "$K/.config"
    touch "$K/.config"
  fi
  rm -rf "$W"
}
trap cleanup EXIT

if [ "${2:-}" != "--no-kernel" ]; then
  cd "$K"
  cp .config "$W/main.config"
  # 原生显示驱动变体（-disp）要 DRM_MSM + 面板驱动；主配置不能开（MSM 会抢走 -min 里的 MDSS 占位节点）。
  # 构建期间临时打开，结束后恢复主配置。
  # 音频变体（-audio）要 ALSA/ASoC + AudioReach + CS35L41（主 DTS 里 LPASS 宏默认是开的，先不进主配置）。
  # USB-C 变体（-usbc / -desk）要 UCSI + FSA4480 + dwc3 双角色 + xHCI。
  VARIANT_CFG=()
  DISP_CFG=(-e BACKLIGHT_CLASS_DEVICE -e DRM_MSM -e DRM_MSM_DPU -e DRM_MSM_DSI -e DRM_MSM_DSI_7NM_PHY -e DRM_PANEL_XIAOMI_FUXI
            -e DRM_MSM_MDSS -e QCOM_LLCC -d DRM_MSM_HDMI)
  USBC_CFG=(-e UCSI_PMIC_GLINK -e TYPEC_MUX_FSA4480 -e USB_DWC3_DUAL_ROLE -e USB_XHCI_HCD -e USB_XHCI_PLATFORM
            -e USB_STORAGE -e USB_UAS)
  AUDIO_CFG=(-e SOUND -e SND -e SND_SOC -e SND_SOC_QCOM -e SND_SOC_SC8280XP -e SND_SOC_QDSP6
              -e I2C -e I2C_QCOM_GENI -e QCOM_GENI_SE -e QCOM_GPI_DMA
              -e SND_SOC_CS35L41_I2C -e SND_SOC_TOPOLOGY -e QCOM_APR -e SOUNDWIRE -e SOUNDWIRE_QCOM
              -e SND_SOC_WCD938X_SDW -e SND_SOC_LPASS_RX_MACRO -e SND_SOC_LPASS_TX_MACRO -e SND_SOC_LPASS_VA_MACRO
              -e PINCTRL_LPASS_LPI -e PINCTRL_SM8550_LPASS_LPI -e SND_SOC_SIMPLE_MUX)
  case "$FUXI_DTB" in
    *-audio-disp) VARIANT_CFG=("${DISP_CFG[@]}" "${AUDIO_CFG[@]}" -d DRM_MSM_DP) ;;
    *-disp) VARIANT_CFG=("${DISP_CFG[@]}" -d DRM_MSM_DP) ;;
    *-usbc) VARIANT_CFG=("${USBC_CFG[@]}") ;;
    *-desk) VARIANT_CFG=("${DISP_CFG[@]}" "${USBC_CFG[@]}" -e DRM_MSM_DP) ;;
    *-audio*) VARIANT_CFG=("${AUDIO_CFG[@]}") ;;
    *-camera) VARIANT_CFG=(-e I2C_QCOM_CCI -e I2C_CHARDEV -e FUXI_CAMERA_POWER -e MEDIA_SUPPORT -e MEDIA_CAMERA_SUPPORT
              -e MEDIA_PLATFORM_SUPPORT -e V4L_PLATFORM_DRIVERS -e VIDEO_DEV -e VIDEO_QCOM_CAMSS) ;;
    *-sleep) VARIANT_CFG=(-e SUSPEND -e PM_SLEEP) ; FUXI_PM=1 ;;
    *-full) VARIANT_CFG=("${DISP_CFG[@]}" "${USBC_CFG[@]}" "${AUDIO_CFG[@]}" -e DRM_MSM_DP) ;;
  esac
  # FUXI_PM=1：调频 + 温控（qcom-cpufreq-hw/EPSS、schedutil、TSENS、PMIC 过温、LMh、CPU 与 GPU devfreq 降频冷却），任何变体都可叠加
  PM_CFG=(-e CPU_FREQ -e CPU_FREQ_STAT -e CPU_FREQ_DEFAULT_GOV_SCHEDUTIL -e CPU_FREQ_GOV_SCHEDUTIL -e CPU_FREQ_GOV_PERFORMANCE
          -e CPU_FREQ_GOV_POWERSAVE -e ARM_QCOM_CPUFREQ_HW -e ENERGY_MODEL -e THERMAL -e THERMAL_OF -e THERMAL_GOV_STEP_WISE
          -e CPU_THERMAL -e DEVFREQ_THERMAL -e NVMEM_QCOM_QFPROM -e QCOM_TSENS -e IIO -e QCOM_SPMI_TEMP_ALARM -e QCOM_LMH -e INTERCONNECT_QCOM_OSM_L3)
  [ "${FUXI_PM:-0}" = 1 ] && VARIANT_CFG+=("${PM_CFG[@]}")
  # FUXI_SUSPEND=1：在任意变体上叠加 s2idle 挂起（*-sleep 变体会顶掉 audio-disp 等配置，不能用来叠加）
  [ "${FUXI_SUSPEND:-0}" = 1 ] && VARIANT_CFG+=(-e SUSPEND -e PM_SLEEP)
  # FUXI_NET=1：叠加策略路由与 nftables 对象，供 Mihomo/Clash TUN 透明代理使用。
  # 主配置缺 IP_ADVANCED_ROUTER/IP_MULTIPLE_TABLES（ip rule / fwmark 表）和部分 NFT 对象
  # （NFT_REDIR、NF_TABLES_NETDEV、NFT_SOCKET、NFT_TPROXY），TUN auto-route 会报
  # "operation not supported"（10-30 实测）。任意变体可叠加。
  [ "${FUXI_NET:-0}" = 1 ] && VARIANT_CFG+=(-e IP_ADVANCED_ROUTER -e IP_MULTIPLE_TABLES -e IP_ROUTE_MULTIPATH
            -e NF_TABLES -e NF_TABLES_INET -e NF_TABLES_NETDEV -e NFT_NAT -e NFT_MASQ -e NFT_REDIR
            -e NFT_SOCKET -e NFT_TPROXY -e NETFILTER_XT_MARK -e NET_CLS_ACT -e NET_SCHED
            -e NF_CONNTRACK -e NF_NAT)
  if [ "${#VARIANT_CFG[@]}" -gt 0 ]; then
    ./scripts/config "${VARIANT_CFG[@]}"
    "${MAKE[@]}" olddefconfig >/dev/null
    # olddefconfig 会悄悄丢掉依赖不满足的选项（10-28：面板驱动缺 BACKLIGHT_CLASS_DEVICE，
    # 所有 disp/desk/full 镜像里其实都没有面板驱动）→ 要求的 -e 选项必须真的变成 y，否则报错
    miss=()
    for ((j = 0; j < ${#VARIANT_CFG[@]}; j++)); do
      [ "${VARIANT_CFG[j]}" = -e ] || continue
      o=${VARIANT_CFG[j+1]}
      grep -q "^CONFIG_$o=y" .config || miss+=("$o")
    done
    [ ${#miss[@]} -eq 0 ] || { echo "[config] 这些选项没能打开（依赖不满足）：${miss[*]}"; exit 1; }
  fi
  # 每次都按当前 .config 重新生成 auto.conf：olddefconfig 在配置没变时不改 .config 的时间戳，
  # 所以先 touch，强制 make 重跑 syncconfig，保证普通构建不会沿用上一个变体的 auto.conf
  touch .config
  "${MAKE[@]}" olddefconfig >/dev/null
  # initramfs 改动不会触发重新打包，每次都强制重建
  rm -f usr/initramfs_data.cpio usr/initramfs_data.cpio.gz
  echo "[kernel] make dtb → Image.gz（日志 $L/kbuild.log）"
  # 先单独编 DTB：内核用 .incbin 把它嵌进去
  { "${MAKE[@]}" "qcom/$FUXI_DTB.dtb" && "${MAKE[@]}" FUXI_DTB="$FUXI_DTB" Image.gz; } > "$L/kbuild.log" 2>&1 ||
    { grep -m5 -B2 -A3 'error' "$L/kbuild.log"; exit 1; }
  grep -q '^CONFIG_FUXI_FORCE_BUILTIN_DTB=y' .config || { echo "需要 CONFIG_FUXI_FORCE_BUILTIN_DTB=y"; exit 1; }
fi

# 镜像头里的 cmdline 只是记录（不生效），和内建 DTB 保持一致
CMDLINE=$(fdtget "$DTB" /chosen bootargs | sed 's/ *$//')
cat "$K/arch/arm64/boot/Image.gz" "$BAIT_DTB" > "$W/kernel-dtb"
: > "$W/ramdisk"
OUT="$B/work/kbuild/abl-fuxi-$NAME.img"
if [ "${2:-}" = "--no-kernel" ]; then
  for suffix in config dtb build.json; do
    [ ! -e "${OUT%.img}.$suffix" ] || {
      echo "--no-kernel 不能覆盖有构建记录的镜像，请使用新名字或重新编译"
      exit 1
    }
  done
fi
python3 "$B/build/edk2-msm/tools/mkbootimg.py" \
  --header_version 1 --os_version 13.0.0 --os_patch_level 2022-11 \
  --kernel "$W/kernel-dtb" --ramdisk "$W/ramdisk" \
  --base 0x0 --kernel_offset 0x00000000 --ramdisk_offset 0x01000000 --tags_offset 0x00000100 \
  --pagesize 4096 --cmdline "${CMDLINE:0:500}" -o "$OUT"
# 保存本次真正使用的配置，而非退出时恢复的主配置。避免只凭镜像名字判断功能。
if [ "${2:-}" != "--no-kernel" ]; then
  cp "$K/.config" "${OUT%.img}.config"
  cp "$DTB" "${OUT%.img}.dtb"
  python3 - "$OUT" "$K" "$FUXI_DTB" "$FUXI_PM" "$BAIT_DTB" <<'PY'
import datetime
import hashlib
import json
import pathlib
import subprocess
import sys

out, kernel, dtb_name, pm, bait = sys.argv[1:]
out, kernel = pathlib.Path(out), pathlib.Path(kernel)
files = {
    "boot_image": out,
    "config": out.with_suffix(".config"),
    "builtin_dtb": out.with_suffix(".dtb"),
    "kernel_image_gz": kernel / "arch/arm64/boot/Image.gz",
    "abl_dtb": pathlib.Path(bait),
}
record = {
    "built_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "dtb": dtb_name,
    "power_management_requested": pm == "1",
    "kernel_commit": subprocess.check_output(
        ["git", "-C", str(kernel), "rev-parse", "HEAD"], text=True
    ).strip(),
    "kernel_branch": subprocess.check_output(
        ["git", "-C", str(kernel), "rev-parse", "--abbrev-ref", "HEAD"], text=True
    ).strip(),
    "kernel_tracked_changes": bool(subprocess.check_output(
        ["git", "-C", str(kernel), "status", "--porcelain", "--untracked-files=no"], text=True
    ).strip()),
    "sha256": {key: hashlib.sha256(path.read_bytes()).hexdigest()
               for key, path in files.items()},
}
# 可复现性指纹：记录 dirty diff 的 sha256 与未跟踪文件清单，
# 避免两份不同工作树生成一模一样的 build.json（旧版只有布尔值）。
_dirty = subprocess.run(["git", "-C", str(kernel), "diff", "HEAD"],
                        capture_output=True, text=True).stdout
_untracked = subprocess.run(["git", "-C", str(kernel), "ls-files", "--others",
                             "--exclude-standard"],
                            capture_output=True, text=True).stdout.splitlines()
record["kernel_dirty_diff_sha256"] = (
    hashlib.sha256(_dirty.encode()).hexdigest() if _dirty.strip() else "")
record["kernel_untracked_files"] = _untracked[:200]
record["kernel_untracked_count"] = len(_untracked)
record["kernel_clean"] = (not _dirty.strip()) and not _untracked
out.with_suffix(".build.json").write_text(json.dumps(record, indent=2) + "\n")
PY
fi
echo "[ok] $OUT $(stat -c %s "$OUT") bytes; Image $(stat -c %s "$K/arch/arm64/boot/Image") bytes"
echo "[cmdline] $CMDLINE"
