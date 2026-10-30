#!/bin/bash
# 多 agent 互斥锁（建议性，防两个 agent 同时改同一工作区）
# 用法:
#   scripts/fuxi-agent-lock.sh acquire <owner> [note]   # 加锁（<12h 的他人锁会拒绝）
#   scripts/fuxi-agent-lock.sh status                   # 查看
#   scripts/fuxi-agent-lock.sh release [--force]        # 释放
set -u
B="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LK="$B/work/claude-logs/agent.lock"
mkdir -p "$(dirname "$LK")"
now=$(date +%s)

case "${1:-status}" in
  acquire)
    owner="${2:?用法: acquire <owner> [note]}"
    note="${3:-}"
    if [ -f "$LK" ]; then
      read -r cur_owner cur_ts < <(python3 -c "import json;d=json.load(open('$LK'));print(d.get('owner','?'),int(d.get('ts',0)))" 2>/dev/null)
      hrs=$(( (now - ${cur_ts:-0}) / 3600 ))
      if [ "${cur_owner:-?}" != "$owner" ] && [ "$hrs" -lt 12 ]; then
        echo "拒绝：${cur_owner} 在 ${hrs}h 前持有锁（确认无并行 agent 后可 release --force）"
        exit 1
      fi
    fi
    printf '{"owner":"%s","note":"%s","host":"%s","pid":%d,"ts":%d}\n' \
      "$owner" "$note" "$(hostname)" "$$" "$now" > "$LK"
    echo "已加锁：$owner（${note:-无备注}）"
    ;;
  status)
    if [ -f "$LK" ]; then
      python3 - "$LK" <<'PY'
import json, sys, time
d = json.load(open(sys.argv[1]))
print("owner :", d.get("owner"))
print("note  :", d.get("note"))
print("host  :", d.get("host"), "pid:", d.get("pid"))
print("since :", time.strftime("%F %T", time.localtime(d.get("ts", 0))),
      f'（{int((time.time()-d.get("ts",0))/60)} 分钟前）')
PY
    else
      echo "无锁"
    fi
    ;;
  release)
    if [ -f "$LK" ]; then
      rm -f "$LK"
      if [ "${2:-}" = "--force" ]; then echo "已强制释放"; else echo "已释放"; fi
    else
      echo "无锁（无需释放）"
    fi
    ;;
  *)
    echo "用法: $0 acquire <owner> [note] | status | release [--force]"
    exit 2
    ;;
esac
