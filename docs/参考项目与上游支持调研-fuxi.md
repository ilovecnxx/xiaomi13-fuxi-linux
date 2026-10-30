# fuxi 主线 Linux 参考项目与上游支持调研

> 调研时间：2026-10-25 深夜（只做调研，未在设备上执行任何操作）
> 设备：Xiaomi 13（fuxi，SM8550）
> 目的：找出可复用的公开项目/上游支持，指导接下来的主线 Linux 移植

---

## 1. 结论摘要

1. **上游 Linux 主线没有 fuxi 的设备树**：`arch/arm64/boot/dts/qcom/` 只有 `sm8550-hdk/mtp/qrd`、`sm8550-samsung-q5q`、`sm8550-sony-xperia-yodo-pdx234`，没有 `sm8550-xiaomi-fuxi.dts`。
2. **但 SM8550 的主线外设支持已经不少**：`sm8550.dtsi` 里已有 **UFS**（`ufs_mem_hc`/`ufs_mem_phy`）、**USB DWC3**（`usb_1_dwc3`）、DSI 控制器节点；`drivers/phy/qualcomm/phy-qcom-qmp-ufs.c` 里已有 **sm8550 UFS PHY 时序表**。也就是说“主线跑起来后挂 UFS/根分区”的基础是存在的。
3. **暂未找到公开的 fuxi 纯主线 Linux 设备移植**：postmarketOS/Nura、UBports、Droidian 均没有发现 fuxi port；现有 fuxi 专用公开工作主要是 UEFI/UniXNU。相邻的 SM8550 sheng/nuwa 项目可作同 SoC 参考，但不是 fuxi 支持。
4. **Mu-Silicium fuxi UEFI 是可验证的启动器候选**：`hanzi123-bilp/uefi-fuxi` 的固件 workflow 曾成功产出 `fuxi-boot-image`，且 package 中包含 GOP 和 RAM payload 组件。其主要目标仍是 UniXNU，尚无主线 Linux 真机启动证据。
5. 因此建议把 **Mu-Silicium fuxi UEFI + EFI-stub 主线内核**作为无写分区的诊断实验候选，而不是已打通的最终启动链。Linux EFI stub 可从 GOP 取得 framebuffer 信息并交给 sysfb；显示能否持续到 `simpledrm`/fbcon、是否保留内存并跨过早期启动，仍须真机验证，不能据此认定早期启动阻塞已解决。

### 1.1 2026-10-25 网络复核

