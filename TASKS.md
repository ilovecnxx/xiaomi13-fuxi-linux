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

## 2026-10-31 21:00 信号：modem16 #222 run3（只读观测，进行中）

- 手机已开机回 Linux：`7.3.0+ #222`，boot_id `4074043f…`，电量 97%（USB SDP 5V，INPUT_CURRENT_LIMIT 100mA，PD 未协商）。
- 主机侧 NM 共享连接 `fuxi-usb` 丢失，已重建（`enx02f0c5130001`，10.42.0.1/24 shared）；之前 10.42.0.2 被 Meta 代理路由劫持。
- 【已实测】开机 27 s keeper 设 data-centric（voice ps-preferred）；开机 ~24 s 注册 5G SA home，15 min 无拒绝。
  当前只驻留 **5G SA**（LTE Status none），PDC 激活 `VoLTE-CU`，WDS 有 `IMS` APN 档（#4）。
- 【已实测·21:05 更正】IMS 栈是起的、配置是开的，只是**没有 IMS 承载所以没注册**：
  `--imsa-get-ims-registration-status` 用 qmicli 直接跑会 `InvalidOperation`/`too many IMSA actions`
  （qmicli 在 qrtr 上无法「bind+查询」同进程），改用 libqmi-glib 脚本 `scripts/fuxi-qmi-ims.py`
  同进程 bind 后读到：imsa 注册状态 **0 = not-registered**、technology 1；
  ims 设置 voice/sms/video/ut = True（ussd、wifi 语音 False）。`qmicli --wds-get-current-settings` 为
  `OutOfCall` → 本启动没有数据承载，IMS APN 档 #4（'IMS'，type ims）在但未起。imsp 客户端仍 Internal。
- 【推测】此前 EMM cause 7/18 掉线都发生在 LTE 下（voice-centric + 无 IMS 语音）；data-centric 下基带不因无语音停用 E-UTRA/NR。
- 采样：主机侧每 30 s 只读 ssh 采样 75 min → `work/claude-logs/modem16-run3-20261031-2048/reg.txt`（在手机上起 systemd 单元被权限拦截，改主机侧）。
- 下一步：长测结果出来后，查 IMS 为何 InvalidOperation（NV 里 IMS 开关 / 需要 IMS PDN 由 AP 发起 / 需要 Android 的 ims 配置服务），纯只读排查先行。

## 2026-10-31 21:05 IMS 更正 + 采样补跑（进行中）

- 【实测】run3 到 35 min 仍 5G SA home、零拒绝、keeper 零动作、无基带崩溃（`journalctl -b` 无 registration 变化）。
  `dmesg` 无 SMMU/ssr；只有显示侧 `dpu_crtc_get_scanout_position *ERROR* no encoder found`（另记）。
- 【修正】20:48 的 75 min 采样只跑了 7 min（前台进程被回收）。新增 `scripts/diag/modem-reg-sample.sh`
  （主机侧，秒数+间隔参数，输出一行 up/state|tech|signal|registration|ps|bat），21:01 起后台补跑 60 min
  → `work/claude-logs/modem16-run3-20261031-2048/reg2.txt`。
- 【新工具】`scripts/fuxi-qmi-ims.py`（已装 `/usr/local/sbin/fuxi-qmi-ims.py`）：libqmi-glib GI 同进程
  bind→查询 imsa 注册 + ims 业务开关，绕开 qmicli 在 qrtr 上的 bind 限制。只读。
- 【新工具】`scripts/fuxi-ims-pdn.sh status|up|down <handle>`：status 只读（已实测）；up 用
  `--wds-start-network=apn=IMS,ip-type=ipv4v6,profile-id=4` 起 IMS 承载并读 P-CSCF、复测 imsa；**未实机跑 up**。
- 充电侧：SDP 5V、`INPUT_CURRENT_LIMIT=100 mA`、电池 `current_now=-133 mA` → **净放电**（96%，~3%/h），
  PD 仍未协商；长测在电脑 USB 上只能短跑，PD 验证与墙充仍需用户插 67W 头。
- 下一步（22:01 长测结束）：① 起 IMS PDN 看 imsa 是否从 0 前进；② 同时/随后起 3GNET 数据会话，
  确认 modem16 的 IPA 下行在本启动仍通（run3 rmnet_ipa0 DOWN 未建会话）。

## 2026-10-31 21:12–21:27 IMS 承载实验：基带侧拒绝（结论 + 踩坑记录）

