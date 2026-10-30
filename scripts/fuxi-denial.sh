#!/bin/bash
# 在手机（Xiaomi 13 fuxi，主线 Linux + Ubuntu arm64）上安装 / 切换 / 回退 Denial 桌面。
#
# 背景：手机没有显示管理器，Phosh 由系统级 systemd 服务 phosh.service 在 tty7 启动。
# Denial 用同样的方式接入 seat：系统级 denial.service（User=1000、PAMName=login、TTYPath=/dev/tty7）。
# Phosh 与 Denial 互斥（同一 tty / DRM master），同一时间只能跑一个。
#
# 用法：
#   scripts/fuxi-denial.sh status                 # 只读：两个服务/进程/会话/日志尾部
#   scripts/fuxi-denial.sh install [PAYLOAD]      # 把构建树装到手机 /usr（默认 work/denial-arm64/payload）
#   scripts/fuxi-denial.sh deps                   # 可选：装 xwayland + xdg-desktop-portal-wlr
#   scripts/fuxi-denial.sh check                  # 以 fuxi 用户跑 denial-session --check（只读前置检查）
#   scripts/fuxi-denial.sh switch                 # 停 Phosh → 起 Denial；失败自动回退 Phosh
#   scripts/fuxi-denial.sh rollback               # 停 Denial → 起 Phosh
#   scripts/fuxi-denial.sh enable-default         # 验证通过后：开机默认 Denial
#   scripts/fuxi-denial.sh disable-default        # 恢复开机默认 Phosh
#   scripts/fuxi-denial.sh logs [-n N]            # journalctl -u denial
#   scripts/fuxi-denial.sh shot [名字]            # 用 grim 截图 Denial 会话并拉回主机
#
# 红线：本脚本不刷机、不重启、不改内核、不动 recovery_b。切换/回退只动用户态服务。
set -uo pipefail

B="$(cd "$(dirname "$0")/.." && pwd)"
PAYLOAD_DEFAULT="$B/work/denial-arm64/payload"
PICTURES="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")"
SHOT_DIR="${OUTDIR:-$PICTURES/手机截图}"
LOG_DIR="$B/work/claude-logs"
TS="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LOG_DIR"

say() { printf '%s %s\n' "$(date +%T)" "$*"; }

# 远端执行（默认 120s 超时；可用 T=<秒> 覆盖）
ssh_() { timeout "${T:-120}" "$B/scripts/fuxi-ssh.sh" "$@"; }

# 以 fuxi 用户在登录会话里执行命令（与现有 grim 截图脚本同一模式）
ssh_fuxi() {
    timeout "${T:-120}" "$B/scripts/fuxi-ssh.sh" \
        "sudo -u fuxi env XDG_RUNTIME_DIR=/run/user/1000 HOME=/home/fuxi $*"
}

require_device() {
    ssh_ 'echo ok' >/dev/null 2>&1 || {
        echo "ERROR: 手机不可达（scripts/fuxi-ssh.sh 失败）。" >&2
        exit 1
    }
}

# Denial 安装后的关键文件（/usr 前缀，与上游 Arch/Debian 包布局一致）
REQUIRED_FILES=(
    /usr/bin/deniald
    /usr/bin/denialctl
    /usr/bin/denial-portal
    /usr/bin/denial-session
    /usr/bin/denial-settings
    /usr/lib/denial/flutter/lib/libapp.so
    /usr/lib/denial/settings/denial-settings
    /usr/lib/systemd/user/denial-session.target
    /usr/lib/systemd/user/denial-portal.service
    /usr/share/wayland-sessions/denial.desktop
)

