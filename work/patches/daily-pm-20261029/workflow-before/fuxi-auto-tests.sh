#!/bin/bash
# 不需要人看/听的上机测试串起来跑（每个都会自己写 recovery_b、进对应镜像；手机在 Ubuntu 时自动先回 Android）：
#   1. 调频/温控（abl-fuxi-pm2）  2. 传感器 hexagonrpcd + ssccli（abl-fuxi-wifi12）
#   3. 重编带 SSC 的 iio-sensor-proxy（留在 wifi12 的 Ubuntu 里编）  4. 基带首次启动（abl-fuxi-modem3）
# 某一项失败（比如手机卡住）就停下，后面的不跑。M5.2 WiFi 任务跑完后再启动本脚本，别和它同时跑。
# 用法: scripts/fuxi-auto-tests.sh [项目...]   项目：pm sensors sensors-proxy modem（默认全部）
set -u
B="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$B/work/claude-logs/auto-tests-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
say() { echo "$(date +%T) $*"; }
items=("$@"); [ ${#items[@]} -gt 0 ] || items=(pm sensors sensors-proxy modem)
for it in "${items[@]}"; do
  case "$it" in
    pm) cmd=("$B/scripts/fuxi-m6-pm.sh") ;;
    sensors) cmd=("$B/scripts/fuxi-sensors.sh") ;;
    sensors-proxy) cmd=("$B/scripts/fuxi-sensors-proxy.sh") ;;
    modem) cmd=("$B/scripts/fuxi-m5-modem.sh") ;;
    *) say "未知项目 $it"; exit 2 ;;
  esac
  say "======== $it"
  if ! "${cmd[@]}"; then say "FAIL $it，停止"; exit 1; fi
  ssh_ok=$(timeout 8 "$B/scripts/fuxi-ssh.sh" true 2>/dev/null && echo yes || echo no)
  say "$it 完成（ssh $ssh_ok）"
done
say "全部完成，日志 $LOG"
