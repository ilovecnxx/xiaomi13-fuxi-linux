#!/bin/bash
# 采集 modem keeper 运行证据（只读，不改设备）
# 用法: scripts/fuxi-modem-keeper-collect.sh [输出目录]
# 默认输出到 work/claude-logs/modem-keeper-<时间>/
set -u
B="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$B/work/claude-logs/modem-keeper-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT"
SSH="$B/scripts/fuxi-ssh.sh"

echo "采集到 $OUT"
{
  echo "### uname"; "$SSH" 'uname -v; cat /proc/sys/kernel/random/boot_id; cut -d" " -f1 /proc/uptime'
  echo; echo "### keeper service"; "$SSH" 'systemctl is-enabled fuxi-modem-keeper 2>&1; systemctl is-active fuxi-modem-keeper 2>&1'
  echo; echo "### keeper journal"; "$SSH" 'journalctl -u fuxi-modem-keeper --no-pager 2>&1'
  echo; echo "### modem status"; "$SSH" 'mmcli -m any 2>&1'
  echo; echo "### links"; "$SSH" 'ip -br link 2>&1; ip -4 addr 2>&1; ip -4 route 2>&1'
  echo; echo "### keeper triggers"; "$SSH" 'journalctl -u fuxi-modem-keeper --no-pager 2>/dev/null | grep -E "trigger|radio cycle|rejection|not registered|registered \(" ' 
  echo; echo "### MM 版本"; "$SSH" 'systemctl show ModemManager -p ExecStart --value'
} > "$OUT/summary.txt" 2>&1
echo "完成: $OUT/summary.txt ($(wc -l < "$OUT/summary.txt") 行)"