session_unit() {
    cat <<'EOF'
[Unit]
Description=Denial Wayland compositor and mobile desktop shell
Documentation=https://denialwm.org

# 与 Phosh、getty 互斥：三者都占用 tty7 / DRM master
Conflicts=getty@tty1.service phosh.service
After=getty@tty1.service
After=rc-local.service plymouth-quit-wait.service systemd-user-sessions.service
OnFailure=getty@tty1.service

Wants=dbus.socket
After=dbus.socket

# 与 phosh.service 相同的 logind 会话作用域等待
After=session-c1.scope
Before=graphical.target
ConditionPathExists=/dev/tty0

# fuxi：等用户管理器（user@1000）与 logind 就绪再开会话
Wants=user@1000.service
After=user@1000.service systemd-logind.service

[Service]
Environment=LANG=zh_CN.UTF-8
Environment=XDG_CURRENT_DESKTOP=Denial
Environment=XDG_SESSION_DESKTOP=denial
Environment=XDG_SESSION_TYPE=wayland
Environment=DENIAL_SHELL_PROFILE=mobile
# 手机面板 1080x2400，Denial 移动外壳按逻辑坐标工作；缩放由 /etc/denial/outputs.conf 决定
ExecStartPre=+/usr/bin/systemctl --user --machine=fuxi@.host start dbus.socket
ExecStart=/usr/bin/denial-session
# 切到会话 VT（与 phosh.service 的 ExecStartPost=+chvt 7 一致）
ExecStartPost=+chvt 7
TimeoutStartSec=60
User=1000
PAMName=login
WorkingDirectory=~
Restart=always
RestartSec=5s

TTYPath=/dev/tty7
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes

# 必须真正接管 tty，否则会话没有前台终端
StandardInput=tty-fail
StandardOutput=journal
StandardError=journal

UtmpIdentifier=tty7
UtmpMode=user

[Install]
WantedBy=graphical.target
EOF
}

unit_install() {
    say "== 安装 denial.service 与会话配置"
    session_unit | ssh_ 'cat > /etc/systemd/system/denial.service && chmod 644 /etc/systemd/system/denial.service'
    # 移动外壳 + 中文环境写进机器配置（denial-session 会 source 它）
    ssh_ 'set -e
mkdir -p /etc/denial
touch /etc/denial/session.conf
if ! grep -q "^DENIAL_SHELL_PROFILE=mobile$" /etc/denial/session.conf; then
  printf "\n# fuxi: 手机使用移动桌面外壳\nDENIAL_SHELL_PROFILE=mobile\n" >> /etc/denial/session.conf
fi
systemctl daemon-reload
# 新装的 user 单元（denial-session.target 等）要让 fuxi 的用户管理器可见
systemctl --user --machine=fuxi@.host daemon-reload || true
echo unit-ok'
}

cmd_status() {
    require_device
    T=60 ssh_ 'set +e
echo "== 服务 =="
for u in phosh denial; do printf "%-8s enabled=%s active=%s\n" "$u" "$(systemctl is-enabled $u 2>/dev/null)" "$(systemctl is-active $u 2>/dev/null)"; done
echo "== 进程 =="
pgrep -a -x deniald || echo "deniald: 未运行"
pgrep -a -x phoc || echo "phoc: 未运行"
echo "== 会话/seat =="
loginctl list-sessions --no-legend 2>/dev/null
echo "== Wayland sockets =="
ls /run/user/1000/wayland-* 2>/dev/null || echo "(无)"
echo "== denialctl =="
sudo -u fuxi env XDG_RUNTIME_DIR=/run/user/1000 DENIAL_SOCKET=/run/user/1000/denial/control.sock /usr/bin/denialctl status 2>&1 | head -20
echo "== denial 日志尾部 =="
journalctl -u denial -b --no-pager -o cat -n 15 2>/dev/null || echo "(无)"'
}

cmd_install() {
    local payload="${1:-$PAYLOAD_DEFAULT}"
    [ -d "$payload" ] || { echo "ERROR: 构建树不存在：$payload" >&2; exit 1; }
    [ -x "$payload/usr/bin/deniald" ] || { echo "ERROR: $payload 不是 root 镜像式安装树（缺 usr/bin/deniald）。" >&2; exit 1; }
    require_device
    say "== 检查设备端依赖"
    T=60 ssh_ 'for c in tar systemctl journalctl; do command -v $c >/dev/null || echo "MISSING $c"; done; echo ok'
    say "== 上传安装树到 /（不切换会话、不改开机默认）"
    local tarfile
    tarfile="$(mktemp /tmp/denial-payload-XXXXXX.tar)"
    trap 'rm -f "$tarfile"' RETURN
    tar -C "$payload" -cf "$tarfile" . || { echo "ERROR: 打包失败" >&2; exit 1; }
    say "  安装树打包 $(du -h "$tarfile" | cut -f1)，上传并解包到 /"
    T=900 ssh_ 'set -e
cat > /tmp/denial-payload.tar
tar -xpf /tmp/denial-payload.tar -C /
rm -f /tmp/denial-payload.tar
echo upload-ok' < "$tarfile" || {
        echo "ERROR: 上传/解包失败" >&2; exit 1; }
    unit_install
    say "== 安装后自检"
    T=60 ssh_ 'set +e