- 【实测】run3 干净基线到 **38.5 min**（20:32 开机 → 21:11 我主动 offline），全程 registered、零拒绝、
  keeper 零动作。采样 `reg2.txt`。
- 【实测·数据】`nmcli connection up fuxi-mobile`（APN 3gnet）→ `qmapmux0.0` 拿到 IPv4/IPv6，
  `ping -I qmapmux0.0` v4/v6 均 0% 丢包（49–117 ms）→ **IPA 下行在本启动确认可用**。
  注意：必须绑接口测；USB 共享 default 路由 metric 700 比蜂窝 1050 优先，不绑会误报 100% 丢包。
- 【实测·IMS】AP 侧起 IMS 承载被基带拒：`--wds-start-network=3gpp-profile=4` 和 `apn=IMS,ip-type=4`
  都返回 `QMI protocol error (70) InvalidOperation`；**5G SA 和仅 LTE 两种附着下都一样**，
  排除「NR SA 不支持」这个方向。把 profile 4 加进 LTE attach PDN 列表（`1,4`）+ 重启重新附着后
  imsa 仍是 `0 = not-registered`，IMS PDN 也没有自动建立。
- 【推测】基带要求 Android 走的那条路径 `WDS Start Network Interface`（带 APN 类型/mux），
  当前手机 libqmi 1.38 的 GI 没有 `start_network_interface`；或 VoLTE 在本 SIM/运营商侧未开通。
  验证下一步：回 Android 看 VoLTE 是否注册（`getprop | grep -i ims`），能区分是「运营商没开」还是「AP 侧缺路径」。
- 【踩坑·重要】`--dms-set-operating-mode=offline` 之后 **`online` 被拒 `InvalidTransition`**，
  `--dms-set-operating-mode=online`/`mmcli --enable`/`--dms-reset`/`mmcli --reset` 全部无效，
  射频卡在 offline。**唯一恢复办法是重启**（`systemctl reboot` → 回 Android → `adb reboot recovery` 回 Linux）。
  以后不要在这个基带上用 offline/online 切射频；要重附着用重启。
- 【已恢复】attach PDN 列表回到 `1`；模式偏好经 GI 写回 `gsm, umts, lte, 5gnr`（PERMANENT）；
  数据连接已恢复，5G NR home、ping 正常。

## 2026-10-31 21:28–21:35 Android 侧 VoLTE 核查 + 刷回基线

- 【决定性证据】Android 17 里两张卡的 IMS APN **都是 CONNECTED**，并且拿到 P-CSCF：
  联通 `联通IMS`（rmnet_data1）P-CSCF `2408:8142:4001:1::d405/d605`；
  电信 `中国电信(IMS)`（rmnet_data2）P-CSCF `240e:2c::201` 等 4 个。
  `NrVopsSupportInfo mVopsSupport=1`（网络支持 PS 域语音）；`availableServices=[VOICE,SMS,VIDEO]`。
  MBN：sub0 `NV#71546=7;VoLTE-CU(0x0A011561)`、sub1 `hVoLTE_OPNMKT_CT(0x0A0113F2)`
  （和 Linux 侧 PDC 激活的 0xA011561 一致）；`persist.radio.is_vonr_enabled_0=false`、`_1=true`。
  证据存档 `work/claude-logs/ims-android-20261031.txt`。
  → **运营商侧 VoLTE 是开通的**，「SIM 没开」这个假设排除；Linux 缺的是 AP 侧建 IMS PDN 的
  QMI 路径（Android 用 `WDS Start Network Interface`，带 APN 类型/mux；本机 libqmi 1.38 无此 API）。
- 【已回退】`scripts/fuxi-flash.sh flash baseline --yes` 写回 s2idle2（读回校验通过），
  `adb reboot recovery` 回 Linux，`uname -a` = `7.3.0+ #207`，boot_id `e5172f4b`。
  健康检查 3 项失败全是 WiFi 未连：扫描到的 AP 里没有已保存的（lihua/Redmi_9499 不在现场），不是回归。
- 【修 bug】`fuxi-flash.sh status` 原来按 `min(分区,12MiB)` 截取分区算 sha，而镜像是 10.4MiB，
  多读的填充把哈希带偏，把明明在跑的 #222 报成「未知镜像」。已改为按各已知镜像的**文件大小**截取比对；
  实测现在正确显示 `recovery_b = abl-fuxi-modem16-epmap.img`。
