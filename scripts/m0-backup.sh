#!/usr/bin/env bash
# M0：小米13（fuxi）移植前分区备份 —— 全程只读，不写设备
#
# 前置：手机开启「Rooted debugging」并 adb root 成功
# 用法：./scripts/m0-backup.sh [输出目录]
# 产物：backups/<时间戳>/{*.img, SHA256SUMS, manifest.txt}
#
# 说明：
#  - 用 adb exec-out 流式读取 /dev/block/by-name/*，不在设备上落临时文件
#  - 每个分区比对「设备端 sha256」与「本机 sha256」，不一致即为备份损坏
#  - persist/modemst1/modemst2/fsg/fsc 是唯一数据，丢了 IMEI/校准就找不回来
#  - super/userdata 不备份（体积巨大，重刷官方 fastboot 包即可恢复）
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ADB=${ADB:-$HERE/../tools/platform-tools/adb}
OUT=${1:-$HERE/../backups/$(date +%Y%m%d-%H%M%S)}

# 关键分区（双槽）
PARTS="persist modemst1 modemst2 fsg fsc
boot_a boot_b init_boot_a init_boot_b
vendor_boot_a vendor_boot_b vbmeta_a vbmeta_b
vbmeta_system_a vbmeta_system_b dtbo_a dtbo_b
recovery_a recovery_b"

fail=0
d() { "$ADB" shell "$*" 2>&1 | tr -d '\r'; }

echo "== 前置检查 =="
"$ADB" devices | grep -q "device$" || { echo "错误: 设备未连接"; exit 1; }
uid=$(d 'id -u')
if [ "$uid" != "0" ]; then
  echo "错误: 当前 uid=$uid，不是 root。"
  echo "请在手机上开启: 设置 → 系统 → 开发者选项 → Rooted debugging，然后重试。"
  exit 1
fi
echo "root OK"

mkdir -p "$OUT"
MAN="$OUT/manifest.txt"
echo "# fuxi 分区备份 $(date -Is)" | tee "$MAN"
echo "# device: $(d 'getprop ro.build.display.id') / kernel $(d 'uname -r')" | tee -a "$MAN"
echo "# 分区             大小(字节)        设备sha256前16位    本机校验" | tee -a "$MAN"

: > "$OUT/SHA256SUMS"

ok=0; skipped=0
# 前置校验：by-name 必须存在（若 /dev 异常会全是空，必须直接报错而不是"全部跳过"）
n=$(d 'ls /dev/block/by-name 2>/dev/null | wc -l' | tr -d ' ')
if [ "${n:-0}" -lt 10 ]; then
  echo "错误: /dev/block/by-name 只有 ${n:-0} 个条目，疑似 /dev 异常或未 root。终止。"
  exit 1
fi
echo "by-name 条目数: $n"

for p in $PARTS; do
  dev=/dev/block/by-name/$p
  if [ "$(d "test -e $dev && echo YES")" != "YES" ]; then
    printf "%-18s %s\n" "$p" "跳过（分区不存在）" | tee -a "$MAN"
    skipped=$((skipped+1)); continue
  fi
  size=$(d "blockdev --getsize64 $dev")
  printf "备份 %-18s %10s 字节 ... " "$p" "$size"
  if ! "$ADB" exec-out "dd if=$dev bs=1M 2>/dev/null" > "$OUT/$p.img"; then
    echo "失败"; fail=1; continue
  fi
  local_size=$(stat -c%s "$OUT/$p.img" 2>/dev/null || echo 0)
  if [ "$local_size" != "$size" ]; then
    echo "大小不符 (本地 $local_size != 设备 $size)"; fail=1; continue
  fi
  dev_sha=$(d "sha256sum $dev" | awk '{print $1}')
  loc_sha=$(sha256sum "$OUT/$p.img" | awk '{print $1}')
  if [ "$dev_sha" = "$loc_sha" ]; then
    echo "OK"
    ok=$((ok+1))
    echo "$loc_sha  $p.img" >> "$OUT/SHA256SUMS"
    printf "%-18s %14s   %s  OK\n" "$p" "$size" "${dev_sha:0:16}" >> "$MAN"
  else
    echo "SHA256 不一致!"
    printf "%-18s %14s   %s  MISMATCH(本机 %s)\n" "$p" "$size" "${dev_sha:0:16}" "${loc_sha:0:16}" >> "$MAN"
    fail=1
  fi
done

echo
echo "== 结果 =="
echo "目录: $OUT"
echo "成功: $ok 个   跳过: $skipped 个"
du -sh "$OUT" 2>/dev/null
if [ "$fail" != "0" ] || [ "$ok" -eq 0 ]; then
  echo "❌ 备份失败（成功 $ok 个），见 $MAN"
  exit 1
fi
echo "✅ 已备份 $ok 个分区，全部通过双向 SHA256 校验"
echo
echo "⚠️ 请把 $OUT 复制到另一台机器 / 离线介质，并保留一份 SHA256SUMS 的离线打印。"
exit "$fail"
