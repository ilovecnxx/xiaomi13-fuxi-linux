#!/bin/bash
# 只读验收日常 Linux 镜像：不重启、不刷写、不扫描 WiFi、不读取口令。
# 用法：scripts/fuxi-health.sh [--require-wifi] [--require-sensors]
# 默认仅要求 WiFi 接口可用；--require-wifi 另要求无线已连接、外网路由走 wlp1s0、HTTPS 经 wlp1s0 校验通过、网卡管制域与 /etc/fuxi/wifi-country 一致。
set -euo pipefail
B="$(cd "$(dirname "$0")/.." && pwd)"
require_wifi=0
require_sensors=0
for arg in "$@"; do
  case "$arg" in
    --require-wifi) require_wifi=1 ;;
    --require-sensors) require_sensors=1 ;;
    *) echo "用法: $0 [--require-wifi] [--require-sensors]" >&2; exit 2 ;;
  esac
done
mkdir -p "$B/work/claude-logs"
LOG="$B/work/claude-logs/health-$(date +%Y%m%d-%H%M%S).log"
echo "只读验收，日志 $LOG"
timeout 120 "$B/scripts/fuxi-ssh.sh" "bash -s -- $require_wifi $require_sensors" <<'REMOTE' | tee "$LOG"
set -uo pipefail
require_wifi="$1"
require_sensors="$2"
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
if [ "$require_wifi" = 1 ]; then
  # 外网须真的走无线：默认路由优先 wlp1s0（usb0 只兜底，metric 700），HTTPS 绑定 wlp1s0 且校验证书。
  route=$(ip route get 223.5.5.5 2>/dev/null | head -n 1)
  if grep -q 'dev wlp1s0' <<< "$route"; then pass "外网路由走 WiFi: $route"; else fail "外网路由未走 WiFi: $route"; fi
  if python3 - <<'PY'
import socket, ssl
host = "www.baidu.com"
ip = socket.getaddrinfo(host, 443, socket.AF_INET)[0][4][0]
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, b"wlp1s0")
s.settimeout(10)
s.connect((ip, 443))
s = ssl.create_default_context().wrap_socket(s, server_hostname=host)
s.sendall(b"HEAD / HTTP/1.1\r\nHost: www.baidu.com\r\nConnection: close\r\n\r\n")
assert s.recv(16).startswith(b"HTTP/1.")
PY
  then pass 'HTTPS 经 wlp1s0 连通且证书校验通过'; else fail 'HTTPS 经 wlp1s0 失败'; fi
  country=$(cat /etc/fuxi/wifi-country 2>/dev/null || echo CN)
  if iw reg get 2>/dev/null | grep -A1 '^phy#' | grep -q "country $country"; then pass "无线网卡管制域=$country"
  else fail "无线网卡管制域不是 $country: $(iw reg get 2>/dev/null | grep -A1 '^phy#' | tail -n 1)"; fi
fi
bt=$(timeout 10 bluetoothctl show 2>/dev/null || true)
if grep -q 'Powered: yes' <<< "$bt"; then pass '蓝牙已上电'; else fail '蓝牙未上电'; fi
if systemctl is-failed --quiet rmtfs; then fail 'rmtfs 启动失败'; else pass 'rmtfs 无失败状态'; fi
if [ "$require_sensors" = 1 ]; then
  for service in hexagonrpcd iio-sensor-proxy; do
    if systemctl is-active --quiet "$service"; then pass "$service active"; else fail "$service 未运行"; fi
  done
  pid=$(systemctl show hexagonrpcd -p MainPID --value)
  exe=$(readlink "/proc/$pid/exe" 2>/dev/null || true)
  if [ "$exe" = /usr/local/libexec/hexagonrpcd-fuxi ]; then pass '传感器使用非调试 daemon'; else fail "非预期传感器进程: $exe"; fi
  if timeout 3 qrtr-lookup 400 | awk '$1 == 400 { found=1 } END { exit !found }'; then pass 'SSC QRTR 400 已发布'; else fail 'SSC QRTR 400 缺失'; fi
  for property in HasAccelerometer HasAmbientLight HasProximity; do
    value=$(timeout 5 busctl get-property net.hadess.SensorProxy /net/hadess/SensorProxy net.hadess.SensorProxy "$property" 2>/dev/null || true)
    if [ "$value" = 'b true' ]; then pass "SensorProxy $property"; else fail "SensorProxy $property=$value"; fi
  done
  value=$(timeout 5 busctl get-property net.hadess.SensorProxy /net/hadess/SensorProxy/Compass net.hadess.SensorProxy.Compass HasCompass 2>/dev/null || true)
  if [ "$value" = 'b true' ]; then pass 'SensorProxy HasCompass'; else fail "SensorProxy HasCompass=$value"; fi
  for sensor in accelerometer light proximity magnetometer compass; do
    if output=$(timeout 10 ssccli --sensor "$sensor" --timeout 3 2>&1) && grep -q 'sensor measurement:' <<< "$output"; then
      sample=$(grep 'sensor measurement:' <<< "$output" | tail -n 1)
      pass "$sensor: $sample"
    else fail "$sensor 没有有效测量值"; fi
  done
  crashes=$(journalctl -b -k --no-pager | grep -iE 'adsp.*(fatal|crash)|remoteproc.*crash' || true)
  if [ -z "$crashes" ]; then pass '本次启动未发现 ADSP/remoteproc 崩溃记录'; else fail '本次启动有 ADSP/remoteproc 崩溃记录'; printf '%s\n' "$crashes"; fi
  restarts=$(systemctl show phosh -p NRestarts --value)
  if [ "$restarts" = 0 ]; then pass 'Phosh 本次启动无需重试'; else fail "Phosh 重试次数=$restarts"; fi
fi
printf '验收结束：失败项=%s；触摸交互、实际充电仍需各自验证；无线 SSH 用 FUXI_HOST=<无线 IP> scripts/fuxi-ssh.sh 复验。\n' "$failures"
[ "$failures" -eq 0 ]
REMOTE
