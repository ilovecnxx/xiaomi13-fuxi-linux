#!/bin/bash
# ssh 到主线内核上的 Ubuntu（USB 网络：手机 10.42.0.2，主机 NM 共享连接 fuxi-usb 10.42.0.1）
# 用法: scripts/fuxi-ssh.sh [命令...]
B="$(cd "$(dirname "$0")/.." && pwd)"
exec ssh -i "$B/work/ssh/fuxi_root" -o UserKnownHostsFile="$B/work/ssh/known_hosts" -o StrictHostKeyChecking=accept-new \
  -o ConnectTimeout=5 root@10.42.0.2 "$@"
