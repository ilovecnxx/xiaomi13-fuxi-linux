#!/bin/bash
# 把当前进度（文档/脚本/研究记录 + 进度摘要）发布到 GitHub。
#
# 发布原则（重要）：
#   - 只发布面向公众的技术资料：docs（白名单，排除交接/任务/评审/宣传/内部网络工具）、
#     research、scripts（公开构建/验收/诊断脚本）。
#   - 绝不上传任何“宣传资料/推广素材”（本脚本同时按文件名过滤 promo/宣传/marketing/推广）。
#   - 不上传内部交接笔记、任务派单、CODEX 评审请求、账号/口令/token。
#   - 不上传内核/ABL 镜像（体积大、非公开产物；如需可选 FUXI_PUBLISH_IMAGES=1）。
#
# 用法: bash scripts/publish-progress.sh "提交说明"
set -e
B="/home/user/文档/deepseek-harness/default-workspace/linux-android"
REPO="${FUXI_GH_REPO:-ilovecnxx/fuxi-linux-build}"
MSG="${1:-progress update $(date +%Y-%m-%d_%H:%M)}"
STAGE="$B/work/gh-publish"
export GIT_TERMINAL_PROMPT=0

# --- 排除规则：任何命中即跳过（宣传/内部/敏感） ---
EXCLUDE_DOC_RE='交接|任务|评审|宣传|推广|promo|marketing|广告|Clash|DSH手机移植|Chromium浏览器移植'
EXCLUDE_PROMO_RE='宣传|推广|promo|marketing|广告'
# 自研软件（部署脚本/工具）不发布
EXCLUDE_SCRIPT_RE='fuxi-chromium|fuxi-dsh|fuxi-shot|superterm|fuxi-mobile|mobile-chrome'

if [ ! -d "$STAGE/.git" ]; then
  rm -rf "$STAGE"
  gh repo clone "$REPO" "$STAGE" -- --depth 1 >/dev/null 2>&1 || {
    mkdir -p "$STAGE" && cd "$STAGE" && git init -q && git remote add origin "https://github.com/${REPO}.git"
  }
fi
cd "$STAGE"
# 不清空已发布目录：避免误删既有文件（如历史文档），只增量覆盖
mkdir -p docs research scripts

# docs：白名单式拷贝（跳过排除项）
for f in "$B"/docs/*.md; do
  [ -f "$f" ] || continue
  base=$(basename "$f")
  echo "$base" | grep -qE "$EXCLUDE_DOC_RE" && continue
  echo "$base" | grep -qE "$EXCLUDE_PROMO_RE" && continue
  cp -f "$f" docs/
done

# research
for f in "$B"/research/*.md; do
  [ -f "$f" ] || continue
  base=$(basename "$f")
  echo "$base" | grep -qE "$EXCLUDE_PROMO_RE" && continue
  cp -f "$f" research/
done

# scripts：公开脚本，排除内部/敏感/含口令的
for f in "$B"/scripts/*.sh; do
  [ -f "$f" ] || continue
  base=$(basename "$f")
  echo "$base" | grep -qE "$EXCLUDE_PROMO_RE" && continue
  echo "$base" | grep -qE "$EXCLUDE_SCRIPT_RE" && continue
  # 跳过明显含硬编码 sudo 口令的内部实现脚本
  grep -qE 'echo[[:space:]]+[0-9]{4,}[[:space:]]*\|[[:space:]]*sudo[[:space:]]+-S' "$f" && continue
  cp -f "$f" scripts/
done

# 可选镜像（默认关闭）
if [ "${FUXI_PUBLISH_IMAGES:-0}" = "1" ]; then
  mkdir -p boot-images
  for f in "$B"/work/kbuild/abl-fuxi-*.img; do
    [ -f "$f" ] || continue
    sz=$(stat -c %s "$f")
    [ "$sz" -lt 6291456 ] && cp -f "$f" boot-images/ || true
  done
fi

# PROGRESS.md 由人工维护（不在此覆盖），若缺失才生成占位
[ -f PROGRESS.md ] || printf '# fuxi 主线移植进度\n\n见 docs/。\n' > PROGRESS.md

git add -A
git -c user.name="fuxi-agent" -c user.email="fuxi-agent@local" commit -q -m "$MSG" || { echo "无改动"; exit 0; }
git push -q origin HEAD:master 2>&1 | tail -3 || git push -q origin HEAD:main 2>&1 | tail -3
echo "已推送: $MSG"
