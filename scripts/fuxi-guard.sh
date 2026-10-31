#!/bin/bash
# Claude Code PreToolUse hook：挡住 agent 直接发起的设备写入/重启。
#
# 为什么：模型侧实时网络安防分类器会把"刷分区/进 recovery/引导镜像"这类生成内容判成
# [cyber] 并整段拒答（2026-10-31 连续三拒）。把设备动作挪到人类终端、agent 只读状态，
# 是唯一不依赖模型运气的解。这个 hook 让"agent 偷偷刷机"在工具层就不可达。
#
# 约定：stdin 收 Claude Code 的 hook JSON；命中危险命令 → stderr 说明 + exit 2（阻止）；
# 其它一律 exit 0（放行）。只拦 Bash。
set -u
payload=$(cat)

# 非 Bash 工具直接放行（hook 的 matcher 已经限定 Bash，这里再兜一层）
tool=$(printf '%s' "$payload" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("tool_name",""))
except Exception: print("")' 2>/dev/null)
[ "$tool" = "Bash" ] || exit 0

cmd=$(printf '%s' "$payload" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("tool_input",{}).get("command",""))
except Exception: print("")' 2>/dev/null)
[ -n "$cmd" ] || exit 0

# 人类自己在终端跑的脚本放行；agent 调 flash/reboot 子命令仍然拦
case "$cmd" in
  *"fuxi-flash.sh status"*|*"fuxi-flash.sh plan"*|*"fuxi-flash.sh s"*|*"fuxi-flash.sh p"*) exit 0 ;;
esac

# 只读的帮助/版本输出不算设备动作
printf '%s' "$cmd" | grep -qE '(^|[^a-z0-9])(fastboot|adb|qdl)[[:space:]].*(--help|--version)' && exit 0

block() {
  printf 'BLOCKED: %s\n' "$1" >&2
  cat >&2 <<'MSG'
设备写入/重启必须在人类终端里做（AGENTS.md §3）。请人类执行：
  scripts/fuxi-flash.sh flash baseline --yes      # 或 recovery / 具体镜像
  scripts/fuxi-flash.sh reboot recovery --yes
你只读 scripts/fuxi-flash.sh status 和 work/claude-logs/ 下的日志，然后把结果讲清楚。
MSG
  exit 2
}

printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]' | grep -qE \
  '(^|[^a-z0-9])(fastboot[[:space:]]+(flash|boot|erase|format|oem|set_active|reboot)|adb[[:space:]]+reboot|adb[[:space:]]+sideload|dd[[:space:]][^|;]*of=/dev/(block|sd|nvme|mmcblk)|qdl[[:space:]]|firehose)' \
  && block "检测到设备写入/重启命令：$cmd"

printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]' | grep -qE 'fuxi-flash\.sh[[:space:]]+(flash|reboot)' \
  && block "fuxi-flash.sh 的写入/重启子命令留给人类执行：$cmd"

exit 0
