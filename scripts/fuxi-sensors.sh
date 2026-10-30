#!/bin/bash
# 传感器第一步：让 ADSP 上的传感器子系统（SSC，sensorspd）能读到它的配置文件。
# 主线做法：hexagonrpcd 通过 FastRPC（/dev/fastrpc-adsp，内核 CONFIG_QCOM_FASTRPC）给 DSP 提供文件，
# 文件取自 Android（只读复制），Ubuntu 包 hexagonrpcd 的默认根目录是 /var/lib/droid-juicer/sensors/：
#   acdb/                ← /vendor/etc/acdbdata（音频校准数据，以后音频也可能用到）
#   dsp/                 ← /vendor/dsp（DSP 侧动态库）
#   sensors/config/      ← /vendor/etc/sensors/config
#   sensors/registry/    ← /mnt/vendor/persist/sensors/registry/registry（本机传感器标定，persist 分区只读复制）
#   sensors/sns_reg.conf ← /vendor/etc/sensors/sns_reg_config
#   sensors/odm-config/  ← /odm/etc/sensors/config
#   sensors/sns_reg_version ← /mnt/vendor/persist/sensors/registry/sns_reg_version
#   socinfo/             ← Android /sys/devices/soc0 的只读快照（虚拟文件系统不会直接读主机 sysfs）
# libssc-bin 提供 ssccli；桌面集成通过 fuxi-sensors-proxy.sh 安装设备规则和就绪等待，
# 仅在已安装的 iio-sensor-proxy 缺少 SSC 支持时重编该包。
# 用法: scripts/fuxi-sensors.sh [镜像，默认 work/kbuild/abl-fuxi-daily-pm1.img]
#       scripts/fuxi-sensors.sh --deploy-only （手机已在 Linux，使用已采集的文件）
set -euo pipefail
B="$(cd "$(dirname "$0")/.." && pwd)"
ADB="$B/tools/platform-tools/adb"
IMG="${1:-$B/work/kbuild/abl-fuxi-daily-pm1.img}"
DEPLOY_ONLY=0
[ "$IMG" != --deploy-only ] || DEPLOY_ONLY=1
LOG="$B/work/claude-logs/sensors-$(date +%Y%m%d-%H%M%S).log"
S="$B/work/firmware-sensors"
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1
say() { echo "$(date +%T) $*"; }
. "$B/scripts/fuxi-lib.sh"
ssh_() { timeout "${T:-120}" "$B/scripts/fuxi-ssh.sh" "$@"; }

if [ "$DEPLOY_ONLY" = 0 ]; then
say "== 1. 从 Android 只读拉取（保留修改时间）"
fuxi_ensure_android || exit 1
mkdir -p "$S/sensors" "$S/socinfo"
pull() { timeout 600 "$ADB" pull -a "$1" "$2" >/dev/null 2>&1 && say "pulled $1"; }
[ -d "$S/acdb" ] || pull /vendor/etc/acdbdata "$S/acdb"
[ -d "$S/dsp" ] || pull /vendor/dsp "$S/dsp"
# 用新快照目录，避免 adb pull 到已有目录时多套一层 config/；保留快照供追溯。
SNAP=$(mktemp -d "$B/work/firmware-sensors-copy.XXXXXX")
pull /vendor/etc/sensors/config "$SNAP/config"
pull /odm/etc/sensors/config "$SNAP/odm-config"
pull /mnt/vendor/persist/sensors/registry/registry "$SNAP/registry"
for part in config odm-config registry; do
  mkdir -p "$S/sensors/$part"
  cp -a "$SNAP/$part/." "$S/sensors/$part/"
done
pull /vendor/etc/sensors/sns_reg_config "$S/sensors/sns_reg.conf"
pull /mnt/vendor/persist/sensors/registry/sns_reg_version "$S/sensors/sns_reg_version"
for name in hw_platform platform_subtype platform_subtype_id platform_version soc_id revision; do
  timeout 10 "$ADB" exec-out cat "/sys/devices/soc0/$name" > "$S/socinfo/$name"
done
say "大小 $(du -sh "$S" | cut -f1)；传感器配置 $(ls "$S/sensors/config" 2>/dev/null | wc -l) 个"

say "== 2. 进 Ubuntu"
FUXI_KEEP=1 "$B/scripts/fuxi-test-recovery.sh" "$IMG" 'uname -v' | grep -vE 'pushed' || { say "FAIL 没进 Ubuntu"; exit 1; }
fi

