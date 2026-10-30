#!/bin/bash
# M5.2：手机回到 Android 后一条命令跑完 WiFi + 蓝牙的部署与验证（手机最终留在 Ubuntu）。
#   1. 等 Android（最长 WAIT_ANDROID 秒，默认 1 小时；手机在 Ubuntu 会先重启回 Android），adb root，只读拉取蓝牙固件 /vendor/bt_firmware/image/hmt*
#   2. 生成固件目录（scripts/fuxi-wcn7850-firmware.sh）
#   3. 写 recovery_b 并重启进 Ubuntu（scripts/fuxi-test-recovery.sh，FUXI_KEEP=1）
#   4. 部署固件、work/rootfs-overlay（fuxi-firmware-devices.service 取代 fuxi-remoteproc.service），
#      NetworkManager 不接管 usb0，apt 装 iw/wireless-regdb/bluez/wpasupplicant/network-manager
#   5. 启动服务，检查 ADSP、wlan0（扫描）、hci0
# 用法: scripts/fuxi-m5-wifi-bt.sh [镜像，默认 work/kbuild/abl-fuxi-s2idle2.img]
# 日志: work/claude-logs/m5-wifi-bt-<时间>.log
set -u
B="$(cd "$(dirname "$0")/.." && pwd)"
ADB="$B/tools/platform-tools/adb"
IMG="${1:-$B/work/kbuild/abl-fuxi-s2idle2.img}"
LOG="$B/work/claude-logs/m5-wifi-bt-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
say() { echo "$(date +%T) $*"; }
. "$B/scripts/fuxi-lib.sh"
ssh_() { timeout "${T:-120}" "$B/scripts/fuxi-ssh.sh" "$@"; }

say "== 1. 等 Android"
fuxi_ensure_android || exit 1
mkdir -p "$B/work/firmware-src/bt"
say "蓝牙固件目录: $(timeout 20 "$ADB" shell 'ls /vendor/bt_firmware/image 2>&1 | tr "\n" " "')"
for f in $(timeout 20 "$ADB" shell 'cd /vendor/bt_firmware/image 2>/dev/null && ls | grep -i "^hmt"' | tr -d '\r'); do
  timeout 30 "$ADB" pull "/vendor/bt_firmware/image/$f" "$B/work/firmware-src/bt/" >/dev/null && say "pulled $f"
done

say "== 2. 固件目录"
"$B/scripts/fuxi-wcn7850-firmware.sh"

say "== 3. 写 recovery_b 并进 Ubuntu"
FUXI_KEEP=1 "$B/scripts/fuxi-test-recovery.sh" "$IMG" 'uname -v' | grep -vE 'pushed' || { say "FAIL 没进 Ubuntu"; exit 1; }

say "== 4. 部署"
tar -C "$B/work/firmware" -cf - . | ssh_ 'tar -C /lib/firmware -xmf - && echo firmware-ok'
# Android 的 regdb.bin 会让上游固件崩（见 fuxi-wcn7850-firmware.sh）；旧部署留下的改名备查，不删
ssh_ 'd=/lib/firmware/ath12k/WCN7850/hw2.0; [ -e $d/regdb.bin ] && mv $d/regdb.bin $d/regdb.bin.android; true'
tar -C "$B/work/rootfs-overlay" -cf - . | ssh_ 'tar --no-same-owner --no-overwrite-dir -C / -xmf - && chmod 755 /usr/local/sbin/fuxi-firmware-devices && echo overlay-ok'
ssh_ 'set -e
mkdir -p /etc/NetworkManager/conf.d
printf "%s\n" "# fuxi：usb0 由 fuxi-usbnet.service 配静态 10.42.0.2（主机共享连接），NetworkManager 别接管" "[keyfile]" "unmanaged-devices=interface-name:usb0" > /etc/NetworkManager/conf.d/10-fuxi-usb0.conf
systemctl disable fuxi-remoteproc.service 2>/dev/null || true
systemctl daemon-reload
systemctl enable fuxi-firmware-devices.service fuxi-wifi-regdom.service
[ -s /etc/fuxi/bt-address ] && systemctl enable fuxi-bt-address.service
grep -q fuxi-firmware-devices /root/fuxi-mainline-backup/CHANGES.txt || echo "fuxi-mainline 第十一次（M5.2）: /lib/firmware/{ath12k,qca}；fuxi-firmware-devices.service 取代 fuxi-remoteproc.service；NetworkManager conf.d/10-fuxi-usb0.conf；apt: iw wireless-regdb bluez rfkill wpasupplicant network-manager" >> /root/fuxi-mainline-backup/CHANGES.txt
echo deploy-ok'
T=900 ssh_ 'DEBIAN_FRONTEND=noninteractive apt-get install -y iw wireless-regdb bluez rfkill wpasupplicant network-manager 2>&1 | tail -n 3'

say "== 5. 启动并检查"
T=180 ssh_ 'systemctl restart fuxi-firmware-devices.service; journalctl -u fuxi-firmware-devices -b --no-pager -o cat | tail -n 6; sleep 15
echo "--- remoteproc"; for r in /sys/class/remoteproc/*; do echo "$(cat $r/name) $(cat $r/state)"; done
echo "--- 网卡"; ip -br link
echo "--- iw"; iw dev 2>&1 | head -n 12
w=$(iw dev 2>/dev/null | awk "/Interface/{print \$2; exit}")
if [ -n "$w" ]; then ip link set "$w" up; sleep 2; echo "--- 扫描 $w: $(iw dev "$w" scan 2>&1 | grep -c "SSID:") 个 SSID"; iw dev "$w" scan 2>/dev/null | grep "SSID:" | sort | uniq -c | sort -rn | head -n 8; fi
echo "--- 蓝牙"; ls /sys/class/bluetooth 2>&1; timeout 20 bluetoothctl show 2>&1 | head -n 8
echo "--- dmesg"; dmesg | grep -iE "ath12k|bluetooth: hci0|qca|regulatory|cfg80211" | grep -viE "registered|initialized|socket layer" | tail -n 25'
say "完成，日志 $LOG"
