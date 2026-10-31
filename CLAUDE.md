# CLAUDE.md — linux-android 项目

本项目的强制协议见下方导入的 AGENTS.md（**开工前必须执行**）。

@AGENTS.md

## Claude Code 额外约定

- 上下文纪律见全局 `~/.claude/CLAUDE.md`；切换任务前用 `/handoff` 写交接、再 `/clear`。
- 新会话开场用 `/start`（会读 TASKS.md 并先跑 `scripts/fuxi-agent-preflight.sh`）。
- 长任务/实验前先 `scripts/fuxi-agent-lock.sh acquire claude "<任务>"`，结束 `release`。
- 涉及刷机/重启：先读 `work/state/current-device.json` 的 `device_current`，确认基线镜像与哈希，
  试验后刷回 `s2idle2`(#207) 并跑健康检查。
