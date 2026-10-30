#!/bin/bash
# 基带跑起来之后（scripts/fuxi-m5-modem.sh 通过）的日常操作与验证：启用、SIM PIN、注册、短信、移动数据。
# 用法（手机在 Ubuntu）：
#   scripts/fuxi-modem-use.sh status
#   FUXI_SIM_PIN=1234 scripts/fuxi-modem-use.sh unlock
#   FUXI_APN=cmnet scripts/fuxi-modem-use.sh data        # 移动 cmnet / 联通 3gnet / 电信 ctnet
#   FUXI_SMS_TO=1380000xxxx scripts/fuxi-modem-use.sh sms  # 发一条测试短信（会产生费用，按用户要求才跑）
#   scripts/fuxi-modem-use.sh mbn                          # 列出基带里的运营商配置（VoLTE 用）
set -u
B="$(cd "$(dirname "$0")/.." && pwd)"
ssh_() { timeout "${T:-120}" "$B/scripts/fuxi-ssh.sh" "$@"; }
M='m=$(mmcli -L 2>/dev/null | grep -o "Modem/[0-9]*" | head -n 1 | cut -d/ -f2); [ -n "$m" ] || { echo "ModemManager 没找到基带"; exit 1; }'

case "${1:-status}" in
  status)
    ssh_ "$M"'
mmcli -m $m | grep -E "state|power state|access tech|signal quality|operator name|registration|primary sim path|ports"
s=$(mmcli -m $m | grep -o "SIM/[0-9]*" | head -n 1 | cut -d/ -f2); [ -n "$s" ] && mmcli -i $s | grep -E "active|operator name|emergency" ' ;;
  unlock)
    [ -n "${FUXI_SIM_PIN:-}" ] || { echo "需要 FUXI_SIM_PIN"; exit 2; }
    ssh_ "$M"'; s=$(mmcli -m $m | grep -o "SIM/[0-9]*" | head -n 1 | cut -d/ -f2); mmcli -i $s --pin='"$FUXI_SIM_PIN"' && mmcli -m $m -e' ;;
  data)
    APN="${FUXI_APN:?需要 FUXI_APN}"
    T=180 ssh_ "$M"'; mmcli -m $m -e >/dev/null 2>&1
nmcli -t -f NAME connection show | grep -qx fuxi-mobile || nmcli connection add type gsm ifname "*" con-name fuxi-mobile apn '"$APN"' connection.autoconnect yes
nmcli connection up fuxi-mobile && sleep 5
ip -br addr | grep -iE "rmnet|wwan|qmapmux|ipa"
ping -c 3 -W 3 -I $(ip -br addr | awk "/rmnet|wwan|qmapmux/{print \$1; exit}" | cut -d@ -f1) 223.5.5.5' ;;
  sms)
    TO="${FUXI_SMS_TO:?需要 FUXI_SMS_TO}"
    ssh_ "$M"'; p=$(mmcli -m $m --messaging-create-sms="text='"'"'fuxi mainline linux test'"'"',number='"$TO"'" | grep -o "SMS/[0-9]*" | cut -d/ -f2); mmcli -s $p --send && echo sent' ;;
  mbn)
    T=60 ssh_ 'qmicli -p -d qrtr://0 --pdc-list-configs=platform 2>&1 | head -n 40; qmicli -p -d qrtr://0 --pdc-get-selected-config=platform 2>&1 | head -n 10' ;;
  *) echo "未知命令 $1"; exit 2 ;;
esac
