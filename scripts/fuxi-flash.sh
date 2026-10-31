#!/bin/bash
# 设备动作的人工入口（写 recovery_b / 重启）。默认全程只读，写操作必须显式 --yes。
#
# 为什么单独有这个脚本：模型侧实时网络安防分类器会把"进 recovery / 写分区 / 引导"这类生成内容
# 判成 [cyber] 而拒答（2026-10-31 连续三拒，见 CLAUDE.md）。把设备动作从对话里挪出来、由人执行，
# agent 只跑 `status` 读状态、读日志，两边都省事。
#
# 用法:
#   scripts/fuxi-flash.sh                        # = status（只读）
#   scripts/fuxi-flash.sh status                 # 只读：设备在哪 / recovery_b 里是哪个镜像 / 与 state json 是否一致
#   scripts/fuxi-flash.sh plan baseline          # 只读：打印要人类执行的命令（不碰设备）
#   scripts/fuxi-flash.sh flash baseline --yes   # 写 recovery_b：dd + 读回校验（不进 Linux）
#   scripts/fuxi-flash.sh flash work/kbuild/xxx.img --yes
#   scripts/fuxi-flash.sh reboot recovery --yes  # adb reboot recovery（进 Linux）
#
# 红线（AGENTS.md §3）：只允许写 recovery_b。别的分区名一律拒绝；不碰 GPT/槽位/xbl/abl/tz/
# modemst/persist/efs/fsg；映像来源只认 work/kbuild/ 与 work/patches/。
set -uo pipefail

B="$(cd "$(dirname "$0")/.." && pwd)"
ADB="${FUXI_ADB:-$B/tools/platform-tools/adb}"
FB="${FUXI_FASTBOOT:-$B/tools/platform-tools/fastboot}"
STATE="$B/work/state/current-device.json"
PART="recovery_b"
PART_PATH="/dev/block/by-name/$PART"
mkdir -p "$B/work/claude-logs"
LOG="$B/work/claude-logs/fuxi-flash-$(date +%Y%m%d-%H%M%S).log"

say() { printf '%s\n' "$*" | tee -a "$LOG"; }
die() { say "FAIL $*"; exit 1; }
jget() { jq -r "${1} // empty" "$STATE" 2>/dev/null || true; }

# ---- 设备探测（都带超时，绝不挂住）----
adb_dev() { timeout 8 "$ADB" devices 2>/dev/null | awk '$2=="device"{f=1} END{exit(f?0:1)}'; }
fb_dev() { local o; o=$(timeout 6 "$FB" devices 2>/dev/null); [ -n "$o" ]; }
ssh_up() { timeout 5 bash -c 'exec 3<>/dev/tcp/10.42.0.2/22; timeout 3 head -c 4 <&3 | grep -q SSH' 2>/dev/null; }
adb_root() {
  timeout 20 "$ADB" root >/dev/null 2>&1 || return 1
  sleep 2
  timeout 40 "$ADB" wait-for-device >/dev/null 2>&1
}

