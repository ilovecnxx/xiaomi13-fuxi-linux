# CLAUDE.md — linux-android 项目

本项目的强制协议见下方导入的 AGENTS.md（**开工前必须执行**）。

@AGENTS.md

## Claude Code 额外约定

- 上下文纪律见全局 `~/.claude/CLAUDE.md`；切换任务前用 `/handoff` 写交接、再 `/clear`。
- 新会话开场用 `/start`（会读 TASKS.md 并先跑 `scripts/fuxi-agent-preflight.sh`）。
- 长任务/实验前先 `scripts/fuxi-agent-lock.sh acquire claude "<任务>"`，结束 `release`。
- 涉及刷机/重启：先读 `work/state/current-device.json` 的 `device_current`，确认基线镜像与哈希，
  试验后刷回 `s2idle2`(#207) 并跑健康检查。

## 对话安全写法（模型侧 `[cyber]` 误报）

模型（Opus 4.8 等）的实时网络安防分类器会对**生成内容**做判定，把"进 recovery / 写分区 / 引导镜像"
这类正当的嵌入式工作判成违规并整段拒答。2026-10-31 20:32 连续三拒
（`msg_011CgaKWnD…`、`msg_011CgaKXw7…`、`msg_011CgaKYZ…`）就发生在 `adb reboot recovery` 之后：
不是 prompt 有问题，是模型准备输出的那段过程被拦。触发词未定位，下面只是降低误报概率的做法。

1. **设备动作由人在终端做，agent 只读状态。** 写 `recovery_b`、重启、进 recovery/bootloader 一律走
   `scripts/fuxi-flash.sh`（默认只读，`--yes` 才动手；只认 `work/kbuild|work/patches` 下的镜像、
   写前比对 state json 的 sha256、写后读回校验）。agent 侧只允许 `scripts/fuxi-flash.sh status`
   和 `scripts/fuxi-health.sh`。
2. **不把原始产物贴进对话**：hex dump、分区 dump、反汇编、签名 blob 落到 `work/` 下，
   让 agent 用 read/grep 按需取。大段二进制和裸地址是高频触发项。
3. **一次一步、动词中性**：说"把镜像写到 recovery_b 并读回校验"，不说"绕过 ABL 校验/解锁/提权"。
   设备事实（分区名、镜像路径、sha256、`adb reboot recovery`）照写，不用自我审查。
4. **被拒后不要连发"继续"。** Claude Code 会注入"不要重复该内容"，重放只会再撞一次。
   改法：`/clear` 开新会话，带上 `TASKS.md` 的状态重新起一个窄任务；或换模型/换入口。
5. 真误报用 `/feedback` 上报，附 message id + 当时那一步；顺手记一行到 `TASKS.md`，别让下个 agent 重踩。