for f in /usr/bin/deniald /usr/bin/denialctl /usr/bin/denial-portal /usr/bin/denial-session \
         /usr/bin/denial-settings \
         /usr/lib/denial/flutter/lib/libapp.so \
         /usr/lib/denial/flutter/lib/libflutter_engine.so \
         /usr/lib/denial/flutter/data/icudtl.dat \
         /usr/lib/denial/settings/denial-settings \
         /usr/lib/systemd/user/denial-session.target \
         /usr/share/wayland-sessions/denial.desktop; do
  [ -e "$f" ] && printf "OK   %s\n" "$f" || printf "MISS %s\n" "$f"
done
echo "-- ELF 架构（必须全为 aarch64） --"
file /usr/bin/deniald /usr/bin/denialctl /usr/bin/denial-portal \
     /usr/lib/denial/flutter/lib/libapp.so \
     /usr/lib/denial/flutter/lib/libflutter_engine.so \
     /usr/lib/denial/settings/denial-settings 2>/dev/null | sed "s/^/     /"
echo "-- session.conf --"
grep -n "DENIAL_SHELL_PROFILE" /etc/denial/session.conf || echo "(未设置 mobile)"
systemctl cat denial >/dev/null 2>&1 && echo "OK   denial.service 已加载" || echo "MISS denial.service"
echo "== 当前仍在 Phosh =="; systemctl is-active phosh'
    say "完成。下一步：scripts/fuxi-denial.sh check（前置检查）→ switch（失败自动回退）"
}

cmd_deps() {
    require_device
    say "== 安装 xwayland 与 wlr portal（arm64）"
    T=600 ssh_ 'export DEBIAN_FRONTEND=noninteractive; apt-get update -q 2>&1 | tail -n 1
apt-get install -y --no-install-recommends xwayland xdg-desktop-portal-wlr 2>&1 | tail -n 5
dpkg -s xwayland xdg-desktop-portal-wlr 2>/dev/null | grep -E "^Package|^Status"'
}

cmd_check() {
    require_device
    say "== denial-session --check（以 fuxi 用户；只做前置检查，不启动合成器）"
    T=120 ssh_ 'set +e
sudo -u fuxi env XDG_RUNTIME_DIR=/run/user/1000 HOME=/home/fuxi /usr/bin/denial-session --check 2>&1 | tail -40
echo "exit=$?"'
}

# 切换后验证：服务 active + deniald 进程 + denialctl status 有响应
verify_denial_up() {
    local i
    for i in $(seq 1 12); do
        sleep 3
        if T=30 ssh_ 'systemctl is-active --quiet denial && pgrep -x deniald >/dev/null' >/dev/null 2>&1; then
            T=30 ssh_ 'sudo -u fuxi env XDG_RUNTIME_DIR=/run/user/1000 DENIAL_SOCKET=/run/user/1000/denial/control.sock /usr/bin/denialctl status' >/tmp/denial-status-$$.txt 2>&1
            if [ $? -eq 0 ]; then
                sed -n '1,20p' /tmp/denial-status-$$.txt
                rm -f /tmp/denial-status-$$.txt
                return 0
            fi
        fi
        say "  等待 Denial 就绪（${i}/12）"
    done
    rm -f /tmp/denial-status-$$.txt
    return 1
}

cmd_switch() {
    require_device
    say "== 切换：Phosh → Denial"
    local log="$LOG_DIR/denial-switch-$TS.log"
    T=120 ssh_ 'set -e
systemctl is-active --quiet denial && { echo "denial 已在运行"; exit 0; }
echo "-- 停止 phosh"
systemctl stop phosh.service
sleep 2
echo "-- 启动 denial"
systemctl start denial.service
sleep 3
systemctl is-active denial.service' 2>&1 | tee "$log"
    if ! verify_denial_up; then
        say "!! Denial 未在 36s 内就绪，自动回退 Phosh"
        T=120 ssh_ 'set +e
systemctl stop denial.service
systemctl start phosh.service
sleep 3
echo "phosh=$(systemctl is-active phosh.service)"' 2>&1 | tee -a "$log"
        echo "已回退 Phosh。取证：scripts/fuxi-denial.sh logs；切换日志 $log" >&2
        exit 1
    fi
    say "Denial 已启动（未改开机默认；重启仍回 Phosh）"
    say "截图：scripts/fuxi-denial.sh shot denial-first"
    say "回退：scripts/fuxi-denial.sh rollback"
}

