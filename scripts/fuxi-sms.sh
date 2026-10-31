#!/bin/bash
# 短信收发入口（走 ModemManager；qmicli 1.38 的 WMS 只有路由/能力查询）。
# 用法:
#   fuxi-sms.sh status                 # 只读：存储/能力/已存短信
#   fuxi-sms.sh list                   # 只读：列已存短信
#   fuxi-sms.sh show <索引>            # 只读：看一条短信
#   fuxi-sms.sh store <号码> <文本>     # 创建并存入设备（不发送、不产生费用）
#   fuxi-sms.sh send  <号码> <文本>     # 创建并发送（会产生费用，需用户同意）
#   fuxi-sms.sh delete <索引>          # 删除一条
set -u
B="$(cd "$(dirname "$0")/.." && pwd)"
S() { timeout 40 "$B/scripts/fuxi-ssh.sh" "$@"; }

cmd="${1:-status}"
case "$cmd" in
  status)
    S 'mmcli -m 0 --messaging-status; echo "--- 已存短信 ---"; mmcli -m 0 --messaging-list-sms; echo "--- 默认存储 ---"; mmcli -m 0 2>/dev/null | grep -iE "storage|messaging" | head -4'
    ;;
  list) S 'mmcli -m 0 --messaging-list-sms' ;;
  show) S "mmcli -s ${2:?索引} 2>&1 | grep -E 'number|text|state|timestamp|storage' | head -8" ;;
  delete) S "mmcli -s ${2:?索引} --delete" ;;
  store|send)
    num="${2:?号码}"; txt="${3:?文本}"
    # 文本用 base64 传，避开 mmcli 属性解析器不认空格/逗号的问题（它会把空格当分隔符）
    b64=$(printf '%s' "$txt" | base64 -w0)
    S "printf '%s' '$b64' | base64 -d > /var/tmp/fuxi-sms.txt" >/dev/null 2>&1
    out=$(S "mmcli -m 0 --messaging-create-sms-with-text=/var/tmp/fuxi-sms.txt --messaging-create-sms=number=$num" 2>&1)
    echo "$out"
    idx=$(printf '%s' "$out" | grep -oE 'SMS/[0-9]+' | grep -oE '[0-9]+$' | head -1)
    [ -n "$idx" ] || { echo "!! 创建失败"; exit 1; }
    if [ "$cmd" = send ]; then
      echo "== 发送 SMS/$idx → $num"
      S "mmcli -s $idx --send" 2>&1 | head -5
    else
      echo "== 存入 SIM（不发送）SMS/$idx"
      S "mmcli -s $idx --store-in-storage=sm" 2>&1 | head -5
    fi
    ;;
  *) echo "用法: $0 status|list|show <idx>|store <num> <text>|send <num> <text>|delete <idx>"; exit 2 ;;
esac
