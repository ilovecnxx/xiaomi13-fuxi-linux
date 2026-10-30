#!/usr/bin/env bash
# 小米13 (fuxi) 可行性探测脚本 —— 只读，不修改设备任何内容
# 用法: ./scripts/probe-device.sh [输出文件]
set -uo pipefail

ADB="${ADB:-$(dirname "$0")/../tools/platform-tools/adb}"
OUT="${1:-$(dirname "$0")/../reports/device-probe.txt}"
mkdir -p "$(dirname "$OUT")"
: > "$OUT"

say() { printf '\n===== %s =====\n' "$*" >> "$OUT"; }
sh_() { # 在设备上执行，容忍失败
  local desc="$1"; shift
  say "$desc"
  "$ADB" shell "$@" 2>&1 | sed 's/\r$//' >> "$OUT" || echo "[命令失败]" >> "$OUT"
}

say "探测时间"; date -Is >> "$OUT"
say "adb 版本"; "$ADB" version >> "$OUT" 2>&1
say "设备列表"; "$ADB" devices -l >> "$OUT" 2>&1

echo "[1/9] 构建属性..."
sh_ "构建属性" 'getprop | grep -E "ro.product.(device|model|name|brand)|ro.build.(version.release|version.sdk|type|date|flavor|version.incremental)|ro.lineage|ro.modversion|ro.build.ab_update|ro.boot.slot_suffix|ro.boot.dynamic_partitions|ro.treble|ro.vndk|ro.product.cpu.abilist|ro.build.version.security_patch|ro.boot.verifiedbootstate|ro.boot.flash.locked|ro.debuggable|ro.secure|ro.product.cpu.pagesize"'

echo "[2/9] 内核..."
sh_ "内核版本" 'uname -a; echo ---; cat /proc/version; echo ---; cat /proc/cmdline'

echo "[3/9] 内存页大小..."
say "页大小"
"$ADB" shell 'getconf PAGESIZE 2>/dev/null || toybox getconf PAGESIZE 2>/dev/null || grep -m1 KernelPageSize /proc/self/smaps' 2>&1 | sed 's/\r$//' >> "$OUT"

echo "[4/9] root / SELinux..."
sh_ "当前身份" 'id; echo ---; getenforce 2>/dev/null; echo ---; which su 2>/dev/null; ls -d /data/adb 2>/dev/null; ls /data/adb/modules 2>/dev/null'
say "adb root 尝试"
"$ADB" root 2>&1 | sed 's/\r$//' >> "$OUT"
sleep 3
"$ADB" wait-for-device 2>&1 >> "$OUT" || true
say "adb root 后身份"
"$ADB" shell 'id; getenforce' 2>&1 | sed 's/\r$//' >> "$OUT"

echo "[5/9] 分区与块设备..."
sh_ "by-name 分区" 'ls /dev/block/by-name/ 2>/dev/null | sort'
sh_ "分区表" 'cat /proc/partitions'
sh_ "槽位/super 信息" 'ls -l /dev/block/by-name/super /dev/block/by-name/boot /dev/block/by-name/init_boot /dev/block/by-name/userdata 2>/dev/null'

echo "[6/9] 存储空间..."
sh_ "df" 'df -h 2>/dev/null | grep -E "Filesystem|/data|/storage|/cache"'

echo "[7/9] 挂载与 /data 文件系统..."
sh_ "mount (data)" 'mount 2>/dev/null | grep -E " /data | /cache | /storage/emulated "'

echo "[8/9] 用户态能力..."
sh_ "userland 工具" 'for t in chroot unshare mount nsenter proot busybox toybox curl wget tar; do printf "%-10s %s\n" "$t" "$(command -v $t 2>/dev/null || echo -)"; done; echo ---; ls /system/etc/ld.config*.txt 2>/dev/null | head'

echo "[9/9] 已有 Linux 环境痕迹..."
sh_ "termux/容器痕迹" 'ls -d /data/data/com.termux 2>/dev/null; ls -d /data/local/ubuntu* /data/ubuntu* 2>/dev/null; echo "(空=无)"'

say "完成"
echo "探测结果已写入: $OUT"
