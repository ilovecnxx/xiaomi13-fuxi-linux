#!/bin/bash
# 将已可用的 SSC 接到桌面：设备专用 udev 类型 + 有界的 QRTR 就绪等待。
# 仅当已安装包缺少 libssc 时重编 Ubuntu 3.9；--rebuild 可显式要求重编。
# 前提：手机在 Linux，已部署 Android 文件副本和 hexagonrpcd。
set -euo pipefail
B="$(cd "$(dirname "$0")/.." && pwd)"
case "${1:-}" in '') rebuild=0;; --rebuild) rebuild=1;; *) echo "用法: $0 [--rebuild]" >&2; exit 2;; esac
[ "$#" -le 1 ] || exit 2
mkdir -p "$B/work/claude-logs"
LOG="$B/work/claude-logs/sensors-proxy-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
say() { echo "$(date +%T) $*"; }
ssh_() { timeout "${T:-120}" "$B/scripts/fuxi-ssh.sh" "$@"; }

say '== 1. 检查桌面代理的 SSC 支持'
ssc_support=$(ssh_ 'if ldd /usr/libexec/iio-sensor-proxy 2>/dev/null | grep -q "libssc\.so"; then echo yes; else echo no; fi')
if [ "$ssc_support" != yes ] || [ "$rebuild" = 1 ]; then
  say '== 重编 iio-sensor-proxy（保留既有构建目录）'
  tar -C "$B/work/src/iio-sensor-proxy" -cf - iio-sensor-proxy_3.9.orig.tar.bz2 iio-sensor-proxy_3.9-1ubuntu1.debian.tar.xz | T=3600 ssh_ 'bash -euo pipefail -c '\''
    install -d /root/build /root/fuxi-mainline-backup
    stage=$(mktemp -d /root/build/iio-sensor-proxy.XXXXXX)
    tar -C "$stage" -xf -
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y --no-install-recommends build-essential debhelper fakeroot dpkg-dev meson pkgconf libgudev-1.0-dev systemd-dev libpolkit-gobject-1-dev libssc-dev locales-all gtk-doc-tools libgtk-3-dev < /dev/null
    cd "$stage"
    tar xf iio-sensor-proxy_3.9.orig.tar.bz2
    cd iio-sensor-proxy-3.9
    tar xf ../iio-sensor-proxy_3.9-1ubuntu1.debian.tar.xz
    sed -i "s/^# ARCHES_QCOM_SSC = arm64/ARCHES_QCOM_SSC = arm64/" debian/rules
    grep -q "^ARCHES_QCOM_SSC = arm64" debian/rules
    DEB_BUILD_OPTIONS=nocheck dpkg-buildpackage -b -uc -us -d > "$stage/build.log" 2>&1 || { tail -n 60 "$stage/build.log"; exit 1; }
    cd "$stage"
    dpkg -i iio-sensor-proxy_*_arm64.deb
    ldd /usr/libexec/iio-sensor-proxy | grep "libssc\.so"
    apt-mark hold iio-sensor-proxy
    touch /root/fuxi-mainline-backup/CHANGES.txt
    grep -q "iio-sensor-proxy（SSC）" /root/fuxi-mainline-backup/CHANGES.txt || echo "fuxi-mainline（传感器）: iio-sensor-proxy 3.9 重编（ssc-support=enabled），apt-mark hold" >> /root/fuxi-mainline-backup/CHANGES.txt
    echo "build directory: $stage"
  '\'''
else
  say '已安装的 iio-sensor-proxy 支持 SSC，复用该包'
fi

say '== 2. 部署桌面规则与服务就绪检测'
tar -C "$B/work/rootfs-overlay" -cf - \
  etc/udev/rules.d/81-fuxi-ssc.rules \
  etc/systemd/system/iio-sensor-proxy.service.d/20-fuxi-ssc.conf \
  usr/local/libexec/fuxi-wait-ssc | ssh_ 'set -e
    tar -C / -xf -
    chmod 755 /usr/local/libexec/fuxi-wait-ssc
    systemctl daemon-reload
    udevadm control --reload-rules
    udevadm trigger --action=change /sys/class/misc/fastrpc-adsp
    udevadm settle --timeout=10
    systemctl restart iio-sensor-proxy
    systemctl is-active iio-sensor-proxy'
say '== 3. 验证桌面探测结果（异步探测最多等待 15 秒）'
ssh_ 'set -e
  for attempt in $(seq 1 15); do
    ready=1
    for property in HasAccelerometer HasAmbientLight HasProximity; do
      value=$(busctl get-property net.hadess.SensorProxy /net/hadess/SensorProxy net.hadess.SensorProxy "$property")
      [ "$value" = "b true" ] || ready=0
    done
    [ "$ready" = 0 ] || break
    sleep 1
  done
  [ "$ready" = 1 ] || { echo "FAIL: desktop sensors missing"; exit 1; }
  for property in HasAccelerometer HasAmbientLight HasProximity; do
    printf "%s: " "$property"
    busctl get-property net.hadess.SensorProxy /net/hadess/SensorProxy net.hadess.SensorProxy "$property"
  done
  timeout 6 stdbuf -oL monitor-sensor --all || test "$?" = 124'
say "完成，日志 $LOG"
