#!/bin/bash
# USB-C（OTG/USB3/FSA4480）上机验证。手机须先在 Android。
#   1. 写 recovery_b（USB-C 变体，默认 abl-fuxi-usbc1；桌面变体 abl-fuxi-desk3 还带原生显示 + DP）并进 Ubuntu
#   2. 接电脑时：检查 typec 端口、角色（应为 device）、USB 速度（USB3 线 + USB3 口应为 super-speed）
#   3. 手机上后台记录 3 分钟的角色/lsusb/DP 状态；请用户拔掉电脑线、用 OTG 转接头接 U 盘/键盘/扩展坞，
#      30 秒后再插回电脑；脚本等 ssh 恢复后取回记录
# 用法: scripts/fuxi-m6-usbc.sh [镜像]
set -u
B="$(cd "$(dirname "$0")/.." && pwd)"
IMG="${1:-$B/work/kbuild/abl-fuxi-usbc2.img}"
LOG="$B/work/claude-logs/m6-usbc-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
say() { echo "$(date +%T) $*"; }
ssh_() { timeout "${T:-120}" "$B/scripts/fuxi-ssh.sh" "$@"; }

say "== 1. 进 Ubuntu（$IMG）"
FUXI_KEEP=1 "$B/scripts/fuxi-test-recovery.sh" "$IMG" 'uname -v' | grep -vE 'pushed' || { say "FAIL 没进 Ubuntu"; exit 1; }

say "== 2. 接电脑时的状态"
T=120 ssh_ 'sleep 20
echo "--- typec"; for p in /sys/class/typec/port*; do echo "$p data_role=$(cat $p/data_role 2>/dev/null) power_role=$(cat $p/power_role 2>/dev/null) orientation=$(cat $p/orientation 2>/dev/null)"; ls $p 2>/dev/null | grep partner; done
echo "--- usb_role"; for r in /sys/class/usb_role/*; do echo "$r $(cat $r/role)"; done
echo "--- udc"; for u in /sys/class/udc/*; do echo "$u $(cat $u/current_speed) $(cat $u/state)"; done
echo "--- dmesg"; dmesg | grep -iE "ucsi|typec|fsa4480|dwc3|xhci|qmp|role|altmode|msm_dp|\bdp\b" | tail -n 30'

say "== 3. OTG 测试：请拔掉电脑线，用 OTG 转接头接 U 盘/键盘/扩展坞 30 秒，然后插回电脑"
T=30 ssh_ 'rm -f /root/usbc-test.done; nohup sh -c "for i in \$(seq 180); do echo \"== \$(date +%T) role=\$(cat /sys/class/usb_role/*/role 2>/dev/null)\"; cat /sys/bus/usb/devices/*/product 2>/dev/null; cat /sys/class/drm/card*-DP-*/status 2>/dev/null; sleep 1; done > /root/usbc-test.log 2>&1; dmesg | tail -n 80 >> /root/usbc-test.log; touch /root/usbc-test.done" >/dev/null 2>&1 &
echo logger-started'
notify-send -u critical fuxi "USB-C 测试：拔掉电脑线，用 OTG 接 U 盘/键盘/扩展坞 30 秒，再插回电脑" 2>/dev/null || true
sleep 20
e=$(( $(date +%s) + 600 ))
until T=8 ssh_ true 2>/dev/null; do
  [ "$(date +%s)" -lt "$e" ] || { say "FAIL 10 分钟内没重新连上（手机可能卡在主机模式：长按电源回 Android）"; exit 1; }
  sleep 5
done
say "ssh 恢复，等记录写完"
T=240 ssh_ 'until [ -e /root/usbc-test.done ]; do sleep 5; done; grep -vE "^\s*$" /root/usbc-test.log | uniq | tail -n 120'
say "完成，日志 $LOG"
