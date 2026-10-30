#!/bin/bash
# Read-only audio bring-up checks. Does not enable mixers or play/record audio.
set -euo pipefail
B="$(cd "$(dirname "$0")/.." && pwd)"
case "${1:-}" in '') wait_seconds=0;; --wait) wait_seconds=30;; *) echo "用法: $0 [--wait]" >&2; exit 2;; esac
[ "$#" -le 1 ] || exit 2
mkdir -p "$B/work/claude-logs"
LOG="$B/work/claude-logs/audio-check-$(date +%Y%m%d-%H%M%S).log"
echo "只读音频检查，日志 $LOG"
timeout 75 "$B/scripts/fuxi-ssh.sh" "bash -s -- $wait_seconds" <<'REMOTE' | tee "$LOG"
set -uo pipefail
export LC_ALL=C
failures=0
pass() { printf 'PASS %s\n' "$*"; }
fail() { printf 'FAIL %s\n' "$*"; failures=$((failures + 1)); }
uname -rv
grep -q 'fuxi.fb=' /proc/cmdline || { fail '不是预期的 fuxi Linux 环境'; exit 1; }
deadline=$((SECONDS + $1))
while ! grep -q Xiaomi /proc/asound/cards 2>/dev/null && (( SECONDS < deadline )); do sleep 1; done
if [ -r /proc/asound/cards ]; then cat /proc/asound/cards; else fail 'ALSA 未启用'; fi
card=$(awk '/Xiaomi/ {print $1; exit}' /proc/asound/cards 2>/dev/null || true)
if [[ "$card" =~ ^[0-9]+$ ]]; then
  pass "Xiaomi 声卡 card$card 已注册"
  for tool in aplay amixer; do command -v "$tool" >/dev/null || fail "缺少 $tool"; done
  if command -v aplay >/dev/null; then
    playback=$(aplay -l 2>&1)
    printf '%s\n' "$playback"
    if grep -q "^card $card:.*device 0:" <<< "$playback"; then pass 'PCM 播放设备 0 存在'; else fail 'PCM 播放设备 0 缺失'; fi
  fi
  if command -v amixer >/dev/null; then
    controls=$(amixer -D "hw:$card" controls)
    for prefix in B T; do
      if grep -q "name='$prefix Digital PCM Volume'" <<< "$controls"; then
        pass "$prefix 功放音量控件存在"
        if volume=$(amixer -D "hw:$card" cget "name='$prefix Digital PCM Volume'"); then
          printf '%s\n' "$volume"
          if grep -q 'min=0,max=816,' <<< "$volume"; then
            pass "$prefix 内核音量上限已生效（816）"
          else fail "$prefix 音量上限未生效，禁止播放测试"; fi
        else fail "$prefix 音量控件读取失败"; fi
      else fail "$prefix 功放控件缺失"; fi
    done
    printf '%s\n' "$controls" | grep -E 'MI2S|PCM Source|RCV' || true
  fi
else fail 'Xiaomi 声卡尚未注册'; fi
shopt -s nullglob
for address in 0040 0042; do
  found=0
  for device in /sys/bus/i2c/devices/*-"$address"; do
    driver=$(readlink -f "$device/driver" 2>/dev/null || true)
    if [ "${driver##*/}" = cs35l41 ]; then
      pass "CS35L41 ${device##*/} 已绑定"; found=1
    fi
  done
  [ "$found" = 1 ] || fail "CS35L41 @$address 未绑定"
done
echo '--- 音频内核日志'
journalctl -b -k --no-pager | grep -iE 'cs35l41|sc8280xp|asoc|q6apm|audioreach|tplg|gpr' | tail -n 60 || true
printf '音频检查失败项=%s（不代表实际出声或录音验收）\n' "$failures"
[ "$failures" = 0 ]
REMOTE