cmd_rollback() {
    require_device
    say "== 回退：Denial → Phosh"
    local log="$LOG_DIR/denial-rollback-$TS.log"
    T=180 ssh_ 'set +e
systemctl stop denial.service 2>/dev/null
systemctl start phosh.service
sleep 5
echo "phosh=$(systemctl is-active phosh.service) denial=$(systemctl is-active denial.service)"
loginctl list-sessions --no-legend 2>/dev/null
journalctl -u denial -b --no-pager -o cat -n 10' 2>&1 | tee "$log"
    if ! T=30 ssh_ 'systemctl is-active --quiet phosh' >/dev/null 2>&1; then
        echo "ERROR: Phosh 未起来，请检查：systemctl status phosh；journalctl -u phosh -b" >&2
        exit 1
    fi
    say "已回退 Phosh（日志 $log）"
}

cmd_enable_default() {
    require_device
    say "== 把开机默认改成 Denial（先确认当前 Denial 会话可用）"
    T=60 ssh_ 'set -e
systemctl is-active --quiet denial || { echo "ERROR: denial 当前未运行，先 switch 并验证" >&2; exit 1; }
systemctl disable phosh.service
systemctl enable denial.service
printf "phosh enabled=%s active=%s\ndenial enabled=%s active=%s\n" \
  "$(systemctl is-enabled phosh)" "$(systemctl is-active phosh)" \
  "$(systemctl is-enabled denial)" "$(systemctl is-active denial)"'
    say "开机默认已改为 Denial；回退：scripts/fuxi-denial.sh rollback && scripts/fuxi-denial.sh disable-default"
}

cmd_disable_default() {
    require_device
    say "== 恢复开机默认 Phosh"
    T=60 ssh_ 'set -e
systemctl disable denial.service 2>/dev/null || true
systemctl enable phosh.service
printf "phosh enabled=%s\ndenial enabled=%s\n" "$(systemctl is-enabled phosh)" "$(systemctl is-enabled denial 2>/dev/null || echo disabled)"'
}

cmd_logs() {
    require_device
    local n="${1:-60}"
    T=60 ssh_ "journalctl -u denial -b --no-pager -o short-iso 2>/dev/null | tail -n $n"
}

cmd_shot() {
    require_device
    local name="${1:-denial-$(date +%Y%m%d-%H%M%S)}"
    mkdir -p "$SHOT_DIR"
    local remote="/tmp/fuxi-denial-shot-$$.png"
    T=60 ssh_ "set -e
sock=\$(ls /run/user/1000/wayland-* 2>/dev/null | head -1)
[ -n \"\$sock\" ] || { echo 'ERROR: 没有 Wayland socket' >&2; exit 1; }
sudo -u fuxi env XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=\${sock##*/} grim '$remote'" || {
        echo "ERROR: grim 截图失败（Denial 是否在跑？是否支持 screencopy？）" >&2; exit 1; }
    T=60 ssh_ "cat '$remote'; rm -f '$remote'" > "$SHOT_DIR/$name.png" || {
        echo "ERROR: 拉回截图失败" >&2; rm -f "$SHOT_DIR/$name.png"; exit 1; }
    echo "$SHOT_DIR/$name.png"
}

main() {
    local cmd="${1:-}"
    case "$cmd" in
        status)         cmd_status ;;
        install)        shift; cmd_install "$@" ;;
        deps)           cmd_deps ;;
        check)          cmd_check ;;
        switch)         cmd_switch ;;
        rollback)       cmd_rollback ;;
        enable-default) cmd_enable_default ;;
        disable-default) cmd_disable_default ;;
        logs)           shift; cmd_logs "$@" ;;
        shot)           shift; cmd_shot "$@" ;;
        *)
            sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
            exit 2
            ;;
    esac
}

main "$@"
