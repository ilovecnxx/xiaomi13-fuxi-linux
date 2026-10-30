#!/bin/bash
# M5.4（基带）：手机在 Android 时一条命令跑完基带的部署与首次启动（手机最终留在 Ubuntu）。
#   1. 等 Android，adb root，只读拉取：modem 分区 image/ 里的 modem.*、modem_dtb.*、ipa_fws.*、modem_pr/（运营商配置），
#      以及 modemst1/modemst2/fsg/fsc 的只读 dd 拷贝（IMEI、射频校准；失败就用 backups/20261024-172623/）
#   2. 写 recovery_b（基带变体镜像）并进 Ubuntu（FUXI_KEEP=1）
#   3. 部署固件、EFS 副本（/var/lib/fuxi-rmtfs）、rootfs-overlay（含 rmtfs 文件模式 drop-in）；
#      apt 安装期间用 policy-rc.d 禁止服务自启（防止 rmtfs 用发行版默认的 -P 碰真分区）
#   4. bind IPA → 启动 tqftpserv、rmtfs（由它启动基带）→ 检查 remoteproc、ModemManager、SIM
# 用法: scripts/fuxi-m5-modem.sh [镜像，默认 work/kbuild/abl-fuxi-modem4.img]
# 日志: work/claude-logs/m5-modem-<时间>.log
set -u
B="$(cd "$(dirname "$0")/.." && pwd)"
ADB="$B/tools/platform-tools/adb"
IMG="${1:-$B/work/kbuild/abl-fuxi-modem4.img}"
LOG="$B/work/claude-logs/m5-modem-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
say() { echo "$(date +%T) $*"; }
. "$B/scripts/fuxi-lib.sh"
ssh_() { timeout "${T:-120}" "$B/scripts/fuxi-ssh.sh" "$@"; }
FW="$B/work/firmware-modem"           # 单独放，不进 work/firmware（太大，WiFi 脚本每次都会整包推）
EFS="$B/work/efs-copy"
D=qcom/sm8550/xiaomi/fuxi

say "== 1. 等 Android，拉固件与 EFS 拷贝"
fuxi_ensure_android || exit 1
mkdir -p "$FW/$D" "$EFS"
for dir in /vendor/firmware_mnt/image /vendor/firmware; do
  for f in $(timeout 30 "$ADB" shell "cd $dir 2>/dev/null && ls | grep -E '^(modem|modem_dtb|ipa_fws)\.(mdt|b[0-9]+|mbn)\$'" | tr -d '\r'); do
    [ -f "$FW/$D/$f" ] || timeout 120 "$ADB" pull "$dir/$f" "$FW/$D/" >/dev/null
  done
done
if [ ! -d "$FW/$D/modem_pr" ]; then
  timeout 600 "$ADB" pull /vendor/firmware_mnt/image/modem_pr "$FW/$D/" >/dev/null 2>&1 || say "WARN 没拉到 modem_pr（运营商配置）"
