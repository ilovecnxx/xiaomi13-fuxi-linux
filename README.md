# Xiaomi 13 `fuxi` 主线 Linux 移植

目标是在 Xiaomi 13（SM8550）上运行主线 Linux 与完整手机/桌面用户空间。
当前已能从 `recovery_b` 启动主线内核 `7.3.0+` 和 `linux` 分区上的 Ubuntu 26.10；
普通重启回 Android。最终路线不使用 Android vendor kernel、Halium 或 Android HAL。

**进度入口**：`TASKS.md`（当前任务/下一步）→ `work/state/current-device.json`（基线/哈希）→ `docs/目标-M5.md` 末节（最新实机结果）。
历史更新流水已收敛到 `CHANGELOG.md` 与 `docs/archive/`；本文件只保留：项目简介、能力表、构建/访问、边界与自动化说明。

## 已有能力与待验收项

| 项目 | 当前证据 |
|---|---|
| 主线启动、UFS rootfs | 已实机运行；ABL 直接引导，Ubuntu 根文件系统位于 sda33 |
| 双系统 | recovery_b 进 Linux，普通启动进 Android；操作见 `docs/双系统启动说明.md` |
| 显示、触摸、Phosh | screen-audio9 原生 MSM DSI 实物画面与触控位置获用户确认；GPU（FD740）渲染与 120 Hz 已启用并获用户确认；自动熄屏/唤醒与自动亮度已测；旋转待验收 |
| 基础桌面应用 | Epiphany 软件渲染已显示 HTTPS 网页；中文输入和文本保存获用户确认；文件选择器待验收 |
| Chromium 浏览器 | Debian arm64 Chromium 150 隔离装到 `/opt/chromium`（非 dpkg、可回退），硬件 GL 渲染；**移动端 UI 层**：注入安卓-Chrome 风顶栏地址药丸 + 底栏 5 键，systemd --user 服务跨重启自启，注册 https 默认；实测服务 active、覆盖层在、截图分区佐证；待用户手指验收。见 `docs/Chromium浏览器移植-20261030.md`、评审请求 `docs/archive/CODEX评审请求-Chromium移动UI-20261030.md` |
| 电量 | 可读电量与充电状态；仍需独立确认实际充电和续航 |
| WiFi、蓝牙 | 10-29 整机重启验收：自动连网、外网/HTTPS 走 WiFi、WiFi SSH、管制域 CN；蓝牙出厂地址与对端 L2CAP 链路通过；蓝牙耳机/A2DP 待验收 |
| USB 联网、时间 | USB 网络的 DNS 与正常证书校验 HTTPS 已实测；120 个系统根证书，Asia/Shanghai 时区，NTP 已同步 |
| CPU 调频、温控 | daily-pm1 已实机运行：3 个 schedutil 策略、43 个热区、3 个 CPU cooling 设备 |
| 传感器 | 加速度、光线、距离、磁场、指南针已有实测数据；SensorProxy 已接入，物理旋转方向与桌面联动待验收 |
| 音频 | 两颗 CS35L41 可听（用户确认）；主麦克风经扬声器回环测试通过（#194）；第二麦克风（AMIC5→ADC4→SWR_MIC1，PipeWire profile 3）回环通过，待用户实录确认；耳机、保护标定待做 |
| 蜂窝 | **数据通路已打通**（modem16 #222，run1/run2：ping v4/v6、HTTPS、~85 Mbit/s）；注册稳定性未解决；IMS/VoLTE、短信、通话、双卡未开始 |
| 相机 | 仅有调研与诊断材料，不可用 |
| 定位/GNSS | 未开始（路线图原先未覆盖，已列入 remaining） |

WiFi 当前使用上游固件和参考板标定，小米标定的兼容性仍待解决。
日常基线镜像（`s2idle2 #207`）已启用 CPU 深度空闲、NO_HZ_IDLE，并关闭无主时钟/电源、强制 sync_state；M5.2（WiFi/蓝牙）已于 10-30 02:15 完成重启复验；s2idle 挂起可用（rtcwake 与电源键唤醒，挂起中 CXSD/AOSD 计数增长），但空闲自动挂起关闭、WiFi 唤醒未做，续航目标未完成。

## 构建

```bash
# 当前日用组合（原生显示 120 Hz + 扬声器/主麦克风 + GPU + 深度空闲 + 关闭无主时钟/电源）：
FUXI_DTB=sm8550-xiaomi-fuxi-r120idle-mic-rupdclk-audio-disp scripts/fuxi-build-abl.sh <名字>
# 无显示驱动的最小镜像（simpledrm）：scripts/fuxi-build-abl.sh daily
```

默认启用 CPU 调频、TSENS 和温控；构建不会操作手机。产物位于：

