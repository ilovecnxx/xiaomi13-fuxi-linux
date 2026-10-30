# 01 · 小米 13（fuxi）mainline 驱动现状矩阵（2026-10）

**一句话结论**：SM8550 的 SoC 级主线支持已经相当完整，真正缺的是 fuxi 这台机器的板级件——面板、音频 codec、蜂窝语音、相机、传感器；其中「面板」与「语音」是致命阻断项。

## 1. SoC 级：主线已基本到位

当前主线 master 为 `7.3.0`（2026-10）。`arch/arm64/boot/dts/qcom/sm8550.dtsi` 已包含：mdss + DPU 9.0 + DSI 4nm PHY + DP、Adreno 740 GPU、USB dwc3/eUSB2/QMP PHY、UFS（`qcom,sm8550-ufshc`）、PCIe0/1、IPA、MPSS/ADSP/CDSP PAS、LPASS 音频宏、CAMSS、Venus iris、i2c/spi/gpi、tsens/PDC；PMIC 侧 pm8550/pm8550b/pm8550ve/pm8550vs/pm8010 的 dtsi 也都在树内（由板级 DTS include）。真机 DTS 也已进主线：Sony Xperia 1 V（yodo/pdx234）与三星 Tab S9（q5q）；但前者没有显示/触摸节点，后者用 `simple-framebuffer`——说明「SoC 能跑主线」≠「手机外设可用」。

## 2. fuxi 器件 × 驱动状态

板级事实来自小米 vendor DTS（LineageOS 24.0 devicetrees 分支）；主线状态来自 2026-10 master 源码。

