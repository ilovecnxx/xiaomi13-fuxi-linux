#!/bin/bash
# 启停 device-watch：start|stop|status|restart（避免 pkill -f 自杀）
B="/home/user/文档/deepseek-harness/default-workspace/linux-android"
PIDF="$B/logs/watcher.pid"
case "$1" in
  start)
    [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null && { echo "already running pid=$(cat "$PIDF")"; exit 0; }
    setsid nohup bash "$B/scripts/device-watch.sh" >/dev/null 2>&1 </dev/null &
    echo $! > "$PIDF"; sleep 1; echo "started pid=$(cat "$PIDF")"
    ;;
  stop)
    [ -f "$PIDF" ] && { p=$(cat "$PIDF"); kill "$p" 2>/dev/null; rm -f "$PIDF"; echo "stopped $p"; } || echo "not running"
    ;;
  status)
    if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; then echo "running pid=$(cat "$PIDF")"; else echo "not running"; fi
    ;;
  restart) "$0" stop; "$0" start ;;
  *) echo "usage: $0 start|stop|status|restart"; exit 1 ;;
esac