```text
work/kbuild/abl-fuxi-daily.img
work/kbuild/abl-fuxi-daily.config
work/kbuild/abl-fuxi-daily.dtb
work/kbuild/abl-fuxi-daily.build.json
```

同名配置、DTB 和 JSON 用于追溯本次实际构建。构建互斥锁防止共用源码树时串用配置；
成功和失败退出均恢复原始配置。`FUXI_PM=0` 仅用于调频/温控对照实验。
`--no-kernel` 只复用当前内核重打包，不重新验证内核配置。
为防止旧记录误配新镜像，它不能覆盖已有构建记录的同名产物。

变体示例：`FUXI_DTB=sm8550-xiaomi-fuxi-disp scripts/fuxi-build-abl.sh display-test`。
变体是实验镜像，不应只凭编译成功就替换日常镜像。

## 访问与测试

```bash
scripts/fuxi-ssh.sh                    # USB SSH，手机 10.42.0.2；FUXI_HOST=<无线 IP> 走 WiFi
scripts/fuxi-health.sh                 # 只读验收日常 Linux 镜像
scripts/fuxi-health.sh --require-wifi  # 另要求 WiFi 已连接
scripts/fuxi-health.sh --require-sensors # 另测五类真实数据、桌面接口与启动状态
scripts/fuxi-audio-check.sh --wait     # 音频候选：只读检查声卡、两颗功放和音量上限
scripts/fuxi-audio-smoke.sh --desktop # 音频候选：PipeWire 静音流和功放路径检查
python3 scripts/fuxi-audio-diagnose.py --desktop-silence # 实时 PLL、槽位、故障位及音频调度检查
python3 scripts/fuxi-basic-check.py --network # 基础桌面、根证书、键盘设置及 HTTPS 检查；不播放声音
scripts/fuxi-basic-desktop.sh        # 部署基础应用、时区、键盘大小与软件渲染启动器；只改 Linux rootfs
scripts/fuxi-chinese-input.sh        # 安装并配置 Stevia 拼音输入源；不改密码和内核
python3 -m unittest discover -s scripts/tests -v
```

部署沿用已验证流程：`scripts/fuxi-test-recovery.sh <镜像> '<检查命令>'`。
**该命令会重启手机并写入 recovery_b**；默认测试后回 Android，`FUXI_KEEP=1` 则留在 Linux。
测试前核对设备、镜像和备份；失败恢复方式见双系统说明。

传感器已采集的本机 Android 配置可用 `scripts/fuxi-sensors.sh --deploy-only` 部署到 Linux；
该方式不刷 recovery。只更新桌面接口使用 `scripts/fuxi-sensors-proxy.sh`，已支持 SSC 的包直接复用。
配置来源、只读注册表视图和已知限制见 `docs/传感器启动修复-20261029.md`。

## 操作边界

- Linux 系统修改限定在 `linux` 分区和 `recovery_b`；Android 系统与固件分区只读。
- 不回锁 bootloader，不改 GPT 槽位，不擦写 `persist`、`modemst1/2`、`fsg`、`fsc`。
- modem 实验只使用 EFS 文件副本；无 MPSS 的日常镜像跳过 rmtfs 服务。
- 备份必须核对哈希。10-24 原始备份在 `backups/20261024-172623/`；
  本轮修改前的完整 recovery_b 备份在 `work/backup/daily-pm-20261029/`。

## 资料入口

- `docs/archive/进展-20261029.md`：本轮改动、实测结果、备份与未完成项。
- `docs/基本功能修复-20261029.md`：当前基本功能优先级、浏览器、证书、时区、键盘修复与验收边界。
- `docs/音频出声修复-20261029.md`：当前实际出声、增益修复、用户反馈及保护边界。
- `docs/音频启动验证-20261029.md`：此前声卡、硬件诊断与实时调度的修复记录。
- `docs/目标-M5.md`：独立使用目标、无线/Phosh 与各外设实验历史。
- `docs/双系统启动说明.md`：启动、切换与恢复。
- `docs/音频调研.md`、`docs/相机调研.md`、`docs/蜂窝调研.md`、`docs/传感器调研.md`：功能诊断。
- `build/linux/`：含本机未提交改动的内核源码；不要重置或用旧脚本覆盖。
- `work/rootfs-overlay/`：用户空间服务与配置；`work/claude-logs/`：构建和实机日志。
- `docs/kbuild-镜像清单-20261031.md`：225 个镜像的清单/引用状态/哈希与保留策略。
- `docs/历史遗留与清理记录-20261031.md`：本轮收尾处理的历史遗留项与保留说明。


## 版本管理与自动发布

本地仓库（`main`）跟踪源码/文档/脚本/补丁/状态；大件产物、设备备份、私钥、第三方源码一律忽略：

