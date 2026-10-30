#!/bin/bash
# 只读验收日常 Linux 镜像：不重启、不刷写、不扫描 WiFi、不读取口令。
# 用法：scripts/fuxi-health.sh [--require-wifi]
# 默认仅要求 WiFi 接口可用；--require-wifi 另要求无线已连接（不证明外网/无线 SSH 可用）。
set -euo pipefail
B="$(cd "$(dirname "$0")/.." && pwd)"
require_wifi=0
case "${1:-}" in
  '') ;;
  --require-wifi) require_wifi=1 ;;
  *) echo "用法: $0 [--require-wifi]" >&2; exit 2 ;;
esac
[ "$#" -le 1 ] || exit 2
mkdir -p "$B/work/claude-logs"
LOG="$B/work/claude-logs/health-$(date +%Y%m%d-%H%M%S).log"
echo "只读验收，日志 $LOG"
timeout 90 "$B/scripts/fuxi-ssh.sh" "bash -s -- $require_wifi" <<'REMOTE' | tee "$LOG"
set -uo pipefail
require_wifi="$1"
failures=0
pass() { printf 'PASS %s\n' "$*"; }
fail() { printf 'FAIL %s\n' "$*"; failures=$((failures + 1)); }
printf 'kernel: %s\n' "$(uname -srv)"
printf 'uptime: %s\n' "$(uptime -p)"
grep -q 'fuxi.fb=' /proc/cmdline || { fail '不是预期的 fuxi Linux 启动环境'; exit 1; }
state=$(systemctl is-system-running 2>/dev/null || true)
if [ "$state" = running ]; then pass "systemd $state"; else
  fail "systemd $state"; systemctl --failed --no-pager
fi
for service in phosh fuxi-firmware-devices bluetooth; do
  if systemctl is-active --quiet "$service"; then pass "$service active"; else fail "$service 未运行"; fi
done
for process in phoc phosh; do
  if pgrep -x "$process" >/dev/null; then pass "$process 进程存在"; else fail "$process 进程缺失"; fi
done
if systemctl --user --machine=fuxi@.host is-active --quiet mobi.phosh.OSK.service || pgrep -x squeekboard >/dev/null; then
  pass '屏幕键盘服务已运行（Stevia 或 Squeekboard）'
else fail '屏幕键盘服务未运行'; fi
shopt -s nullglob
policies=(/sys/devices/system/cpu/cpufreq/policy*)
if [ "${#policies[@]}" -eq 3 ]; then pass '3 个 CPU 调频策略'; else fail "CPU 调频策略数量=${#policies[@]}，预期 3"; fi
for policy in "${policies[@]}"; do
  gov=$(cat "$policy/scaling_governor")
  freq=$(cat "$policy/scaling_cur_freq")
  cpus=$(cat "$policy/related_cpus")
  if [ "$gov" = schedutil ] && [[ "$freq" =~ ^[0-9]+$ ]] && [ "$freq" -gt 0 ]; then
    pass "${policy##*/} cpus=$cpus governor=$gov frequency=${freq}kHz"
  else fail "${policy##*/} governor=$gov frequency=$freq"; fi
done
zones=(/sys/class/thermal/thermal_zone*)
valid=0
maximum=-273000
for zone in "${zones[@]}"; do
  temp=$(cat "$zone/temp" 2>/dev/null || true)
  if [[ "$temp" =~ ^-?[0-9]+$ ]] && (( temp > -40000 && temp < 120000 )); then
    valid=$((valid + 1))
    (( temp > maximum )) && maximum=$temp
  else fail "${zone##*/} 无效温度: $temp"; fi
done
if [ "$valid" -ge 2 ]; then pass "有效热区=$valid 最高温度=${maximum}m°C"; else fail "有效热区仅 $valid"; fi
cooling=0
for device in /sys/class/thermal/cooling_device*; do
  case "$(cat "$device/type")" in cpufreq-*) cooling=$((cooling + 1));; esac
done
if [ "$cooling" -eq 3 ]; then pass '3 个 CPU cooling 设备'; else fail "CPU cooling 设备数量=$cooling"; fi
if grep -qi 'FTM5' /proc/bus/input/devices; then pass 'FTM5 触摸设备已注册'; else fail 'FTM5 触摸设备缺失'; fi
display=0
for connector in /sys/class/drm/card*-*/status; do
  [ "$(cat "$connector")" = connected ] && display=$((display + 1))
done
if [ "$display" -gt 0 ]; then pass "DRM 已连接输出=$display"; else fail '没有已连接的 DRM 输出'; fi
capacity=$(cat /sys/class/power_supply/qcom-battmgr-bat/capacity 2>/dev/null || true)
status=$(cat /sys/class/power_supply/qcom-battmgr-bat/status 2>/dev/null || true)
if [[ "$capacity" =~ ^[0-9]+$ ]] && [ "$capacity" -le 100 ]; then
  pass "电量=$capacity% 状态=$status（仅验证读数）"
else fail '无法读取有效电量'; fi
wifi=$(nmcli -t -f TYPE,STATE device 2>/dev/null | grep '^wifi:' || true)
case "$wifi" in
  wifi:connected*) pass 'WiFi 已连接';;
  wifi:disconnected) if [ "$require_wifi" = 1 ]; then fail 'WiFi 未连接'; else pass 'WiFi 接口可用（尚未联网验收）'; fi;;
  *) fail "WiFi 不可用: $wifi";;
esac
bt=$(timeout 10 bluetoothctl show 2>/dev/null || true)
if grep -q 'Powered: yes' <<< "$bt"; then pass '蓝牙已上电'; else fail '蓝牙未上电'; fi
if systemctl is-failed --quiet rmtfs; then fail 'rmtfs 启动失败'; else pass 'rmtfs 无失败状态'; fi
printf '验收结束：失败项=%s；触摸交互、实际充电、无线 SSH 仍需各自验证。\n' "$failures"
[ "$failures" -eq 0 ]
REMOTE
