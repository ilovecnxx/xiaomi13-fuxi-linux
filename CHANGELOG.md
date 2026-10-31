# CHANGELOG

Xiaomi 13（fuxi / SM8550）Android + 主线 Linux 双系统。
版本对应 GitHub release（`ilovecnxx/xiaomi13-fuxi-linux-ubuntu26.10-kernel7.3`）。

## 未发布 — 2026-10-31：设备动作脚本化 + 对话安全写法

- 新增 `scripts/fuxi-flash.sh`：刷写/重启的人工入口。默认只读（`status`/`plan`），`--yes` 才动设备；
  只写 `recovery_b`；镜像限定 `work/kbuild|work/patches`；写前比对 state json 的 sha256（未知镜像需
  `--allow-unknown-image`），写后读回全量 sha256 校验；日志 `work/claude-logs/flash-*.log`。
- `CLAUDE.md` 新增「对话安全写法（模型侧 `[cyber]` 误报）」：设备动作由人执行、原始产物落文件、
  一次一步、被拒后不要连发"继续"。
- 起因：20:32 `adb reboot recovery` 后 Opus 4.8 连续三次 `[cyber]` 拒答（生成侧判定）。未实机刷写。

## v0.5.0 — 2026-10-31：蜂窝数据打通 + keeper + 工程收尾

### 蜂窝 / 基带
- **modem16-epmap（#222）**：`ipa_data-v5.5.c` 端点 `AP_MODEM_RX` 23→24、`MODEM_AP_RX` 21→22（按厂商 dataipa IPA_5_5 表），
  rmnet 下行打通。两轮实机各约 1263/1279 s：无 SMMU fault / FATAL IPA / 崩溃；ping v4+v6、DNS/HTTPS、~85 Mbit/s。
- **modem15-haltorder（#221）**：halt 挪到 modem offline 事件后，SSR 手动 stop/start 两次均恢复成功。
- **modem keeper** 部署（`fuxi-modem-keeper.service`）：开机设 data-centric；被拒/掉线后射频 low→on 循环。
  首轮 25 min 注册全 home、零网络拒绝、零触发（证据 `work/claude-logs/modem16-keeper-run1-20261031/`）。
- 遗留：注册稳定性未解决（EMM cause 7 / 无 IMS 语音），短信/通话/双卡未开始；本次启动 rmnet 未建数据会话。

### 工程 / 可复现性
- 内核源码版本化：`build/linux` 分支 `fuxi/20261031`（提交 `c3890463b` + 清理提交 `18e74dc1d`），全量补丁
  `work/patches/full-tree-20261031/`（5302 行，反向 apply 校验通过）。
- `build.json` 新增 `kernel_branch` / `kernel_dirty_diff_sha256` / `kernel_untracked_files` / `kernel_clean`。
- 文档：`TASKS.md` 重写；README 当前状态更新；历史交接归档到 `docs/archive/`；
  新增 `docs/历史遗留与清理记录-20261031.md`、`docs/kbuild-镜像清单-20261031.md`。
- 清理：删除 4 份旧版文档副本、470MB 冗余发布/暂存目录与 `.venv`；补齐 7 个备份目录的 `SHA256SUMS`；
  修 `publish-progress.sh` 旧仓库名、`fuxi-m5-wifi-bt.sh` 旧默认镜像。

## v0.4.0 — 2026-10-30：本机硬件配置 + #207 日常镜像
- 省电：熄屏电流 117→28.5 mA（深度空闲 + NO_HZ + 去 `*_ignore_unused` + 强制 sync_state）
- WiFi 5 GHz 在 CN 管制域可用；s2idle 挂起可用（#207 修复恢复后管制域回 US）
- 本机硬件配置归档（面板/相机模块/射频地址），配件供应商差异记录

## v0.3.0 — 2026-10-29：M6 上机
- 原生 MSM DSI 显示 + Adreno 740（小米签名 ZAP）+ 120 Hz，用户现场确认
- 音频：CS35L41×2 可听；主/第二麦克风回环；WiFi 连网 + WiFi SSH；传感器五类数据

## v0.2.0 — 2026-10-27：M5/M6 硬件就绪
- 触摸（ST FTM5）、按键、电量/充电（battmgr）、WiFi/蓝牙硬件就绪；ABL 直接引导 recovery_b 双系统

## v0.1.0 — 2026-10-26：双系统首版
- Android 13（fuxi）+ 主线 Linux 7.3 双系统，UFS rootfs（Ubuntu 26.10），USB 串口/网络