- 【存档】刷写前把当时 recovery_b 前 10MiB 存到 `work/backup/recovery-b-unknown-20261031/`（前 10,436,608 字节 = #222）。
- 下一步（无需设备）：给 libqmi 加/升 `Start Network Interface` 能力，或自己按 QMI 报目录发原始请求；
  之后重新刷 #222 验证 IMS PDN + P-CSCF + imsa 注册。

## 2026-10-31 21:40 IMS 承载矩阵测试：AP 侧全部被拒（结论固化）

- 新工具 `scripts/fuxi-ims-attach.py`（已装 `/usr/local/sbin/`）：同一进程内依次试 6 种起 IMS 承载的方式
  （GI 绕开 qmicli 的 bind 限制）。在 #222 上实测：

  | 变体 | 结果 |
  |---|---|
  | profile 4（APN 档 type=ims） | `InvalidOperation` |
  | `apn=IMS` + ipv6 | `InvalidOperation` |
  | `apn=ims` + ipv6 | `InvalidOperation` |
  | `apn=IMS` + ipv4 | `InvalidOperation` |
  | `apn=IMS`（不指定 ip 族） | `InvalidOperation` |
  | profile 4 + 绑定 mux 1 | `add_link` 报 EEXIST；`bind_mux` 报 `Internal` |

- 结论：**AP 侧 `WDS Start Network` 对 IMS APN 是硬拒**，与 RAT、IP 族、APN 大小写无关；
  mux 绑定路径也不通（endpoint 参数或链路状态另有问题，未继续挖）。
  剩下唯一方向是 Android 用的 `WDS Start Network Interface`(QMI 0x00A0 一类)，libqmi 1.38 没实现，
  需要「升级/打补丁 libqmi」或「按 QMI 报目录手写原始请求」。外网源码在这个环境抓不到（web_fetch 被解析到内网地址）。
- 旁证：SMS 子系统是活的（`wms-get-routes` 返回 6 条路由，存储 sm/me），**短信不依赖 IMS**，
  可以先做成一个用户可见功能（只读列短信免费，发短信会产生费用，要用户同意）。

## 2026-10-31 21:42 短信（WMS/MM）：工具就绪，等人决定是否真发

- `scripts/fuxi-sms.sh`：status/list/show/store/send/delete，走 ModemManager（qmicli 1.38 的 WMS 只有路由/能力查询，
  没有收发；`--wms-get-supported-messages` 直接 `InvalidQmiCommand`）。
- 踩坑：`--messaging-create-sms="text=带 空格,..."` 会被 MM 属性解析器在空格处截断；
  可靠做法是 `--messaging-create-sms-with-text=<文件>` + `--messaging-create-sms=number=...`（脚本已用 base64 传文本）。
- `--store`/`--store-in-storage=sm|me` 都报 Unsupported（MM 的 QMI 插件不支持存草稿）→ **没法免费验证发信路径**。
- 现状：modem 已注册 5G SA（PS attached、CS detached），`mmcli --messaging-status` 支持存储 sm/me，当前无短信。
- 待用户决定：发一条自测短信（约 0.1 元）还是由用户从另一部手机发一条（免费，只验证收）。

## 2026-10-31 21:45 短信实测：也卡在同一层（CS 无附着 + 无 IMS）

- 用户同意后向本机 `+8618607340261` 发自测短信，两次都失败：
  - 5G SA：`QMI protocol error (53) NetworkNotReady`（WMS 写短信部件失败）
  - 切到仅 LTE 重试：MM 报「已到超时限制」（基带没有回送信结果）
  - 两条都没有投递（收件箱始终为空，也没有自收短信）→ 大概率没扣费；超时那条无法 100% 确认。
- 原因：两种路径都不通。`--nas-get-serving-system` 在 5G SA 和仅 LTE 下都是 **CS: detached**（没有 SGs/CS 域），
  而 `SMS over IMS` 又需要 IMS PDN（`dd7` 那条没打通）。SMS 与 VoLTE 卡在同一层：AP 侧的附着/IMS 配置。
- 工具：`scripts/fuxi-sms.sh`（status/list/show/store/send/delete，走 MM，文本用 base64+文件传避免属性解析坑）、
  `scripts/fuxi-qmi-modes.py`（一次写回 RAT 位掩码；qmicli 只能单值）。
