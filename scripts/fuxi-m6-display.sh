#!/bin/bash
# M6（显示/GPU）：原生 MSM 显示驱动 + 面板驱动 + Adreno 740 的上机验证。手机须先在 Android。
#   1. adb root，只读拉取 GPU 固件：a740_sqe.fw、gmu_gen70200.bin → qcom/；a740_zap.* → qcom/sm8550/xiaomi/fuxi/
#   2. 写 recovery_b（显示变体镜像），进 Ubuntu（FUXI_KEEP=1）
#   3. 部署 GPU 固件，检查 DSI/面板/DPU/GPU 日志、/sys/class/drm、背光
# 屏幕黑了 = 面板初始化失败：长按电源回 Android，日志在 work/claude-logs/ 里（ssh 还在的话）。
# 用法: scripts/fuxi-m6-display.sh [镜像，默认 work/kbuild/abl-fuxi-disp5.img]
set -u
B="$(cd "$(dirname "$0")/.." && pwd)"
ADB="$B/tools/platform-tools/adb"
IMG="${1:-$B/work/kbuild/abl-fuxi-disp5.img}"
LOG="$B/work/claude-logs/m6-display-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
say() { echo "$(date +%T) $*"; }
. "$B/scripts/fuxi-lib.sh"
ssh_() { timeout "${T:-120}" "$B/scripts/fuxi-ssh.sh" "$@"; }
F="$B/work/firmware"

say "== 1. GPU 固件"
fuxi_ensure_android || exit 1
mkdir -p "$F/qcom/sm8550/xiaomi/fuxi"
# ZAP 只取 /odm/firmware：/vendor/firmware 的 a740_zap.mdt/.b02 是高通测试密钥签名，量产 TZ 拒绝
# （Linux 报 error -22 initializing firmware）；Android kgsl 实际加载的是 /odm 下小米签名版。
for p in $(timeout 30 "$ADB" shell 'find /vendor/firmware /vendor/firmware_mnt/image -maxdepth 1 \( -name "a740_sqe.fw" -o -name "gmu_gen70200.bin" \) 2>/dev/null
  find /odm/firmware -maxdepth 1 \( -name "a740_zap.mdt" -o -name "a740_zap.b[0-9][0-9]" \) 2>/dev/null' | tr -d '\r'); do
  case "$(basename "$p")" in
    a740_zap.*) d="$F/qcom/sm8550/xiaomi/fuxi" ;;
    *) d="$F/qcom" ;;
  esac
  timeout 30 "$ADB" pull "$p" "$d/" >/dev/null && say "pulled $p"
done
ls "$F/qcom" "$F/qcom/sm8550/xiaomi/fuxi" | grep -E 'a740|gmu' || say "WARN 没找到 GPU 固件"
if grep -aq 'for testing only' "$F/qcom/sm8550/xiaomi/fuxi/a740_zap.mdt" 2>/dev/null; then
  say "FAIL a740_zap.mdt 是测试密钥签名，TZ 会拒绝；需要 /odm/firmware 的小米签名版"; exit 1
fi

say "== 2. 显示变体进 Ubuntu（请看屏幕：应先出现启动日志，再到登录界面）"
notify-send -u critical fuxi "显示驱动测试：手机即将重启进 Linux，请看屏幕是否正常显示" 2>/dev/null || true
FUXI_KEEP=1 "$B/scripts/fuxi-test-recovery.sh" "$IMG" 'uname -v' | grep -vE 'pushed' || { say "FAIL 没进 Ubuntu（屏幕黑也可能 ssh 正常）"; exit 1; }

say "== 3. 部署 GPU 固件并检查"
tar -C "$F" -cf - qcom | ssh_ 'tar -C /lib/firmware -xmf - && echo gpu-fw-ok'
ssh_ 'echo "--- drm"; ls /sys/class/drm/; cat /sys/class/drm/card*-DSI-1/status /sys/class/drm/card*-DSI-1/modes 2>/dev/null
echo "--- backlight"; for b in /sys/class/backlight/*; do echo "$b $(cat $b/brightness)/$(cat $b/max_brightness)"; done
echo "--- dmesg"; dmesg | grep -iE "msm|dsi|dpu|panel|adreno|a7xx|gmu|zap|simpledrm|fbcon|drm" | grep -viE "calling|initcall" | tail -n 40'
say "完成，日志 $LOG"
