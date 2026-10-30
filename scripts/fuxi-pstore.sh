#!/bin/bash
# 取回上一轮内核日志（ramoops，DTS 里 0xa7000000 起 4 MB；从 wifi8 镜像起有）。
# 卡死后长按电源会冷启动，DDR 内容可能丢；热重启（panic 后 reboot、看门狗）才一定保得住。
# systemd-pstore.service 开机时把 /sys/fs/pstore 搬到 /var/lib/systemd/pstore/<时间>/。
# 用法: scripts/fuxi-pstore.sh（手机在 Ubuntu）→ work/claude-logs/pstore-<时间>/
set -u
B="$(cd "$(dirname "$0")/.." && pwd)"
D="$B/work/claude-logs/pstore-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$D"
timeout 60 "$B/scripts/fuxi-ssh.sh" 'ls -lR /sys/fs/pstore /var/lib/systemd/pstore 2>/dev/null | head -n 30; tar -C / -cf - sys/fs/pstore var/lib/systemd/pstore 2>/dev/null' > "$D/pstore.tar" 2> "$D/err.txt"
tar -C "$D" -xf "$D/pstore.tar" 2>/dev/null
find "$D" -type f -name 'console-ramoops*' -o -type f -name 'dmesg-ramoops*' | while read -r f; do echo "== $f"; tail -n 40 "$f"; done
echo "保存在 $D"
