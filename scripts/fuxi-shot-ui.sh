#!/usr/bin/env bash
# 打开“手机截图”小软件：确保本地服务在跑，再用 Chrome 独立窗口打开界面。
# 也可以直接在终端跑本脚本；重复点击只会复用同一个服务。
set -euo pipefail
B="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-8099}"
URL="http://127.0.0.1:${PORT}/"
LOG="$B/work/logs/fuxi-shot-server.log"
mkdir -p "$B/work/logs"

up() { curl -sf -o /dev/null --max-time 1 "$URL/api/list"; }

if ! up; then
  setsid nohup python3 "$B/scripts/fuxi-shot-server.py" >>"$LOG" 2>&1 </dev/null &
  for _ in $(seq 1 50); do up && break; sleep 0.1; done
fi
up || { echo "ERROR: 服务没起来，看日志 $LOG" >&2; exit 1; }

exec google-chrome --app="$URL" --class=FuxiShot --window-size=640,1040 >/dev/null 2>&1
