#!/bin/bash
# 把本机真实的蓝牙/WiFi MAC 地址从 Android 读出来，配到主线 Ubuntu：
#   蓝牙：WCN7850 控制器没有出厂地址 → hci0 "Unconfigured"、开不了 → /etc/fuxi/bt-address + fuxi-bt-address.service
#   WiFi：ath12k 用的是高通占位地址 00:03:7f:… → /etc/systemd/network/10-fuxi-wlan.link 固定成本机地址
# 地址只存在本机 work/device-info/radio-addresses.txt（设备标识，不要发布）。
# 用法: scripts/fuxi-radio-addresses.sh [镜像，默认 work/kbuild/abl-fuxi-daily-pm1.img]
set -u
B="$(cd "$(dirname "$0")/.." && pwd)"
IMG="${1:-$B/work/kbuild/abl-fuxi-daily-pm1.img}"
. "$B/scripts/fuxi-lib.sh"
ADB="$FUXI_ADB"
LOG="$B/work/claude-logs/radio-addresses-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
say() { echo "$(date +%T) $*"; }
ssh_() { timeout "${T:-120}" "$B/scripts/fuxi-ssh.sh" "$@"; }
mac_ok() { echo "$1" | grep -qiE '^([0-9a-f]{2}:){5}[0-9a-f]{2}$' && [ "$1" != "00:00:00:00:00:00" ] && [ "$1" != "02:00:00:00:00:00" ]; }

say "== 1. Android 里读地址"
fuxi_ensure_android || exit 1
bt=$(timeout 20 "$ADB" shell 'settings get secure bluetooth_address 2>/dev/null' < /dev/null | tr -d '\r' | tr 'a-f' 'A-F')
mac_ok "$bt" || bt=$(timeout 20 "$ADB" shell 'getprop persist.vendor.service.bdroid.bdaddr; getprop ro.boot.btmacaddr' < /dev/null | tr -d '\r' | grep -m1 -iE '([0-9a-f]{2}:){5}' | tr 'a-f' 'A-F')
wl=$(timeout 20 "$ADB" shell 'cat /mnt/vendor/persist/wlan_mac.bin 2>/dev/null | grep -m1 -i "Intf0MacAddress" | cut -d= -f2' < /dev/null | tr -d '\r\n' | sed 's/../&:/g; s/:$//' | tr 'A-F' 'a-f')
mac_ok "$wl" || wl=$(timeout 20 "$ADB" shell 'getprop ro.boot.wifimacaddr; cat /sys/class/net/wlan0/address 2>/dev/null' < /dev/null | tr -d '\r' | grep -m1 -iE '([0-9a-f]{2}:){5}' | tr 'A-F' 'a-f')
mac_ok "$bt" && say "蓝牙地址已读到（${bt:0:8}:…）" || { say "WARN 没读到蓝牙地址"; bt=""; }
mac_ok "$wl" && say "WiFi 地址已读到（${wl:0:8}:…）" || { say "WARN 没读到 WiFi 地址"; wl=""; }
mkdir -p "$B/work/device-info"
printf 'bt=%s\nwlan=%s\n' "$bt" "$wl" > "$B/work/device-info/radio-addresses.txt"; chmod 600 "$B/work/device-info/radio-addresses.txt"

say "== 2. 进 Ubuntu（$IMG）并部署"
FUXI_KEEP=1 "$B/scripts/fuxi-test-recovery.sh" "$IMG" 'uname -v' | grep -vE 'pushed' || { say "FAIL 没进 Ubuntu"; exit 1; }
tar -C "$B/work/rootfs-overlay" -cf - usr/local/sbin/fuxi-bt-address etc/systemd/system/fuxi-bt-address.service | ssh_ 'tar --no-same-owner --no-overwrite-dir -C / -xmf - && chmod 755 /usr/local/sbin/fuxi-bt-address && echo overlay-ok'
ssh_ "mkdir -p /etc/fuxi
[ -n '$bt' ] && echo '$bt' > /etc/fuxi/bt-address
[ -n '$wl' ] && printf '%s\n' '# fuxi：ath12k 默认用高通占位地址，固定成本机 WiFi 地址（取自 Android）' '[Match]' 'Driver=ath12k_wifi7_pci' '' '[Link]' 'MACAddress=$wl' 'NamePolicy=kernel database onboard slot path' > /etc/systemd/network/10-fuxi-wlan.link
grep -q fuxi-bt-address /root/fuxi-mainline-backup/CHANGES.txt || echo 'fuxi-mainline（M5.2）: /etc/fuxi/bt-address + fuxi-bt-address.service（蓝牙公用地址）；/etc/systemd/network/10-fuxi-wlan.link（WiFi MAC）' >> /root/fuxi-mainline-backup/CHANGES.txt
systemctl daemon-reload; systemctl enable fuxi-bt-address.service 2>&1 | tail -n 1
systemctl restart fuxi-bt-address.service; sleep 3
journalctl -u fuxi-bt-address -b --no-pager -o cat | tail -n 3
timeout 10 bluetoothctl power on 2>&1 | tail -n 1
timeout 25 bluetoothctl --timeout 15 scan on > /tmp/bt.txt 2>&1; echo \"蓝牙扫到设备数: \$(grep -c 'NEW.*Device' /tmp/bt.txt)\"
timeout 10 bluetoothctl show 2>&1 | grep -E 'Powered|Discovering'"
say "完成，日志 $LOG（WiFi MAC 的 .link 下次开机生效）"
