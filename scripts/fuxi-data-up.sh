#!/bin/bash
# 蜂窝数据验收（走 NetworkManager 的 fuxi-mobile 连接，APN 3gnet）。用法: fuxi-data-up.sh [up|down|status]
# up：起连接 → 等 qmapmux 拿地址 → ping v4/v6 → 打印 rmnet/qmapmux 计数；down：断开。只动这一个连接。
set -u
B="$(cd "$(dirname "$0")/.." && pwd)"
S() { timeout 60 "$B/scripts/fuxi-ssh.sh" "$@"; }

up() {
  echo "== 起连接 fuxi-mobile"
  S "nmcli connection up fuxi-mobile 2>&1 | tail -3"
  echo "== 等 qmapmux 地址（最多 20 s）"
  for _ in $(seq 1 10); do
    ip=$(S "ip -4 -br addr show qmapmux0.0 2>/dev/null | awk '{print \$3}'" 2>/dev/null)
    [ -n "$ip" ] && break
    sleep 2
  done
  echo "ipv4=$ip"
  S "ip -br link show rmnet_ipa0; ip -br addr show qmapmux0.0" 2>&1 | sed -n '1,4p'
  # 必须绑到蜂窝接口：USB 共享的默认路由 metric 更低，不绑会走 usb0（假失败）
  echo "== ping v4（绑 qmapmux0.0）"
  S "ping -4 -I qmapmux0.0 -c 4 -W 2 223.5.5.5 2>&1 | tail -2"
  echo "== ping v6（绑 qmapmux0.0）"
  S "ping -6 -I qmapmux0.0 -c 3 -W 2 2400:3200::1 2>&1 | tail -2"
  echo "== 计数"
  S "ip -s link show rmnet_ipa0 | tail -4; ip -s link show qmapmux0.0 | tail -4" 2>&1
}

down() { S "nmcli connection down fuxi-mobile 2>&1 | tail -2"; }

status() { S "nmcli -f NAME,TYPE,DEVICE,STATE connection show | grep -E 'gsm|NAME'; ip -br link show rmnet_ipa0; ip -br addr show qmapmux0.0" 2>&1; }

case "${1:-up}" in
  up) up ;;
  down) down ;;
  status) status ;;
  *) echo "用法: $0 up|down|status"; exit 2 ;;
esac
