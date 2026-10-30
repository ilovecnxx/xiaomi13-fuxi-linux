#!/bin/bash
# 自动启动试验循环：等待 fastboot → boot/flash 镜像 → 监测设备返回状态 → 记录耗时到磁盘。
# 用法:
#   scripts/auto-boot-loop.sh [--flash] img1.img [img2.img ...]
# 环境变量:
#   ATTEMPTS=1           每张镜像重复次数
#   BOOT_TIMEOUT=240     等待设备重新出现在 USB 上的秒数（超时=判为卡死，需人工）
#   MODE=boot|flash      boot=fastboot boot（不写分区，推荐），flash=写 boot_b
# 结果: logs/auto-results.tsv  过程: logs/auto-loop.log
B="/home/user/文档/deepseek-harness/default-workspace/linux-android"
ADB="$B/tools/platform-tools/adb"; FB="$B/tools/platform-tools/fastboot"
LOGDIR="$B/logs"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/auto-loop.log"; RES="$LOGDIR/auto-results.tsv"
[ -f "$RES" ] || printf 'time\timage\tmd5\tcmd_rc\treturn_state\tduration_s\tnote\n' > "$RES"

MODE="${MODE:-boot}"; ATTEMPTS="${ATTEMPTS:-1}"; BOOT_TIMEOUT="${BOOT_TIMEOUT:-240}"
IMGS=(); for a in "$@"; do [ "$a" = "--flash" ] && MODE=flash || IMGS+=("$a"); done

log(){ echo "$(date '+%F %T') $*" | tee -a "$LOG"; }

usb_state(){
  local o; o=$(lsusb 2>/dev/null)
  if echo "$o" | grep -qE '18d1:4ee[0-9]|18d1:4e11'; then echo fastboot
  elif echo "$o" | grep -q '18d1:d00d'; then echo adb
  elif echo "$o" | grep -q '05c6:9008'; then echo edl
  elif echo "$o" | grep -q '18d1:'; then echo other
  else echo none; fi
}

wait_state(){ # wait_state <state> <timeout_s>  (fastboot 额外用 fastboot devices 校验)
  local want="$1" t="$2" t0; t0=$(date +%s)
  while :; do
    local st; st=$(usb_state)
    if [ "$st" = "$want" ]; then
      if [ "$want" = fastboot ]; then
        if timeout 8 "$FB" devices 2>/dev/null | grep -q fastboot; then return 0; fi
      else return 0; fi
    fi
    [ $(( $(date +%s) - t0 )) -ge "$t" ] && return 1
    sleep 1
  done
}

# 让设备回到 fastboot（必要时从 adb 主动重启）
ensure_fastboot(){
  local t0; t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt 120 ]; do
    case "$(usb_state)" in
      fastboot) wait_state fastboot 20 && return 0 ;;
      adb) log "state=adb, 执行 adb reboot bootloader"; timeout 20 "$ADB" reboot bootloader >>"$LOG" 2>&1; sleep 5 ;;
      edl) log "state=EDL(9008)，无法自动恢复"; return 1 ;;
      none) sleep 2 ;;
      *) sleep 2 ;;
    esac
  done
  return 1
}

boot_once(){ # boot_once <img>
  local img="$1" t0 t1 rc st first
  log "==== boot $img (MODE=$MODE) ===="
  ensure_fastboot || { log "无法进入 fastboot（USB 未枚举），需要人工重启/插拔"; return 3; }
  t0=$(date +%s%3N)
  if [ "$MODE" = flash ]; then
    timeout 180 "$FB" flash boot_b "$img" >>"$LOG" 2>&1; rc=$?
    log "fastboot flash boot_b rc=$rc"
    timeout 30 "$FB" reboot bootloader >>"$LOG" 2>&1
  else
    timeout 180 "$FB" boot "$img" >>"$LOG" 2>&1; rc=$?
    log "fastboot boot rc=$rc"
  fi
  # fastboot boot 成功后设备会掉 USB；等它以 adb/fastboot/edl 回来
  local t_start; t_start=$(date +%s)
  local timeline=""; st="none"; first=""
  while [ $(( $(date +%s) - t_start )) -lt "$BOOT_TIMEOUT" ]; do
    st=$(usb_state)
    timeline+="$st,"
    case "$st" in
      adb|fastboot|edl)
        # 等 2 秒确认稳定（避免枚举抖动）
        sleep 2; st2=$(usb_state)
        if [ "$st2" = "$st" ]; then break; fi ;;
    esac
    sleep 1
  done
  t1=$(date +%s%3N)
  local dur=$(( (t1 - t0) / 1000 ))
  local md5; md5=$(md5sum "$img" | cut -d' ' -f1)
  local note=""
  if [ $(( $(date +%s) - t_start )) -ge "$BOOT_TIMEOUT" ] && [ "$st" = none ]; then
    st="timeout"; note="HANG_MANUAL_RESET_NEEDED"
    log "!! $BOOT_TIMEOUT 秒内设备未回到 USB，判定卡死"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date '+%F %T')" "$(basename "$img")" "$md5" "$rc" "$st" "$dur" "$note" >> "$RES"
  log "RESULT img=$(basename "$img") rc=$rc state=$st duration=${dur}s timeline=${timeline}"
  [ "$st" = "timeout" ] && return 3
  return 0
}

log "auto-boot-loop start: MODE=$MODE ATTEMPTS=$ATTEMPTS BOOT_TIMEOUT=$BOOT_TIMEOUT imgs=${IMGS[*]}"
rc_all=0
for img in "${IMGS[@]}"; do
  [ -f "$img" ] || { log "缺少镜像 $img"; rc_all=2; continue; }
  for i in $(seq 1 "$ATTEMPTS"); do
    boot_once "$img"; rc=$?
    if [ "$rc" -eq 3 ]; then log "停止：需要人工介入（设备卡死或无 USB）"; exit 3; fi
    [ "$rc" -ne 0 ] && rc_all=$rc
  done
done
log "auto-boot-loop done rc=$rc_all"
exit "$rc_all"
