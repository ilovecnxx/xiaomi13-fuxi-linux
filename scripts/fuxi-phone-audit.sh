#!/bin/bash
# 手机状态核查（只读）：在 Android 下对照 10-24 的分区备份清单，找出被改过的分区；识别 recovery_b 里是哪个镜像。
# 用于「手机被别的程序/模型动过」之后决定要还原什么。本脚本不写任何分区。
#   - 清单分区：持久数据（persist/modemst/fsg/fsc）、boot/init_boot/vendor_boot/vbmeta/dtbo/recovery（a/b）
#   - recovery_b：按每个 work/kbuild/*.img 的长度读回算 sha256，与本机镜像逐个比对
#   - 槽位/版本：ro.boot.slot_suffix、ro.build.fingerprint、ro.boot.verifiedbootstate
# 还原原则：只写 recovery_b（与 sda33）；Android/固件分区只有和备份不一致且用户同意时才用备份写回。
# 用法: scripts/fuxi-phone-audit.sh     报告: work/claude-logs/phone-audit-<时间>.txt
set -u
B="$(cd "$(dirname "$0")/.." && pwd)"
. "$B/scripts/fuxi-lib.sh"
ADB="$FUXI_ADB"
MAN="$B/backups/20261024-172623/manifest.txt"
R="$B/work/claude-logs/phone-audit-$(date +%Y%m%d-%H%M%S).txt"
exec > >(tee -a "$R") 2>&1
say() { echo "$(date +%T) $*"; }

fuxi_ensure_android "${WAIT_ANDROID:-600}" || exit 1
say "== 系统"
timeout 20 "$ADB" shell 'echo "slot=$(getprop ro.boot.slot_suffix) vbstate=$(getprop ro.boot.verifiedbootstate) unlocked=$(getprop ro.boot.flash.locked)"; getprop ro.build.fingerprint; getprop ro.build.date; uptime' | tr -d '\r'

say "== 分区对照 10-24 备份（设备 sha256 前 16 位）"
changed=()
while read -r part size want _; do
  case "$part" in ''|\#*) continue ;; esac
  got=$(timeout 300 "$ADB" shell "head -c $size /dev/block/by-name/$part | sha256sum | cut -c1-16" < /dev/null | tr -d '\r')
  if [ "$got" = "$want" ]; then printf "  %-16s 一致 %s\n" "$part" "$got"
  else printf "  %-16s ★不同  现在 %s  备份 %s\n" "$part" "$got" "$want"; changed+=("$part"); fi
done < "$MAN"

say "== recovery_b 里是哪个镜像"
found=""
for img in "$B"/work/kbuild/abl-fuxi-*.img "$B"/work/patches/abl-recovery-dualboot-20261027/recovery-linux.img; do
  [ -f "$img" ] || continue
  n=$(stat -c %s "$img"); want=$(sha256sum "$img" | cut -c1-16)
  got=$(timeout 120 "$ADB" shell "head -c $n /dev/block/by-name/recovery_b | sha256sum | cut -c1-16" < /dev/null | tr -d '\r')
  [ "$got" = "$want" ] && { found=$(basename "$img"); break; }
done
echo "  recovery_b = ${found:-（不是本机任何已知镜像）}"
timeout 20 "$ADB" shell 'head -c 8 /dev/block/by-name/recovery_b | od -c | head -n 1' | tr -d '\r'

say "== 结论"
if [ ${#changed[@]} -eq 0 ]; then echo "  清单里的分区都与 10-24 备份一致"
else echo "  与备份不同的分区：${changed[*]}（recovery_b 不同是正常的：里面是 Linux 镜像）"; fi
echo "报告 $R"
