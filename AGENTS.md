# AGENTS.md — 接手本项目的强制协议

适用于任何 AI agent（Claude Code / Codex / DSH / 其他）。**开始任何工作前必须按顺序执行，禁止跳过。**

## 0. 先读（按顺序）

1. `TASKS.md` —— 当前任务、下一步、已失败方案
2. `work/state/current-device.json` —— 设备/镜像/哈希基线（`device_current` / `baseline_daily_sha256`）
3. `docs/目标-M5.md` 最后 2–3 节 —— 最新实机结果
4. `CHANGELOG.md` —— 版本与已知边界
5. `docs/历史遗留与清理记录-20261031.md` —— 哪些目录是历史快照，别当现状

## 1. 开工自检（必须全 PASS）

```bash
scripts/fuxi-agent-preflight.sh            # 默认：git/内核分支/state/TASKS/锁
scripts/fuxi-agent-preflight.sh --full     # 额外：补丁哈希一致性、基线镜像哈希
scripts/fuxi-agent-preflight.sh --device --with-tests   # 要上机/要跑测试时再加
```

默认检查：项目 git、内核分支与工作区、state json 可解析、`TASKS.md` 新鲜度、agent 锁（WARN）。
`--full` 追加：全量补丁哈希一致性、基线镜像哈希。**任何 FAIL 都先修复，不要带着失败状态写代码。**

## 2. 写作纪律

- **多 agent 并行时**才需要锁：`scripts/fuxi-agent-lock.sh acquire "<名字>" "<任务>"`，结束 `release`（单人场景可跳过）。
- 一次只做一件事；改内核前确认 `git -C build/linux status` 干净，改完立刻提交到 `fuxi/20261031`
  并重导出 `work/patches/full-tree-20261031/full-20261031.diff`（含 SHA256SUMS）。
- **不要重置 `build/linux`**；不要覆盖 `work/kbuild/` 里被引用的镜像；不要删 `work/claude-logs/`。
- 提交信息写清：改了什么 / 为什么 / 证据在哪（日志或命令输出）。

## 3. 设备红线

- 可写：`linux` 分区（sda33）+ `recovery_b`；**禁止** GPT/槽位/xbl/abl/tz/modemst/persist/efs/fsg。
- **刷机/重启前必须确认**；每次设备试验后必须刷回基线 `s2idle2`(#207) 并跑
  `scripts/fuxi-health.sh --require-wifi --require-sensors`，**失败项必须为 0**。
- 物理操作（看屏幕、插 SIM、拔线、长按电源）需用户配合。

## 4. 完成定义（DoD）

- 57 项主机测试通过；涉及实机的结论有日志落在 `work/claude-logs/`；
- 文档、`TASKS.md`、state json 同步更新；重大节点更新 `CHANGELOG.md`；
- 汇报必须区分【已实测】/【仅编译通过】/【推测】。

## 5. 交接

用 `/handoff` 生成 10 节证据化交接，或按 `~/.claude/commands/handoff.md` 的规范手写；
新 agent 按本文件第 0、1 节接收。**不要重试已记录为失败的方案**，除非文档写明可翻案条件。
