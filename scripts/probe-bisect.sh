#!/bin/bash
# 自动可达性探针 bisect：对每个 probe 点重建固件、boot、测量回到 adb 的时间。
# 早回(<35s)=到达该点；~40s=未到达（Gunyah 看门狗兜底复位）。
B="/home/user/文档/deepseek-harness/default-workspace/linux-android"
DRV="$B/build/edk2-msm/Silicon/Qualcomm/sm8550/Drivers/FuxiLinuxBoot/FuxiLinuxBoot.c"
ADB="$B/tools/platform-tools/adb"; FB="$B/tools/platform-tools/fastboot"
LOG="$B/logs/probe-bisect.log"
for N in "$@"; do
  echo "$(date '+%F %T') ==== probe $N ====" >> "$LOG"
  # 1) 改 cmdline 里的 fuxi.probe=N
  python3 - "$N" <<'PY' >> "$LOG" 2>&1
import re,sys
n=sys.argv[1]
p="/home/user/文档/deepseek-harness/default-workspace/linux-android/build/edk2-msm/Silicon/Qualcomm/sm8550/Drivers/FuxiLinuxBoot/FuxiLinuxBoot.c"
s=open(p,encoding='utf-8').read()
s=re.sub(r'fuxi\.probe=\d+', f'fuxi.probe={n}', s)
s=re.sub(r'\s*fuxi\.probe=\d+', '', s) if 'fuxi.probe=' not in s else s
# 若无 fuxi.probe 则追加到 rdinit 前
if f'fuxi.probe={n}' not in s:
    s=s.replace(' fuxi.fb=', f' fuxi.probe={n} fuxi.fb=',1)
open(p,'w',encoding='utf-8').write(s)
print("set probe", n)
PY
  grep -o "fuxi.probe=[0-9]*" "$DRV" | head -1 >> "$LOG"
  # 2) 建固件
  ( cd "$B/build/edk2-msm" && PATH="$B/tools/ccwrap:$B/tools:$PATH" ./build.sh --device fuxi --toolchain GCC5 -r DEBUG > /tmp/fw-probe-bisect.log 2>&1 ) || { echo "BUILD FAIL" >> "$LOG"; continue; }
  cp -f "$B/build/edk2-msm/boot-fuxi.img" "$B/work/kbuild/boot-fuxi-probeN.img"
  # 3) 等 adb → 重启 bootloader
  for i in $(seq 1 60); do
    timeout 5 "$ADB" devices 2>/dev/null | tail -n +2 | grep -q device && break
    sleep 2
  done
  if ! timeout 5 "$ADB" devices 2>/dev/null | tail -n +2 | grep -q device; then
    echo "NO_ADB (需要人工)" >> "$LOG"; exit 2
  fi
  timeout 20 "$ADB" reboot bootloader >/dev/null 2>&1
  ok=0
  for i in $(seq 1 60); do
    if timeout 4 "$FB" devices 2>/dev/null | grep -q fastboot; then ok=1; break; fi
    sleep 1
  done
  [ "$ok" = 1 ] || { echo "NO_FASTBOOT (需要拔插USB)" >> "$LOG"; exit 3; }
  T0=$(date +%s)
  timeout 60 "$FB" boot "$B/work/kbuild/boot-fuxi-probeN.img" >> "$LOG" 2>&1
  rc=$?
  echo "boot rc=$rc at $(date '+%H:%M:%S')" >> "$LOG"
  # 4) 测回 adb 时间（最多 150s）
  got=0
  for i in $(seq 1 75); do
    sleep 2
    if timeout 4 "$ADB" devices 2>/dev/null | tail -n +2 | grep -q device; then
      got=1; T1=$(date +%s); echo "probe $N RETURNED delta=$((T1-T0))s" >> "$LOG"; break
    fi
  done
  [ "$got" = 1 ] || echo "probe $N NO_RETURN_150s" >> "$LOG"
done
echo "$(date '+%F %T') ==== bisect done ====" >> "$LOG"
