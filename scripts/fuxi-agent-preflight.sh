#!/bin/bash
# 接手/切换 agent 的开工自检。全部 PASS 才能开始修改代码。
# 用法: scripts/fuxi-agent-preflight.sh [--with-tests] [--device]
#   退出码 0 = 可以开始；非 0 = 先修复
set -u
B="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0; WARN=0
DO_TESTS=0; DO_DEVICE=0
for a in "$@"; do
  case "$a" in
    --with-tests) DO_TESTS=1 ;;
    --device) DO_DEVICE=1 ;;
  esac
done
ok(){ printf 'PASS  %s\n' "$*"; }
bad(){ printf 'FAIL  %s\n' "$*"; FAIL=$((FAIL+1)); }
wrn(){ printf 'WARN  %s\n' "$*"; WARN=$((WARN+1)); }

echo "== fuxi agent preflight ($(date '+%F %T')) =="

# 1) 项目仓库
if git -C "$B" rev-parse --git-dir >/dev/null 2>&1; then
  if [ -z "$(git -C "$B" status --porcelain)" ]; then
    ok "项目 git 干净（$(git -C "$B" describe --tags --always 2>/dev/null)）"
  else
    bad "项目 git 有未提交改动：$(git -C "$B" status --porcelain | wc -l) 个（先提交或说明原因）"
  fi
else
  bad "项目不是 git 仓库：$B"
fi

# 2) 内核仓库 + 分支 + 补丁一致性
K="$B/build/linux"
if [ -d "$K/.git" ]; then
  br="$(git -C "$K" branch --show-current)"
  [ "$br" = "fuxi/20261031" ] && ok "内核分支 $br" || bad "内核分支是 '$br'（应为 fuxi/20261031）"
  if [ -z "$(git -C "$K" status --porcelain)" ]; then ok "内核工作区干净"; else bad "内核工作区有未提交改动"; fi
  P="$B/work/patches/full-tree-20261031/full-20261031.diff"
  S="$B/work/patches/full-tree-20261031/SHA256SUMS"
  if [ -f "$P" ] && [ -f "$S" ]; then
    live="$(git -C "$K" diff master.."$br" | sha256sum | cut -d' ' -f1)"
    saved="$(cut -d' ' -f1 "$S")"
    if [ "$live" = "$saved" ]; then ok "全量补丁与分支一致（${live:0:12}…）"; else bad "全量补丁已漂移（live=${live:0:12}… saved=${saved:0:12}…），需重导出"; fi
  else
    bad "缺少全量补丁或 SHA256SUMS（$P）"
  fi
else
  bad "找不到内核树 $K"
fi

# 3) 设备状态快照 + 基线镜像哈希
ST="$B/work/state/current-device.json"
if python3 -c "import json;json.load(open('$ST'))" 2>/dev/null; then
  base="$(python3 -c "import json;d=json.load(open('$ST'));print(d.get('baseline_daily_sha256',''))")"
  img="$B/work/kbuild/abl-fuxi-s2idle2.img"
  if [ -f "$img" ]; then
    cur="$(sha256sum "$img" | cut -d' ' -f1)"
    if [ "$cur" = "$base" ]; then ok "基线镜像哈希与 state json 一致"; else bad "基线镜像哈希不匹配（state=${base:0:12}… 实际=${cur:0:12}…）"; fi
  else
    wrn "缺少基线镜像 $img"
  fi
else
  bad "state json 不可解析：$ST"
fi

# 4) TASKS.md 新鲜度
if [ -f "$B/TASKS.md" ]; then
  age=$(( ( $(date +%s) - $(stat -c %Y "$B/TASKS.md") ) / 3600 ))
  if [ "$age" -le 24 ]; then ok "TASKS.md 最近更新 ${age}h 前"; else wrn "TASKS.md 已 ${age}h 未更新，交接可能过期"; fi
else
  bad "缺少 TASKS.md"
fi

# 5) agent 互斥锁
LK="$B/work/claude-logs/agent.lock"
if [ -f "$LK" ]; then
  info="$(python3 -c "import json,time;d=json.load(open('$LK'));print(d.get('owner','?'),d.get('note',''),int((time.time()-d.get('ts',0))/3600))" 2>/dev/null)"
  owner="${info%% *}"
  hrs="$(echo "$info" | awk '{print $NF}')"
  if [ "${hrs:-0}" -ge 12 ]; then wrn "存在陈旧 agent 锁（$owner，${hrs}h 前），可 lock.sh release --force"; else bad "另一 agent 持锁：$info（先确认无并行改动）"; fi
else
  ok "无 agent 锁"
fi

# 6) 可选：主机测试
if [ "$DO_TESTS" = 1 ]; then
  echo; echo "== 主机测试 =="
  if ( cd "$B" && python3 -m unittest discover -s scripts/tests >/tmp/fuxi-preflight-tests.log 2>&1 ); then
    ok "57 项主机测试通过"
  else
    bad "主机测试失败，见 /tmp/fuxi-preflight-tests.log 尾部"
    tail -5 /tmp/fuxi-preflight-tests.log
  fi
fi

# 7) 可选：设备连通
if [ "$DO_DEVICE" = 1 ]; then
  echo; echo "== 设备连通 =="
  if timeout 15 "$B/scripts/fuxi-ssh.sh" 'uname -v; cut -d" " -f1 /proc/uptime' >/tmp/fuxi-preflight-dev.log 2>&1; then
    ok "设备可达：$(tr '\n' ' ' < /tmp/fuxi-preflight-dev.log)"
  else
    wrn "设备不可达（要上机前先确认 USB/WiFi 与设备状态）"
  fi
fi

echo
if [ "$FAIL" -gt 0 ]; then
  echo "结果：$FAIL 项 FAIL、$WARN 项 WARN —— 禁止开始修改，先修复"
  exit 1
fi
echo "结果：全部 PASS（WARN $WARN）—— 可以开始"
exit 0