- `.gitignore` 对 `work/` 采用白名单：只跟踪 `patches/ state/ deploy/ rootfs-overlay/ device-info/ chromium-mobile/`
- 永不入库：`*.img`、`*.ext4`、`backups/`、`work/backup/`、`work/ssh/`（含设备私钥）、`work/efs-copy/`（基带标定）、`build/`、`research/src-mm/`
- 提交约定：自动提交信息为 `auto: <时间> (N files)`；里程碑请用常规提交信息，并可 `git tag vX.Y`

**自动同步（已安装 cron，每 10 分钟）**

```bash
scripts/git-autosync.sh              # 本地提交 + 发布 GitHub
scripts/git-autosync.sh --no-publish # 只本地提交
scripts/git-autosync.sh --dry-run    # 预演
scripts/git-autosync.sh --status     # 最近提交 / 发布仓库 / 日志
```

- 本地仓库：`main`，记录全部内部资料
- GitHub 全量分支：`origin/main` = `https://github.com/ilovecnxx/xiaomi13-fuxi-linux-ubuntu26.10-kernel7.3`
  的 `main` 分支（2026-11-01 起手动推送，含 TASKS.md/交接文档/补丁/脚本；`master` 仍是旧的精选公开快照，两者历史无关）
- GitHub 精选快照：仍由 `scripts/publish-progress.sh` 发布白名单子集到 `work/gh-publish`（不重复入库）
- 日志：`work/claude-logs/git-autosync.log`
- 暂停自动同步：`crontab -e` 删除 `git-autosync.sh` 那一行

## 换电脑继续开发

全量开发历史在 GitHub 的 `main` 分支（`master` 是旧的精选快照，别用）：

```bash
git clone -b main https://github.com/ilovecnxx/xiaomi13-fuxi-linux-ubuntu26.10-kernel7.3.git linux-android
cd linux-android
scripts/fuxi-agent-preflight.sh          # 先看缺什么：内核树/工具链/state
```

仓库**不含**大件：`build/linux`（内核源码树）、`work/kbuild/*.img`（镜像）、`backups/`、`work/ssh/`
都在 `.gitignore` 内，需要在新机重建，见下一节与 `docs/kbuild-镜像清单-20261031.md`。
推回 GitHub：`git push origin main`（需要自己的 PAT 或 `gh auth login`）。

## 内核源码与可复现性

- 内核源码在 `build/linux`（torvalds 主干 clone），累计移植改动已提交到本地分支 **`fuxi/20261031`**（基于 `5b0764a53`）。
- 全量补丁：`work/patches/full-tree-20261031/full-20261031.diff`（5427 行，含 `SHA256SUMS`，反向 apply 校验通过）；误提交的 `ipa_mem.c.orig` 已移除并备份到 `work/patches/full-tree-20261031/removed-artifacts/`。
- `.build.json` 现在记录 `kernel_branch` / `kernel_dirty_diff_sha256` / `kernel_untracked_files` / `kernel_clean`；
  构建前确认内核树干净，否则记下 dirty-diff 指纹。
- 镜像清单与保留策略：`docs/kbuild-镜像清单-20261031.md`；历史遗留处理：`docs/历史遗留与清理记录-20261031.md`。
- **新机器重建内核树**（`build/linux` 不入库）：

```bash
git clone https://github.com/torvalds/linux build/linux    # 完整 clone，别用 --depth 1（要 5b0764a53）
git -C build/linux switch -c fuxi/20261031 5b0764a53235d3c77e1ed674e836e1b3fe1a4b1f
git -C build/linux apply --3way work/patches/full-tree-20261031/full-20261031.diff
git -C build/linux add -A && git -C build/linux commit -m "fuxi: 从全量补丁还原累计移植改动"
git -C build/linux diff 5b0764a53..fuxi/20261031 | sha256sum   # 应等于 96c51693…
```

  本机 `build/linux` 的 `master` 恰好就停在 `5b0764a53`，所以 preflight 用 `master..fuxi/20261031` 校验；
  新机的 `master` 会更新，比对时直接对 `5b0764a53` 做 diff。

## 切换 agent / 接力开发（必读）

任何 agent（Claude Code / Codex / DSH / 其他）接手本项目，先按 [`AGENTS.md`](AGENTS.md) 执行：

1. 读 `TASKS.md` → `work/state/current-device.json` → `docs/目标-M5.md` 末节 → `CHANGELOG.md`；
2. 跑 `scripts/fuxi-agent-preflight.sh`（可加 `--device` / `--with-tests`），**全 PASS 才开工**；
3. 改代码前 `scripts/fuxi-agent-lock.sh acquire <名字> "<任务>"`，结束 `release`；
4. 交接用 `/handoff`（10 节证据化格式），完成后更新 `TASKS.md` 与 state json。

`CLAUDE.md` 自动导入 `AGENTS.md`，Claude Code 新会话会直接读到；其他 agent 读 `AGENTS.md` 即可。
