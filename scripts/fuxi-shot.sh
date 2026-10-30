#!/usr/bin/env bash
# 抓一张手机屏幕 → 裁成真实分辨率 → 存回电脑。
# 用法: scripts/fuxi-shot.sh [文件名前缀]
#   OUTDIR 可覆盖保存目录（默认 XDG 图片/手机截图）
# 依赖: 手机可 SSH（scripts/fuxi-ssh.sh）、手机内有 grim、主机有 ffmpeg。
set -euo pipefail
B="$(cd "$(dirname "$0")/.." && pwd)"
PICTURES="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")"
BASE="${OUTDIR:-$PICTURES/手机截图}"
NAME="${1:-shot-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$BASE"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REMOTE="/tmp/fuxi-shot-$$.png"
# 手机端：以 fuxi 用户进入 phosh 的 Wayland 会话截图
if ! "$B/scripts/fuxi-ssh.sh" "sudo -u fuxi XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 grim '$REMOTE'"; then
  echo "ERROR: 手机端 grim 截图失败（手机是否在线 / phosh 是否在跑？）" >&2
  exit 1
fi
"$B/scripts/fuxi-ssh.sh" "cat '$REMOTE'; rm -f '$REMOTE'" > "$TMP/raw.png"

# 手机合成缓冲可能是 2700x6000（面板 2.5 倍），真实画面在左上角
MODE=$("$B/scripts/fuxi-ssh.sh" "cat /sys/class/drm/card*-*/modes 2>/dev/null | grep -m1 -E '^[0-9]+x[0-9]+$'" | tr -d '[:space:]')
MODE="${MODE:-1080x2400}"
CROP="${MODE%x*}:${MODE#*x}:0:0"
ffmpeg -loglevel error -y -i "$TMP/raw.png" -vf "crop=$CROP" "$BASE/$NAME.png"
echo "$BASE/$NAME.png"