fi
say "基带固件: $(cd "$FW/$D" && ls | grep -vE '\.b[0-9]+$' | tr '\n' ' ')；$(du -sh "$FW" | cut -f1)"
for x in modem.mdt modem_dtb.mdt ipa_fws.mdt; do [ -f "$FW/$D/$x" ] || say "WARN 缺 $x（DTS 里 firmware-name 要跟着改）"; done
# EFS：只读 dd（if= 分区 → 手机 /data/local/tmp → pull），文件名按 rmtfs 文件模式的命名
for p in modemst1:modem_fs1 modemst2:modem_fs2 fsg:modem_fsg fsc:modem_fsc; do
  part=${p%%:*}; name=${p##*:}
  if timeout 60 "$ADB" shell "dd if=/dev/block/by-name/$part of=/data/local/tmp/$name bs=1M 2>/dev/null" &&
     timeout 60 "$ADB" pull "/data/local/tmp/$name" "$EFS/$name" >/dev/null; then
    timeout 20 "$ADB" shell "rm -f /data/local/tmp/$name"
  else
    say "WARN $part 只读拷贝失败，用 10-24 备份"; cp "$B/backups/20261024-172623/$part.img" "$EFS/$name"
  fi
done
ls -l "$EFS"

say "== 2. 写 recovery_b 并进 Ubuntu"
FUXI_KEEP=1 "$B/scripts/fuxi-test-recovery.sh" "$IMG" 'uname -v' | grep -vE 'pushed' || { say "FAIL 没进 Ubuntu"; exit 1; }

say "== 3. 部署"
tar -C "$FW" -cf - qcom | T=600 ssh_ 'tar -C /lib/firmware -xmf - && echo modem-fw-ok'
tar -C "$EFS" -cf - . | ssh_ 'mkdir -p /var/lib/fuxi-rmtfs && chmod 700 /var/lib/fuxi-rmtfs && tar -C /var/lib/fuxi-rmtfs -xmf - && echo efs-ok'
tar -C "$B/work/rootfs-overlay" -cf - . | ssh_ 'tar --no-same-owner --no-overwrite-dir -C / -xmf - && chmod 755 /usr/local/sbin/fuxi-firmware-devices && echo overlay-ok'
T=900 ssh_ 'printf "#!/bin/sh\nexit 101\n" > /usr/sbin/policy-rc.d; chmod 755 /usr/sbin/policy-rc.d
DEBIAN_FRONTEND=noninteractive apt-get install -y rmtfs tqftpserv qrtr-tools modemmanager libqmi-utils 2>&1 | tail -n 3
rm -f /usr/sbin/policy-rc.d
echo "--- rmtfs 选项/文件名"; rmtfs -h 2>&1 | head -n 5; strings "$(command -v rmtfs)" | grep -E "^modem_fs|^/boot/" | sort -u | tr "\n" " "; echo
grep -q fuxi-rmtfs /root/fuxi-mainline-backup/CHANGES.txt || echo "fuxi-mainline 第十二次（M5.4 基带）: /lib/firmware/qcom/sm8550/xiaomi/fuxi/{modem,modem_dtb,ipa_fws}.*、modem_pr/；/var/lib/fuxi-rmtfs（EFS 副本）；rmtfs.service.d/10-fuxi.conf；apt: rmtfs tqftpserv qrtr-tools modemmanager libqmi-utils" >> /root/fuxi-mainline-backup/CHANGES.txt
systemctl daemon-reload; systemctl enable rmtfs tqftpserv ModemManager 2>&1 | tail -n 2; echo deploy-ok'

say "== 4. 启动并检查"
T=300 ssh_ 'systemctl restart fuxi-firmware-devices.service; journalctl -u fuxi-firmware-devices -b --no-pager -o cat | tail -n 4
echo "--- ipa"; ls -l /sys/bus/platform/devices/3f40000.ipa/driver 2>&1
systemctl restart tqftpserv rmtfs; sleep 20
echo "--- remoteproc"; for r in /sys/class/remoteproc/*; do echo "$(cat $r/name) $(cat $r/state)"; done
systemctl --no-pager -l status rmtfs | tail -n 6
systemctl restart ModemManager; sleep 15
echo "--- qrtr"; qrtr-lookup 2>/dev/null | head -n 30
echo "--- mmcli"; mmcli -L; m=$(mmcli -L 2>/dev/null | grep -o "Modem/[0-9]*" | head -n 1 | cut -d/ -f2)
[ -n "$m" ] && mmcli -m "$m" | grep -E "manufacturer|model|revision|equipment id|state|signal|sim|operator name|access tech" | sed "s/equipment id: .*/equipment id: (已隐藏)/"
echo "--- 网卡"; ip -br link | grep -iE "rmnet|ipa"
echo "--- dmesg"; dmesg | grep -iE "ipa|mpss|4080000|modem|rmtfs|qrtr" | grep -viE "calling|initcall" | tail -n 30'
say "完成，日志 $LOG"
