#!/bin/bash
# 调频 + 温控上机验证（镜像 abl-fuxi-pm1 = 主配置 + FUXI_PM=1）。手机须先在 Android。
#   1. 进 Ubuntu；2. 看 cpufreq 策略/频率表/调速器、热区温度、LMh；3. 8 线程满载 30 秒，每 5 秒记一次频率与最高温度
# 风险：某个热区读数异常（比如误报 >115°C）会触发温控关机——那只是干净关机，长按电源回 Android 即可。
# 用法: scripts/fuxi-m6-pm.sh [镜像]
set -u
B="$(cd "$(dirname "$0")/.." && pwd)"
IMG="${1:-$B/work/kbuild/abl-fuxi-pm2.img}"
LOG="$B/work/claude-logs/m6-pm-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
say() { echo "$(date +%T) $*"; }
ssh_() { timeout "${T:-120}" "$B/scripts/fuxi-ssh.sh" "$@"; }

say "== 1. 进 Ubuntu（$IMG）"
FUXI_KEEP=1 "$B/scripts/fuxi-test-recovery.sh" "$IMG" 'uname -v' | grep -vE 'pushed' || { say "FAIL 没进 Ubuntu"; exit 1; }

say "== 2. 状态"
ssh_ 'cd /sys/devices/system/cpu/cpufreq 2>/dev/null || { echo "没有 cpufreq"; exit 0; }
for p in policy*; do echo "$p cpus=$(cat $p/related_cpus) gov=$(cat $p/scaling_governor) cur=$(cat $p/scaling_cur_freq) min=$(cat $p/cpuinfo_min_freq) max=$(cat $p/cpuinfo_max_freq)"; echo "  表: $(cat $p/scaling_available_frequencies)"; done
echo "--- 热区"; for z in /sys/class/thermal/thermal_zone*; do printf "%s %s %s\n" "$(basename $z)" "$(cat $z/type)" "$(cat $z/temp 2>/dev/null)"; done | sort -k3 -n -r | head -n 50
echo "--- cooling"; for c in /sys/class/thermal/cooling_device*; do echo "$(cat $c/type) $(cat $c/cur_state)/$(cat $c/max_state)"; done | sort | uniq -c | head
echo "--- dmesg"; dmesg | grep -iE "cpufreq|tsens|thermal|lmh|qfprom|temp.alarm|osm" | tail -n 25'

say "== 3. 满载 30 秒"
T=90 ssh_ 'for i in 1 2 3 4 5 6 7 8; do (timeout 30 sh -c "while :; do :; done" &) ; done
for t in 0 5 10 15 20 25 30; do
  f=$(for p in /sys/devices/system/cpu/cpufreq/policy*; do echo -n "$(basename $p)=$(( $(cat $p/scaling_cur_freq) / 1000 ))MHz "; done)
  m=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -n | tail -n 1)
  echo "t=${t}s $f 最高 $((m / 1000))°C"; sleep 5
done'
say "完成，日志 $LOG"