- 已恢复：模式偏好 `gsm, umts, lte, 5gnr`（PERMANENT）、5G SA 注册正常、草稿短信清空、电量 97%。
- 下一步（三选一）：① 原始 QMI / 补 libqmi 的 `Start Network Interface`（同时解 IMS 与 SMS-over-IMS，重）；
  ② 查 CS 附着（combined attach / SMS over NAS，中等）；③ 蜂窝先挂起，转做别的子系统。

## 2026-10-31 21:55 CS 附着路线也走不通（SMS over SGs 排除）

- 新工具 `scripts/fuxi-qmi-prefs.py`（读/写 voice_domain + usage_preference；`when=now|perm` 控制是否随 power cycle 生效）。
- 实验：把 voice domain 从 `PS_PREFERRED`(3) 改成 `CS_PREFERRED`(2)（促 combined attach）→ 重启 power cycle 生效
  → **5G SA 与仅 LTE 下 `--nas-get-serving-system` 都是 `CS: detached`**。5G SA 本来没有 CS 域；
  LTE 下也不 attach CS，说明这张卡/这个网络没有 SGs（2G/3G 退网），combined attach 没有意义。
- 结论：**SMS over SGs 不可用**；短信只能走 SMSoIP（需要 IMS PDN）。→ 短信与 VoLTE 是同一个硬卡点，
  不是两个独立问题。SMS 子系统本身（WMS 路由、MM 收发、存储）都是好的。
- 已恢复默认：voice=`PS_PREFERRED`(3，PERMANENT)、mode=`gsm,umts,lte,5gnr`(92)、5G NR 注册正常、
  keeper active、电量 96%。设备仍在 #222。

## 2026-10-31 22:20–22:35 IMS：NM 能起「IMS APN」承载，但基带不认作 IMS PDN

- 【已实测】NetworkManager 用 `gsm.apn=IMS` 能**成功激活**（拿到 IPv6，`qmapmux0.0`），
  而我们的 GI/qmicli 直接 `start_network`（profile 4 / apn=IMS / 各种 ip 族）全部 `InvalidOperation`。
  说明差别不在「APN 名称」或「消息」，而在 NM 的调用流程/客户端状态。
- 【未解】想抓 NM 实际发的 QMI：这台 NM 没有 QMI 调试域（`nmcli general logging domains QMI` 报 Unknown domain），
  libqmi 也没输出 `G_MESSAGES_DEBUG=QMI`（重启 NM 时还顺带把 MM 弄成 unmanaged 一次）。
  设备上**没有 strace / tcpdump**，抓不到字节。
- 【已实测】尝试复现 NM 的 mux 绑定：`bind_mux_data_port`（mux 0 和 1、EMBEDDED/HSUSB/PCIE/HSIC/BAM_DMUX 五种 endpoint）
  **全部 `QMI protocol error (3) Internal`**。所以 NM 很可能根本没调这条（或用了我们没暴露的参数）。
- 【关键负面结果】即使 NM 把 IMS APN 承载起起来，`imsa` 注册状态仍是 0，短信重发仍 `NetworkNotReady(53)`
  → 这条承载**没有被基带当成 IMS PDN**（没有 P-CSCF / 没有 APN type=ims 语义）。
  `--wds-get-current-settings` 对新客户端是 `OutOfCall`，读不到别人的 P-CSCF，无法直接验证。
- 结论：IMS 的缺口精确定位在「用 APN type=ims 语义建立 IMS PDN」。libqmi 的 Start Network 没有 APN type TLV；
  继续需要有 QMI 规范或能抓到 Android/NM 的真实请求字节。**这条路今晚不再试，避免重复失败。**
- 旁支已收尾：WiFi（iPhone 热点）实测空口 -39dBm/1200Mbit/s、吞吐约 4Mbit/s（瓶颈在热点出口）；
  已关闭 `CU_888` 的自动重连；健康检查在热点下 0 失败。

## 2026-10-31 23:05 收尾：IMS 挂起，转相机；主机缺构建工具链

- **IMS 挂起**（不是放弃）：卡在「带 APN type=ims 语义建 IMS PDN」，libqmi 无该 TLV，
  需要 QMI 规范或抓真实请求字节；已记录在 22:35 节，别重复试同样的变体。
