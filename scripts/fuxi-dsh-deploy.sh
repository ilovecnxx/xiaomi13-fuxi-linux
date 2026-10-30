#!/bin/bash
# 在手机上（Ubuntu arm64 主线 Linux，Xiaomi 13 fuxi）部署 DeepSeek Harness Web，
# 并注入“DeepSeek 安卓端”风格的移动网页皮肤。浏览器里用，不生成安卓 APK。
#
# 用法:
#   FUXI_HOST=10.10.10.43 scripts/fuxi-dsh-deploy.sh              # WiFi 部署（当前手机可达方式）
#   scripts/fuxi-dsh-deploy.sh                                     # USB 网络部署（手机 10.42.0.2）
#   scripts/fuxi-dsh-deploy.sh --api-key sk-xxx                    # 用 API key（可选；否则手机网页里登录 DeepSeek 账号）
#   scripts/fuxi-dsh-deploy.sh --native                            # 强制安装 WebKitGTK，桌面图标用原生 GTK 窗口打开
#   scripts/fuxi-dsh-deploy.sh --bind 10.10.10.43                  # 绑定 WiFi IP（默认 127.0.0.1，仅手机本机浏览器访问）
#   scripts/fuxi-dsh-deploy.sh --as fuxi                           # 日常以普通用户 fuxi 运行（默认，桌面点击用）
#   scripts/fuxi-dsh-deploy.sh --as root                           # 日常以 root 用户运行（单用户/无 fuxi 时）
#   scripts/fuxi-dsh-deploy.sh --rollback                          # 回滚最近一次部署（恢复 index.html/unit/启动器）
#
# 幂等：重复执行会重装固定版本的 DSH 并重新注入主题；主题注入有备份、不会重复追加。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SSH=( "$ROOT/scripts/fuxi-ssh.sh" )
PHONE="${FUXI_HOST:-10.42.0.2}"
BIND="127.0.0.1"
PORT="3080"
DSH_VERSION="0.2.1-rc.5"   # @deepseek-ai/dsh@next 的实际版本；升级前端类名需重新核对皮肤
API_KEY="${DEEPSEEK_API_KEY:-}"
ROLLBACK=0
NATIVE=0
IDLE_MIN="${DSH_IDLE_MIN:-10}"
RUN_AS="${DSH_PHONE_USER:-fuxi}"   # 日常运行/桌面 App 的用户（root 或 fuxi）

while [ "$#" -gt 0 ]; do
  case "$1" in
    --bind) BIND="${2:?--bind 需要一个 IP}"; shift 2 ;;
    --port) PORT="${2:?--port 需要一个端口}"; shift 2 ;;
    --api-key) API_KEY="$2"; shift 2 ;;
    --rollback) ROLLBACK=1; shift ;;
    --host) PHONE="$2"; shift 2 ;;
    --native) NATIVE=1; shift ;;
    --idle-min) IDLE_MIN="$2"; shift 2 ;;
    --as) RUN_AS="${2:?--as 需要用户名(root/fuxi)}"; shift 2 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

export FUXI_HOST="$PHONE"

echo "==> 部署目标: ${PHONE} (bind=${BIND}:${PORT})"

