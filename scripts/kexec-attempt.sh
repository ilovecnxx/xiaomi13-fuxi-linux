#!/bin/bash
# 一次尝试：重启→抢 shell→下载→kexec 主线→抓日志
B="/home/user/文档/deepseek-harness/default-workspace/linux-android"
FB="$B/tools/platform-tools/fastboot"
cd "$B"
LOG=/tmp/acm-attempt.log
rm -f "$LOG"; rm -rf /tmp/acm-capture; mkdir -p /tmp/acm-capture
pgrep -f watch-acm.sh >/dev/null || nohup bash scripts/watch-acm.sh >/dev/null 2>&1 &
"$FB" reboot
for i in $(seq 1 60); do [ -e /dev/ttyACM0 ] && break; sleep 1; done
sudo -n chmod 666 /dev/ttyACM0 2>/dev/null || true
nohup bash -c 'cat /dev/ttyACM0' > "$LOG" 2>/dev/null &
sleep 2
# 等待 shell 提示符
for i in $(seq 1 40); do grep -q "~ #" "$LOG" 2>/dev/null && break; sleep 1; done
echo "[host] shell ready=$(grep -c '~ #' "$LOG" 2>/dev/null)"
send() { printf '%s\n' "$1" > /dev/ttyACM0; sleep "${2:-3}"; }
send 'mkdir -p /k' 1
send 'cd /k' 1
send 'wget -q -O kexec http://192.168.77.1:8000/kexec-static' 5
send 'chmod +x kexec' 1
send 'wget -q -O Image http://192.168.77.1:8000/Image-mainline' 25
send 'wget -q -O fuxi.dtb http://192.168.77.1:8000/fuxi-stock.dtb' 5
send 'ls -l /k' 2
send 'C="console=ttyGS0,115200n8 loglevel=7 rdinit=/init"' 1
send 'kexec -l /k/Image --dtb=/k/fuxi.dtb --command-line="$C"' 8
send 'echo ABOUT_TO_JUMP' 2
echo "[host] 发送 kexec -e"
printf 'kexec -e\n' > /dev/ttyACM0
sleep 45
echo "[host] 捕获目录:"; ls /tmp/acm-capture/
for f in /tmp/acm-capture/*.log; do echo "--- $f ---"; sed 's/\r//' "$f" | head -25; done 2>/dev/null
