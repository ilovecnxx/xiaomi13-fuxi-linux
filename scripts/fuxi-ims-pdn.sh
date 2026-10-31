#!/bin/bash
# IMS PDN 实验（modem16 #222 上验证 VoLTE 前置条件）。用法: fuxi-ims-pdn.sh status|up|down <handle>
# status 只读；up 用 qmicli 起 IMS APN（profile 4）并读 P-CSCF、查 IMSA 注册；down 断开该承载。
# 依赖手机上 qmicli 与 /usr/local/sbin/fuxi-qmi-ims.py（libqmi-glib GI，能在同进程 bind 后查询）。
set -u
B="$(cd "$(dirname "$0")/.." && pwd)"
S() { timeout 40 "$B/scripts/fuxi-ssh.sh" "$@"; }
Q() { S "qmicli -d qrtr://0 $*"; }

status() {
  echo "== 承载（只读，OutOfCall 表示没有数据承载）"
  Q --wds-get-current-settings 2>&1 | sed -n '1,25p'
  echo "== IMS 状态（imsa 注册 + ims 业务开关）"
  S "/usr/local/sbin/fuxi-qmi-ims.py" 2>&1 | grep -v "n/a (qmi_core" | sed -n '1,20p'
}

up() {
  echo "== 起 IMS PDN（profile 4 / APN IMS / ipv4v6）"
  out=$(Q --wds-start-network=3gpp-profile=4 2>&1)
  echo "$out"
  h=$(printf '%s\n' "$out" | sed -n "s/.*Packet data handle: '\([0-9]*\)'.*/\1/p" | head -1)
  if [ -z "$h" ]; then echo "!! 起网失败（见上）；承载未建立"; return 1; fi
  echo "== handle=$h：读 P-CSCF / 地址"
  Q --wds-get-current-settings 2>&1 | sed -n '1,25p'
  echo "== IMS 状态（有承载后看 imsa 是否从 0=not-registered 前进）"
  S "/usr/local/sbin/fuxi-qmi-ims.py" 2>&1 | grep -v "n/a (qmi_core" | sed -n '1,20p'
  echo "== 断开用: $0 down $h"
}

down() {
  h=${1:-}
  if [ -z "$h" ]; then echo "用法: $0 down <packet-data-handle>"; return 2; fi
  Q --wds-stop-network="$h" 2>&1 | sed -n '1,10p'
}

case "${1:-status}" in
  status) status ;;
  up) up ;;
  down) shift; down "${1:-}" ;;
  *) echo "用法: $0 status|up|down <handle>"; exit 2 ;;
esac
