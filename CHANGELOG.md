# CHANGELOG

Xiaomi 13（fuxi / SM8550）Android + 主线 Linux 双系统。
版本对应 GitHub release（`ilovecnxx/xiaomi13-fuxi-linux-ubuntu26.10-kernel7.3`）。

## 未发布 — 2026-11-01：相机 OV13B10 出帧 + 全量历史上 GitHub

### 相机（OV13B10 超广角）
- I2C 地址按厂商 sensormodule 从 `0x10` 改到 `0x36`（内核 `c9b7bbd22`），**camera5 #227 实测 probe 成功**，
  libcamera 0.7.0 simple 管线识别出摄像头。
- camera6 #228 补 `DMABUF_HEAPS`/`UDMABUF` 后 dma-buf 分配器就位，`cam -c1 --capture=3` 抓到 3 帧；
  但 raw 帧约 60% 字节成段变 0 —— 根因是 `&camss` 缺 `dma-coherent`（内核 `476dc80e0`）。
- 新增 DTB 变体 `r120idle-mic-rupdclk-audio-disp-camera`（日常全量 + 相机）；
  `work/kbuild/abl-fuxi-daily-camera.img`（sha256 `4b1e5f9e…`）**仅编译通过、未上机**。
- 另加 `scripts/v4l2ctl.py`（手机无 v4l-utils 时读写 v4l2 控件）。

### 工程
- 全量开发历史（含 TASKS.md/交接/补丁/脚本）推送到 GitHub `main` 分支；
  README 新增「换电脑继续开发」与「新机器重建内核树」步骤。
- 全量补丁重导出：`work/patches/full-tree-20261031/full-20261031.diff`（69 文件 / 5427 行，sha256 `96c51693…`）。

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
