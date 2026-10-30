#!/bin/bash
# M6（音频第一步）：两个扬声器（CS35L41 ×2，Secondary MI2S）上机验证。手机须先在 Android。
#   1. 生成拓扑（scripts/fuxi-audio-tplg.sh），写 recovery_b（音频变体镜像），进 Ubuntu（FUXI_KEEP=1）
#   2. 部署拓扑 /lib/firmware/qcom/sm8550/Xiaomi-13-tplg.bin，装 alsa-utils / rtkit；
#      声卡第一次 probe 时 ADSP 可能还没起/拓扑还不在，没注册就 bind 一次
#   3. 功放走直通（PCM Source = ASP，不加载 Cirrus DSP 固件），数字 -30 dB / 模拟 raw 5，播放淡入淡出的半幅 1 kHz 短音
#      → 请用户听：上下两个扬声器有没有声音
#   4. （audio2 镜像）用 UCM（work/rootfs-overlay 里的 Qualcomm/sm8550/Xiaomi-13）打开 Mic1/Mic2 各录 3 秒，看峰值
# 用法: scripts/fuxi-m6-audio.sh [镜像，默认 work/kbuild/abl-fuxi-audio-probe4.img]
#       scripts/fuxi-m6-audio.sh --probe-only <镜像> （只验证注册，不播放/录音）
#   SD=1 scripts/fuxi-audio-tplg.sh 可换数据线（没声音时试 SD0）
set -euo pipefail
B="$(cd "$(dirname "$0")/.." && pwd)"
PROBE_ONLY=0
if [ "${1:-}" = --probe-only ]; then PROBE_ONLY=1; shift; fi
IMG="${1:-$B/work/kbuild/abl-fuxi-audio-probe4.img}"
[ "$#" -le 1 ] || { echo "用法: $0 [--probe-only] [镜像]" >&2; exit 2; }
LOG="$B/work/claude-logs/m6-audio-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1
say() { echo "$(date +%T) $*"; }
ssh_() { timeout "${T:-120}" "$B/scripts/fuxi-ssh.sh" "$@"; }

say "== 1. 拓扑 + 进 Ubuntu"
"$B/scripts/fuxi-audio-tplg.sh" || exit 1
FUXI_KEEP=1 "$B/scripts/fuxi-test-recovery.sh" "$IMG" 'uname -v' | grep -vE 'pushed' || { say "FAIL 没进 Ubuntu"; exit 1; }

say "== 2. 部署"
tar -C "$B/work/firmware-audio" -cf - qcom | ssh_ 'tar -C /lib/firmware -xmf - && echo tplg-ok'
tar -C "$B/work/rootfs-overlay" -cf - usr/share/alsa | ssh_ 'tar --no-same-owner --no-overwrite-dir -C / -xmf - && echo ucm-ok'
T=600 ssh_ 'set -e
command -v aplay >/dev/null || DEBIAN_FRONTEND=noninteractive apt-get install -y alsa-utils
if ! dpkg-query -W -f="${Status}" rtkit 2>/dev/null | grep -qx "install ok installed"; then
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends rtkit
fi
grep -q Xiaomi-13-tplg /root/fuxi-mainline-backup/CHANGES.txt || echo "fuxi-mainline（M6 音频）: /lib/firmware/qcom/sm8550/Xiaomi-13-tplg.bin；apt: alsa-utils rtkit" >> /root/fuxi-mainline-backup/CHANGES.txt
for i in $(seq 30); do grep -q adsp /sys/class/remoteproc/*/name && grep -q running /sys/class/remoteproc/*/state && break; sleep 1; done
if [ ! -e /proc/asound/cards ] || ! grep -q Xiaomi /proc/asound/cards; then
  for dev in /sys/bus/platform/devices/sound*; do [ -e "$dev/driver" ] || { echo "bind $(basename $dev)"; echo "$(basename $dev)" > /sys/bus/platform/drivers/snd-sc8280xp/bind; }; done
  sleep 3
fi
echo "--- 声卡"; cat /proc/asound/cards; aplay -l 2>&1 | head -n 12
echo "--- dmesg"; dmesg | grep -iE "cs35l41|sc8280xp|snd|asoc|q6apm|tplg|i2c 880000|geni_i2c|audioreach" | tail -n 30'

# 必须先证明两颗功放和声卡都已注册；旧流程可能在失败后仍输出“完成”。
"$B/scripts/fuxi-audio-check.sh" --wait
ssh_ 'set -e
alsaucm -c hw:0 set _fboot ""
systemctl --user --machine=fuxi@.host restart pipewire pipewire-pulse wireplumber
u(){ runuser -u fuxi -- env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus XDG_RUNTIME_DIR=/run/user/1000 "$@"; }
sink=
for i in $(seq 10); do
  if sink=$(u wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null); then break; fi
  sleep 1
done
# Only normalize this speaker sink; other default outputs retain their volume.
# UCM already applies the tested -30 dB digital / raw 5 analog hardware levels.
if printf "%s\n" "$sink" | grep -Fq "alsa_output.platform-sound.HiFi__Speaker__sink"; then
  u wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.0
fi'
if [ "$PROBE_ONLY" = 1 ]; then
  say "注册检查通过；未播放/录音。日志 $LOG"
  exit 0
fi

say "== 3. 低音量直通播放（请听上下扬声器）"
notify-send -u critical fuxi "音频测试：请听手机扬声器有没有 1 kHz 短音（上方两声，下方两声）" 2>/dev/null || true
"$B/scripts/fuxi-audio-smoke.sh" --tone
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
