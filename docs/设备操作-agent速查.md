# 设备操作 · agent 速查

**给人看的完整教程**在 `docs/双系统启动说明.md`（含刷写/回退/构建全过程，agent 不需要整篇读）。
本文件是 agent 侧的边界：只读什么、能跑什么、怎么汇报。

## 只读

- `work/state/current-device.json` —— 设备在哪、跑的是哪个镜像、sha256
- `TASKS.md` —— 当前任务与下一步
- `work/claude-logs/` —— 最近一次健康检查 / 刷写 / 采样的日志

## 可以跑

```bash
scripts/fuxi-flash.sh status            # 设备位置 + recovery_b 内容 + 与 state json 对照
scripts/fuxi-flash.sh plan baseline     # 打印人类要执行的命令（不执行）
scripts/fuxi-health.sh --require-wifi --require-sensors
scripts/fuxi-ssh.sh 'uptime; dmesg | tail -20'   # 只读取证
```

## 不要跑（`scripts/fuxi-guard.sh` 会在工具层拦）

- `fastboot flash|boot|erase|reformat|reboot`
- `adb reboot` / `adb sideload`
- `dd … of=/dev/block|sd|nvme|mmcblk`
- `qdl`
- `scripts/fuxi-flash.sh flash|reboot` —— **这两步留给人类**

## 汇报格式

结论 + 证据路径（日志/命令输出）+ 需要人类执行的那一条命令（只给脚本名和参数）。
不展开过程、不复述教程、不贴 hex/分区 dump。

## 为什么有这份文件

模型侧的实时安防分类器会把"一步步刷分区/进 recovery"的**生成内容**判成 `[cyber]` 并整段拒答
（2026-10-31 20:32 三连拒，见 `docs/Claude-Code-误报-设备动作边界-20261031.md`）。
让 agent 只输出结论、把过程交给脚本和人类，是唯一不依赖模型运气的做法。
