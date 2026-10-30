#!/bin/bash
# 手机重启回 Android 后的完整执行链（可断点续跑）。
# 每一步成功后记到 work/state/after-reboot.done；重跑时跳过已完成的步骤，失败的步骤从头再来。
# 需要人配合的步骤（看屏幕/听声音/插拔）会先 notify-send 提醒；WiFi 账号从环境变量来（没给就跳过连网这步）。
# 用法: scripts/fuxi-after-reboot.sh [--list] [--reset] [--from 步骤] [--only 步骤]
#   FUXI_WIFI_SSID=... FUXI_WIFI_PSK=... FUXI_PIN=... scripts/fuxi-after-reboot.sh
# 注意：别在本脚本运行时修改它调用的子脚本（bash 边读边执行）。
set -u
B="$(cd "$(dirname "$0")/.." && pwd)"
STATE="$B/work/state/after-reboot.done"
mkdir -p "$(dirname "$STATE")"; touch "$STATE"
LOG="$B/work/claude-logs/after-reboot-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
say() { echo "$(date +%T) $*"; }
ssh_() { timeout "${T:-120}" "$B/scripts/fuxi-ssh.sh" "$@"; }

wifi_connect() {
  [ -n "${FUXI_WIFI_SSID:-}" ] || { say "没有 FUXI_WIFI_SSID，跳过（以后补跑：--only wifi-connect）"; return 2; }
  T=120 ssh_ "nmcli dev wifi rescan >/dev/null 2>&1; sleep 5; nmcli dev wifi connect '$FUXI_WIFI_SSID' password '${FUXI_WIFI_PSK:-}' && sleep 5 && ip -br addr show | grep -E '^wl'"
}

# 步骤名|命令（在 B 下执行）|说明
STEPS=(
  "wifi-bt|scripts/fuxi-m5-wifi-bt.sh|WiFi/蓝牙部署与验证（wifi12）"
  "wifi-connect|wifi_connect|连 WiFi（FUXI_WIFI_SSID/PSK）"
  "pm|scripts/fuxi-m6-pm.sh|调频/温控（pm2）"
  "sensors|scripts/fuxi-sensors.sh|hexagonrpcd + ssccli（wifi12）"
  "sensors-proxy|scripts/fuxi-sensors-proxy.sh|重编带 SSC 的 iio-sensor-proxy"
  "phosh|scripts/fuxi-m5-phosh.sh \"\${FUXI_PIN:-}\"|Phosh 手机界面（PIN 由 FUXI_PIN 传入，没给就跳过）"
  "display|scripts/fuxi-m6-display.sh|原生显示 + GPU（需要看屏幕）"
  "modem|scripts/fuxi-m5-modem.sh|基带首次启动（modem4）"
  "audio1|scripts/fuxi-m6-audio.sh work/kbuild/abl-fuxi-audio4.img|扬声器（需要听）"
  "audio2|scripts/fuxi-m6-audio.sh work/kbuild/abl-fuxi-audio3.img|麦克风（需要说话）"
  "usbc|scripts/fuxi-m6-usbc.sh|USB-C OTG/USB3（需要插拔）"
  "camera|scripts/fuxi-camera-probe.sh|相机 CCI/传感器 ID 探测（camera2）"
  "sleep|scripts/fuxi-m6-sleep.sh|CPU 深度空闲 + s2idle 挂起（sleep2）"
)

case "${1:-}" in
  --list) for s in "${STEPS[@]}"; do n=${s%%|*}; grep -qx "$n" "$STATE" && m=done || m=todo; echo "$m  $n  — ${s##*|}"; done; exit 0 ;;
  --reset) : > "$STATE"; echo "已清空进度"; exit 0 ;;
esac
FROM=""; ONLY=""
[ "${1:-}" = --from ] && FROM="${2:?}"
[ "${1:-}" = --only ] && ONLY="${2:?}"

started=0; [ -z "$FROM" ] && started=1
for s in "${STEPS[@]}"; do
  n=${s%%|*}; rest=${s#*|}; cmd=${rest%%|*}; desc=${rest##*|}
  [ "$n" = "$FROM" ] && started=1
  [ "$started" = 1 ] || continue
  [ -n "$ONLY" ] && [ "$n" != "$ONLY" ] && continue
  if [ -z "$ONLY" ] && grep -qx "$n" "$STATE"; then say "跳过已完成：$n"; continue; fi
  say "======== $n：$desc"
  notify-send fuxi "开始：$desc" 2>/dev/null || true
  ( cd "$B" && eval "$cmd" ); rc=$?
  if [ $rc = 0 ]; then echo "$n" >> "$STATE"; say "完成 $n"
  elif [ $rc = 2 ]; then say "跳过 $n（条件不满足）"
  else say "FAIL $n（rc=$rc），停止；修好后重跑本脚本会从这一步继续"; exit 1; fi
done
say "执行链结束，日志 $LOG"
