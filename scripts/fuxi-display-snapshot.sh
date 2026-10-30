#!/bin/bash
# Capture one read-only Linux display/DRM snapshot over USB SSH.
# This does not change brightness, modes, services, boot state, or partitions.
set -euo pipefail
B="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$B/work/claude-logs/display-snapshot-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$B/work/claude-logs"
timeout 120 "$B/scripts/fuxi-ssh.sh" 'bash -s' <<'REMOTE' | tee "$LOG"
set -uo pipefail
grep -q 'fuxi.fb=' /proc/cmdline || { echo 'ERROR: device is not booted into the expected Linux image'; exit 2; }
[ "$(findmnt -n -o SOURCE /)" = /dev/sda33 ] || { echo 'ERROR: unexpected Linux root filesystem'; exit 2; }
section() { printf '\n--- %s ---\n' "$1"; }

section identity
printf 'kernel: '; uname -srv
printf 'boot_id: '; cat /proc/sys/kernel/random/boot_id
printf 'uptime: '; uptime -p
printf 'cmdline: '; cat /proc/cmdline
printf 'rootfs: '; findmnt -n -o SOURCE,FSTYPE,OPTIONS /

section drm-cards-and-connectors
shopt -s nullglob
for card in /sys/class/drm/card[0-9]*; do
  [[ "${card##*/}" =~ ^card[0-9]+$ ]] || continue
  driver=unavailable
  device=unavailable
  if [ -L "$card/device/driver" ]; then driver=$(basename "$(readlink -f "$card/device/driver")"); fi
  [ -e "$card/device" ] && device=$(readlink -f "$card/device")
  printf '%s driver=%s device=%s\n' "${card##*/}" "$driver" "$device"
done
connectors=(/sys/class/drm/card*-*)
if ((${#connectors[@]} == 0)); then echo 'no DRM connector entries'; fi
for connector in "${connectors[@]}"; do
  [ -r "$connector/status" ] || continue
  printf '\n%s status=%s\n' "${connector##*/}" "$(cat "$connector/status")"
  for attr in enabled dpms modes; do
    [ -r "$connector/$attr" ] && { printf '%s: ' "$attr"; tr '\n' ' ' < "$connector/$attr"; printf '\n'; }
  done
done

section backlight
backlights=(/sys/class/backlight/*)
if ((${#backlights[@]} == 0)); then echo 'no backlight class devices'; fi
for backlight in "${backlights[@]}"; do
  printf '%s\n' "${backlight##*/}"
  for attr in brightness actual_brightness max_brightness bl_power type; do
    [ -r "$backlight/$attr" ] && printf '  %s=%s\n' "$attr" "$(cat "$backlight/$attr")"
  done
done

section input-devices
if [ -r /proc/bus/input/devices ]; then
  awk 'BEGIN { RS=""; ORS="\n\n" } /Name=|Handlers=/ { print }' /proc/bus/input/devices
fi
printf 'event nodes: '; printf '%s ' /dev/input/event*; printf '\n'

section desktop-state
systemctl is-active phosh phoc 2>&1 || true
systemctl show phosh -p NRestarts -p ActiveEnterTimestamp 2>&1 || true
pgrep -a -x phosh || true
pgrep -a -x phoc || true

section drm-debugfs-state-if-already-mounted
for state in /sys/kernel/debug/dri/*/state; do
  [ -r "$state" ] || continue
  printf '\n%s\n' "$state"
  cat "$state"
done

section relevant-kernel-log
dmesg --color=never 2>/dev/null | grep -iE 'drm|dsi|dpu|panel|backlight|touch|ftm5|underrun|underflow' | tail -n 180 || true

section relevant-desktop-log
journalctl -b -u phosh -u phoc --no-pager -n 100 2>&1 || true
printf '\nSnapshot is read-only; screen quality, brightness changes, touch accuracy, refresh stability and blank/wake still require one physical acceptance.\n'
REMOTE
printf 'log=%s\n' "$LOG"
