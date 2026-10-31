#!/bin/bash
# 主机侧只读注册采样（每 IV 秒一次 ssh 拉一行）。用法: modem-reg-sample.sh <输出目录> <秒数> [间隔秒=30]
# 只读：mmcli 查询 + 读 sysfs，不写设备。
set -u
D=${1:?outdir}; SEC=${2:-4200}; IV=${3:-30}
B="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$D"
OUT="$D/reg2.txt"
end=$(( $(date +%s) + SEC ))
echo "# start $(date -Is) interval=${IV}s seconds=${SEC}" >>"$OUT"
while [ "$(date +%s)" -lt "$end" ]; do
  line=$(timeout 12 "$B/scripts/fuxi-ssh.sh" 'bash -s' 2>/dev/null <<'EOF'
u=$(cut -d. -f1 /proc/uptime)
s=$(mmcli -m any 2>/dev/null | tr -s ' ')
st=$(printf "%s\n" "$s" | sed "s/\x1b\[[0-9;]*m//g" | awk -F': ' '/^[ |]+state:/{print $2; exit}')
at=$(printf "%s\n" "$s" | sed "s/\x1b\[[0-9;]*m//g" | awk -F': ' '/access tech:/{print $2; exit}')
sq=$(printf "%s\n" "$s" | sed "s/\x1b\[[0-9;]*m//g" | awk -F': ' '/signal quality:/{print $2; exit}')
rg=$(printf "%s\n" "$s" | sed "s/\x1b\[[0-9;]*m//g" | awk -F': ' '/registration:/{print $2; exit}')
ps=$(printf "%s\n" "$s" | sed "s/\x1b\[[0-9;]*m//g" | awk -F': ' '/packet service state:/{print $2; exit}')
bat=$(cat /sys/class/power_supply/qcom-battmgr-bat/capacity 2>/dev/null)
echo "up=$u ${st:-?}|${at:-?}|${sq:-?}|${rg:-?}|${ps:-?}| bat=$bat"
EOF
)
  if [ -n "$line" ]; then
    printf '%s %s\n' "$(date +%H:%M:%S)" "$line" >>"$OUT"
  else
    printf '%s SSH-FAIL\n' "$(date +%H:%M:%S)" >>"$OUT"
  fi
  sleep "$IV"
done
echo "# end $(date -Is)" >>"$OUT"
