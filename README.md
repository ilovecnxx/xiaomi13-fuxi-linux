# Xiaomi 13 `fuxi` 主线 Linux 移植

目标是在 Xiaomi 13（SM8550）上运行主线 Linux 与完整手机/桌面用户空间。
当前已能从 `recovery_b` 启动主线内核 `7.3.0+` 和 `linux` 分区上的 Ubuntu 26.10；
普通重启回 Android。最终路线不使用 Android vendor kernel、Halium 或 Android HAL。

**进度入口（2026-10-31）：新会话先读 `TASKS.md`（当前状态/下一步）→ `docs/目标-M5.md` 末节（最新实机结果）。**
**2026-10-31 02:40 更新：** 设备正运行 **modem16-epmap（#222，实验镜像）**，`recovery_b` 也是它；
modem keeper 已部署并 active，5G NR 注册 25 min 稳定、零触发；数据通路在该镜像 run1/run2 已打通（~85 Mbit/s），
但本次启动 rmnet 未建会话。**日用基线仍是 `s2idle2 #207`，测试结束必须刷回并跑健康检查。**
按用户要求，当前优先完善基本功能，高级驱动接入暂缓。已修复 HTTPS 根证书缺失、浏览器启动退出和竖屏键盘按键过小，
用户确认放大后可以准确输入，中文输入和文本保存也已确认；本轮记录见 `docs/基本功能修复-20261029.md`。
**2026-10-29 20:00 更新：** 当时运行 `screen-audio9-host-bindingfix`（`#187`，现已不是当前镜像）。原生 MSM DSI 显示已获用户现场确认画面正常、触控准确；
Adreno 740 改用 `/odm/firmware` 的小米签名 ZAP 后初始化成功（原先取自 `/vendor/firmware` 的是高通测试签名，TZ 返回 `-22`），
Phosh 已切到 GPU（FD740）渲染，用户确认明显流畅。随后 `screen120-gputherm`（`#189`）以 120 Hz 运行并接入 GPU 温控，用户确认更顺滑、画面正常，随后 `screen120-regcn`（`#190`）补上 WiFi 管制域支持，`screen120-blfix`（`#191`）修复熄屏时亮度写入报错，`idle2-nohz`（`#193`）开启 CPU 深度空闲与无节拍内核（熄屏电池电流约减半），`mic1`（`#194`）再加入 WCD9385 主麦克风，`ru5sync`（`#199`）去掉全部 `*_ignore_unused` 并修复卡住的 sync_state（熄屏电池电流 117→28.5 mA），`wifi5g`（`#200`）修复 CN 管制域下 5 GHz 不可见，`battsign5`（`#205`）修正电池电流符号并静默固件 0x50 消息，`s2idle1`（`#206`）开启 s2idle 挂起（SoC 首次进入深度睡眠），`s2idle2`（`#207`）修复挂起恢复后 WiFi 管制域回到 US，10-29 当时 recovery_b 即该镜像（2026-10-31 已改为实验镜像，见顶部更新）；空闲自动挂起已用 gschema override 关闭（s2idle 中 WiFi 不能唤醒）。详见 `docs/GPU初始化故障定位-20261029.md` 与 `docs/显示驱动故障定位-20261029.md` 末节。
`audio-probe4`（`#172`）和原 `recovery_b` 备份仍可回退。
原有音频配置保留；此前 `audio-probe4`（`#172`）两颗功放独立测试可听，用户已确认桌面四声短音均可听见；
保护/标定仍未完成，详见 `docs/音频出声修复-20261029.md`。`daily-pm1` 保留作回退，状态见 `work/state/current-device.json`。
早期 `docs/archive/交接-给CODEX.md`、`docs/archive/交接-给CLAUDE.md` 记录的是历史启动实验，
不能以其中“尚未启动主线”的旧结论判断当前状态（其余历史交接见 `docs/archive/`）。
**2026-10-30 14:36 更新：** 计划第 1 项 M5.2 复验通过：设备仍运行 `s2idle2`（#207），自动连接 5 GHz（5180 MHz）、管制域 CN、蓝牙 Powered、Phosh NRestarts=0；
本轮整机只读健康检查 0 失败，57 项主机回归通过；WiFi/蓝牙五个固件在设备、主机和隔离重生成结果间逐字节一致。日志见 `work/claude-logs/health-20261030-143144.log`、`work/claude-logs/host-regression-20261030-1440.log` 和 `work/claude-logs/m52-firmware-hash-20261030-1430.log`。
**15:06 实时状态复核：** 设备仍为同一 boot_id 的 #207，systemd `running`、5 GHz/CN、蓝牙 Powered、Phosh NRestarts=0；快照 `work/claude-logs/final-status-20261030-1506.log`。
基带实验里安装的 `protection-domain-mapper` 已启用，但 #214 仍重复触发 IPA SMEM 断言；计划第 2 项留待后续处理。
**15:34 只读复验：** `scripts/fuxi-health.sh --require-wifi --require-sensors` 失败 0，主机回归 57 项通过；设备仍是 #207、同一 boot_id，5 GHz/CN、蓝牙 Powered、Phosh NRestarts=0、systemd 无 failed units。日志：`work/claude-logs/health-20261030-153450.log`、`work/claude-logs/host-regression-20261030-latest.log`、`work/claude-logs/final-status-20261030-153450.log`。本轮未重启或刷写；M5.2 固件哈希复现性以 14:30 记录为准。
**15:48 源码复核与状态：** #214 的 PDR `-6` 在当前代码对应 domain-list 成功返回但没有匹配路径（`-ENXIO`），无应答应为事务超时 `-110`；QRTR 服务公告错误也见于无基带的挂起恢复记录。当前源码确有 `CONFIG_QCOM_PD_MAPPER`（`drivers/soc/qcom/Kconfig:79`、`Makefile:10`、`qcom_pd_mapper.c`），#207 与 modem8 配置均为 `=y`，手机 sysfs 有已绑定的 `qcom_pd_mapper.qcom-pdm-mapper`；用户空间 `protection-domain-mapper` 同时 active（17:39 更正，旧说法“源码没有该项”错误）；用户空间 pd-mapper 安装后故障仍复现。状态快照 `work/claude-logs/final-status-20261030-1544.log`；下一步采集 PDR 响应域列表并定位 PAS `-12`。

