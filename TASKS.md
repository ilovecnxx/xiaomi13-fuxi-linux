## Handoff — 2026-10-31 基带（modem）注册稳定性 + modem keeper

### 目标
- 小米 13（fuxi）主线 Linux 蜂窝：IPA 数据通路稳定 → LTE/5G 注册稳定 → 短信、通话、双卡。

### 已完成
- modem12–15：IMEM 映射、SMEM 整段映射进 IPA IOMMU、SSR 在 offline 事件后 halt GSI 通道；基带崩溃恢复可用。
- modem16-epmap（#222）：`ipa_data-v5.5.c` 端点 AP_MODEM_RX 23→24、MODEM_AP_RX 21→22，rmnet 下行打通，两次启动实机通过（ping v4/v6、HTTPS、约 85 Mbit/s）。
- 01:55 曾刷回 s2idle2（#207），health 失败 0；02:09 又刷 modem16 到 recovery_b 准备测 keeper（日志 `work/claude-logs/modem16-keeper-flash-20261031.log`）。

### 关键文件及改动
- `work/patches/modem16-epmap-20261031/`：当前基带内核补丁；镜像 `work/kbuild/abl-fuxi-modem16-epmap.img`。
- `work/patches/mm-simslot-20261030/`：MM 双卡 active slot 补丁（手机 `/usr/local/lib/fuxi-mm/src/ModemManager`，drop-in `fuxi-patched.conf`）。
- `scripts/fuxi-modem-keeper.py` + `work/deploy/modem-keeper-20261031/`（keeper、service、usage 工具、MM drop-in）：开机设 data-centric，被拒/掉线后做射频 low→on 循环，带退避。
- 详细记录：`docs/目标-M5.md` 末节（01:30、01:55 两节）。

### 关键结论与坑
- 掉线原因方向：EMM cause 7（EPS services not allowed）/ voice-centric 下无 IMS 语音 → 基带停用 E-UTRA；只有 `mmcli --set-power-state-low` 再 `-on` 能恢复，data-centric 单独无效。
- 恢复 #207：`scripts/fuxi-test-recovery.sh work/kbuild/abl-fuxi-s2idle2.img`（需 USB adb），之后跑 `scripts/fuxi-health.sh --require-wifi --require-sensors`。
- 手机上没有 `curl`/`resolvectl`；补丁版 MM 前台跑会中途退出，用 `systemd-run --unit=mm-patched` 或 drop-in。
- MM 日志存档前过滤 password/psk/pin 行。
- 记忆里写着“自主刷机已暂停”（10-30），刷机/重启前先跟用户确认。

### 未完成 TODO
- keeper 是否已部署到手机、是否 active：未确认；`work/claude-logs/modem16-keeper-run1-20261031/` 为空，测试没跑。
- 注册稳定性长测（keeper 下 ≥1200 s，统计 registered 比例、射频循环次数）。
- IMS/VoLTE；短信；通话；卡 2 电信；移动卡全网通。
- 更新 `work/state/current-device.json`（仍写 #207）、README 进度。

### 下一步先做什么
1. ssh 到手机：`uname -v` 看是否 #222，`systemctl status fuxi-modem-keeper ModemManager`。
2. 若 keeper 未部署：按 `work/deploy/modem-keeper-20261031/` 拷到 `/usr/local/sbin`、`/etc/systemd/system` 后 enable，再开始 run1 记录。
