#!/bin/bash
# 相机镜像一键试验：回 Android → 写 recovery_b → 进 Linux → 抓相机日志 → 刷回基线 → 健康检查
# 用法: scripts/fuxi-camera-trial.sh <abl 镜像> [--keep]   (--keep: 测完不刷回基线)
# 只调用 fuxi-flash.sh / fuxi-ssh.sh / fuxi-health.sh，红线检查由它们负责。
set -u
B="$(cd "$(dirname "$0")/.." && pwd)"; cd "$B"
IMG="${1:?用法: fuxi-camera-trial.sh <abl 镜像> [--keep]}"; KEEP="${2:-}"
NAME="$(basename "$IMG" .img)"
LOG="work/claude-logs/trial-${NAME#abl-fuxi-}-$(date +%Y%m%d-%H%M).log"
say() { echo "$(date +%T) $*" | tee -a "$LOG"; }
dev_state() { scripts/fuxi-flash.sh status 2>/dev/null | sed -n 's/^device: *//p' | head -1; }
wait_state() { # <android|ubuntu> <秒>
  local e=$(( $(date +%s) + $2 ))
  while [ "$(date +%s)" -lt "$e" ]; do
    case "$1" in
      android) [ "$(dev_state)" = android ] && return 0 ;;
      ubuntu)  timeout 8 scripts/fuxi-ssh.sh true >/dev/null 2>&1 && return 0 ;;
    esac; sleep 5
  done; return 1; }
to_android() {
  [ "$(dev_state)" = android ] && return 0
  say "重启回 Android"; timeout 15 scripts/fuxi-ssh.sh 'systemctl reboot' >/dev/null 2>&1
  sleep 10; wait_state android 240 || { say "FAIL 240s 内没进 Android"; exit 1; }; }
boot_img() { # <镜像|baseline> [--allow-unknown-image]
  to_android
  say "写 recovery_b: $1"
  scripts/fuxi-flash.sh flash "$@" --yes 2>&1 | tee -a "$LOG" | grep -q "写入并校验通过" \
    || { say "FAIL 写入失败"; exit 2; }
  scripts/fuxi-flash.sh reboot recovery --yes >>"$LOG" 2>&1
  sleep 10; wait_state ubuntu 240 || { say "FAIL 240s 内 Linux SSH 不可用"; exit 3; }; }

say "== 试验 $IMG sha256 $(sha256sum "$IMG" | cut -c1-16)…"
boot_img "$IMG" --allow-unknown-image
say "== 相机日志"
timeout 60 scripts/fuxi-ssh.sh 'uname -v; D=/sys/kernel/debug
  echo ---dmesg; dmesg | grep -iE "ov13b10|camss|csiphy|cci|clk-branch|mclk"
  echo ---subdev; ls /dev/v4l-subdev* 2>&1
  echo ---media; command -v media-ctl >/dev/null && media-ctl -p -d /dev/media0 2>&1 | head -60
  echo ---clk; grep -E "cam_cc_mclk1_clk |cam_cc_cci_0_clk " $D/clk/clk_summary
  echo ---gpio; grep -E "gpio(91|101|117) " $D/gpio
  echo ---cam; command -v cam >/dev/null && timeout 20 cam -l 2>&1 | head -20' >>"$LOG" 2>&1
grep -iE "ov13b10" "$LOG" | tail -5
if [ "$KEEP" = --keep ]; then say "--keep：保留试验镜像"; echo "LOG $LOG"; exit 0; fi
say "== 刷回基线 s2idle2"
boot_img baseline
say "== 健康检查"
scripts/fuxi-health.sh --require-wifi --require-sensors >>"$LOG" 2>&1; rc=$?
tail -3 "$LOG"; say "health rc=$rc"; echo "LOG $LOG"; exit $rc