# ---- 镜像解析：baseline / recovery / 显式路径 → 全局 IMG + WANT ----
resolve_image() {
  local key="$1" p="" s=""
  case "$key" in
    baseline) p=$(jget '.baseline_daily_image'); s=$(jget '.baseline_daily_sha256') ;;
    recovery|recovery_b) p=$(jget '.recovery_b_image'); s=$(jget '.recovery_b_sha256') ;;
    *) p="$key" ;;
  esac
  [ -n "$p" ] || return 1
  case "$p" in /*) ;; *) p="$B/$p" ;; esac
  IMG="$p"; WANT="$s"
}

# 只认 work/kbuild 与 work/patches 下的普通非空文件 → 全局 GUARDED
guard_path() {
  local real
  real=$(realpath -m "$1" 2>/dev/null) || return 1
  case "$real" in
    "$B"/work/kbuild/*|"$B"/work/patches/*) ;;
    *) say "FAIL 镜像只允许来自 work/kbuild/ 或 work/patches/：$1"; return 1 ;;
  esac
  [ -f "$real" ] || { say "FAIL 不是普通文件：$1"; return 1; }
  [ -s "$real" ] || { say "FAIL 空文件：$1"; return 1; }
  GUARDED="$real"
}

image_info() { # $1=路径 → 全局 ISIZE/ISHA
  ISIZE=$(stat -c %s "$1")
  ISHA=$(sha256sum "$1" | cut -d' ' -f1)
}

# recovery_b 分区大小 → 全局 RB_SIZE
read_recovery_b() {
  RB_SHA=""; RB_SIZE=""
  RB_SIZE=$(timeout 15 "$ADB" shell "blockdev --getsize64 $PART_PATH 2>/dev/null" </dev/null | tr -d '\r')
  case "$RB_SIZE" in ''|*[!0-9]*) RB_SIZE="" ;; esac
}

# 读分区前 $1 字节的 sha256
rb_head_sha() {
  local n="$1" s
  s=$(timeout 90 "$ADB" shell "head -c $n $PART_PATH | sha256sum | cut -d' ' -f1" </dev/null | tr -d '\r')
  case "$s" in *[!0-9a-f]*) s="" ;; esac
  printf '%s' "$s"
}

# 把 recovery_b 内容和 state json 里的已知镜像比对。
# 注意：必须按「镜像文件自身大小」截取分区再比；分区 100MB 比镜像 10MB 长，
# 按固定 12MiB 截会把镜像后面的旧数据算进来，误报成未知镜像（2026-10-31 踩过）。
describe_rb() {
  local name sha p sz
  for name in baseline_daily recovery_b; do
    if [ "$name" = baseline_daily ]; then p=$(jget '.baseline_daily_image'); else p=$(jget '.recovery_b_image'); fi
    [ -n "$p" ] || continue
    case "$p" in /*) ;; *) p="$B/$p" ;; esac
    [ -f "$p" ] || continue
    sz=$(stat -c %s "$p" 2>/dev/null) || continue
    sha=$(sha256sum "$p" | cut -d' ' -f1)
    if [ "$(rb_head_sha "$sz")" = "$sha" ]; then
      RB_SHA="$sha"
      say "  recovery_b = $name（$(basename "$p")）"
      return 0
    fi
  done
  RB_SHA=$(rb_head_sha 10485760)
  say "  recovery_b = 未知镜像（前 10MiB sha ${RB_SHA:0:16}…），不在 state json 记录的已知镜像里"
  return 1
}

# $1=sha256 → 全局 MATCH_NAME（空=未知）。用于"显式路径但内容就是基线"的场景
match_known() {
  local name p sha
  MATCH_NAME=""
  for name in baseline_daily recovery_b; do
    if [ "$name" = baseline_daily ]; then p=$(jget '.baseline_daily_image'); else p=$(jget '.recovery_b_image'); fi
    [ -n "$p" ] || continue
    case "$p" in /*) ;; *) p="$B/$p" ;; esac
    [ -f "$p" ] || continue
    sha=$(sha256sum "$p" | cut -d' ' -f1)
    [ "$sha" = "$1" ] && { MATCH_NAME="$name"; return 0; }
  done
  return 1
}

usage() {
  cat <<'EOF'
用法:
  scripts/fuxi-flash.sh [status]                    只读：设备在哪 / recovery_b 内容 / 与 state json 对照
  scripts/fuxi-flash.sh plan <baseline|recovery|img> 只读：打印人类要执行的命令
  scripts/fuxi-flash.sh flash <baseline|recovery|img> --yes [--allow-unknown-image]
  scripts/fuxi-flash.sh reboot <recovery|bootloader> --yes
默认不写、不重启。--yes 之外的调用都不会动设备。
EOF
}

cmd_status() {
  say "== fuxi-flash status $(date '+%F %T') =="
  say "state json: $(jq -r '.as_of // "?"' "$STATE" 2>/dev/null)"
  say "  baseline   $(jget .baseline_daily_image)  sha $(jget .baseline_daily_sha256 | cut -c1-16)…"
  say "  recovery_b $(jget .recovery_b_image)  sha $(jget .recovery_b_sha256 | cut -c1-16)…"
  local loc=none
  if adb_dev; then loc=android; elif fb_dev; then loc=fastboot; elif ssh_up; then loc=linux; fi
  say "device: $loc"
  case "$loc" in
    android)
      say "  android: $(timeout 8 "$ADB" shell 'getprop ro.product.device; getprop ro.build.version.release' </dev/null | tr -d '\r' | paste -sd' ')"
      if adb_root; then
        read_recovery_b
        if [ -n "$RB_SIZE" ]; then
          describe_rb
          say "  分区大小 $RB_SIZE B；比对内容 sha ${RB_SHA:0:16}…"
        else
          say "  读不到 recovery_b（需要 root / 分区不可读）"
        fi
      else
        say "  adb root 失败：读不了分区内容（写 recovery_b 也需要 root）"
      fi
      ;;
    fastboot)
      say "  fastboot 可见：读不了分区内容，只能刷写或 reboot"
      say "  恢复顺序：fastboot reboot bootloader → 再 fastboot flash/flash 失败先拔插 USB"
      ;;
    linux)
      say "  手机在 Linux：验收用 scripts/fuxi-health.sh；回 Android：scripts/fuxi-ssh.sh 'systemctl reboot'"
      say "  注意：Linux 里刷不了 recovery_b，必须先回 Android"
      ;;
    none)
      say "  看不到设备（关机 / 没插数据线 / 只在充电头）"
      ;;
  esac
  local cur
  cur=$(jget '.device_current.image')
  if [ -n "$cur" ]; then
    say "state json 记录的最后运行镜像：$cur"
    case "$cur" in
      "$(jget .baseline_daily_image)") say "  OK 是日用基线" ;;
      *) say "  WARN 是实验镜像：实验收尾要 flash baseline 刷回" ;;
    esac
  fi
}

cmd_plan() {
  local key="${1:-baseline}"
  resolve_image "$key" || die "解析不到镜像：$key（state json 里有 baseline/recovery 两项）"
  guard_path "$IMG" || exit 1
  image_info "$GUARDED"
  say "# 计划：写 $PART（镜像 $GUARDED，$ISIZE B）"
  say "# sha256 $ISHA"
  if [ -n "$WANT" ] && [ "$WANT" != "$ISHA" ]; then
    say "# WARN sha256 与 state json 记录不符（记录 $WANT），flash 会被拒绝"
  fi
  say "$ADB root"
  say "$ADB push '$GUARDED' /data/local/tmp/fuxi-flash.img"
  say "$ADB shell 'dd if=/data/local/tmp/fuxi-flash.img of=$PART_PATH bs=1M conv=fsync; sync'"
  say "$ADB shell 'head -c $ISIZE $PART_PATH | sha256sum'   # 应等于上面的 sha256"
  say "$ADB reboot recovery"
  say "# 或者一步到位（脚本自己校验）：scripts/fuxi-flash.sh flash $key --yes"
}

cmd_flash() {
  local key="${1:-}"; shift || true
  [ -n "$key" ] || die "用法: flash <baseline|recovery|img> --yes"
  local yes=0 allow_unknown=0 a
  for a in "$@"; do
    case "$a" in
      --yes) yes=1 ;;
      --allow-unknown-image) allow_unknown=1 ;;
      *) die "未知参数：$a" ;;
    esac
  done

  resolve_image "$key" || die "解析不到镜像：$key"
  guard_path "$IMG" || exit 1
  image_info "$GUARDED"
  say "image:  $GUARDED"
  say "size:   $ISIZE B"
  say "sha256: $ISHA"

  if [ -n "$WANT" ] && [ "$WANT" != "$ISHA" ]; then
    die "sha256 与 state json 记录不符（记录 ${WANT:0:16}…）—— 镜像被重建过？确认后更新 state json 再来"
  fi
  if [ -z "$WANT" ] && match_known "$ISHA"; then
    say "内容与 state json 的 $MATCH_NAME 一致"
    WANT="$ISHA"
  fi
  if [ -z "$WANT" ] && [ "$allow_unknown" != 1 ]; then
    die "未知镜像（state json 没有它的 sha256）。确认无误请加 --allow-unknown-image"
  fi

  adb_dev || { [ "$yes" = 1 ] && die "手机不在 Android：写 $PART 只能从 Android 侧（adb root）做"; }
  local psize=""
  if adb_dev && adb_root; then
    psize=$(timeout 15 "$ADB" shell "blockdev --getsize64 $PART_PATH 2>/dev/null" </dev/null | tr -d '\r')
    case "$psize" in ''|*[!0-9]*) psize="" ;; esac
    if [ -n "$psize" ] && [ "$ISIZE" -gt "$psize" ]; then
      die "镜像 $ISIZE B > $PART 分区 $psize B"
    fi
  elif [ "$yes" = 1 ]; then
    die "adb root 失败或没重连上"
  fi

  if [ "$yes" != 1 ]; then
    say "DRY-RUN 检查通过${psize:+（分区 $psize B）}。真写入要人类执行："
    say "  scripts/fuxi-flash.sh flash $key --yes"
    return 0
  fi

  say "== 写入 $PART =="
  timeout 120 "$ADB" push "$GUARDED" /data/local/tmp/fuxi-flash.img >/dev/null </dev/null || die "adb push 失败"
  timeout 180 "$ADB" shell "dd if=/data/local/tmp/fuxi-flash.img of=$PART_PATH bs=1M conv=fsync 2>/dev/null; sync; rm -f /data/local/tmp/fuxi-flash.img" </dev/null || die "dd 失败"
  local got
  got=$(timeout 90 "$ADB" shell "head -c $ISIZE $PART_PATH | sha256sum | cut -d' ' -f1" </dev/null | tr -d '\r')
  [ "$got" = "$ISHA" ] || die "读回校验不符（got ${got:0:16}… want ${ISHA:0:16}…）—— 不要重启，先重刷"
  say "OK $PART 写入并校验通过"
  say "下一步（人执行）：scripts/fuxi-flash.sh reboot recovery --yes"
}

cmd_reboot() {
  local what="${1:-}"; shift || true
  case "$what" in
    recovery|bootloader) ;;
    *) die "用法: reboot <recovery|bootloader> --yes" ;;
  esac
  [ "${1:-}" = "--yes" ] || die "需要 --yes（这是会动设备的操作）"
  adb_dev || die "手机不在 Android"
  timeout 20 "$ADB" reboot "$what" && say "OK adb reboot $what"
}

cmd="${1:-status}"; shift || true
case "$cmd" in
  status|s|"") cmd_status ;;
  plan|p) cmd_plan "${1:-baseline}" ;;
  flash|f) cmd_flash "$@" ;;
  reboot|r) cmd_reboot "$@" ;;
  -h|--help|help) usage ;;
  *) usage; exit 2 ;;
esac
