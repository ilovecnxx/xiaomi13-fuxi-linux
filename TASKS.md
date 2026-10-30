## Handoff — 2026-10-31 02:40 基带注册稳定性 + modem keeper 首轮

### 目标
- 小米 13（fuxi）主线 Linux 蜂窝：IPA 数据通路 → LTE/5G 注册稳定 → 短信、通话、双卡。

### 设备当前实况（2026-10-31 02:38 实测）
- 运行 **modem16-epmap #222**（`work/kbuild/abl-fuxi-modem16-epmap.img`，sha256 `20ac7794…76ef`），
  boot_id `aba309f0-4f6c-4961-939a-867ac98bf446`，uptime 25 min。**这是实验镜像，不是日用基线**。
- **baseline = s2idle2 #207**（sha256 `186e102f…cd69`）；recovery_b 当前是 modem16，测试结束必须刷回。
- `fuxi-modem-keeper.service` **enabled + active**（02:08 部署，02:09 起运行）：开机 28s 设 data-centric，
  被拒/掉线后做射频 low→on 循环。**run1 已 25 min：注册全 home、零网络拒绝、零触发**。
- ModemManager = 补丁版 `/usr/local/lib/fuxi-mm/src/ModemManager`（02:09 启动）。
- 调制解调器：registered / home / **5G NR** / CHN-UNICOM / packet attached。
- **本次启动 rmnet 未建立数据会话**（`rmnet_ipa0 DOWN`）；ping 走的是 WiFi。下行能力在 modem16 run1/run2 已验证。

### 已完成（证据）
- modem16 数据通路：`ipa_data-v5.5.c` 端点 `AP_MODEM_RX` 23→24、`MODEM_AP_RX` 21→22；run1/run2 各约 1263/1279 s
  无 SMMU fault / FATAL IPA / 崩溃；ping v4+v6、HTTPS、~85 Mbit/s。补丁 `work/patches/modem16-epmap-20261031/`。
- keeper 部署与首轮运行，证据 `work/claude-logs/modem16-keeper-run1-20261031/summary.txt`。
- 日用基线能力（#207）：显示 120Hz+GPU+触控、WiFi 5G/CN/SSH、蓝牙 L2CAP、双功放+双麦回环、五类传感器、
  熄屏 28.5 mA、s2idle 可挂起、Phosh/中文输入/Chromium 移动 UI —— 详见 `README.md` 与 `docs/目标-M5.md`。

### 仍存问题
- **注册稳定性未解决**：run1/run2 在 214–318 s 掉线；根因指向 **EMM cause 7（EPS services not allowed）+ 无 IMS/VoLTE**，
  只有 `SetPowerState low→on` 能恢复；keeper 是否真有效需长测对照。
- **数据会话未建立**：本次启动 rmnet DOWN，需确认是"未发起连接"还是 MM net port 问题。
- IMS/VoLTE、短信、通话、双卡未开始。

### 已尝试且失败（不要重复）
- data-centric 单独无效（modem12）；MM disable/enable 无效。
- modem13 SMEM 整段映射：SMMU fault 未复现，但基带崩一次后恢复失败循环。
- modem14 崩溃时 HALT GSI：时机错（基带仍在用通道，`-11/-110`）。
- modem15 offline 后 halt：SSR 恢复成功，但下行 RX 恒 0。
- 详见 `docs/目标-M5.md` 10-30 21:10 ～ 10-31 01:55 各节。

### 下一步先做什么
1. 继续 keeper 长测到 **≥1 h**，并做一次**无 keeper 对照**（同一 SIM、同一位置）。
2. 采数据会话：`mmcli -m any --simple-connect` 或 NM 连接后确认 `rmnet_ipa0` 起来、ping 走 rmnet。
3. 测试结束：刷回 `s2idle2 #207` → `scripts/fuxi-health.sh --require-wifi --require-sensors` 必须失败 0。
4. 评估 VoLTE/IMS 路线（注册稳定性的最终解）。
