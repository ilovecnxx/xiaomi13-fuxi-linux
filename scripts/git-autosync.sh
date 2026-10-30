#!/bin/bash
# 自动 git 版本管理 + 自动发布到 GitHub
#
# 每次运行：
#   1. 本地仓库：git add -A → 有改动就提交（auto: 时间戳 (N files)）
#   2. GitHub：调用 scripts/publish-progress.sh 发布白名单子集（docs/research/scripts）
#
# 用法:
#   scripts/git-autosync.sh              # 提交 + 发布
#   scripts/git-autosync.sh --no-publish # 只本地提交
#   scripts/git-autosync.sh --dry-run    # 只显示会做什么
#   scripts/git-autosync.sh --status     # 查看最近提交与发布状态
#
# 安装定时任务（每 10 分钟）：见 README「自动版本管理与发布」
set -u

B="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$B" || exit 1
LOG="$B/work/claude-logs/git-autosync.log"
LOCK="/tmp/fuxi-git-autosync.lock"
mkdir -p "$(dirname "$LOG")"

DRY=0
PUBLISH=1
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --no-publish) PUBLISH=0 ;;
    --status)
      echo "=== 最近 10 次本地提交 ==="
      git log --oneline -10 2>/dev/null || echo "(无提交)"
      echo
      echo "=== 工作树 ==="
      git status --short | head -20
      echo
      echo "=== GitHub 发布仓库最近 5 次 ==="
      git -C "$B/work/gh-publish" log --oneline -5 2>/dev/null || echo "(无发布仓库)"
      echo
      echo "=== 最近同步日志 ==="
      tail -20 "$LOG" 2>/dev/null || echo "(暂无日志)"
      exit 0 ;;
  esac
done

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG"; }

# 日志超过 2MB 时截断保留后 1000 行
if [ -f "$LOG" ] && [ "$(stat -c %s "$LOG")" -gt 2097152 ]; then
  tail -1000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi

# 单实例锁
exec 9>"$LOCK"
flock -n 9 || exit 0

if [ ! -d "$B/.git" ]; then
  log "错误：$B 不是 git 仓库"
  exit 1
fi

# 兼容未配置全局身份的情况
GIT_ID=(-c user.name="${GIT_AUTHOR_NAME:-fuxi-linux-builder}" -c user.email="${GIT_AUTHOR_EMAIL:-builder@localhost}")

# ---------- 1) 本地提交 ----------
git add -A

if git diff --cached --quiet; then
  log "本地：无改动，跳过提交"
  LOCAL_OK=1
else
  N=$(git diff --cached --name-only | wc -l)
  MSG="auto: $(date '+%F %T') (${N} files)"
  if [ "$DRY" = 1 ]; then
    log "本地(dry-run)：将提交 ${N} 个文件"
  else
    if git "${GIT_ID[@]}" commit -q -m "$MSG"; then
      log "本地：已提交 ${N} 个文件 ($(git rev-parse --short HEAD))"
    else
      log "本地：提交失败"
    fi
  fi
fi

# ---------- 2) 发布到 GitHub ----------
if [ "$PUBLISH" = 0 ]; then
  exit 0
fi
if [ "$DRY" = 1 ]; then
  log "发布(dry-run)：将执行 scripts/publish-progress.sh"
  exit 0
fi

if [ -f "$B/scripts/publish-progress.sh" ]; then
  if bash "$B/scripts/publish-progress.sh" "auto: $(date '+%F %T')" >>"$LOG" 2>&1; then
    log "GitHub：发布成功"
  else
    log "GitHub：发布失败（本地提交不受影响，下次重试）"
  fi
else
  log "GitHub：缺少 scripts/publish-progress.sh，跳过"
fi