- **今晚环境限制（重要）**：主机没有 `make`/`clang`/`gcc`/`cc`/`docker`（22:55 核查），
  内核与 ABL 镜像都编不了；手机端重构建也不做（USB 只有 100mA，凌晨已因此掉电关机）。
  → 相机/90Hz/Denial 这些要构建的，都要等工具链恢复 + 手机插充电器。
- **已完成**：今天全部改动已提交（666b915）；主机测试 57 项中 56 通过，
  1 项（`test_fuxi_volume_limit.py`）因本机无 gcc 无法编译，属环境问题。
  设备在 #207 基线，健康检查 3 项失败仅因 iPhone 热点已关闭（不在扫描列表）。
- **下一阶段选定：相机 → 先通超广角 OV13B10**（四摄里唯一主线有驱动的）。
  现有基础：camss 已支持 sm8550、csiphy 驱动在、fuxi 相机 dtsi 有电源树+CCI、
  `drivers/misc/fuxi-camera-power.c` 已实现并编过；缺：媒体子系统配置全关 + 没有 sensor 节点。
  具体改动步骤、DTS 片段、上机验证命令见 `docs/相机实现计划-20261031.md`。

## 2026-10-31 23:25 交接：见 docs/交接-新会话-20261031-2320.md

- 设备已刷回 **#207 s2idle2 基线**（23:18），USB SSH 可用，电量约 95%。
- 今天两条线：**蜂窝**（IMS PDN 卡点固化，短消息/通话都依赖它，详见交接 §4.1/§5）与
  **相机**（新开，OV13B10 已能 probe 到 I2C 0x10，卡在 chip ID `-5`，详见 §4.2）。
- 构建工具链已装好（用户提供 sudo 密码，不入文件）；`fuxi-build-abl.sh` 修了
  `CONFIG_INITRAMFS_SOURCE` 旧绝对路径问题。
- 下一个 agent 请从交接文档 §7 的「下一步」开始，并先跑 `scripts/fuxi-agent-preflight.sh`。

## 2026-11-01 00:30 相机：OV13B10 I2C 地址应为 0x36（不是 0x10）

- 【证据】厂商 `work/device-info/camera/com.qti.sensormodule.fuxi_ofilm_ov13b10_ultra.bin` 偏移 0x16de8：
  `slaveAddr=0x6c`(8 位) / addrType=2 / dataType=2 / ID 寄存器 `0x300b` 期望 `0x0d42`
  → 7 位地址 **0x36**，与 `ov13b10.c` 读 `0x300a`=0x560d42 吻合。同格式下 ov32c=0x30、s5k3k1=0x5a、imx800=0x20，交叉印证。
- 解释了 #223–#225 读 ID 一律 `-5`：一直在问 0x10（无设备应答）。
- 内核 `c9b7bbd22`：DTS `camera@10` → `camera@36`。全量补丁重导出 sha `79544f9b…`（5410 行）。
- 【仅编译通过】`work/kbuild/abl-fuxi-camera5.img`（#227，含 cb0a84212 复位时序），
  sha256 `0f3affcb530fb871e76fa4bdc982904a4b9374f570bef375ff231373cebb5f90`。
- 下一步：用户确认后 `scripts/fuxi-camera-trial.sh work/kbuild/abl-fuxi-camera5.img`（写 recovery_b → 抓日志 → 刷回 #207 → 健康检查）。
- 设备当前跑 **#225 camera3**（recovery_b 已是 s2idle2，下次重启即回基线），电量 87%、-255 mA 放电。

## 2026-11-01 00:35 相机 App 已装；camera5 上机被权限拦截

- 【已实测】手机（#225）`apt-get install` 成功，rc=0，新装 40 个包（约 16.8 MB，不卸载、不升级其他包）：
  `gnome-snapshot` 50.0（桌面名 Snapshot，`/usr/bin/snapshot`）、`libcamera-tools` 0.7.0（`cam`）、
  `gstreamer1.0-libcamera`、`libspa-0.2-libcamera`（PipeWire）、`libcamera-ipa`。日志 `work/claude-logs/camera-app-install-20261101-0032.log`。
- 【推测】sensor 没 probe 成功之前，Snapshot 会显示「无摄像头」；成功后要靠 libcamera simple 管线 + 软件 ISP 出图。
- `fuxi-camera-trial.sh` 抓日志时加了 `cam -l`。
- 用户已确认 camera5 试验，但 `fuxi-camera-trial.sh` 被 Claude Code 自动模式权限分类器拦了两次，**没执行**，设备没有任何改动。
