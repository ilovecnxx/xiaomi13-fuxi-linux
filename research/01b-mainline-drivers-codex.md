# 小米 13（fuxi/SM8550）主线 Linux 可行性（2026-10-24）

**评级：需数月。** SM8550 SoC 公共驱动较完整，可先启动；但 fuxi 的面板、触摸、无线校准、电源、modem 和相机仍是板级移植，不能直接当日用手机。

|子系统|主线状态|证据|
|---|---|---|
|SoC、UFS、USB、PCIe、热|已有|[sm8550.dtsi](https://github.com/torvalds/linux/blob/master/arch/arm64/boot/dts/qcom/sm8550.dtsi)|
|DPU 9.0/DSI/PHY|部分；HDK 文档称可进 UI（软件渲染）；fuxi/MTP 点亮未查证|[DPU](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/msm/disp/dpu1/catalog/dpu_9_0_sm8550.h)、[Linaro HDK](https://devboardsforandroid.linaro.org/_/downloads/en/latest/pdf/)|
|fuxi 面板|完全没有主线节点/驱动|[Lineage proprietary-files](https://github.com/LineageOS/android_device_xiaomi_fuxi/blob/lineage-22.2/proprietary-files.txt)|
|触摸|部分；厂商是 ST FTS V521 SPI；主线 `stmfts` 为 I2C，不能直接用|[fuxi config](https://github.com/LineageOS/android_kernel_xiaomi_sm8550/blob/lineage-22.2/arch/arm64/configs/vendor/fuxi_GKI.config)、[fts_spi](https://github.com/LineageOS/android_kernel_xiaomi_sm8550/tree/lineage-22.2/drivers/input/touchscreen/fts_spi)、[stmfts](https://github.com/torvalds/linux/blob/master/drivers/input/touchscreen/stmfts.c)|
|Adreno 740|部分；内核 a7xx/freedreno、Mesa Freedreno/Turnip 有支持；fuxi 实机硬件加速未查证|[MSM](https://github.com/torvalds/linux/tree/master/drivers/gpu/drm/msm/adreno)、[Mesa](https://docs.mesa3d.org/drivers/freedreno.html)|
|Wi‑Fi/BT|部分；ath12k 支持 WCN7850 系列，需 linux-firmware 和校准；fuxi 具体料号未查证|[ath12k](https://wireless.docs.kernel.org/en/latest/en/users/drivers/ath12k.html)、[firmware](https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/tree/ath12k)|
|modem/通话/SMS|部分到无；QRTR/QMI、IPA/rmnet 有，固件/IMS/音频闭环缺失；SM8550 手机主线通话未查证|[QRTR](https://github.com/torvalds/linux/tree/master/net/qrtr)、[IPA](https://github.com/torvalds/linux/tree/master/drivers/net/ipa)|
|相机|部分；SM8550 CAMSS binding 有，传感器/调谐/libcamera 管线缺 fuxi 资料|[CAMSS](https://github.com/torvalds/linux/blob/master/Documentation/devicetree/bindings/media/qcom,sm8550-camss.yaml)|
|启动|路径可行但须实测；解锁 ABL 通常可刷 boot，`fastboot boot` 是否放行未查证；无需先做 UEFI/U‑Boot|[bootloader](https://source.android.com/docs/core/architecture/bootloader/locking_unlocking)、[fastboot](https://android.googlesource.com/platform/system/core/+/main/fastboot/README.md)|
|充电/电池|部分；Type‑C/PMIC 基础有，Xiaomi 计量/策略/无线充电多为厂商模块|[fuxi GKI](https://github.com/LineageOS/android_kernel_xiaomi_sm8550/blob/lineage-22.2/arch/arm64/configs/vendor/fuxi_GKI.config)|

显示的阻断点是面板驱动：`mdss_dsi_m3_38_0c_0a_dsc_cmd` 表示 DSC 命令模式；需把 vendor XML/C 的初始化、睡眠、TE、亮度序列改写成 DRM panel，接上 DSI、DSC PPS、regulator、GPIO 和背光。主线 DPU 存在不等于 fuxi OLED 已点亮。预计 10–20 人日，若需示波器反查参数则 20–40 人日。

触摸需移植 FTS V521 SPI、IRQ/reset、电源和固件加载，约 8–15 人日；期间可用 USB OTG 键盘。GPU 先用 dumb buffer/llvmpipe，再验证 freedreno；GNOME/KDE 在 Wayland“理论可用”，fuxi 实机性能未查证。

**致命阻断项**

- 无面板/DSC/背光：启动后可能黑屏。
- 无 FTS SPI：无 USB 键盘时无法交互。
- modem/IMS/音频未闭环：不能通话短信。
- 电池计量/充电策略缺失：无法保证安全充电和休眠。
- ath12k 固件/校准缺失：无线不可用。

**从零到亮屏的最小路径**

1. 启动、串口、initramfs（3–5 人日）。
2. UFS、USB gadget/OTG、Type‑C、regulator（5–10）。
3. 面板、DSI、DSC、背光（15–30；首要风险）。
4. FTS V521 SPI 触摸（8–15）。
5. Weston/桌面与 GPU（10–20）。
6. Wi‑Fi/BT、suspend、电池（15–30）；modem/相机另计数十至数百人日，状态未查证。

**结论**：做研究型 Linux 手持终端可行；要在数周内替代 Android 不可行。合理目标是数周完成临时启动，1–3 个月完成亮屏和触摸，再长期补齐无线、电源、GPU；通话和相机属于独立大型项目。
