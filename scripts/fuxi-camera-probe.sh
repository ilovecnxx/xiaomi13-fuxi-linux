#!/bin/bash
# 相机第一步：逐个给 4 个模组上电，在对应 CCI 总线上扫地址、读常见的传感器 ID 寄存器，确定传感器型号。
#   镜像 abl-fuxi-camera1（sm8550-xiaomi-fuxi-camera.dts + CONFIG_FUXI_CAMERA_POWER/I2C_QCOM_CCI/I2C_CHARDEV）
#   ID 寄存器：索尼 0x0016（2 字节 model id），三星 S5K 0x0000（2 字节），豪威 0x300a..0x300c（3 字节），格科 0x03f0（2 字节）
#   每个模组：echo 1 > power → 扫描 → echo 0 > power。只读寄存器（写的是 2 字节寄存器地址）。
# 用法: scripts/fuxi-camera-probe.sh [镜像]（手机先在 Android 或 Ubuntu 都行）
set -u
B="$(cd "$(dirname "$0")/.." && pwd)"
IMG="${1:-$B/work/kbuild/abl-fuxi-camera2.img}"
LOG="$B/work/claude-logs/camera-probe-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
say() { echo "$(date +%T) $*"; }
ssh_() { timeout "${T:-120}" "$B/scripts/fuxi-ssh.sh" "$@"; }

. "$B/scripts/fuxi-lib.sh"
say "== 0. Android 里的相机模组库（文件名一般带传感器型号），只读列出并拉取"
fuxi_ensure_android || exit 1
mkdir -p "$B/work/device-info/camera"
timeout 60 "$FUXI_ADB" shell 'ls /vendor/lib64/camera /odm/lib64/camera 2>/dev/null | grep -iE "sensormodule|sensor|eeprom|ois|actuator" | sort -u' | tr -d '\r' | tee "$B/work/device-info/camera/android-modules.txt"
for f in $(timeout 60 "$FUXI_ADB" shell 'ls /vendor/lib64/camera/*sensormodule* /odm/lib64/camera/*sensormodule* 2>/dev/null' | tr -d '\r'); do
  timeout 60 "$FUXI_ADB" pull "$f" "$B/work/device-info/camera/" >/dev/null 2>&1
done
ls "$B/work/device-info/camera" | head -n 40

say "== 1. 进 Ubuntu（$IMG）"
FUXI_KEEP=1 "$B/scripts/fuxi-test-recovery.sh" "$IMG" 'uname -v' | grep -vE 'pushed' || { say "FAIL 没进 Ubuntu"; exit 1; }

say "== 2. 扫描"
T=900 ssh_ 'command -v i2ctransfer >/dev/null || DEBIAN_FRONTEND=noninteractive apt-get install -y i2c-tools 2>&1 | tail -n 1
modprobe i2c-dev 2>/dev/null
bus_of() {  # $1 = cci 基址（ac15000/ac16000），$2 = 主机号 → i2c 总线号
  for d in /sys/bus/i2c/devices/i2c-*; do
    p=$(readlink -f $d/of_node 2>/dev/null) || continue
    case "$p" in */cci@$1/i2c-bus@$2) basename $d | cut -d- -f2; return;; esac
  done
}
rd() {  # bus addr reg_hi reg_lo n
  i2ctransfer -y $1 w2@$2 $3 $4 r$5 2>/dev/null
}
for m in "cam0 主摄 ac15000 1" "cam2 超广角 ac15000 0" "cam1 前摄 ac16000 1" "cam3 长焦 ac16000 0"; do
  set -- $m
  node=$(ls -d /sys/bus/platform/devices/camera-power-$1 2>/dev/null)
  bus=$(bus_of $3 $4)
  echo "======== $1（$2）CCI $3 主机$4 → i2c-$bus，电源 $node"
  [ -n "$node" ] && [ -n "$bus" ] || { echo "缺电源节点或总线"; continue; }
  echo 1 > $node/power_on || { echo "上电失败"; dmesg | tail -n 5; continue; }
  sleep 0.05
  for a in $(seq 8 119); do
    x=$(printf "0x%02x" $a)
    r=$(rd $bus $x 0x00 0x00 2) || continue
    echo "  地址 $x 有应答：[0x0000]=$r  [0x0016]=$(rd $bus $x 0x00 0x16 2)  [0x300a]=$(rd $bus $x 0x30 0x0a 3)  [0x03f0]=$(rd $bus $x 0x03 0xf0 2)"
  done
  echo 0 > $node/power_on
done
echo "--- CAMSS"; ls /dev/media* /dev/v4l-subdev* 2>&1 | head -n 5
echo "--- dmesg"; dmesg | grep -iE "cci|camera-power|camcc|camss|csiphy" | tail -n 30'
say "完成，日志 $LOG（把 ID 对照传感器型号，记到 docs/相机调研.md）"
