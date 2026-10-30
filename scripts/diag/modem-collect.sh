#!/bin/bash
# 只读采集基带试验数据。用法: modem-collect.sh <标签> [等待到的 uptime 秒数，默认 180]
# 结果保存在 /var/tmp/modem-<标签>-<boot_id 前 8 位>/，并打印摘要
T=${1:?tag}; W=${2:-180}
while [ "$(cut -d. -f1 /proc/uptime)" -lt "$W" ]; do sleep 2; done
B=$(cut -c1-8 /proc/sys/kernel/random/boot_id); D=/var/tmp/modem-$T-$B; mkdir -p $D
uname -a > $D/uname.txt; cat /proc/sys/kernel/random/boot_id >> $D/uname.txt; cat /proc/uptime >> $D/uname.txt
journalctl -b -o short-monotonic --no-pager > $D/journal.txt
dmesg > $D/dmesg.txt
for r in /sys/class/remoteproc/*; do echo "$(basename $r) $(cat $r/name) $(cat $r/state)"; done > $D/remoteproc.txt
qrtr-lookup > $D/qrtr-lookup.txt 2>&1
for s in tms/servreg avs/audio gps/gps_service; do python3 /var/tmp/servreg-query.py $s; done > $D/servreg.txt 2>&1
systemctl --no-pager status pd-mapper rmtfs tqftpserv qrtr-ns ModemManager > $D/services.txt 2>&1
mmcli -L > $D/mmcli.txt 2>&1; mmcli -m any >> $D/mmcli.txt 2>&1
ip -br link > $D/links.txt
systemctl --failed --no-pager > $D/failed.txt
echo "== saved $D"; cat $D/uname.txt $D/remoteproc.txt
echo "== key kernel lines"
grep -E 'PDR:|PAS init image|remoteproc|q6v5|4080000|ipa|smem|error -|fatal|crash|wdog|DOG|stalled|ssr' $D/dmesg.txt | tail -n 120
echo "== servreg"; cat $D/servreg.txt; echo "== qrtr"; cat $D/qrtr-lookup.txt
echo "== mm"; cat $D/mmcli.txt | head -30; grep -iE 'net port|error|fail' $D/journal.txt | grep -i modemmanager | tail -10
echo "== links"; cat $D/links.txt
