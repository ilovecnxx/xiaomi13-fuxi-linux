#!/bin/bash
# M6（音频第一步）：两个扬声器（CS35L41 ×2，Secondary MI2S）上机验证。手机须先在 Android。
#   1. 生成拓扑（scripts/fuxi-audio-tplg.sh），写 recovery_b（音频变体镜像），进 Ubuntu（FUXI_KEEP=1）
#   2. 部署拓扑 /lib/firmware/qcom/sm8550/Xiaomi-13-tplg.bin，装 alsa-utils；
#      声卡第一次 probe 时 ADSP 可能还没起/拓扑还不在，没注册就 bind 一次
#   3. 功放走直通（PCM Source = ASP，不加载 Cirrus DSP 固件），音量压低保护扬声器，播 2 声 440 Hz 正弦
#      → 请用户听：上下两个扬声器有没有声音
#   4. （audio2 镜像）用 UCM（work/rootfs-overlay 里的 Qualcomm/sm8550/Xiaomi-13）打开 Mic1/Mic2 各录 3 秒，看峰值
# 用法: scripts/fuxi-m6-audio.sh [镜像，默认 work/kbuild/abl-fuxi-audio4.img]
#   SD=1 scripts/fuxi-audio-tplg.sh 可换数据线（没声音时试 SD0）
set -u
B="$(cd "$(dirname "$0")/.." && pwd)"
IMG="${1:-$B/work/kbuild/abl-fuxi-audio4.img}"
LOG="$B/work/claude-logs/m6-audio-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
say() { echo "$(date +%T) $*"; }
ssh_() { timeout "${T:-120}" "$B/scripts/fuxi-ssh.sh" "$@"; }

say "== 1. 拓扑 + 进 Ubuntu"
"$B/scripts/fuxi-audio-tplg.sh" || exit 1
FUXI_KEEP=1 "$B/scripts/fuxi-test-recovery.sh" "$IMG" 'uname -v' | grep -vE 'pushed' || { say "FAIL 没进 Ubuntu"; exit 1; }

say "== 2. 部署"
tar -C "$B/work/firmware-audio" -cf - qcom | ssh_ 'tar -C /lib/firmware -xmf - && echo tplg-ok'
tar -C "$B/work/rootfs-overlay" -cf - usr/share/alsa | ssh_ 'tar --no-same-owner --no-overwrite-dir -C / -xmf - && echo ucm-ok'
T=600 ssh_ 'command -v aplay >/dev/null || DEBIAN_FRONTEND=noninteractive apt-get install -y alsa-utils 2>&1 | tail -n 2
grep -q Xiaomi-13-tplg /root/fuxi-mainline-backup/CHANGES.txt || echo "fuxi-mainline（M6 音频）: /lib/firmware/qcom/sm8550/Xiaomi-13-tplg.bin；apt: alsa-utils" >> /root/fuxi-mainline-backup/CHANGES.txt
for i in $(seq 30); do grep -q adsp /sys/class/remoteproc/*/name && grep -q running /sys/class/remoteproc/*/state && break; sleep 1; done
if [ ! -e /proc/asound/cards ] || ! grep -q Xiaomi /proc/asound/cards; then
  for dev in /sys/bus/platform/devices/sound*; do [ -e "$dev/driver" ] || { echo "bind $(basename $dev)"; echo "$(basename $dev)" > /sys/bus/platform/drivers/snd-sc8280xp/bind; }; done
  sleep 3
fi
echo "--- 声卡"; cat /proc/asound/cards; aplay -l 2>&1 | head -n 12
echo "--- dmesg"; dmesg | grep -iE "cs35l41|sc8280xp|snd|asoc|q6apm|tplg|i2c 880000|geni_i2c|audioreach" | tail -n 30'

say "== 3. 直通播放（请听上下扬声器）"
notify-send -u critical fuxi "音频测试：请听手机扬声器有没有 440Hz 的嘟声（两声）" 2>/dev/null || true
T=120 ssh_ 'c=$(grep -m1 Xiaomi /proc/asound/cards | awk "{print \$1}"); [ -n "$c" ] || { echo "没有声卡"; exit 1; }
for p in B T; do
  amixer -c $c -q sset "$p PCM Source" ASP
  amixer -c $c -q sset "$p Digital PCM Volume" -20dB
  amixer -c $c -q sset "$p Analog PCM Volume" 0
done
amixer -c $c -q sset "SECONDARY_MI2S_RX Audio Mixer MultiMedia1" on
amixer -c $c contents | grep -B1 -A2 -iE "Audio Mixer MultiMedia1|PCM Source" | head -n 30
for n in 1 2; do timeout 10 speaker-test -D plughw:$c,0 -c 2 -r 48000 -F S16_LE -t sine -f 440 -l 1 -P 2 2>&1 | tail -n 3; sleep 1; done
echo "--- dmesg"; dmesg | grep -iE "cs35l41|q6apm|audioreach|i2s|mi2s|prm" | tail -n 20'
say "== 4. 麦克风（audio2 镜像才有 WCD：录 3 秒，看峰值；请对着手机说话）"
notify-send fuxi "音频测试：请对着手机说话 10 秒" 2>/dev/null || true
T=180 ssh_ 'c=$(grep -m1 Xiaomi /proc/asound/cards | awk "{print \$1}"); [ -n "$c" ] || exit 0
amixer -c $c controls | grep -q "ADC1 Switch" || { echo "这个镜像没有 WCD，跳过"; exit 0; }
command -v alsaucm >/dev/null || DEBIAN_FRONTEND=noninteractive apt-get install -y alsa-ucm-conf 2>&1 | tail -n 1
for m in Mic1 Mic2; do
  alsaucm -c hw:$c set _verb HiFi set _enadev $m 2>&1 | tail -n 2
  arecord -D hw:$c,2 -f S16_LE -r 48000 -c 1 -d 3 /tmp/$m.wav 2>&1 | tail -n 1
  peak=$(od -An -t d2 -v -j 44 /tmp/$m.wav | tr -s " " "\n" | awk "BEGIN{m=0} {v=\$1<0?-\$1:\$1; if(v>m)m=v} END{print m}")
  echo "$m 峰值 $peak / 32767"
  alsaucm -c hw:$c set _verb HiFi set _disdev $m >/dev/null 2>&1
done
echo "--- dmesg"; dmesg | grep -iE "wcd|swr|soundwire|macro" | tail -n 15'
say "完成，日志 $LOG"
