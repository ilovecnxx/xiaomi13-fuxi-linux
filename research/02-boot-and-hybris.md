# 小米13（fuxi）刷机链路风险与两条原生 Linux 路线

> 2026-10 查证。基线：LineageOS 24.0 / Android 17、kernel 5.15.211、已解锁（verifiedbootstate=orange）、A/B + 动态分区、无 TWRP/Magisk，root 仅来自 `adb root`。

## 1) 引导链路与 fastboot 能力

引导链：PBL → XBL/ABL（`xbl_a/b`、`abl_a/b`）→ 校验 `vbmeta` → 加载 `boot` + `init_boot` + `vendor_boot`。AOSP 明确，Android 13 起通用 ramdisk 移入 `init_boot`，`boot` 内只剩 GKI 内核（[source.android.com](https://source.android.com/docs/core/architecture/partitions/generic-boot)）；fuxi 的 boot 与 init_boot 均存在，另有 `recovery_a/b`、`super`、`persist`、`modemst1/2`、`fsg`。

本机 fastboot 37.0.1 帮助实测支持：`getvar`、`set_active`、`flash`、`boot`、`fetch`、`--disable-verity/--disable-verification flash vbmeta`、`reboot fastboot`（fastbootd，刷 `super` 内逻辑分区）。

**`fastboot boot boot.img` 不写分区**，可零风险验证自编内核（失败长按电源回 bootloader）。fuxi 的 TWRP [BOOT] 版按"只能临时启动"分发（[mi.fiime.cn](https://mi.fiime.cn/Recovery/3458.html)），可作 ABL 支持该命令的间接证据（未真机实测）。限制：boot 须与 `vendor_boot`/`vendor_dlkm` 的 GKI KMI 匹配，否则黑屏。

救援：官方 HyperOS fastboot 包（OS3.0.303.0.WMCTWXM，约 8GB，[xiaomirom.com](https://xiaomirom.com/en/rom/xiaomi-13-fuxi-taiwan-fastboot-recovery-rom/)）可整机重刷；也可先刷社区 TWRP/OrangeFox 到 `recovery_a/b` 做备份。

## 2) 风险分级

| 操作 | 可逆 | 等级 | 恢复手段 |
|---|---|---|---|
| `fastboot boot x.img` 临时引导 | 是，不写盘 | 低 | 长按电源回 fastboot |
| `fastboot set_active a/b` | 是 | 低 | 切回原槽 |
| 刷 `boot`/`init_boot`/`vendor_boot`/`dtbo`/`recovery` | 是 | 中 | 重刷官方包或切另一槽 |
| `--disable-verity --disable-verification flash vbmeta` | 是 | 中 | 重刷官方 vbmeta |
| 进 fastbootd 刷 `super`（system/vendor） | 是（数据丢） | 高 | 官方 fastboot 包整刷 |
| 刷/擦 `persist`、`modemst1/2`、`fsg`、`fsc` | **否**（唯一数据） | 高 | 只能靠事先备份，否则丢 IMEI/校准 |
| 刷 `abl`/`xbl`/`tz`/`hyp`/`devcfg` 或底层 `bk*` 分区 | 实质不可逆 | 致命 | 9008 EDL（需授权） |
| 改过 boot 后回锁 bootloader | 不可逆 | 致命 | 可能开不了机，需重新解锁 |
| 刷入低于当前版本官方固件 | 不可逆 | 高 | ARB 熔断只能 EDL（fuxi 是否启用 ARB **未查证**） |

EDL/9008：官方 MiFlash 需小米授权账号，XDA 称"EDL 不开放，除非有授权账号"（[ARB 说明](https://www.xda-developers.com/xiaomi-anti-rollback-protection-brick-phone/)）；2026 年社区仍需 authorized EDL 服务（[XDA](https://xdaforums.com/t/xiaomi-redmi-note-10-pro-sweet-hard-bricked-need-authorized-edl-flash-service.4755340/)）。"MiFlash Prime 免授权"为第三方修改版，不可依赖；fuxi 的 EDL 授权可行性**未查证**。另：efuse/qfuse 熔断（ARB、安全启动状态）**不可逆、无法备份**。

## 3) 路线一：Droidian/libhybris 半原生

原理：复用 fuxi 的 Android 5.15 内核 + vendor HAL blobs（gralloc/composer、audio、RIL、sensors 等），Android 容器（Halium）+ libhybris 跑 Debian。

现实性：**中低，但明显比路线二现实**。有利：LineageOS 24 的 fuxi 设备树与 vendor blobs 现成；Halium 仓库已有 `halium-13.0/14.0/16.0` 且 2026 年仍在提交（[github.com/halium/android](https://github.com/halium/android/branches)）。不利：Droidian 官方设备列表仅有若干老机型（小米 6X/MIX/Poco/Redmi 等），无 fuxi（[devices.droidian.org](https://devices.droidian.org/)），需从零写 port；Droidian 文档明确"stock 内核不够"，须按 Halium defconfig 重编并以 Docker 打包（binder/binderfs、`CONFIG_MODULES`、pstore 等由 [Halium guide](https://docs.halium.org/) 的 `mer_verify_kernel_config` 校验；[Droidian](https://docs.droidian.org/porting-guide/kernel-compilation/)），而 fuxi 是 GKI + `vendor_dlkm` 模块化，内核/模块/签名一致是主要难点；Android 13+ AIDL HAL 在 Halium 的成熟度**未查证到成功案例**。

关键阻塞：显示（gralloc/composer）、RIL、音频、触摸。前置条件：Halium 合规内核 + 与 vendor 版本匹配的 system.img（推断 `halium-16.0` 最接近 Android 16 底包）+ fastbootd 刷入。

## 4) 路线二：postmarketOS 从零建 port

事实：pmaports 2026-10 全量翻页核查（[gitlab](https://gitlab.com/postmarketOS/pmaports)）**无 `device-xiaomi-fuxi`，也无 sm8550/sm8450 内核包**；上游内核 qcom DTS 只有 `sm8550-hdk/mtp/qrd`，无 fuxi（[kernel.org](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/arch/arm64/boot/dts/qcom)）。SM8550 的 SoC 级 mainline 支持自 v6.8 起（8 Gen 2 HDK 已跑 pmOS；FOSDEM 2026 报告 8 Gen 3"boot to UI day 1"，[slides](https://fosdem.org/2026/events/attachments/SXNNMZ-snapdragon_8_gen_3_mainline_from_day-1_patches_to_product_reality/slides/267187/fosdem_20_bqxykvk.pdf)），但 fuxi 的面板（m3_38_0c_0a）、触摸、UFS 调压、USB、modem 全要自己写 DTS/驱动。

最小闭环：`pmbootstrap init` → 新建 device 包（内核基于自建 `linux-postmarketos-qcom-sm8550`）→ 写 `sm8550-xiaomi-fuxi.dts`（引用 sm8550.dtsi，补 UFS/panel/touch/regulator/USB）→ `fastboot boot` 验证 → 串口日志/亮屏 → GPU(freedreno/Mesa)、WiFi、modem。

人日：熟手到"能亮屏"约 2–4 周，到"能日常用"3–6 个月；新手翻倍。不建议作为第一个里程碑。

## 5) 开工前安全准备

1. 先把社区 TWRP 刷进 `recovery_a`/`recovery_b`（`fastboot flash recovery_a ...`，务必带槽位，SKKK 提示否则可能损坏分区）；备好官方 fastboot 包与 `vbmeta`；电量 >50%。
2. 用 root + `dd` 备份（也可先试 `fastboot fetch persist persist.img` 免 root）：

```bash
adb root
mkdir -p bk                     # 在电脑上存
for p in persist modemst1 modemst2 fsg fsc \
  boot_a boot_b init_boot_a init_boot_b vendor_boot_a vendor_boot_b \
  vbmeta_a vbmeta_b vbmeta_system_a vbmeta_system_b dtbo_a dtbo_b \
  recovery_a recovery_b; do
  adb exec-out "dd if=/dev/block/by-name/$p" > bk/$p.img
done
md5sum bk/*.img > bk/MD5.txt
```

（`super` 约 9GB、`userdata` 362GB 不备，重刷官方包即可恢复；`persist` 丢失的案例见 [XDA](https://xdaforums.com/t/solved-help-need-global-xiaomi-13-fuxi-persist-partition-dump-persist-img.4789572/)。）

3. 先做回滚演练：只重刷官方 `boot`，确认能开机再实验。
4. 红线：不 `erase` `persist`/`modemst`；不回刷低版本固件；改过 boot 前不回锁。

**结论**：链路可控（boot/init_boot/vbmeta 可重刷，`fastboot boot` 可试内核），致命项为 bootloader 链、底层分区与回锁；先走路线一，路线二为长期目标。
