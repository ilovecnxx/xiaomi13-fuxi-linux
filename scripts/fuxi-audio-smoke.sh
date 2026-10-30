#!/bin/bash
# Bounded playback path test. Default: three seconds of silence, no recording.
# --tone explicitly requests four faded, half-scale 1 kHz pulses instead.
# --desktop sends silence through the user's PipeWire and checks both amp paths.
set -euo pipefail
B="$(cd "$(dirname "$0")/.." && pwd)"
case "${1:-}" in '') tone=0;; --tone) tone=1;; --desktop) tone=desktop;; *) echo "用法: $0 [--tone|--desktop]" >&2; exit 2;; esac
[ "$#" -le 1 ] || exit 2
"$B/scripts/fuxi-audio-check.sh" --wait
LOG="$B/work/claude-logs/audio-smoke-$(date +%Y%m%d-%H%M%S).log"
echo "播放通路测试（tone=$tone），日志 $LOG"
timeout 60 "$B/scripts/fuxi-ssh.sh" "bash -s -- $tone" <<'REMOTE' | tee "$LOG"
set -euo pipefail
export LC_ALL=C
tone=$1
card=$(awk '/Xiaomi/ {print $1; exit}' /proc/asound/cards)
[[ "$card" =~ ^[0-9]+$ ]]
u(){ runuser -u fuxi -- env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus XDG_RUNTIME_DIR=/run/user/1000 "$@"; }
if [ "$tone" = desktop ]; then
  systemctl --user --machine=fuxi@.host is-active --quiet wireplumber
  wave=$(mktemp /tmp/fuxi-audio.XXXXXX)
  playpid=
  trap 'if [ -n "$playpid" ]; then kill "$playpid" 2>/dev/null || true; fi; rm -f "$wave"' EXIT
  python3 - "$wave" <<'PY'
import sys, wave
with wave.open(sys.argv[1], 'wb') as output:
    output.setnchannels(2)
    output.setsampwidth(2)
    output.setframerate(48000)
    output.writeframes(bytes(48000 * 4 * 3))
PY
  chmod 644 "$wave"
  timeout 10 runuser -u fuxi -- env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus XDG_RUNTIME_DIR=/run/user/1000 pw-play "$wave" &
  playpid=$!
  sleep 1
  for pair in 0040:B 0042:T; do
    address=${pair%:*}; prefix=${pair#*:}
    count=0
    for path in /sys/kernel/debug/asoc/Xiaomi-13/cs35l41.*-"$address"/dapm/"$prefix Main AMP"; do
      state=$(cat "$path")
      printf '%s\n' "$state"
      grep -q "^$prefix Main AMP: On" <<< "$state"
      count=$((count + 1))
    done
    [ "$count" = 1 ]
  done
  wait "$playpid"
  playpid=
  echo 'PASS user PipeWire stream completed with both amplifier paths on'
  exit 0
fi
ctl() { amixer -D "hw:$card" -q cset "name='$1'" "$2"; }
wp_active=0
wave=
systemctl --user --machine=fuxi@.host is-active --quiet wireplumber && wp_active=1
cleanup() {
  ctl 'SECONDARY_MI2S_RX Audio Mixer MultiMedia1' 0,0 || true
  ctl 'B Digital PCM Volume' 0 || true
  ctl 'T Digital PCM Volume' 0 || true
  if [ -n "$wave" ]; then rm -f "$wave"; fi
  if [ "$wp_active" = 1 ]; then systemctl --user --machine=fuxi@.host start wireplumber; fi
}
trap cleanup EXIT
systemctl --user --machine=fuxi@.host stop wireplumber
cursor=$(journalctl -b -k -n 0 --show-cursor --no-pager | sed -n 's/^-- cursor: //p')
for prefix in B T; do
  ctl "$prefix Digital PCM Volume" 577
  ctl "$prefix Analog PCM Volume" 5
  ctl "$prefix PCM Source" ASP
done
ctl 'RCV MUX' Speaker
ctl 'SECONDARY_MI2S_RX Audio Mixer MultiMedia1' 1,1
if [ "$tone" = 1 ]; then
  wave=$(mktemp /tmp/fuxi-audio-tone.XXXXXX)
  python3 - "$wave" <<'PY'
import array, math, sys, wave
samples = array.array('h')
for channel in (0, 0, 1, 1):
    for frame in range(60000):
        fade = max(0, min(1, frame / 960, (35999 - frame) / 960))
        value = round(16384 * fade * math.sin(2 * math.pi * 1000 * frame / 48000))
        samples.extend((value, 0) if channel == 0 else (0, value))
with wave.open(sys.argv[1], 'wb') as output:
    output.setnchannels(2)
    output.setsampwidth(2)
    output.setframerate(48000)
    output.writeframes(samples.tobytes())
PY
  timeout 12 aplay -D "hw:$card,0" "$wave"
else
  timeout 12 aplay -D "hw:$card,0" -t raw -f S16_LE -r 48000 -c 2 -d 3 /dev/zero
fi
messages=$(journalctl -b -k --after-cursor "$cursor" --no-pager)
printf '%s\n' "$messages"
if grep -qiE 'cs35l41.*(fault|error)|q6apm.*(timeout|error)|audioreach.*(error|fail)|ASoC.*failed|I/O error|PLL.*unlock' <<< "$messages"; then
  echo 'FAIL playback produced a new audio driver error'
  exit 1
fi
echo 'PASS PCM stream completed; physical sound and speaker protection remain separate checks'
REMOTE
