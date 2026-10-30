# fuxi 测试脚本公用函数（source 使用）。需要调用方先定义 B（项目根目录）。
FUXI_ADB="${FUXI_ADB:-$B/tools/platform-tools/adb}"

fuxi_ssh_up() { timeout 5 bash -c 'exec 3<>/dev/tcp/10.42.0.2/22; timeout 3 head -c 4 <&3 | grep -q SSH' 2>/dev/null; }
fuxi_android_up() { [ "$(timeout 5 "$FUXI_ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; }

# 等手机进入 Android（开机完成）并 adb root。手机在 Ubuntu 时先 ssh 重启（正常开机回 Android）。
# 参数：最长等待秒数（默认 WAIT_ANDROID 或 3600）。卡死的手机只能靠用户长按电源，期间每 10 分钟提醒一次。
fuxi_ensure_android() {
  local max="${1:-${WAIT_ANDROID:-3600}}" e n=0
  e=$(( $(date +%s) + max ))
  until fuxi_android_up; do
    if fuxi_ssh_up; then
      echo "$(date +%T) 手机在 Ubuntu，重启回 Android"
      timeout 15 "$B/scripts/fuxi-ssh.sh" 'systemctl reboot' >/dev/null 2>&1
      sleep 30
    fi
    [ "$(date +%s)" -lt "$e" ] || { echo "$(date +%T) FAIL ${max}s 内 Android 没起来"; return 1; }
    n=$((n + 1))
    if [ $((n % 200)) = 1 ]; then
      notify-send -u critical fuxi "等手机回到 Android（卡住请长按电源 20 秒）" 2>/dev/null || true
    fi
    sleep 3
  done
  timeout 20 "$FUXI_ADB" root >/dev/null 2>&1; sleep 2; timeout 30 "$FUXI_ADB" wait-for-device
}