say "== 3. 部署 + hexagonrpcd"
for file in socinfo/soc_id socinfo/hw_platform sensors/sns_reg.conf sensors/sns_reg_version sensors/registry/sns_reg_config; do
  [ -s "$S/$file" ] || { say "FAIL 缺少 $S/$file"; exit 1; }
done
T=600 ssh_ 'set -e; DEBIAN_FRONTEND=noninteractive apt-get install -y hexagonrpcd libssc-bin qrtr-tools; install -d /root/fuxi-mainline-backup; touch /root/fuxi-mainline-backup/CHANGES.txt'
"$B/scripts/fuxi-build-hexagonrpc.sh"
# 必须保留 mtime：SNS 用 sns_reg_config 中的时间戳判断配置是否变化。
tar -C "$S" -cf - acdb dsp sensors socinfo | T=600 ssh_ 'set -e; systemctl stop hexagonrpcd; mkdir -p /var/lib/droid-juicer/sensors; tar --no-same-owner -C /var/lib/droid-juicer/sensors -xf -
# Android registry 文件常为 0600，复制后允许专用 fastrpc 用户读，不向其他用户开放。
chown -R root:fastrpc /var/lib/droid-juicer/sensors
find /var/lib/droid-juicer/sensors -type d -exec chmod 750 {} +
find /var/lib/droid-juicer/sensors -type f -exec chmod 640 {} +
# 日常视图使用 Android 已生成的标定注册表，不让只读 API 重新生成注册表。
install -d -m 755 /var/lib/fuxi-sensors-prebuilt/sensors/config /var/lib/fuxi-sensors-prebuilt/sensors/odm-config
for name in acdb dsp socinfo; do
  ln -sfnT /var/lib/droid-juicer/sensors/$name /var/lib/fuxi-sensors-prebuilt/$name
done
for name in registry sns_reg.conf sns_reg_version; do
  ln -sfnT /var/lib/droid-juicer/sensors/sensors/$name /var/lib/fuxi-sensors-prebuilt/sensors/$name
done
echo files-ok'
cat "$B/work/kbuild/hexagonrpc/hexagonrpcd-fuxi" | ssh_ 'set -e; mkdir -p /usr/local/libexec; cat > /usr/local/libexec/hexagonrpcd-fuxi; chmod 755 /usr/local/libexec/hexagonrpcd-fuxi'
cat "$B/work/rootfs-overlay/etc/systemd/system/hexagonrpcd.service.d/20-fuxi.conf" | ssh_ 'set -e; mkdir -p /etc/systemd/system/hexagonrpcd.service.d; cat > /etc/systemd/system/hexagonrpcd.service.d/20-fuxi.conf'
T=600 ssh_ 'set -e
grep -q droid-juicer /root/fuxi-mainline-backup/CHANGES.txt || echo "fuxi-mainline（传感器）: /var/lib/droid-juicer/sensors（Android acdb/dsp/sensors 只读拷贝）；apt: hexagonrpcd" >> /root/fuxi-mainline-backup/CHANGES.txt
ls -l /dev/fastrpc-* 2>&1
systemctl daemon-reload
systemctl enable hexagonrpcd 2>&1 | tail -n 1; systemctl restart hexagonrpcd
systemctl --no-pager -l status hexagonrpcd | tail -n 15
echo "--- dmesg"; dmesg | grep -iE "fastrpc|sensor|ssc|slpi" | tail -n 20'
"$B/scripts/fuxi-sensors-proxy.sh"
say "== 4. 读传感器（libssc 自带的 ssccli；请拿起手机转一转、用手遮一下屏幕顶部）"
notify-send fuxi "传感器测试：转动手机、遮挡听筒附近 20 秒" 2>/dev/null || true
T=200 ssh_ 'set -eu
failed=0
for s in accelerometer proximity light magnetometer compass; do
  echo "--- $s"
  output=$(timeout 12 ssccli --sensor "$s" --timeout 6 2>&1) || failed=1
  printf "%s\n" "$output"
  # ssccli 0.4.4 在服务缺失时也可能返回 0，不能仅凭退出码记作测试成功。
  if ! printf "%s\n" "$output" | grep -q "sensor measurement:"; then
    failed=1
  fi
done
[ "$failed" -eq 0 ]'
say "完成，日志 $LOG"
