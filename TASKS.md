## Handoff — 2026-10-31 03:25 充电/电池事件 + 暂停 Denial

### 当前优先级
- **充电/电池**（用户 03:21 指示「把充电和电池弄好」）：手机已因 1% 电量关机，先让用户插 67W 充电器充电，
  回 Linux 后实测 PD 快充。详见 `docs/充电电池事件-20261031.md`。
- **Denial 桌面迁移已暂停**：构建进程已杀、teammate 已中断；产物尚未生成（只有源码/依赖/缓存）。
  恢复条件：手机回 Linux + 充电正常后再决定是否继续。方案文档 `docs/桌面换Denial-20261031.md`，
  集成脚本 `scripts/fuxi-denial.sh` 已写好未实机用。

### 设备当前实况（2026-10-31 03:24）
- **手机已关机**（电量 1% 耗尽）。关机前运行 #222 modem16-epmap 实验镜像；主机 lsusb 看到 `05c6:f000`。
- 关机原因：手机接电脑 USB（500mA）跑 Denial 构建（8×clang，整机 ~2A），把电耗到 1%。
- 之前基线仍是 **s2idle2 #207**（sha256 `186e102f…cd69`）；recovery_b 上是 modem16 #222，测试结束必须刷回。

### 已完成（证据）
- 充电诊断：电池 `M3_4500mah_67w`（67W）、健康 75%、循环 1155；USB 口 SDP 5V/500mA；
  杀构建后电池由 -1.977A 转 +255mA（qcom_battmgr.c 的 Xiaomi 电流方向补丁生效）。
- Denial 构建进展（已中断，未产出可安装产物）：依赖装齐、bootstrap 完成、engine 构建开始即被停。
  源码 `/home/fuxi/denial-src`（v0.5.1）、缓存 `/home/fuxi/denial-cache`、日志 `/home/fuxi/denial-logs` 保留在手机。
- 集成脚本 `scripts/fuxi-denial.sh`（install/check/switch/rollback/shot/status 等）已写好、语法校验通过，
  `denial.service` 单元经 `systemd-analyze verify` 通过；**尚未实机安装/切换**。

### 仍存问题
- 充电/电池：PD 快充未在 Linux 验证；关机前 USB_TYPE=Unknown、INPUT_CURRENT_LIMIT 偏低待查。
- 蜂窝（原有，未变）：注册稳定性、IMS/VoLTE、短信/通话/双卡。
- Denial：构建未完成。

### 已尝试且失败（不要重复）
- 手机接电脑 USB 跑全核构建 → 电量耗尽关机（不要再在电脑 USB 供电下跑长构建）。
- 其余历史失败见 AGENTS.md 第 0 节与 `docs/目标-M5.md` 各节。

### 下一步先做什么
1. **用户插 67W 充电器**（或先电脑 USB 慢充到能开机），充几分钟。
2. 关机状态 **音量上 + 电源** 进 Linux（`docs/双系统启动说明.md`）。
3. SSH 恢复后：
   - 实测 PD 充电：插 67W 头看 `qcom-battmgr-usb` 的 VOLTAGE_NOW/USB_TYPE/INPUT_CURRENT_LIMIT，
     电池 CURRENT_NOW 是否几 A 级；不达标则查 charger_pd（ADSP）与 pmic_glink。
   - 健康检查 `scripts/fuxi-health.sh`（当前 recovery_b 是实验镜像 #222，先确认跑的是哪个再决定刷回 #207）。
4. 充电/电池验证 OK 后，再决定是否继续 Denial 迁移（需用户确认）。

## 2026-10-31 20:45 工程：模型 `[cyber]` 误报应对（代码就绪，未上机）

- 现象：20:31 `adb reboot recovery` 之后，Opus 4.8 连续三次拒答（`msg_011CgaKWnD…`/`KXw7…`/`KYZ…`），
  属生成侧判定，不是 prompt 也不是工具错误；原始记录
  `~/.claude/projects/-home-user-linux-android/088f7842-53ee-4893-b3ea-02c9669d73c8.jsonl`（第 252–268 行）。
- 新增 `scripts/fuxi-flash.sh`：设备动作的人工入口。默认只读（`status`/`plan`），`--yes` 才写；
  **只写 recovery_b**；镜像只认 `work/kbuild|work/patches`；写前比对 state json 的 sha256、
  未知镜像需 `--allow-unknown-image`、写后读回全量 sha256 校验；日志落 `work/claude-logs/flash-*.log`。
- `CLAUDE.md` 新增「对话安全写法」：设备动作人来跑、原始产物进文件、一次一步、被拒别连发"继续"。
- 验证：`bash -n` 通过；status / plan / 越权路径 / 未知镜像 / 无设备 / 缺 `--yes` 六条路径在主机逐条实测；
  **未实机刷写**（设备当时不在线），写入路径等下次上机验证。