| 子系统 | fuxi 器件（vendor DTS） | mainline 状态 | 证据 URL |
|---|---|---|---|
| SoC 基础（clk/pinctrl/interconnect/PMIC） | kalama 平台 | 已有 | [sm8550.dtsi](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/arch/arm64/boot/dts/qcom/sm8550.dtsi) |
| UFS | UFS 4.0（公开规格；实际型号未查证） | 已有 | [ufs-qcom.c](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/drivers/ufs/host/ufs-qcom.c) |
| USB/Type-C/PD | dwc3 + pmic-glink + ucsi | 部分 | [sm8550-mtp.dts](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/arch/arm64/boot/dts/qcom/sm8550-mtp.dts) |
| 显示控制器（DPU/DSI/DSC） | DPU 9.0 + DSI 4nm | 已有 | [dpu_hw_catalog.c](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/drivers/gpu/drm/msm/disp/dpu1/dpu_hw_catalog.c) |
| 面板 | 三星 `m3 38 0c 0a`，1080×2400、DSC、cmd mode | **无** | [vendor panel dtsi](https://github.com/LineageOS/android_kernel_xiaomi_sm8550-devicetrees/blob/lineage-24.0/qcom/display/display/dsi-panel-m3-38-0c-0a-dsc-cmd.dtsi)；主线 [panel Makefile](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/drivers/gpu/drm/panel/Makefile) 无 Xiaomi 条目 |
| 触摸 | ST FTS V521，SPI（下游 `compatible = "st,spi"`，固件 `st_fts_m3.ftb`） | 无可直接匹配的主线 SPI 驱动/绑定；需移植或重新实现并核对固件许可 | [fuxi 下游设备树](https://github.com/LineageOS/android_kernel_xiaomi_sm8550-devicetrees/blob/lineage-24.0/qcom/fuxi-sm8550.dtsi)、[nuwa FTS SPI 参考](https://github.com/pubglite55/nuwa-mainline/tree/main/kernel/drivers/input/touchscreen/fts_spi) |
| GPU | Adreno 740（a7xx gen2） | 已有：kernel 侧有 a740 族支持，Mesa freedreno/Turnip 已收录 FD740（GL + Vulkan 1.3 路径）；需从原厂提取 GPU 固件与 DTS | [adreno_gpu.h](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/drivers/gpu/drm/msm/adreno/adreno_gpu.h)；[Mesa FD740](https://gitlab.freedesktop.org/mesa/mesa/-/blob/main/src/freedreno/common/freedreno_devices.py) |
| WiFi/BT | WCN7850（推断，见 §5） | 部分 | [ath12k/pci.c](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/drivers/net/wireless/ath/ath12k/pci.c)（含 WCN7850 固件名） |
| 音频 | `qcom,lpass-cdc` + 2×CS35L41 | 基本无：缺 codec 驱动与 sm8550 machine driver | [codecs/Makefile](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/sound/soc/codecs/Makefile)、[qcom/Makefile](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/sound/soc/qcom/Makefile) |
| 摄像头 | IMX800 / OV13B10 / OV32C / S5K3K1 | 部分→不可用：CAMSS 有 sm8550 资源，仅 OV13B10 有 sensor 驱动，无 ISP/3A | [camss.c](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/drivers/media/platform/qcom/camss/camss.c)、[media/i2c/Makefile](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/drivers/media/i2c/Makefile) |
| Modem/通话/SMS | 高通基带 | 部分：mpss PAS、IPA 驱动在，语音栈没有 | [qcom_q6v5_pas.c](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/drivers/remoteproc/qcom_q6v5_pas.c)；[q6voice 项目](https://postmarketos.org/blog/2026/05/08/q6voice-project/) |
| 传感器 | LSM6DSO/BMI26x/AK991x/TCS3720/SX937x，走 ADSP | 无 | [vendor sensors 配置清单](https://github.com/LineageOS/android_device_xiaomi_fuxi/blob/lineage-24.0/proprietary-files.txt) |
| NPU / GNSS | Hexagon NPU、基带 GNSS | 无（sm8550.dtsi 无节点，无驱动） | [sm8550.dtsi](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/arch/arm64/boot/dts/qcom/sm8550.dtsi) |
| 指纹 | Goodix 屏下（FOD） | 无 | [fuxi dts](https://github.com/LineageOS/android_kernel_xiaomi_sm8550-devicetrees/blob/lineage-24.0/qcom/fuxi-sm8550.dtsi)（`goodix,fingerprint`） |
| NFC | NXP SN100（`qcom,sn-nci`） | 无 | [drivers/nfc/Makefile](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/drivers/nfc/Makefile) |
| 充电/电量 | pm8550b charger，经 ADSP（pmic-glink） | 部分/未查证 | vendor `battery_charger` 节点 |
| 启动链 | 解锁 ABL / edk2-msm / U-Boot | 可行 | [edk2 fuxi.dsc](https://github.com/edk2-porting/edk2-msm/blob/master/Platform/Xiaomi/sm8550/fuxi.dsc)；[qcom_sm8550_defconfig](https://github.com/u-boot/u-boot/blob/main/configs/qcom_sm8550_defconfig) |

## 3. 致命阻断项

1. **面板（最硬）**：fuxi 面板是三星 `m3 38 0c 0a`（1080×2400、DSC、cmd mode），主线 panel 驱动表中没有任何 Xiaomi 机型条目，DSI panel 生成器仓库也无 fuxi 记录 → 没有 DRM/KMS，Wayland 合成、亮度、刷新率都无从谈起。唯一兜底是 UEFI GOP + `simpledrm`（edk2-msm 已有 fuxi 平台并设 1080×2400 framebuffer），但那是「能显示终端」，不是可用桌面，且实机验证未查证。
2. **蜂窝语音**：mpss PAS 与 IPA 驱动存在，但主线没有 q6voice（2026-05 才立项上游化），也没有 VoLTE/IMS 客户端；在 2026 年 2G/3G 退网背景下，「不能打电话」就等于不能当手机。SMS 理论可走 QMI，未验证。
3. **相机**：CAMSS 有 sm8550 资源，但 fuxi 四颗 sensor 中只有 OV13B10 有主线驱动（IMX800/OV32C/S5K3K1 均无），且无 Spectra ISP/3A → 只能算「CSI 能出裸数据」。

其余缺口都可补：UFS 有 SM8550 支持，WiFi 的 WCN7850 有 ath12k；触摸是 ST FTS V521 SPI，主线没有可直接匹配的驱动。GPU 方面 Adreno 740 属 a7xx gen2，kernel 与 Mesa（freedreno/Turnip，FD740）两侧都有支持，但没有 fuxi 实测，ray-tracing 等细节特性未逐一核对。显示控制器（DPU/DSI/DSC）在主线已有 SoC 支持，缺的是 fuxi 面板驱动和整机 DTS。

## 4. 社区 port 与引导链

- **pmaports** 无任何 SM8550/fuxi 设备包（最新 qcom SoC 内核包只到 sm8350）；pmOS/Nura 的 SM8550 工作集中在社区 kernel fork（分支 `bringup`/`s23/bringup2`，最后活动 2025-12），且其 Galaxy S23（SM8550）设备页仍标 `booting = no`。wiki 上 SM8550 SoC 页把 display/GPU/modem 标为 Y，但那是 SoC 级、非手机级。[pmaports](https://gitlab.com/postmarketOS/pmaports/-/tree/master/device/testing) / [SM8550 kernel fork](https://gitlab.postmarketos.org/soc/qcom-sm8550/linux) / [S23 设备页](https://wiki.nura.eco/wiki/Samsung_Galaxy_S23_%28samsung-dm1q%29)
- **Droidian / Mobian**：未查证到 SM8550/fuxi port；lk2nd 支持列表最高只到 msm8996。[lk2nd devices.md](https://github.com/msm8916-mainline/lk2nd/blob/master/Documentation/devices.md)
- **引导不是阻断**：bl 已解锁，ABL 接受自定义 boot.img（LineageOS 官方支持 fuxi）；edk2-msm 有 fuxi 平台且 CI 把 fuxi 列为构建目标；U-Boot 虽有 `qcom_sm8550_defconfig`，但明确面向开发板的 uefi 分区，不是手机方案。[LineageOS fuxi](https://wiki.lineageos.org/devices/fuxi/) / [U-Boot patch](https://lists.u-boot-project.org/pipermail/u-boot/2026-July/625942.html)

## 5. 方法与未查证

所有「已有/部分/无」均以主线源码与 vendor DTS 交叉核对，主线版本 7.3.0（2026-10）。**未查证**：fuxi 的 WLAN 具体 chip ID（vendor `kalama-cnss.dtsi` 同时有 0x1103/0x1107 双配置，据 Wi-Fi 7 规格推断为 WCN7850，未实测）；UEFI 在 fuxi 实机是否已成功点亮；mainline 下 modem 固件加载与 SMS 可用性；充电/电量（`qcom_battmgr` 路径未验证）；UFS 实际型号。