| 项目 | 新状态 | 对 fuxi 主线 Linux 的意义 |
|---|---|---|
| [pubglite55/nuwa-mainline](https://github.com/pubglite55/nuwa-mainline) | 10 月 24 日提交 `26e6329` 增加 Linux 7.0 + SM8550/nuwa 补丁的社区内核 workflow；两条构建 workflow 成功 | 目前公开证据是 CI 编译和 artifact，不是 nuwa 真机启动。其 FTS V521 SPI 驱动可研究；nuwa 的面板、板级 DTS 与 fuxi 不同，不能照搬。 |
| [map220v/sm8550-mainline](https://github.com/map220v/sm8550-mainline) / [sheng 7.3.0 发布](https://github.com/ianchb/sm8550-mainline/releases/tag/7.3.0) | SM8550 小米平板 sheng 的主线派生内核发布 7.3.0，带内核包、启动镜像和配置；对应源码近期有 SPMI 热区、USB-C mux、ath12k 等修订 | 是目前最有价值的同 SoC Linux 参考，可比对 DTS、Kconfig、UFS 和显示实现；sheng 为平板且板级配置不同，不能复制其 PMIC/面板/内存值。 |
| [hanzi123-bilp/uefi-fuxi](https://github.com/hanzi123-bilp/uefi-fuxi) | fuxi UEFI 固件构建 workflow 于 10 月 24 日成功产出 `fuxi-boot-image`；10 月 25 日 loader workflow 的 artifact 为 `fuxi-xnu-boot`，近期改动集中在 XNU/iOS loader | 固件源码确实包含 GOP 与 RAM payload 机制，但 CI 成功不证明固件已在 fuxi 实机工作，也没有发现 Linux EFI 启动器或主线 Linux 真机启动记录。Linux EFI-stub 路径仍需单独实现和实测。 |
| [torvalds/linux DTS](https://github.com/torvalds/linux/tree/master/arch/arm64/boot/dts/qcom) | 当前 SM8550 设备树仍没有 Xiaomi fuxi/nuwa 专用 DTS | fuxi 最小 DTS 和板级启动资源仍是本项目必须解决的工作。 |
| [本项目兼容性构建 CI](https://github.com/ilovecnxx/fuxi-linux-build) | 10 月 25 日最新构建失败：BTF 生成时报 `pahole (pahole) is not available` | 这是厂商内核/模块 ABI 复现仓库的 CI 问题，不改变纯主线 Linux 路线；安装 `pahole` 或在该 CI 配置中禁用 BTF 即可修复构建环境。 |

**路线判断更新**：保持纯主线内核为最终系统。先解决内核 handoff 和早期日志，再做 UFS rootfs、显示和触摸。Mu-Silicium fuxi UEFI + GOP/payload 是有希望的诊断启动器，但其 Linux 启动尚未证实；在确认真机 UEFI 画面并完成 EFI-stub/initramfs 启动前，不能把它算作已打通路径。直接 ABL 启动仍受 DTB overlay/身份匹配和无早期日志阻塞；厂商内核 kexec 只保留为诊断对照，不作为 Linux 系统内核。

---

## 2. 上游 Linux 主线支持现状（SM8550）

| 外设 | 主线状态 | 依据 |
|---|---|---|
| SoC 基础（GCC/PDC/RPMH/互连/I2C/SPI/UART/GPIO） | ✅ 已有 | `sm8550.dtsi` |
| UFS 控制器 | ✅ 已有节点 | `sm8550.dtsi`：`ufs_mem_hc`、`ufs_mem_phy` |
| UFS PHY 驱动 | ✅ 有 sm8550 表 | `drivers/phy/qualcomm/phy-qcom-qmp-ufs.c` 中 `sm8550_ufsphy_*` |
| USB DWC3 | ✅ 已有节点 | `sm8550.dtsi`：`usb_1_dwc3` |
| USB2 PHY / eUSB2 | ✅ 驱动存在 | `phy-qcom-eusb2`、`phy_qcom_snps_eusb2`（fuxi 用的是 PM8550B eUSB2 repeater） |
| 显示 DSI 控制器 | ⚠️ 节点有，DPU/MDSS 支持不完整 | `sm8550.dtsi` 有 `dsi@ae94000`、`dsi@ae96000`；但 **fuxi 面板驱动不存在** |
| 面板 | ❌ 缺 | 下游设备树名为 `dsi_m3_38_0c_0a_dsc_cmd`；本机启动参数也确认该面板，主线无对应 panel 驱动 |
| 触摸 | ❌ 缺 | 下游设备树是 ST FTS V521 SPI（`compatible = "st,spi"`，固件 `st_fts_m3.ftb`）；主线没有可直接匹配的该 SPI 驱动/绑定 |
| 指纹 | ❌ 缺 | 下游是 `goodix,fingerprint`（GPIO 40/41） |
| 摄像头/音频/调制解调器 | ❌/⚠️ | 主线远未支持，不属于“先跑起来”的范围 |

**关键判断**：主线 kernel 在 SM8550 上“能跑、能挂 UFS、能出 USB”是合理的；**fuxi 缺的是自己的 DTS（memory/reserved-memory/regulator/pinctrl/面板）**，不是 SoC 驱动。

---

## 3. fuxi 需要的设备树信息（下游参考来源）

LineageOS 的下游设备树仓库是现成的硬件字典：

- `LineageOS/android_kernel_xiaomi_sm8550-devicetrees`（分支 `lineage-24.0`）
  - `qcom/fuxi-sm8550.dtsi`：PMIC（pm8550/pm8550b/pmk8550）、GPIO、ST FTS V521 SPI 触摸、Goodix 指纹、USB eUSB2 repeater、电池、热区等
  - `qcom/fuxi-sm8550-overlay.dts`：板级覆盖（根身份 `qcom,kalama-mtp`，与 ABL 运行时改写行为一致）
  - `qcom/fuxi-pinctrl.dtsi`：引脚配置
  - `qcom/display/display/fuxi-sde-display-mtp.dtsi` 与 `dsi-panel-m3-38-0c-0a-dsc-cmd.dtsi`：面板 `dsi_m3_38_0c_0a_dsc_cmd`
  - `qcom/audio/fuxi-audio-mtp.dtsi`、`qcom/camera/fuxi-sm8550-camera-sensor.dtsi`：音频/相机
- crDroid/其它 fork 有同源副本（`crdroidandroid/android_kernel_xiaomi_sm8550-devicetrees`）

这些文件是写主线 `sm8550-xiaomi-fuxi.dts` 时**照抄 regulator/GPIO/中断**的第一手资料；但注意主线不能直接吃下游节点名，需要按上游 bindings 翻译。

---

## 4. 社区项目盘点

| 项目 | 方向 | 对我们的价值 |
|---|---|---|
| **`hanzi123-bilp/uefi-fuxi`**（分支 `fuxi`） | Mu-Silicium UEFI 移植（用于 iOS/XNU） | ⭐⭐⭐ **最有价值**。有 `Platforms/Xiaomi/fuxiPkg`（dsc/fdf/DeviceBuild.py）、`Resources/Configs/fuxi.toml`、CI（`.github/workflows/build-fuxi-uefi.yml`，约 4–10 分钟产出 `fuxi-boot-image`）。Mu-Silicium 本身是给 Windows/Linux 用的 UEFI 固件，理论上可直接承载主线 EFI 内核 |
| `hanzi123-bilp/unixnu-fuxi` | UniXNU 设备仓库（iOS/XNU） | ⭐ 设备配置/分区/patches 可参考 |
| `matejkoo217/UniXNU-fuxi` | UniXNU fuxi 设备支持（进行中） | ⭐ 同上 |
| `Xyvern08371/unixnu-fuxi` | 另一套 fuxi UniXNU 仓库（含 loader-shim、appledt、ci-logs） | ⭐ loader/BootShim 细节可参考 |
| `P4rfa1t/fuxi-xnu`、`bangprovn/ios-fuxi`、`Dublin1231/fuxi-xnu-build` | fuxi 上的 XNU/iOS | ⭐ 启动链、触摸驱动验证记录 |
| `UniXNU/UniXNU`、`UniXNU/ShengUfs`、`UniXNU/GopFramebuffer`、`UniXNU/DarwinBoot` | UniXNU 主仓库、**原生 UFS 驱动**、**GOP 帧缓冲交接** | ⭐⭐ UFS/GOP 实现细节；sheng 与 fuxi 同为 SM8550 |
| `UniXNU/UniXNU-sheng` | 小米平板 6S Pro（SM8550）支持 | ⭐⭐ 同 SoC 的 UEFI 布局/内存映射可直接对照 |
| `fuxi-dev/*` | Android 设备树/内核仓库（AOSP 向） | ⭐ 仅 Android 侧参考 |
| postmarketOS / UBports / Droidian | — | ❌ 均无 fuxi 支持（pmaports 404、设备列表无） |
| 上游 kernel DTS | — | ❌ 无 fuxi DTS；SM8550 基础支持已有 |

文档参考：<https://unixnu.com/zh/devices/fuxi>（明确标注两个 fuxi 仓库都在进行中、无真机运行记录）

---

## 5. fuxi 上对 Mu-Silicium UEFI 的实测（本项目）

| 镜像 | 结果 |
|---|---|
| `Mu-fuxi.img`（CI 原样，header v3，1.4MB） | ❌ `fastboot boot` 报 `Failed to load/authenticate boot image: Invalid Parameter`（两次干净重试均失败） |
| 重打包 v3（补 `os_version 13.0.0`、patch 2022-11、page 4096） | ✅ 返回 `Booting OKAY`；但之后 USB 无枚举，无法确认 UEFI 是否真正执行 |
| 重打包 v1（base 0x80000000） | 未完成验证（设备掉出 USB） |

他们 `fuxi.toml` 里的关键参数（来自本机 `xbl_config_a` 的 `uefiplatLA.cfg`）：

```toml
[uefi_fd]
base = 0xA7100000
size = 0x300000
[boot_shim]
requires_kernel_header = true
[boot_image_kernel]
kernel_compression = "gzip"
append_dtb = true
[boot_image]
header_version = 3   # 他们 2026-10-21 实测 Mu-qrd8550.img(v3) 在 fuxi 上可 Booting OKAY
```

CI 产物布局：`Mu-fuxi*.img`（BootShim + gzip(UEFI FV) + fuxi.dtb，mkbootimg v3）与 `SILICIUM_UEFI.fd`。

---

## 6. 建议路线（按性价比排序）

### 路线 A（推荐）：Mu-Silicium UEFI + 主线 EFI 内核
1. fork `hanzi123-bilp/uefi-fuxi`，在 `Platforms/Xiaomi/fuxiPkg` 增加一个 Linux 引导组件（把本项目的 `build/edk2-msm/.../FuxiLinuxBoot` 思路移植过去，或直接用 `LoadImage` 加载带 EFI stub 的主线 `Image`）。
2. 主线内核配置保持 `CONFIG_EFI=y/EFI_STUB=y`，并启用 `CONFIG_DRM_SIMPLEDRM=y` + `FRAMEBUFFER_CONSOLE=y`：
   - UEFI GOP 提供的 framebuffer → simpledrm → fbcon → **启动日志直接上屏**
   - 不再依赖 USB 串口/无 UART 的困境
3. 用他们的 CI 构建（Ubuntu runner 即可，UEFI 阶段不需要 macOS），下载 `fuxi-boot-image` → `fastboot boot`。
4. 成功后用 `PSTORE_BLK` 把 panic 写盘，进一步用主线 UFS 挂载 100GB 分区。

**风险**：该 fork 当前默认入口是 UniXNU/DarwinBoot（iOS 菜单），需要改 FV 内的默认应用/启动顺序；GOP 是否已在该 fuxi 移植里实现需核对 `fuxiPkg` 的 DXE.inc/GPLDrivers。

### 路线 B：沿用 `android-mainline-port` 手册的 ABL 路线
- 给主线 DTB 注入 `__symbols__`（dtbo 引用符号 + hypervisor overlay 符号如 `arch_timer`，指向 `status="disabled"` 容器）
- 用 v2（kernel+ramdisk+DTB）做 RAM 测试；本机实测 fuxi 的 ABL 拒绝 v2 的 dtb 字段（Load Error），需继续验证是否与 DTB 身份（`msm-id`/`board-id`）有关
- 持久启动按三件套 + 自签 AVB

### 路线 C：现有厂商内核 + kexec（本项目已打通的半条路）
- 已能 kexec 跳转，但跳转后日志抓不到；若改成“主线内核 `PSTORE_BLK` 写盘 + 失败自动回原系统”，可继续推进

### 共同前提
- 主线 fuxi DTS 需要自己写：内存/保留内存（可用本机 `/sys/firmware/fdt` 或原厂 DTB 提取）、regulator（照下游 `fuxi-sm8550.dtsi` 翻译）、pinctrl、触摸/面板（后两者可先 disabled）
- 屏幕显示优先用 UEFI GOP + simpledrm（不依赖 fuxi 面板驱动）

---

## 7. 参考链接

- Mu-Silicium fuxi UEFI：<https://github.com/hanzi123-bilp/uefi-fuxi>（分支 `fuxi`）
- UniXNU 主仓库：<https://github.com/UniXNU/UniXNU>
- UniXNU 原生 UFS 驱动：<https://github.com/UniXNU/ShengUfs>
- UniXNU GOP 交接：<https://github.com/UniXNU/GopFramebuffer>
- UniXNU-fuxi（iOS）：<https://github.com/hanzi123-bilp/unixnu-fuxi>、<https://github.com/matejkoo217/UniXNU-fuxi>
- Xyvern08371 的 fuxi UniXNU：<https://github.com/Xyvern08371/unixnu-fuxi>
- LineageOS 下游设备树（硬件字典）：<https://github.com/LineageOS/android_kernel_xiaomi_sm8550-devicetrees>
- fuxi-dev 组织：<https://github.com/fuxi-dev>
- 同型设备主线移植手册：<https://github.com/yzddmr6/android-mainline-port>
- UniXNU 设备文档（fuxi 页）：<https://unixnu.com/zh/devices/fuxi>
- 上游 Linux DTS 目录（确认无 fuxi）：<https://github.com/torvalds/linux/tree/master/arch/arm64/boot/dts/qcom>

---

## 8. 本次调研未覆盖/待确认

- Mu-Silicium fuxi 的 `fuxiPkg` 是否已包含 **display GOP** 与 **UFS 存储**驱动（需读它的 `Include/DXE.inc`、`DXE.inc` 引用的 Silicium 驱动和 GPLDrivers 目录）
- 其 CI 产物 `Mu-fuxi-v3-os.img` 在 fuxi 上“Booting OKAY 后无 USB”到底是黑屏挂住还是 UEFI 正常启动但无外设——需要一次带拍照的验证
- 上游是否有正在评审的 fuxi DTS 补丁（patchwork/lore 搜索未得到有效结果，需换更精确的查询）
- fuxi 面板 `dsi_m3_38_0c_0a` 是否有主线 panel driver 的社区分支

---

# 附录 B：Mu-Silicium 固件能力与“用 UEFI 引导主线 Linux”的可行方案

## B.1 `hanzi123-bilp/uefi-fuxi` 固件现状（读源码得到）

| 项 | 结论 |
|---|---|
| 基础 | Mu-Silicium（Project Mu 派生），`Platforms/Xiaomi/fuxiPkg`，分支 `fuxi` |
| FD 布局 | `base=0xA7100000`、`size=0x300000`（3MiB），位于本机 stock 4MiB FD 窗口 `0xA7000000` 内；来自 `xbl_config_a` 的 `uefiplatLA.cfg` |
| 启动镜像格式 | BootShim + gzip(UEFI FD) + 追加 fuxi DTB，`mkbootimg --header_version 3 --ramdisk Resources/ramdisk --pagesize 4096` |
| `FUXI_VENDOR_HW=0`（当前 CI 构建） | **SimpleFbDxe 直接发布 GOP**（面板在 ABL 交接时已扫描输出，不需要 vendor 显示栈）；含 FatPkg/DiskIo/Partition、UsbBus/UsbKb/UsbMassStorage、FuxiRamDiskDxe、FuxiKeyInputDxe、BdsDxe、GraphicsConsoleDxe |
| `FUXI_VENDOR_HW=1` | 计划导入 stock vendor 驱动（SMEM/时钟/RPMh/UFS/USB/充电/PMIC）；**sheng 上实测：vendor ClockDxe 会让面板黑屏（背光仍亮），原因未解决**；fuxi 未测试 |
| 内部存储（UFS） | ❌ `VENDOR_HW=0` 构建不含 UFSDxe → UEFI 看不到任何块设备（除 payload RAM disk） |
| payload 机制 | `fastboot boot` 的 **ramdisk 字段**是一个 **标签为 `FUXIESP` 的 FAT 卷**；`FuxiRamDiskDxe` 扫描 UEFI 内存图找 FAT 引导扇区标签，发布 BlockIo → FAT 驱动挂载 → BDS/UniXNU 可以像普通文件系统一样读取里面的文件 |
| 屏幕 | 支持（GOP），sheng 的 PORTING.md 记录 ABL 提供 3048x2032 32bit linear framebuffer；但需要 DTB 里保留 `/reserved-memory/splash_region` 才能保持扫描输出 |

参考：`uefi-sheng/Platforms/Xiaomi/shengPkg/PORTING.md`（同 SM8550）、`fuxiPkg/Include/DXE.inc`、`RAW.inc`、`Resources/Configs/fuxi.toml`、`build_uefi.py`。

## B.2 厂商 DXE 二进制：`Project-Silicium/Device-Binaries`

这是 Mu-Silicium 的“厂商 EFI 驱动仓库”（从各设备原厂 bootloader 提取）。**没有 fuxi 目录，但有同 SoC 的 `qrd8550` 和 `dm2q`（三星 Galaxy S23，SM8550）**，其 `QcomPkg/Drivers` 包含完整 SM8550 厂商栈（节选）：

```
UFSDxe DisplayDxe XhciDxe UsbBusDxe UsbConfigDxe UsbDeviceDxe UsbInitDxe
UsbMassStorageDxe UsbMsdDxe UsbPwrCtrlDxe UsbfnDwc3Dxe
PmicDxe ClockDxe TLMMDxe I2CDxe SPIDxe SPMIDxe RpmhDxe SmemDxe CmdDbDxe
RscDxe NpaDxe GLinkDxe PILDxe HALIOMMUDxe PwrUtilsDxe VcsDxe ULogDxe …
```

还有 `RawFiles/`（各厂商面板 XML，如 `Panel_boe_amoled_*`、`Panel_vtdr6130_*` 等；**目前没有 fuxi 的 `dsi_k8_42_02_0a` 面板 XML**）。

用途：
- 若要让 UEFI 自己访问 UFS / 点亮厂商面板，需要把这些厂商 DXE + 面板 XML 导入 `fuxiPkg`（类似 `uefi-sheng` 导入 sheng 的 Binaries）。
- 我们的 Linux 路线**可以不依赖它们**：主线内核自带 SM8550 UFS/USB 驱动，UEFI 只需要负责“装载内核 + 提供 GOP”。见 B.5。

## B.3 其他可复用资料

- `Project-Silicium/Guides`：
  - `General/OS/Arch-Linux/README.md`（UEFI 引导 Arch Linux 的通用流程，最接近我们要做的事）
  - `General/OS/Full-Windows/`、`Windows-PE/`（UEFI 引导 Windows）
  - `SoCs/Snapdragon/Fixing-UFS-LUNs/`、`Mass-Storage/`（UEFI 里访问/暴露 UFS LUN 的方法）
- UniXNU 文档站：`https://unixnu.com/porting/uefi-firmware`、`/porting/sm8550`、`/devices/sheng`、`/concepts/payload`、`/porting/bring-up`
- `UniXNU/uefi-sheng`（同 SM8550 平板，Mu-Silicium fork）：`Building.md`（用 `unixnu` CLI 构建）、`PORTING.md`（内存映射/显示/FD 细节）

## B.4 对本项目的直接价值

1. **争取解决“主线内核启动+屏幕日志”**：fuxi UEFI 的 `SimpleFbDxe` 计划发布 GOP；主线 EFI stub 可将 framebuffer 信息交给 sysfb，配置合适时再由 `simpledrm`/fbcon 显示日志。是否成功、日志能从启动多早开始显示，尚未在 fuxi 实机验证。
2. **解决“内核从哪来”**：3MiB FV 放不下 43MB 内核，但 `fastboot boot` 的 **ramdisk 可以是几十 MB 的 FAT 卷**，内核+initramfs 放进 payload（标签 `FUXIESP`），UEFI 侧用一个小的 DXE 驱动从该卷读取内核并用 EFI stub 启动。
3. **解决“根分区/UFS”**：主线内核自己带 SM8550 UFS 驱动（`sm8550.dtsi` 有 `ufs_mem_hc`/`ufs_mem_phy`，`phy-qcom-qmp-ufs.c` 有 sm8550 表），只要 DTS 把 regulator/pinctrl 写对，内核就能挂载 `linux`(100GB) 分区，不需要 UEFI 访问 UFS。

## B.5 推荐方案 A2（Mu-Silicium + payload ramdisk 里的主线内核）

1. fork `hanzi123-bilp/uefi-fuxi`，新增一个 `FuxiLinuxBootDxe`（可参考本项目 `build/edk2-msm/.../FuxiLinuxBoot` 与 UniXNU 的 `DarwinBoot`）：
   - 在 `ReadyToBoot` 时用 `SimpleFileSystem` 打开 `FUXIESP` 卷上的 `/linux/Image`（EFI stub 内核）
   - 用 `LoadImage` + `StartImage` 启动（主线 Image 是 PE32+，标准流程即可），cmdline 通过 `LoadedImage->LoadOptions` 传入 `console=tty0 loglevel=7 rdinit=/init`
   - 内存属性/`ExitBootServices` 交给标准流程（Mu-Silicium 已验证可引导 Linux/Windows）
2. 制作 **FAT payload**：`mkfs.vfat -n FUXIESP`，放入 `/linux/Image`（主线内核，带内建 fuxi DTB），必要时放 initramfs。
3. 构建启动镜像：把 `Resources/ramdisk` 指向该 FAT 镜像，`build_uefi.py` 会 `mkbootimg --ramdisk <fat.img>` 打包（注意 `fastboot boot` 的下载大小上限，常见 256MB 足够）。
4. 修 DTB：加入 ABL splash framebuffer 的 `/reserved-memory/splash_region`（防止内核把显示缓冲当普通内存用掉）；其余 reserved-memory 用我们已有的 44 个 `no-map` 区。
5. `fastboot boot` 后：GOP → simpledrm → fbcon，**屏幕上应直接出现主线内核启动日志**；之后内核探测 UFS/USB，用 `PSTORE_BLK` 把 panic 落盘。
6. 成功后再考虑：主线 DTS 里打开 UFS/regulator/pinctrl、移植 ST FTS V521 SPI 触摸、实现 `dsi_m3_38_0c_0a` 面板驱动。

## B.6 风险与待验证

- fuxi 的 ABL 对 v3 镜像：我们实测原版 `Mu-fuxi.img` 被拒（Invalid Parameter），补 `os_version` 的 v3 返回 `Booting OKAY`，但尚未确认 UEFI 是否真正运行（USB 无枚举）。**需要一次带屏幕拍照的验证**。
- `FUXI_VENDOR_HW=0` 下 UEFI 无 UFS/USB host 控制器驱动；payload ramdisk 是内核来源，但 payload FAT 卷需要 `RamDiskDxe + FAT + DiskIo`（DXE.inc 已含）才能被 `SimpleFileSystem` 看到。
- 主线内核在 UEFI 下能否通过 `ExitBootServices`（我们自己的 edk2-msm 路径曾在此附近出问题并静默死亡）仍未知；Mu-Silicium 的 BDS/内存处理更成熟，值得一试。
- `/reserved-memory/splash_region` 的地址/大小需要从 ABL 交接的 FDT 里读（可先由我们 UEFI 驱动打印 GOP framebuffer base 与 memory map 获得）。
- 面板 XML 缺失意味着 UEFI 原生显示初始化（VENDOR_HW=1 的 DisplayDxe）不可用；但我们用 GOP 就够。

## B.7 下一步调研项

- 读 `Project-Silicium/Guides/General/OS/Arch-Linux/README.md`，确认 UEFI 引导 Linux 的具体要求（kernel 参数、initrd、EFI stub/GRUB 选择）。
- 看 `uefi-sheng` 的 vendor 导入工具（`unixnu` CLI 的 firmware inputs），评估“只导入 UFS 相关 vendor DXE”是否可行。
- 找 fuxi 原厂固件里的面板 XML（`Panel_*m3*38*0c*0a*.xml`）——可能在官方 fastboot ROM 的 `xbl`/UEFI FD 中；拿到后 VENDOR_HW=1 才可能点亮厂商显示栈。
- 确认 `Mu-fuxi-v3-os.img` 引导后屏幕状态（黑屏/菜单），决定是否需要重新打包 payload。

---

# 附录 C：Mu-Silicium 官方“Arch Linux ARM”指南要点与 fuxi 差距

来源：`Project-Silicium/Guides/General/OS/Arch-Linux/README.md`（标注 Outdated，但流程结构有参考价值）

## C.1 指南要求（精简）

1. 设备需有可用的 **UEFI 镜像**（他们用 Robotix22/Mu-Qcom 的 releases）。
2. 根分区与 ESP 放在三种位置之一：**内部 UFS** / SD 卡 / USB 外置存储。
3. UFS 方案（Method 1）要**重新分区 userdata**（用 parted/gdisk 从 Android 恢复环境操作），
   新建 `esp`(FAT32, ~512MB) 与 `arch`(ext4)；风险极高（可能变砖）。
4. 若设备没有 MassStorage 指南，需要用 `Mass-Storage.zip` 在 UEFI 的
   `Windows Boot Manager → Developer Menu → USB Mass Storage Mode` 里把 UFS 暴露给电脑。
5. 引导器：**rEFInd** 装到 ESP；UEFI 从 ESP 加载 rEFInd → 加载 Arch 内核。
6. 前提：UEFI 必须能访问 UFS（或 USB）上的 ESP。

## C.2 fuxi 当前差距

| 指南要求 | fuxi 现状（`uefi-fuxi`，VENDOR_HW=0） |
|---|---|
| UEFI 能看到 ESP（UFS） | ❌ 没有 UFSDxe（缺少厂商 UFS 栈） |
| UEFI 能读 USB 外置存储 | ⚠️ 有 UsbBus/UsbMassStorage DXE，但**没有 XHCI 主机控制器驱动**（fuxi 仓库内无 XhciDxe；厂商包里才有） |
| rEFInd / EFI 引导器 | 可放进 ESP 或用 payload；但上面两条先卡住 |
| 显示 | ✅ SimpleFbDxe 发布 GOP（依赖 ABL 已经点亮的面板） |

## C.3 结论：fuxi 上引导 Linux 的两条现实路径

### C1（内部存储）：导入同 SoC 厂商栈里的 UFS 相关 DXE
- 从 `Project-Silicium/Device-Binaries/qrd8550/QcomPkg/Drivers` 里挑 **UFSDxe + 它依赖的 vendor 驱动**
  （PmicDxe/ClockDxe/TLMMDxe/I2CDxe/SPIDxe/SmemDxe/RpmhDxe/CmdDbDxe/RscDxe/NpaDxe/GLinkDxe/HALIOMMUDxe 等），
  导入 `fuxiPkg`（`FUXI_VENDOR_HW=1` 路径），保留 `SimpleFbDxe` 作为 GOP 来源。
- 风险：sheng 实测 vendor `ClockDxe` 会让面板黑屏（背光仍亮），原因未解；fuxi 未验证。
  可尝试只导入 UFS 最小依赖子集、把显示完全交给 SimpleFbDxe。
- 成功后：ESP/根分区放到 UFS（或复用现有 100GB `linux` 分区），用 rEFInd 或我们的 EFI Linux loader 启动主线。

### C2（不碰 UFS）：payload ramdisk 携带内核（附录 B.5）
- 不改 UEFI 的存储能力；`fastboot boot` 的 ramdisk 用一个 **FAT 卷（标签 `FUXIESP`）**，
  里面放 `/linux/Image`（EFI stub 主线内核，带内建 fuxi DTB）+ 可选 initramfs。
- 在 fuxi UEFI 里加一个 `FuxiLinuxBootDxe`：`SimpleFileSystem` 打开 `FUXIESP` 卷 → `LoadImage`/`StartImage` 启动内核。
- 显示走 `SimpleFbDxe` 的 GOP → 主线 `simpledrm + fbcon`；内核自己驱动 UFS（主线已有 SM8550 UFS/PHY 支持）挂根分区。
- 优点：不依赖厂商 blob、不需要改 UFS 分区；缺点：内核必须能通过 UEFI `ExitBootServices` 并正确接管（需实测）。

## C.4 建议的验证顺序

1. 先把 **`Mu-fuxi-v3-os.img` 引导后屏幕状态**拍下来：是否出现 UEFI/UniXNU 菜单。
   - 有菜单 → UEFI 显示链路可用，C2 方案成立；
   - 黑屏 → 先解决 BootShim/FD 参数（对照 `uefi-sheng` 的 `sheng.toml`）。
2. 在 C2 上把“GOP + payload 内核 + simpledrm 控制台”跑通 —— 这是**第一次能看到主线启动日志**的最短路径。
3. 再按 C1 导入 UFS 厂商栈，评估“UEFI 直接读 ESP 启动 rEFInd”的路线。
4. 主线 DTS 逐步补 UFS/regulator/pinctrl（下游 `fuxi-sm8550.dtsi` 可翻译），之后根分区上 100GB `linux`。

---

# 附录 D：另外三篇“Android 手机上跑 Linux”参考（2024–2026）

用户提供的三份资料：

1. **Arch Linux 在红米 5 Plus（vince，MSM8953）**：<https://blog.zrlab.org/posts/archlinux-on-vince/>
2. **Debian 移植到红米 Note 4X（mido，MSM8953）**：<https://github.com/calico-cat-3333/debian-on-mido>
3. **高通编译主线 Linux（msm8916 为例）**：<https://blog.qingxian.dpdns.org/post/2>

## 共同方法
- 启动器：老平台用 **lk2nd**（替换 Android bootloader，提供标准启动流程）；SDM835+ 才考虑 **edk2**。
- 内核：直接用 **主线内核**（`msm8953-mainline/linux`、`msm8916-mainline/linux`），配置参考 postmarketOS 的 device config。
- 打包：`cat Image dtb > kernel-with-dtb`，再用 **mkbootimg 生成 boot.img（kernel+dtb，无 ramdisk）**，由 lk2nd 引导。
- rootfs：debootstrap/arch-chroot + qemu-user-static 交叉生成，写进 ext4 分区。
- 进阶：新版 debian-on-mido 改用 **extlinux 启动方案**（内核/initramfs 放在可写文件系统里，而不是只读 boot.img）。

## 对 fuxi（SM8550）的适用性
| 方法 | 是否可用 |
|---|---|
| lk2nd | ❌ SM8550 不支持（lk2nd 最高到 msm8996/older） |
| edk2 / UEFI | ✅ 我们正在走（自编 EDK2 + FuxiLinuxBoot） |
| 主线内核 + 追加 DTB 的 boot.img | ⚠️ fuxi 是 GKI v4/A-B 动态分区，ABL 不从 boot.img 的 dtb 字段取 DTB；我们已改为**把 DTB 编进内核**（`CONFIG_FUXI_FORCE_BUILTIN_DTB=y`） |
| debootstrap rootfs + ext4 | ✅ 已做过（Ubuntu 26.10 rootfs 在 sda33） |
| extlinux/可写内核 | ⚠️ 取决于 UEFI 能否读 UFS；当前 fuxi UEFI 无 UFS 驱动 |

## 可借鉴点
- 他们的内核配置来自 postmarketOS，包含 **simple-framebuffer / simpledrm 显示兜底** 与 **g_serial 串口控制台**——与我们 `fuxi_early`/`USB_G_SERIAL` 思路一致。
- debian-on-mido 的 **extlinux 方案** 值得在 fuxi UEFI 能访问 UFS 后采用（内核升级不用重刷 boot）。
- 三篇都说明：老平台的“boot.img + dtb”是 lk2nd 的协议，**不能照搬到 SM8550 的 ABL**；fuxi 的启动链问题必须在 UEFI/ABL 层解决。