**17:40 更新：** 内核 PD mapper 在源码中存在且已启用（更正旧记录）。诊断镜像 `modem9-pdrpasdiag`（#215）编译通过、config/DTB/哈希已核验，尚未上机；手机仍为 #207。详见 `docs/目标-M5.md` 末节。

**21:10 更新：** modem12 第二次启动在 1047 s 进入 IPA 崩溃循环（SMEM 区 SMMU fault），已刷回 #207。完整交接见 `docs/交接-新会话-20261030-2110.md`。

## 已有能力与待验收项

| 项目 | 当前证据 |
|---|---|
| 主线启动、UFS rootfs | 已实机运行；ABL 直接引导，Ubuntu 根文件系统位于 sda33 |
| 双系统 | recovery_b 进 Linux，普通启动进 Android；操作见 `docs/双系统启动说明.md` |
| 显示、触摸、Phosh | screen-audio9 原生 MSM DSI 实物画面与触控位置获用户确认；GPU（FD740）渲染与 120 Hz 已启用并获用户确认；自动熄屏/唤醒与自动亮度已测；旋转待验收 |
| 基础桌面应用 | Epiphany 软件渲染已显示 HTTPS 网页；中文输入和文本保存获用户确认；文件选择器待验收 |
| Chromium 浏览器 | Debian arm64 Chromium 150 隔离装到 `/opt/chromium`（非 dpkg、可回退），硬件 GL 渲染；**移动端 UI 层**：注入安卓-Chrome 风顶栏地址药丸 + 底栏 5 键，systemd --user 服务跨重启自启，注册 https 默认；实测服务 active、覆盖层在、截图分区佐证；待用户手指验收。见 `docs/Chromium浏览器移植-20261030.md`、评审请求 `docs/CODEX评审请求-Chromium移动UI-20261030.md` |
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

- `docs/进展-20261029.md`：本轮改动、实测结果、备份与未完成项。
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

- 本地仓库：`main`，只在本机（无 remote），记录全部内部资料
- GitHub：仅发布白名单子集（docs/research/scripts，排除交接/任务/评审/宣传/内部工具/镜像），
  由 `scripts/publish-progress.sh` 推送到 `work/gh-publish`（该目录在 `.gitignore` 内，不重复入库）
- 日志：`work/claude-logs/git-autosync.log`
- 暂停自动同步：`crontab -e` 删除 `git-autosync.sh` 那一行

## 内核源码与可复现性

- 内核源码在 `build/linux`（torvalds 主干 clone），累计移植改动已提交到本地分支 **`fuxi/20261031`**（基于 `5b0764a53`）。
- 全量补丁：`work/patches/full-tree-20261031/full-20261031.diff`（6027 行，含 `SHA256SUMS`，反向 apply 校验通过）。
- `.build.json` 现在记录 `kernel_branch` / `kernel_dirty_diff_sha256` / `kernel_untracked_files` / `kernel_clean`；
  构建前确认内核树干净，否则记下 dirty-diff 指纹。
- 镜像清单与保留策略：`docs/kbuild-镜像清单-20261031.md`；历史遗留处理：`docs/历史遗留与清理记录-20261031.md`。
