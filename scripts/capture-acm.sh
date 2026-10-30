#!/bin/bash
# 持续捕获 ttyACM*，设备重枚举后自动重连
OUT=/tmp/cap; mkdir -p "$OUT"
while :; do
  for dev in /dev/ttyACM*; do
    [ -c "$dev" ] || continue
    n=$(basename "$dev")
    if ! pgrep -f "cat $dev" >/dev/null 2>&1; then
      sudo -n chmod 666 "$dev" 2>/dev/null || true
      ( while :; do cat "$dev" 2>/dev/null; sleep 0.3; done >> "$OUT/$n.log" 2>/dev/null ) &
      echo "$(date +%H:%M:%S) attach $dev" >> "$OUT/index.log"
    fi
  done
  sleep 0.5
done