if [ "$ROLLBACK" = 1 ]; then
  echo "==> 回滚手机端 DSH 皮肤与配置（RUN_AS=${RUN_AS}）"
  DSH_REMOTE_SCRIPT=$(cat <<'REMOTE'
  set -u
  echo "-- 恢复 index.html 最近备份"
  for f in $(find / -path '*dsh-web-frontend/dist/index.html.bak.*' 2>/dev/null | sort -r); do
    orig="${f%.bak.*}"
    if [ -f "$orig" ]; then cp -a "$orig" "$orig.before-rollback.$(date +%s)" 2>/dev/null || true; fi
    cp -a "$f" "$orig" && echo "  恢复: $orig <- $f"
    break
  done
  echo "-- 移除皮肤文件"
  rm -f $(find / -path '*dsh-web-frontend/dist/deepseek-android.css' 2>/dev/null) \
        $(find / -path '*dsh-web-frontend/dist/deepseek-android.js' 2>/dev/null) 2>/dev/null || true
  echo "-- 移除系统级单元/启动器（历史残留）"
  systemctl disable --now dsh-web.service 2>/dev/null || true
  systemctl disable --now dsh-web-idle.timer 2>/dev/null || true
  rm -f /etc/systemd/system/dsh-web.service /etc/systemd/system/dsh-web-idle.timer /etc/systemd/system/dsh-web-idle.service
  rm -f /usr/local/bin/dsh-web-idle-check /usr/local/bin/dsh-web-launcher /usr/local/bin/dsh-web-open /usr/local/bin/dsh-web-window
  systemctl daemon-reload 2>/dev/null || true
  echo "-- 移除桌面图标"
  rm -f /usr/share/applications/dsh-web.desktop /usr/share/icons/hicolor/scalable/apps/dsh-web.svg
  echo "-- 移除用户级单元（按实际 RUN_AS 用户）"
  for UN in "@RUN_AS@" fuxi root; do
    [ -n "$UN" ] || continue
    id "$UN" >/dev/null 2>&1 || continue
    HH="$(getent passwd "$UN" | cut -d: -f6)"; UU="$(id -u "$UN")"
    sudo -u "$UN" env XDG_RUNTIME_DIR="/run/user/$UU" HOME="$HH" systemctl --user disable --now dsh-web-idle.timer 2>/dev/null || true
    sudo -u "$UN" env XDG_RUNTIME_DIR="/run/user/$UU" HOME="$HH" systemctl --user stop dsh-web.service 2>/dev/null || true
    rm -f "$HH/.config/systemd/user/dsh-web.service" "$HH/.config/systemd/user/dsh-web-idle.service" "$HH/.config/systemd/user/dsh-web-idle.timer"
    rm -f "$HH/.local/bin/dsh-web-launcher" "$HH/.local/bin/dsh-web-idle-check" "$HH/.config/dsh-web.env"
    rm -rf "$HH/.local/state/dsh-web"
    echo "  清理用户 $UN"
  done
  echo "回滚完成"
REMOTE
)
  # 把 RUN_AS 代入脚本并真正通过 SSH 执行
  RENDERED_RB="$(printf '%s' "$DSH_REMOTE_SCRIPT" | sed "s|@RUN_AS@|${RUN_AS}|g")"
  printf '%s\n' "$RENDERED_RB" | "${SSH[@]}" bash -s
  exit $?
fi

echo "==> 上传皮肤文件到手机"
tar czf - -C "$ROOT/work/dsh-phone" . | "${SSH[@]}" 'mkdir -p /root/dsh-phone && tar xzf - -C /root/dsh-phone && chmod +x /root/dsh-phone/apply-theme.sh && echo 上传完成'

echo "==> 手机端安装 Node.js / DSH / systemd / 皮肤（这一步会访问 apt 与 npm 仓库）"
# API key 不拼进命令行（避免 ps/历史泄露），通过远端 env 从标准输入读取
"${SSH[@]}" "read -r DSH_API_KEY_IN; export DSH_API_KEY_IN; BIND='$BIND' PORT='$PORT' DSH_VERSION='$DSH_VERSION' NATIVE='$NATIVE' IDLE_MIN='$IDLE_MIN' RUN_AS='$RUN_AS' NPM_REG='${DSH_NPM_REG:-https://registry.npmmirror.com}' bash /root/dsh-phone/install-remote.sh" <<< "$API_KEY"

echo
echo "=============================================================="
echo "部署完成。手机桌面会出现“DeepSeek”图标，点开即可；"
echo "优先用原生 WebKitGTK 窗口（GTK 原生，无地址栏），没有则退 Chromium --app。"
echo "首次若提示需要认证：用 SSH 打开 App 内出现的带 token URL（token 已脱敏，不在此打印）。"
echo "模型：网页内 设置→模型 登录 DeepSeek 账号；或已配置 API key 时自动生效。"
echo "回滚：FUXI_HOST=${PHONE} $0 --rollback --as ${RUN_AS}"
echo "=============================================================="
