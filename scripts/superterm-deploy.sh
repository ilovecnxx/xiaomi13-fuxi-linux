#!/bin/bash
# 在手机（Xiaomi 13 fuxi，Ubuntu 26.10 arm64 主线 Linux + Phosh）部署 SuperTerm 原生超级终端 App。
# 把 work/superterm 打包上传，调用 packaging/install-remote.sh 安装成 ~/.local/share/superterm，
# 生成桌面图标 superterm.desktop。原生 GTK4+WebKit 窗口，非安卓 APK。
#
# 用法:
#   FUXI_HOST=10.10.10.43 scripts/superterm-deploy.sh        # WiFi 部署
#   scripts/superterm-deploy.sh                               # USB 网络部署（手机 10.42.0.2）
#   scripts/superterm-deploy.sh --user fuxi                   # 目标用户（默认 fuxi）
#   scripts/superterm-deploy.sh --no-deps                     # 跳过 apt/npm 依赖安装
#   scripts/superterm-deploy.sh --rollback                    # 回滚到上一版本
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PHONE="${FUXI_HOST:-10.42.0.2}"
KEY="$ROOT/work/ssh/fuxi_root"
KNOWN="$ROOT/work/ssh/known_hosts"
TARGET_USER="fuxi"
NO_DEPS=0
ROLLBACK=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --user) TARGET_USER="$2"; shift 2;;
    --no-deps) NO_DEPS=1; shift;;
    --rollback) ROLLBACK=1; shift;;
    -h|--help) sed -n '1,20p' "$0"; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

ssh_run(){ ssh -i "$KEY" -o UserKnownHostsFile="$KNOWN" -o StrictHostKeyChecking=accept-new \
  -o ConnectTimeout=8 root@"$PHONE" "$@"; }

echo "[deploy] target $PHONE user=$TARGET_USER"
ssh_run 'echo remote-ok'

if [ "$ROLLBACK" = 1 ]; then
  echo "[deploy] rollback"
  tar -C "$ROOT/work/superterm/packaging" -czf - install-remote.sh | \
    ssh -i "$KEY" -o UserKnownHostsFile="$KNOWN" -o StrictHostKeyChecking=accept-new root@"$PHONE" \
      'mkdir -p /root/superterm-pkg && tar -C /root/superterm-pkg -xzf - && chmod +x /root/superterm-pkg/install-remote.sh && /root/superterm-pkg/install-remote.sh --user '"$TARGET_USER"' --rollback'
  exit 0
fi

echo "[deploy] staging package"
# stage: source tree + packaging (exclude pycache/tests caches)
tar --exclude='__pycache__' --exclude='*.pyc' -C "$ROOT/work/superterm" -czf /tmp/superterm-pkg.tgz .
ssh -i "$KEY" -o UserKnownHostsFile="$KNOWN" -o StrictHostKeyChecking=accept-new root@"$PHONE" 'rm -rf /root/superterm-pkg && mkdir -p /root/superterm-pkg'
cat /tmp/superterm-pkg.tgz | ssh -i "$KEY" -o UserKnownHostsFile="$KNOWN" -o StrictHostKeyChecking=accept-new root@"$PHONE" 'tar -C /root/superterm-pkg -xzf -'

echo "[deploy] running installer"
DEPS_FLAG=""; [ "$NO_DEPS" = 1 ] && DEPS_FLAG="--no-deps"
ssh -i "$KEY" -o UserKnownHostsFile="$KNOWN" -o StrictHostKeyChecking=accept-new root@"$PHONE" \
  "chmod +x /root/superterm-pkg/packaging/install-remote.sh && /root/superterm-pkg/packaging/install-remote.sh --user $TARGET_USER $DEPS_FLAG"

echo "[deploy] done. 手机上桌面出现 SuperTerm 图标，点开即用。"
