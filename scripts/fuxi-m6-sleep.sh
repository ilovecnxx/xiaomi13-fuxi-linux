#!/bin/bash
# 省电上机验证（镜像 abl-fuxi-sleep1 = 主 DTS 去掉 cpuidle.off=1 + 调频温控 + SUSPEND）。手机须先在 Android 或 Ubuntu。
#   1. 进 Ubuntu；2. 闲置 60 秒前后对比 cpuidle 各状态的进入次数/时间、电池电流（battmgr current_now）；
#   3. s2idle 挂起 20 秒后由 RTC 唤醒（rtcwake -m freeze）。USB 网络会断开再恢复，脚本等 ssh 回来。
# 风险：空闲/挂起时卡死 → 长按电源回 Android；上一轮内核日志在 /sys/fs/pstore（ramoops）。
# 用法: scripts/fuxi-m6-sleep.sh [镜像]
set -u
B="$(cd "$(dirname "$0")/.." && pwd)"
IMG="${1:-$B/work/kbuild/abl-fuxi-sleep2.img}"
LOG="$B/work/claude-logs/m6-sleep-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
say() { echo "$(date +%T) $*"; }
ssh_() { timeout "${T:-120}" "$B/scripts/fuxi-ssh.sh" "$@"; }

say "== 1. 进 Ubuntu（$IMG）"
FUXI_KEEP=1 "$B/scripts/fuxi-test-recovery.sh" "$IMG" 'uname -v' | grep -vE 'pushed' || { say "FAIL 没进 Ubuntu"; exit 1; }

say "== 2. 闲置 60 秒"
T=150 ssh_ 'snap() { for c in /sys/devices/system/cpu/cpu[0-7]; do for s in $c/cpuidle/state*; do printf "%s/%s %s %s %s\n" $(basename $c) $(cat $s/name) $(cat $s/usage) $(cat $s/time) $(cat $s/disable); done; done; }
cur() { cat /sys/class/power_supply/*battery*/current_now 2>/dev/null | head -n 1; }
echo "--- cpuidle 驱动：$(cat /sys/devices/system/cpu/cpuidle/current_driver 2>/dev/null)/$(cat /sys/devices/system/cpu/cpuidle/current_governor_ro 2>/dev/null)"
ls /sys/kernel/debug/pm_genpd 2>/dev/null | grep -i cluster
snap > /tmp/i0; c0=$(cur); sleep 60; snap > /tmp/i1; c1=$(cur)
echo "--- 60 秒内各状态（次数增量 / 时间增量 ms）"
paste /tmp/i0 /tmp/i1 | awk "{printf \"%-24s %8d %8d\n\", \$1\"/\"\$2, \$7-\$3, (\$8-\$4)/1000}" | sort | head -n 40
echo "--- 电池电流 前 $c0 后 $c1（µA，负数=放电）"
cat /sys/class/power_supply/*battery*/status 2>/dev/null | head -n 1'

say "== 3. s2idle 挂起 20 秒"
T=30 ssh_ 'cat /sys/power/state /sys/power/mem_sleep; (sleep 2; rtcwake -m freeze -s 20 >/tmp/rtcwake.log 2>&1) >/dev/null 2>&1 & echo started'
sleep 30
e=$(( $(date +%s) + 120 ))
until T=8 ssh_ true 2>/dev/null; do [ "$(date +%s)" -lt "$e" ] || { say "FAIL 挂起后 2 分钟没恢复（长按电源回 Android）"; exit 1; }; sleep 5; done
T=60 ssh_ 'cat /tmp/rtcwake.log; cat /sys/power/suspend_stats/success /sys/power/suspend_stats/fail 2>/dev/null
echo "--- dmesg"; dmesg | grep -iE "PM: suspend|freeze|resume|wakeup|psci|cpuidle|genpd" | tail -n 25'
say "完成，日志 $LOG"
