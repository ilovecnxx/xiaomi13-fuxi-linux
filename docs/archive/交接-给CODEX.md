# fuxi 主线 Linux 移植 —— 交接文档（给下一个接手者/CODEX）

> 更新：2026-10-25（按本轮 GitHub/上游复核修订）
> 工作目录：`/home/user/文档/deepseek-harness/default-workspace/linux-android`
> 设备：小米 13（fuxi，SM8550，序列号 f8286c82），bootloader 已解锁，4K 页，A/B 动态分区

---

## 0. 当前交接结论

- **目标唯一**：最终系统使用纯主线 Linux 内核和用户空间。厂商内核、Android 用户空间/chroot、Halium/Droidian 均不作为路线；UEFI 仅作临时启动/诊断工具，不是最终系统本身。
- **已验证的历史结果**：Ubuntu 用户空间曾在 fuxi 上随厂商 5.15 内核启动并提供 SSH/HTTP；自编厂商内核能加载大部分匹配模块；从厂商内核执行 kexec 确实造成 USB 断开/重枚举。
- **当前主阻塞**：主线 Linux 7.3 经 ABL、手写 EDK2 和 kexec 的测试均没有取得可靠的早期主线日志。现有观察符合“handoff 后无声复位/停止”，但具体死因尚未定位，不能把某个未证实的 DTB/EFI 假设写成根因。
- **最优近期实验**：先验证 fuxi 的 Mu-Silicium UEFI 是否确实运行并显示 GOP，再用它尝试 EFI-stub 主线内核 + 内置最小 initramfs。这个启动路径仍是候选；GitHub CI 成功不等于设备启动成功。
- **不要先做**：`PSTORE_BLK` 依赖块设备先工作，UFS 尚未验证；它不能帮助定位 UFS probe 前的早期静默故障。先让最小内核在屏幕或 USB 输出日志，再推进 UFS/rootfs。
- **设备状态未复测**：最后一次记录是重打包的 Mu-fuxi v3 `fastboot boot` 返回 `Booting OKAY` 后 USB 无枚举。当前是否在 fastboot、UEFI 或关机状态未知。下面的分区状态也是历史记录，开始新实验前必须只读确认。

---

## 1. 本机环境

| 项 | 值 |
|---|---|
| OS | Ubuntu（内核 6.x，x86_64，12 核，30GB RAM，磁盘约 40G 可用） |
| 交叉编译 | `aarch64-linux-gnu-gcc`、`clang` 22.1.8、`clang-21`（用户后装）、`ld.lld`、`pahole` |
| adb/fastboot | `tools/platform-tools/`（udev 规则已装，fastboot 一般免 sudo） |
| sudo | 需要时由用户在本机输入 |
| GitHub | `gh` 已配置，可查询项目仓库；不要输出凭据 |

**注意**：`tools/platform-tools/fastboot` 偶发卡死（`fastboot reboot bootloader` 十分钟无响应）。所有 fastboot 调用请套 `timeout`；卡住后 `kill` 掉进程，必要时让用户长按电源重启。

---

## 2. 分区状态（上次记录；尚未重新查询）

| 分区 | 当前内容 | 说明 |
|---|---|---|
| `boot_b` | `work/kbuild/boot_b_kcore.img` | 自编厂商内核：stock 配置 + KEXEC + PROC_KCORE，39MB |
| `init_boot_b` | `work/initboot/init_boot_auto2.img` | 厂商 init（容错模块加载）+ 内嵌静态 `kexec` + 自动下载并 kexec |
| `vendor_boot_b` | `work/kbuild/vendor_boot_b_patched.img` | stock vendor ramdisk（326 模块），修补 4 个模块 CRC、去签名 |
| `cust`（sda30，2GB） | 曾写入 Ubuntu base/seed 测试内容 | 被多次写入过；需要恢复时参照备份与外置盘记录 |
| `linux`（sda33，100GB） | 曾写入 Ubuntu 26.10 rootfs（含 XFCE） | 挂载验证过；未证实由主线内核直接挂载启动。保留给未来纯主线 Linux rootfs 实验，不沿用 chroot 路线 |
| A 槽 | 从未部署系统，`set_active a` 进不了 Android | 恢复 Android 用 B 槽 stock 镜像 |

**最后一次设备状态记录**：Mu-fuxi v3 测试后 `lsusb` 和 `fastboot devices` 均无设备，无法确认是固件停留还是设备挂起。没有在本轮网络调研中操作手机。下一位接手者应先询问/确认设备是否已手动重启，再做 `fastboot devices`、`adb devices` 等只读检查；不要根据旧记录直接执行刷写或恢复。

---

## 3. 备份与恢复

- 完整分区备份：`backups/20261024-172623/`（19 个 img，930MB，含 `SHA256SUMS` 与 `manifest.txt`）
- **一键恢复 Android**（在 fastboot 下）：

```bash
cd /home/user/文档/deepseek-harness/default-workspace/linux-android
bash scripts/restore-stock.sh    # 刷回 boot_b/init_boot_b/vendor_boot_b/dtbo_b 并重启
```

- 恢复后应能进 LineageOS（A 槽本就不可用，属正常）。

---

## 4. 已验证的成果（有屏幕/串口/HTTP 证据）

### 4.1 原生 Ubuntu 26.10（厂商内核路线）
- 使用 `fuxilinux` 仓库（在移动硬盘 NTFS 上，路径见 §7；当前未挂载）的 known-working 镜像时：
  - 手机启动后 HTTP 返回 `distro="Ubuntu 26.10"`，USB-NCM `192.168.77.2`，
  - 当时通过本地保存的项目 SSH 凭据可 root 登录（厂商内核 5.15.211）；密钥不应复制进交接材料。
- 该仓库的 `docs/mainline-7.3-bringup.md` 记录：他们**也没能**用主线 7.3 启动（ABL DTB/DTBO 选择问题），最终 B 槽 ubuntu 用的是厂商内核。

### 4.2 厂商模块 ABI 问题已解决（关键突破）
- 内核镜像内嵌 IKCONFIG，可无损提取厂商配置：

```bash
build/linux/scripts/extract-ikconfig work/kbuild/stock-kernel.img > work/kbuild/config-stock
```

- 厂商实际用 **AOSP clang 22.0.2（含 PGO/BOLT/LTO）+ Full LTO + CFI** 构建。
- 用 `config-stock` + **CFI + ThinLTO**，以本机 Ubuntu clang 22.1.8 构建：
  - **全部 326 个厂商模块 CRC 不符数 = 0**（脚本思路见 §6）
  - 加 `CONFIG_KEXEC=y` 后只有 11 个符号 CRC 变化：`kernel_kobj`(7 处) 和 `iommu_*`(4 处)，对应模块是 modem/adsp/minidump/iommu 辅助类，非显示/USB 核心。
- 已把受影响的 4 个关键模块（`arm_smmu.ko`、`qcom_iommu_util.ko`、`rproc_qcom_common.ko`、`qcom-dload-mode.ko`）的 `__versions` CRC 改成新内核的值并**去掉追加签名**（`CONFIG_MODULE_SIG_FORCE` 未开，可加载），重打进 vendor ramdisk。

### 4.3 KEXEC 通道
- 静态 aarch64 kexec 已构建：`work/kbuild/kexec-static`（841KB，`kexec-tools 2.0.28`）。
  - 构建方法：`work/kexec-src/kexec-tools-2.0.28` 正常 `./configure --host=aarch64-linux-gnu --without-xen && make`，
    然后**手工**用完整对象列表链接（见 §6.3 的命令），否则 purgatory 与静态标志冲突。
- 在厂商 initramfs 的 busybox root shell 里执行：
  `kexec -l /k/Image --dtb=/k/fuxi.dtb --command-line="console=ttyGS0,115200n8 loglevel=7 rdinit=/init"` → `kexec -e`
  - 现象：设备 USB 断电重枚举、HTTP `boot_id` 变化 → **kexec 确实执行了**
  - 但跳转后的主线内核控制台日志抓不到；随后设备回到 fastboot/诊断态。

### 4.4 手写 EDK2 路线（仅诊断；未打通主线启动）
- `build/edk2-msm` 的 fuxi 移植可编译并运行到 BDS；自写 DXE 驱动 `FuxiLinuxBoot`：
  - 从 FV 读内核/DTB（处理 `ReadFile` 的 4 字节前缀）、安装 FDT 配置表、手工按 PE 段表装载 arm64 内核、跳转
  - 放宽了 EDK2 `ExitBootServices` 的 runtime 内存对齐校验（`MdeModulePkg/Core/Dxe/Mem/Page.c`）
  - 增加了 **Tiano 压缩内核 + 启动时解压**（`UefiDecompressLib`），解决固件体积问题
- 固件体积红线（实测）：`boot-fuxi.img` 约 16MB 可启动，18MB 会触发 EDK2 PEI assert（`FvVol not found`）。
- 主线内核经手写 EDK2 驱动跳转后同样**无可读输出**（最后记录在 `SetUefiImageMemoryAttributes` 后）；是否进入内核、为何停止都未证实。

### 4.5 其他已验证事实
- 厂商模块 vermagic：`5.15.211-g9d5787a9b37e SMP preempt mod_unload modversions aarch64`
- 源码精确提交：`9d5787a9b37e3ed5e368b7e635ad6e436a629cfa`（LineageOS `android_kernel_xiaomi_sm8550`）
- 让版本串不带 dirty `+`：patch `scripts/setlocalversion` 的 short 分支，把 `echo "+"` 改成 `:`（并 `CONFIG_LOCALVERSION_AUTO=n`、`LOCALVERSION="-g9d5787a9b37e"`）
- OpenSSL 3 下编译老内核：patch `scripts/extract-cert.c`，把 `#else` 改成 `#elif OPENSSL_VERSION_NUMBER < 0x30000000L`（跳过 ENGINE API）
- GitHub 仓库：<https://github.com/ilovecnxx/fuxi-linux-build>（私有）
  - `config/vendor-config` = 提取的厂商配置
  - `scripts/build-kernel.sh` = 固定提交克隆 + 应用配置 + 构建 Image
  - `.github/workflows/build.yml` = ubuntu-24.04 + clang-22 构建并上传 Image；2026-10-25 最新构建失败，日志显示缺少 `pahole`，BTF 生成失败。该仓库是厂商内核 ABI 复现，不是主线内核构建。

---

## 5. 阻塞与当前建议

### 已确认的阻塞

- ABL 直接启动：自制 boot 镜像被接受/发送过，但 handoff 后没拿到主线日志；v2 镜像内带 DTB 的尝试有 `Load Error`。当前不足以判定唯一根因。
- 设备树：本机 fuxi vendor DTB 的 MSM/board ID 与 nuwa、sheng 不同。主线 DTB 的 overlay `__symbols__` 不匹配是需要继续验证的风险，不是已证实的静默复位根因。不要把 overlay symbol 随意指向 disabled 占位节点。
- 手写 EDK2：固件可构建并运行到 BDS，但自写 Linux 入口跳转后无可读日志。
- Mu-Silicium：v3 boot image 曾得到 `Booting OKAY`，但其后 USB 无枚举；没有屏幕证据，也没有 Linux 启动证据。
- kexec：观察到 USB 断开/重枚举，只能说明跳转路径被触发，不能证明主线已经正常执行。
- 日志通道：无已确认可用 UART。handoff 中记录 DRAM 复位后清零，ramoops 不可靠；`pstore/blk` 又需要 UFS 可用，因此不是当前第一步。

### 下一步（按顺序；只读核验先行）

1. **确认设备和分区现状**：先只读查询 USB/fastboot/slot。核对当前 `boot_b`、`init_boot_b`、`vendor_boot_b` 是否仍是表中测试镜像。未确认前不要刷写，也不要假设 `restore-stock.sh` 一定适用于当前状态。
2. **核对并构建临时 UEFI 显示探针**：参考 `work/uefi-fuxi/` 和 [Mu-Silicium fuxi UEFI](https://github.com/hanzi123-bilp/uefi-fuxi)。该固件包含 `SimpleFbDxe`/GOP 与 RAM payload 机制；先确认屏幕上确实出现固件画面，才继续 Linux loader。
3. **主线 EFI-stub 最小启动**：使用主线 7.3 `Image` + 内置最小 initramfs + fuxi DTB；在 EFI payload 启动器提供 command line，配置 EFI stub、sysfb/simpledrm、fbcon/VT。成功判据是屏幕或 USB 得到内核明确标记及 initramfs shell，不以 `fastboot boot` 返回 OKAY 作为成功。
4. **早期启动后再接 UFS**：先拿到最小 initramfs 的可靠标记，再补 fuxi UFS 电源、时钟、PHY、复位与 regulator 节点；确认块设备后才讨论 `PSTORE_BLK` 和把现有 `linux` 分区用作纯 Linux rootfs。
5. **接着补板级外设**：面板是 `dsi_m3_38_0c_0a_dsc_cmd`；触摸是 ST FTS V521 SPI，不是 Goodix GT9916（Goodix 是屏下指纹）。驱动矩阵见 `research/01-mainline-drivers.md`。

### 新的公开参考（2026-10-25）

- [sheng 7.3.0 内核发布](https://github.com/ianchb/sm8550-mainline/releases/tag/7.3.0)：近期有可下载内核包、启动镜像与配置，是同 SoC 的主线派生 Linux 参考；板级 DTS 不可直接复用。
- [nuwa-mainline](https://github.com/pubglite55/nuwa-mainline)：10 月 24 日 Linux 7.0 社区内核 CI 成功，现有公开证据是编译，不是 nuwa 真机启动；其 FTS SPI 实现值得读，nuwa M2 面板与 fuxi 不同。
- [uefi-fuxi](https://github.com/hanzi123-bilp/uefi-fuxi)：固件构建 CI 有成功 artifact；10 月 25 日最新 loader artifact 为 `fuxi-xnu-boot`，近期工作是 XNU/iOS loader。没有发现主线 Linux 真机启动记录。
- [本项目兼容性内核 CI](https://github.com/ilovecnxx/fuxi-linux-build)：10 月 25 日失败原因是未安装 `pahole`，导致 BTF 生成失败；这是厂商内核 CI 环境问题。
- 上游 Linux SM8550 目前仍无 fuxi/nuwa DTS。SoC 支持可参考，fuxi 的内存、PMIC、overlay 身份和板级外围仍需自己验证。

---

## 6. 关键经验 / 踩坑（避免重复）

### 6.1 设备/启动器
- **每次启动尝试后 ABL 会拒绝后续命令**，必须先 `fastboot reboot bootloader` 再操作。
- `fastboot boot` 返回 OKAY 不代表启动：要看 USB 是否重枚举（`udevadm monitor`/`lsusb`）。
- ABL 会按 `msm-id`/`board-id` 选择 DTB 并尝试应用 dtbo overlay。主线 DTB 缺 overlay 所需 `__symbols__` 会导致 overlay 无法正常解析；本机 v2 DTB 的 `Load Error` 尚未证明由此导致，也不能断言 dtb 只能来自 `vendor_boot`。
- 关机/重启后 USB 端点可能“假死”，需要用户长按电源。

### 6.2 内核构建
- 源码树必须精确到 `9d5787a9b37e…`，否则 vermagic 不同，厂商模块全部拒绝加载。
- 配置必须接近 `config-stock`（尤其 **CFI/LTO 相关**），否则模块 CRC 大面积不符。
- ThinLTO 可用（Full LTO 需要 ~20–30GB 内存，容易 OOM）；`DEBUG_INFO_BTF` 可关，否则可能 `.btf.vmlinux.bin.o` 链接失败。
- UFS 内置会牵出 `ipc_logging`/`qcom_clk_set_flags`/`qcom_smem_get` 等模块符号，不建议走“全内置 UFS”路线。
- 显示驱动（msm_drm）不在该内核源码树里（techpack 缺失），因此**厂商内核 + VT/fbcon 看不到屏幕文字日志**；屏幕显示依赖 vendor 模块的 KMS。

### 6.3 kexec 静态链接
`kexec-tools` 里 purgatory 会继承全局 `LDFLAGS` 导致链接失败。正确做法：正常 `make` 后手工链接：

```bash
cd work/kexec-src/kexec-tools-2.0.28
aarch64-linux-gnu-gcc -static -o /tmp/kexec-aarch64-static \
  kexec/kexec.o kexec/ifdown.o kexec/kexec-elf.o kexec/kexec-elf-exec.o kexec/kexec-elf-core.o \
  kexec/kexec-elf-rel.o kexec/kexec-elf-boot.o kexec/kexec-pe-zboot.o kexec/kexec-iomem.o \
  kexec/firmware_memmap.o kexec/crashdump.o kexec/crashdump-xen.o kexec/phys_arch.o kexec/lzma.o \
  kexec/zlib.o kexec/kexec-xen.o kexec/symbols.o kexec/proc_iomem.o kexec/add_buffer.o \
  kexec/kexec-uImage.o kexec/fs2dt.o kexec/mem_regions.o kexec/dt-ops.o \
  kexec/arch/arm64/crashdump-arm64.o kexec/arch/arm64/kexec-arm64.o kexec/arch/arm64/kexec-elf-arm64.o \
  kexec/arch/arm64/kexec-uImage-arm64.o kexec/arch/arm64/kexec-image-arm64.o \
  kexec/arch/arm64/kexec-vmlinuz-arm64.o kexec/libfdt/fdt.o kexec/libfdt/fdt_ro.o kexec/libfdt/fdt_wip.o \
  kexec/libfdt/fdt_sw.o kexec/libfdt/fdt_rw.o kexec/libfdt/fdt_strerror.o kexec/purgatory.o \
  libutil.a -g -O2
```

### 6.4 串口/调试
- 厂商 init 的 shell 只在启动后 90–180 秒内存在（看门狗），超时自动重启到 bootloader。
- `/dev/ttyACM*` 权限：VID `1d6b` 的 gadget 也要 udev 放行；节点权限会被重置，需要在 udev 或循环 `chmod`。
- 多个 `cat /dev/ttyACM*` 会抢数据，务必保证单读者；设备重枚举后同一节点名需要“重连循环”而不是只打开一次。
- 串口长命令可能被行编辑吞掉（进入 `>` 续行状态）；建议短命令 + 等待提示符。
- **不要**用 `pkill -f "<含自身命令行的字符串>"`，会自杀（本会话踩过多次）；用 `ps -eo pid,args | awk` 精确匹配。

### 6.5 initramfs
- 厂商的 initramfs 是**两个拼接的 cpio**（两个 `TRAILER!!!`）；只解第一个会丢失后续内容，必须按偏移拆分再分别解包。
- `vendor_boot` v4 头字段偏移：ramdisk_size=24、dtb_size=2100、table 相关在 **2112/2116/2120**、bootconfig_size=2124；搞错会写出 table 与 bootconfig 重叠的坏镜像（本会话踩过）。
- kernel 的 `Fv->ReadFile`/`Fd` 会带 4 字节前缀，内核和 DTB 需要 magic 扫描对齐。

---

## 7. 产物索引（都在工作目录下）

| 路径 | 内容 |
|---|---|
| `work/kbuild/config-stock` | 从备份内核 IKCONFIG 提取的厂商原始配置（**最可信基线**） |
| `work/kbuild/config-stock-verified` | stock + CFI + ThinLTO（验证 0 CRC 不符） |
| `work/kbuild/Image-stock.img` | 纯 stock 配置厂商内核（39MB，未实际刷入过；仅 ABI/诊断参考） |
| `work/kbuild/Image-kexec-kcore.img` / `boot_b_kcore.img` | stock + KEXEC + PROC_KCORE（已刷入过） |
| `work/kbuild/Image-kexec.img` / `Image-vt-kexec.img` | 更早的 KEXEC / VT+KEXEC 变体 |
| `work/kbuild/boot-fuxi-mini-usb.img`（9.2MB）、`boot-fuxi-usb.img`（16MB）、`boot-fuxi-33MB.img`（15MB） | UEFI 固件变体（主线内核 + 启动器） |
| `work/kbuild/boot-v2-mainline.img` | v2 RAM 测试镜像（fuxi 上被 ABL 拒绝） |
| `work/kbuild/kexec-static` | 静态 aarch64 kexec（841KB） |
| `work/kbuild/vendor_boot_b_patched.img` | 含修补模块的 vendor_boot |
| `work/initboot/init_boot_patched.img` | 模块加载容错的 initramfs |
| `work/initboot/init_boot_auto2.img` | 内嵌 kexec + 自动下载并 kexec 的 initramfs |
| `work/kbuild/fuxi-stock.dtb` / `stock-base.dtb` | 原厂 DTB / vendor_boot 基础 DTB |
| `work/kbuild/kernel/` | 内核源码树（LineageOS，已 checkout 到 9d5787a9b37e） |
| `build/linux/` | 主线 7.3 源码树（有未提交 fuxi DTS、`setup.c`/early marker 等调试改动；不要重跑会覆盖配置/状态的构建脚本前先检查 diff） |
| `build/edk2-msm/` | UEFI 固件源码树（含 `FuxiLinuxBoot` 驱动） |
| `backups/20261024-172623/` | 19 分区备份（930MB） |
| `scripts/` | `restore-stock.sh`、`flash-three.sh`、`kexec-attempt.sh`、`capture-acm.sh`、`test-vt-kexec.sh`、`kexec-mainline.sh` |
| `work/android-mainline-port/` | 同型设备移植手册（yzddmr6，强烈建议先读 `experience/bootloader-and-boot.md`） |
| `work/gh-repo/` | GitHub CI 仓库源码 |
| `docs/原生移植可行性-小米13.md` | 本项目完整记录（含 §11–§15 的实测细节） |

移动硬盘（NTFS，路径 `/run/media/user/D284315584313D73/Users/user/Documents/ChatGPT/fuxilinux`）当前**未挂载**，里面有：
- 已验证可启动的 Ubuntu 镜像（`artifacts/build/known-working-20261020-ssh/`）
- Ubuntu rootfs seed ext4
- `kernel-config-baseline.txt`、PowerShell 安装脚本、dtb 分析工具等

---

## 8. 接手顺序

1. 阅读本文件 §0、§2、§5，再读 `docs/参考项目与上游支持调研-fuxi.md` 与 `research/01-mainline-drivers.md`。
2. 检查 `git -C build/linux status --short`、当前 `.config`、已有内核和 UEFI payload；本地源码有未提交诊断改动，先备份/比对，不要盲目重跑构建脚本覆盖它们。
3. 查询设备现状后，先做 UEFI/GOP 可见性和 EFI-stub 主线最小 initramfs 的无写分区验证；明确记下每次镜像哈希、启动器、DTB、command line、屏幕/USB证据。
4. 只在 initramfs 确认启动后推进 UFS、主线 rootfs、面板和触摸；此顺序避免把显示、UFS 和 kernel handoff 混成一个无法定位的故障。
5. `fastboot boot` 不写分区；不要用 `flash-three.sh` 或任何 `flash`/`erase` 命令作为常规测试。恢复脚本只在确认设备分区状态及恢复目标后再用。

---

## 9. 历史诊断命令（不是当前主线默认流程）

下面厂商内核构建与 USB 传输命令只供理解旧实验；不要把厂商内核作为最终系统启动。当前主线验证应先审阅 `build/linux` 的未提交改动和配置，再单独准备 EFI-stub/initramfs payload。

```bash
B=/home/user/文档/deepseek-harness/default-workspace/linux-android
cd $B

# 只读确认连接（不触发启动/刷写）
tools/platform-tools/fastboot devices
tools/platform-tools/adb devices

# 构建厂商内核（stock 基线，需在 work/kbuild/kernel 里已 checkout 精确提交）
cd work/kbuild/kernel
cp ../config-stock-verified .config
./scripts/config --enable KEXEC --enable PROC_KCORE
make ARCH=arm64 CC=clang LD=ld.lld LLVM=1 olddefconfig
make ARCH=arm64 CC=clang LD=ld.lld LLVM=1 -j12 Image

# 打包 boot_b
cd $B
python3 build/edk2-msm/tools/mkbootimg.py --kernel work/kbuild/kernel/arch/arm64/boot/Image \
  --ramdisk build/native/empty-ramdisk --header_version 4 --pagesize 4096 \
  --os_version 17.0.0 --os_patch_level 2026-10 --output work/kbuild/boot_b_new.img

# 串口捕获（单读者、自动重连）
bash scripts/capture-acm.sh &   # 日志在 /tmp/cap/

# HTTP 传文件到手机（手机侧 busybox wget）
cd work/transfer && python3 -m http.server 8000 --bind 192.168.77.1
# 手机侧：wget -q -O /k/Image http://192.168.77.1:8000/Image-mainline
```

---

## 10. 风险与未验证声明

- 设备当前状态、当前活动槽和各分区实际内容均未在本次网络调研中查询；所有存储布局均是交接时的历史记录。
- 移动硬盘目前未挂载，原 Ubuntu 镜像/`cust.img` 备份不能假设当前可用。工作区内备份清单在 `backups/20261024-172623/`，可用前先核对 SHA256。
- 所有“主线内核经 UEFI/ABL/kexec 后静默停止”的结论都只是现象记录，未取得内核日志或确定根因。
- Mu-Silicium UEFI 的编译成功、`fastboot boot` 返回 `Booting OKAY`、或 USB 消失，都不能单独证明 UEFI 菜单/GOP/Linux 已在真机工作。
- 同 SoC 的 sheng/nuwa 项目只提供参考，不是 Xiaomi 13 fuxi 的可启动镜像或板级 DTS。
- 不要在文档、终端输出或提交中放入 sudo 密码、SSH 私钥、访问 token、设备序列号以外的私密标识或校准数据。

---

# 附录 A：2026-10-25 深夜补充（GitHub 生态调研 + Mu-Silicium UEFI 实测）

## A.1 找到的 fuxi 相关项目

| 仓库 | 内容 | 与 Linux 的关系 |
|---|---|---|
| `hanzi123-bilp/uefi-fuxi` | **基于 Mu-Silicium 的 fuxi UEFI 移植**（分支 `fuxi`，含 `Platforms/Xiaomi/fuxiPkg`）。固件 workflow 有 `fuxi-boot-image` artifact；10 月 25 日最新 loader artifact 是 `fuxi-xnu-boot` | 可研究 GOP/RAM payload 作为 Linux 诊断启动器；固件/loader 的 CI 不证明主线 Linux 真机启动 |
| `hanzi123-bilp/unixnu-fuxi` | UniXNU 设备仓库（iOS/XNU），有 `board.toml`、`configs`、`patches`、`kits` | 仅参考设备配置/分区信息 |
| `matejkoo217/UniXNU-fuxi` | UniXNU fuxi 设备支持（进行中） | 同上 |
| `P4rfa1t/fuxi-xnu` | fuxi 上的 XNU + iOS（loader/kernel/CI） | 同上 |
| `UniXNU/UniXNU`、`UniXNU/ShengUfs`、`UniXNU/GopFramebuffer` | UniXNU 主仓库，含**原生 UFS 驱动**、GPU 扫描输出交接组件 | UFS/GOP 实现可参考 |
| `UniXNU/UniXNU-sheng` | 小米平板 6S Pro（sheng，同 SM8550）设备支持 | 同一 SoC 的 UEFI 布局参考 |

参考文档：<https://unixnu.com/zh/devices/fuxi>（明确说两个 fuxi 社区仓库都在进行中、无真机运行记录）

## A.2 已下载并分析 Mu-Silicium fuxi UEFI

```text
work/uefi-fuxi/Mu-fuxi.img              1.4MB  （CI 原始产物，header v3）
work/uefi-fuxi/SILICIUM_UEFI.fd         UEFI 固件卷
work/uefi-fuxi/payload.bin              1,435,983B（从 Mu-fuxi.img 偏移 0x1000 提取 = BootShim+gzip(FV)+fuxi.dtb）
work/uefi-fuxi/Mu-fuxi-v3-os.img        重打包 v3（补 os_version 13.0.0 / patch 2022-11 / page 4096）
work/uefi-fuxi/Mu-fuxi-v1.img           重打包 v1（base 0x80000000，page 4096）
```

关键参数（来自他们的 `Resources/Configs/fuxi.toml`）：
- UEFI FD：`base = 0xA7100000`，`size = 0x300000`（来自本机 `xbl_config_a` 的 `uefiplatLA.cfg`：`0xA7000000, 0x00400000, "UEFI FD"`）
- `boot_shim.requires_kernel_header = true`（载荷前带 ARM64 image header）
- `kernel_compression = gzip`，`append_dtb = true`（设备树追加在 gzip 流后面，位于 kernel 字段内）
- 他们 2026-10-21 实测：`fastboot boot` `Mu-qrd8550.img`（v3 容器，kernel at 0x1000）返回 **Booting OKAY**

## A.3 实测结果（同一台 fuxi）

| 镜像 | fastboot boot 结果 | 备注 |
|---|---|---|
| `Mu-fuxi.img`（原样） | ❌ `FAILED (remote: 'Failed to load/authenticate boot image: Invalid Parameter')` | 两次干净重试均失败 |
| `Mu-fuxi-v3-os.img`（重打包补 os_version） | ✅ `Booting OKAY` | 但之后 USB 无枚举、设备不在 fastboot，**无法确认 UEFI 是否真正运行**（可能黑屏/挂住） |
| `Mu-fuxi-v1.img` | 状态未确认（测试被打断，设备随后掉出 USB） | 需要重新上电后重测 |

**最后记录的设备状态**：该次测试后 `lsusb`、`fastboot devices` 均无结果；真实屏幕状态/设备当前状态未知。本次没有操作设备。若用户确认仍需恢复 fastboot，再按设备实际状态处理。

## A.4 建议的下一步（Mu-Silicium 路线）

1. 在确认设备可用并计划做设备实验后，用 `fastboot boot work/uefi-fuxi/Mu-fuxi-v3-os.img` 验证屏幕是否有固件画面；返回 OKAY 不算通过。
2. 若 GOP/固件运行得到屏幕证据，再评估是否在 `Platforms/Xiaomi/fuxiPkg` 增加 Linux EFI 启动应用（相当于本项目 `build/edk2-msm/.../FuxiLinuxBoot` 的改写）：
   - 不要把内核塞进约 3 MiB FV；把主线 `Image` 放进 `FUXIESP` RAM payload FAT 卷，例如 `/linux/Image`。
   - 由 EFI 应用从 payload 的 SimpleFileSystem 读取内核，使用 EFI stub 标准入口加载，并设置 `LoadOptions`。DTB 必须明确通过 EFI configuration table 或确认过的内建 DTB 交给内核。
   - 最小 initramfs 优先编进内核，减少启动器变量；启用并核对 EFI stub、EFI framebuffer/sysfb、simpledrm、fbcon/VT 配置。
   - 用它的 CI 构建（`.github/workflows/build-fuxi-uefi.yml`，ubuntu-24.04 + CLANGPDB，约 10 分钟）→ 下载 `fuxi-boot-image` → `fastboot boot`
   - 验收：屏幕显示主线内核/内置 initramfs 的明确启动标记，或抓到可确认的 USB shell；固件本身的 GOP 仍需设备验证。
3. 若 UEFI 黑屏：先用宿主侧对比镜像结构、BootShim、FD 参数和 GOP 配置；不要仅凭另一个机型 `Booting OKAY` 的记录替代 fuxi 设备证据。

## A.5 其他新增产物

- `docs/交接-给CODEX.md`（本文件）
- `scripts/flash-three.sh`、`scripts/capture-acm.sh`、`scripts/kexec-attempt.sh`、`scripts/restore-stock.sh`
- GitHub CI：<https://github.com/ilovecnxx/fuxi-linux-build>（厂商内核构建；2026-10-25 失败原因为缺少 `pahole`，与主线 Linux bring-up 分开处理）

---

## 附录 B：调研文档索引

- `docs/参考项目与上游支持调研-fuxi.md`
  - 上游 Linux SM8550 支持现状（UFS/USB 已有，fuxi DTS/面板缺失）
  - GitHub 进展：nuwa 7.0 CI、sheng 7.3.0 主线派生发布、fuxi UEFI/XNU loader 更新及验证范围
  - fuxi 下游硬件事实：`m3_38_0c_0a` 面板、ST FTS V521 SPI 触摸、Goodix 屏下指纹
  - Mu-Silicium fuxi UEFI 的能力、FD 布局、payload 机制（`FUXIESP` FAT 卷）
  - `Project-Silicium/Device-Binaries` 里同 SoC（qrd8550/dm2q）的完整厂商 DXE 清单（含 UFSDxe/DisplayDxe/XhciDxe）
  - 候选诊断路线：payload RAM disk + UEFI GOP + EFI-stub 主线内核；尚待真机启动证明

---

# 附录 C：2026-10-25 深夜 固件内嵌内核实验记录

## 目标
把主线内核（mini 配置，12MB）Tiano 压缩后放进 EDK2 固件卷（FV），由 FuxiLinuxBoot 驱动解压→手工 PE 装载→跳转，完全不依赖 ramdisk/内存扫描。

## 已验证
- **刷 boot_b 部署 EDK2 固件可行**（`fastboot flash boot_b boot-fuxi.img` + reboot），显示正常（能看到 TianoCore/EDK2 控制台）。
- **ABL 拒绝 `fastboot boot` 大内核（gzip 解压后 >16MB 左右）**：报 `Failed to load/authenticate boot image: Load Error`；历史小镜像现在也失败，但刷 boot_b 后能启动 → 判断与 fastboot boot 的校验/尺寸有关。
- **PEI FV 解压上限再次确认**：FV 内容 20MB（15MB 内核）时 `ASSERT [Sec] FwVol.c(222)`；内核 Tiano 压缩 3.6MB、FV 内容 8.9MB 时可过 PEI 进入 DXE/BDS。
- 进入 DXE 后出现**异步异常**（`Asynchronous Exception at 0xA8BDA9C6`，异常处理器递归打印 `PrintLib Buffer==NULL`），随后设备**反复重启**。

## 当前状态
- 已刷回**备份的原厂 boot_b / init_boot_b / vendor_boot_b**，LineageOS 已正常启动（adb devices 可见 `f8286c82 device`，USB MTP 正常）。
- `vbmeta_b` 被替换为 `--disable-verity --disable-verification` 版本（用于允许自定义 boot）；回滚用 `backups/20261024-172623/vbmeta_b.img`。
- 固件实验产物：`build/edk2-msm/boot-fuxi.img`（32MB FD + mini 内核 Tiano）。

## 下一步建议
1. 异步异常定位：多半是 FuxiLinuxBoot 在 ReadyToBoot 阶段的 GOP 写帧缓冲/CPU 异常；可先**注释掉 GOP Blt 探针与 raw framebuffer 绿色探针**，只保留打印与内核装载，确认是否还在。
2. 把固件实验与日常使用解耦：每次刷 boot_b 前先确认 `backups/20261024-172623/boot_b.img` 可回滚；或先把 `dtbo_b`/`boot_a` 作为备用槽。
3. 若目标只是“看到主线内核日志”：优先试 UEFI 控制台 + 内嵌 mini 内核，不要在 DXE 做额外硬件探测（避免异常）。
4. 已确认主线内核自身支持 SM8550 UFS/USB；等内核能跑起来后再逐步打开 UFS/regulator/pinctrl 节点。

---

# 附录 D：2026-10-25 23:0x 固件异常排查（第 1 轮）

## 实验
1. 禁用 FuxiLinuxBoot 的 GOP Blt 探针 + raw 帧缓冲绿色探针 → 重编 → 刷 boot_b → 仍然出现同样的：
   `Asynchronous Exception at 0x00000000A8BDA9C6` + `Recursive exception occurred while dumping the CPU state`，
   异常处理器在 `UefiLibPrint.c(202)` / `PrintLibInternal.c(587)` 因 `Buffer == NULL` 递归断言。
2. 加 `--no-exception-disp` 构建（不打印异常信息）→ 设备**仍然反复重启**（刷入后 60 秒内回到 fastboot），说明异常没有消失、只是不显示。

## 观察到的关键线索
- 屏幕滚动的正常输出里能看到：`InstallProtocolInterface: 964E5B22-6459-11D2-8E39-00A0C969723B`（**SimpleFileSystem**）、
  `Evaluate DXE DEPEX for FFS(BAD0554E-...)`、若干 `PUSH GUID(...) = TRUE`。
  → 异常发生在 **DXE 后半段、磁盘/文件系统/UBS 驱动装载附近**，早于（或打断）FuxiLinuxBoot 的 ReadyToBoot 打印。
- 16MB FD 方案（FV 8.9MB）能过 PEI；32MB FD 方案同样进入 DXE 后异常 → 不是 PEI 体积问题。
- 异常地址 0xA8BDA9C6 位于 DxeCore/解压后 FV 的运行区域，不是 FuxiLinuxBoot（其位于 FD_BASE=0xCE000000 附近）。

## 当前状态
- 已刷回原厂 `boot_b/init_boot_b/vendor_boot_b`，**LineageOS 正常启动**（adb/MTP 正常）。
- `vbmeta_b` 为关闭校验版本；原厂备份在 `backups/20261024-172623/vbmeta_b.img`。
- 固件镜像：`build/edk2-msm/boot-fuxi.img`（32MB FD + mini 内核 Tiano + 无异常打印构建）。

## 下一轮建议（按顺序试）
1. **裁剪 FDF**：去掉 DiskIo/Partition/FatPkg/UsbBus/UsbMassStorage/Bds 菜单等与本方案无关的驱动，只保留：CPU/GIC/Timer/Serial(SimpleTextInOut)/SimpleFbDxe/GraphicsConsole/FuxiLinuxBoot。
   目的是排除“无存储却跑磁盘驱动”导致的异常。
2. 若仍异常：把 FuxiLinuxBoot 从 `ReadyToBoot` 提前到 **DXE 早期（用 DEPEX 或 gEfiDxeSmmReadyToLockProtocolGuid 之后）**，在磁盘驱动之前完成内核装载与跳转。
3. 若仍异常：怀疑 FV 解压地址/内存属性（EDK2 PEI 把 DXE FV 解压到不合适的地址），可改 `PcdDxeFvBase`/内存映射 PCD，或参考 Mu-Silicium 的 `FuxiBootMemoryDxe` 做法先声明 framebuffer/DRAM 区域。
4. 每次实验前保持 `backups/20261024-172623/boot_b.img` 可回滚（已多次验证恢复有效）。

### D.1 第 2 次实验：裁剪 FDF 驱动集
- 注释掉 29 个与启动无关的驱动（USB 主机、DiskIo/Partition/Fat/FvSimpleFS、Shell、UiApp/SetupBrowser/DisplayEngine/DriverHealth/Logo、SimpleInit、KernelFdt/BootSlot/SwitchSlots、HiiDatabase、ACPI、SMBIOS、DtPlatform、SetCPUFreq、TerminalDxe）。
- 结果：固件体积降到 4.7MB（FV 3.7MB），能过 PEI 并运行，但**约 48 秒后仍复位回 fastboot**，异常依旧（不是磁盘/USB/UI 驱动导致）。
- 已生成对照镜像：`work/kbuild/boot-fuxi-nodriver.img`（4.7MB，**完全不含 FuxiLinuxBoot 驱动**），用于下一次二分：
  - 若它稳定不重启 → 异常由 FuxiLinuxBoot 引起；
  - 若它也重启 → 异常在 EDK2/DXE 基础层（内存映射/GIC/定时器），与我们的驱动无关。

### D.2 当前恢复状态
- Android 已恢复（adb `f8286c82 device`、MTP 正常），`boot_b` 为原厂备份镜像。
- `sm8550.fdf`/`fuxi.fdf.inc` 已恢复原状；实验镜像我方均留档。

### D.3 第 3 次实验（二分对照组）：无 FuxiLinuxBoot 驱动
- 镜像：`work/kbuild/boot-fuxi-nodriver.img`（4.7MB，裁剪驱动集 + 无 FuxiLinuxBoot）
- 结果：**稳定运行 ≥100 秒不重启**，屏幕显示完整 BDS 日志：
  - `[Bds] Entry...`
  - Boot Options：`Boot0000: Simple Init`、`Boot0001: UEFI Shell`
  - `[Bds] Booting Simple Init ...` → `Unable to boot!`
  - `[Bds] Expand \EFI\BOOT\BOOTAA64.EFI -> <null string>`
  - 全程**没有异步异常**
- **结论：异步异常在 FuxiLinuxBoot 驱动内部**（基础 EDK2/BDS 稳定）。
- 副作用：稳定固件不会自动重启，测试后需要长按电源才能回 fastboot。

### D.4 自动化测试循环（进行中）
- 在 STAGE1 探针里开启 `gBS->SetWatchdogTimer(30s)` + `CpuDeadLoop()`：
  测试镜像若死循环，30 秒后看门狗复位 → ABL 回到 fastboot，实现无人值守迭代。
- 测试镜像：`work/kbuild/boot-fuxi-stage1.img`（只打印 STAGE1 + 看门狗死循环，不读 DTB/内核）。

### D.5 第 4 次实验：STAGE 分段镜像 + 自动复位尝试
- 已生成 5 个分段镜像（裁剪驱动集基础上，只保留 FuxiLinuxBoot 的不同阶段）：
  - `work/kbuild/boot-fuxi-stage1.img`：入口只打印 `STAGE1` + `ArmSelfReset(20)` + 死循环
  - `stage2`：+ `FindFvFile(DTB)` 并打印结果
  - `stage3`：+ `FindFvFile(内核)` 并打印大小
  - `stage4`：+ Tiano 解压完成后打印（死循环，不跳转）
  - `stage5`：完整流程（解压→PE 装载→跳转），跳转前 arm 1 小时定时复位（避免误复位）
- `ArmSelfReset` 实现：`gBS->CreateEvent(EVT_TIMER)` + `SetTimer` + 回调里 `gST->RuntimeServices->ResetSystem(EfiResetCold)`。
- 实测：
  - `fastboot boot stage*.img`（4.6MB）返回 **Booting OKAY 但设备原地不动**（ABL 静默拒绝，和手册“v2/无身份 DTB 会被 ABL 忽略”一致）→ 只能 `flash boot_b`。
  - `flash boot_b stage1` + reboot：设备运行固件，但 **90 秒内没有回到 fastboot**（自复位未生效或 ABL 反复启动固件形成循环）→ 需要拍照确认屏幕状态、并手动长按电源回 fastboot。
- 下一步：确认屏幕是否有 `STAGE1` 字样与是否在循环重启；若定时器不工作，改用 PMIC/QcomWDogDxe 或 BDS 失败重启路径，或直接每次测试后手动 power cycle。

### D.6 第 5 次实验：确认异常落在 FuxiLinuxBoot 模块内
- 屏幕照片显示：
  - `Loading driver at 0x000A8B12000 EntryPoint=0x0000A8BD150D FuxiLinuxBoot.efi`
  - `UefiImageMemoryAttributes - 0x00000000A8B12000 - 0x...1000`
  - 之前异步异常地址 `0xA8BDA9C6` 位于该加载区域附近（+0xC89C6）→ **异常在 FuxiLinuxBoot 驱动自身代码**，与 BDS/磁盘/USB 无关（与无驱动对照组稳定运行相互印证）。
- 已构建“单次点亮诊断镜像”：`work/kbuild/boot-fuxi-probe.img`
  - 依次打印 `[P1] driver entry`、`[P2] GOP read ok`、`[P3] files read`、`[P4] decompress done kernel=...`、`[P5] PE load + LoadedImage ok, stopping before jump`
  - 停在跳转前死循环（ArmSelfReset 1 小时防止误复位），并用 `--no-exception-disp` 关闭异常刷屏
  - 刷入后一张照片即可判断崩在哪个阶段。
- 设备当前仍停在旧固件（无 USB），需要长按电源 → 音量下+电源 进 fastboot 才能继续。

### D.7 下一轮计划
1. 刷 `boot-fuxi-probe.img`，拍屏看最后出现的 `[P?]`：
   - 停在 P1/P2 → 早期打印/GOP 相关
   - 停在 P3 → FV 读 DTB/内核
   - 停在 P4 → Tiano 解压（12MB 内存操作）
   - 停在 P5 → PE 装载/LoadedImage
2. 针对失败阶段做最小化修复（例如去掉 GOP/FDT 安装、缩小内核、换 AllocatePages 代替 AllocatePool 等）。
3. 通过后再恢复完整流程（跳转 → 内核日志）。

### D.8 第 6 次实验观察（未压缩内核 + 无解压路径）
- 构建：内核以**未压缩 Image**（12MB）放入 FV 的 FREEFORM 文件，FV 压缩后启动镜像 4.08MB（`work/kbuild/boot-fuxi-raw.img`）。
- 刷 boot_b 后屏幕现象：BDS 正常输出 → `Loading driver at 0x000ACB02000 EntryPoint=0x0000ACB0D1D FuxiLinuxBoot.efi` → `UefiImageMemoryAttributes ...` → **之后再无任何输出**（没有我们的 `[FuxiLinuxBoot]` 打印、没有异常、没有品红块）。
- 推断：驱动被 dispatch 的时间**晚于 ReadyToBoot 事件**，导致 `CreateEventEx(EVT_SIGNAL, ReadyToBoot)` 注册后事件不会再触发 → 启动逻辑从未执行。
- 修复镜像已构建：`work/kbuild/boot-fuxi-imm.img`（3.9MB）
  - 入口注册事件后**立即直接调用** `FuxiLinuxBootOnReadyToBoot(NULL,NULL)` 一次（事件失败/已错过时兜底）
  - 启动逻辑里加 **GOP 品红方块进度标记**：stage1 入口、stage3 文件读取后、stage5 PE 装载前、stage7 跳转前（横排 32x32 方块，x=stage*40）
- 待测：刷 `boot-fuxi-imm.img` 后拍照，看品红方块数量或异常文字即可定位。

### D.9 第 7–9 次实验：颜色区分固件/内核打点（关键结论）
- 内核 `fuxi_mark` 改为**绿色**（固件 FuxiLinuxBoot 的 FuxiFwMark 保持品红）。
- 刷 `work/kbuild/boot-fuxi-green.img` 后照片显示：**只有品红块（4-5 个）、没有任何绿色块**。
- 结论：
  - 固件驱动已执行并跳转，内核 EFI stub 已运行（屏幕有 `ExitBootServices: runtime entry start unaligned ..., relaxed` 与一串 `SetUefiImageMemoryAttributes` 输出）；
  - 但内核本体 `start_kernel` **没有执行**（无绿色 `fuxi_mark`），即**卡在 EFI stub → 内核入口这一段**。
- 尝试 `efi=debug`：该内核版本**没有 `CONFIG_EFI_DEBUG`** 配置项，stub 调试打印无法开启，屏幕无 stub 日志。
- 已构建：`boot-fuxi-efidebug.img`（cmdline 含 `efi=debug nokaslr`）、`boot-fuxi-green.img`、`boot-fuxi-marks4.img`。
- 设备已刷回原厂 `boot_b/init_boot_b/vendor_boot_b`，**Android 已恢复**（adb/MTP 正常）。

### D.10 下一轮计划（stub→内核入口）
1. 在 `drivers/firmware/efi/libstub/arm64-stub.c` 的 `efi_enter_kernel` 等关键点插入 `efi_printk`（无条件输出到 ConOut），确认 stub 最后停在哪一步。
2. 检查我们手工 PE 装载的入口地址与 `EFI stub` 期望：`Image` 的 `text_offset`/`image_size`、装载地址 2MB 对齐、DTB 指针。
3. 试用 kernel 的 `earlycon`（若有可用设备）或让 stub 直接以 `x0=dtb` 跳 `_text` 前打印寄存器状态。
4. 每次实验前保留原厂 boot_b 备份可回滚（已验证多次）。

### D.11 2026-10-26 凌晨结论（暂停点）
- 开启 `CONFIG_RELOCATABLE=y` + `CONFIG_RANDOMIZE_BASE=y` 后重刷：屏幕上 `SetUefiImageMemoryAttributes` 的地址发生变化（KASLR 重定位生效），但**仍无绿色内核块** → 内核本体仍未执行。
- 判断问题在 **stub → 内核入口的最终跳转**（地址/MMU/参数），而不是内核初始化。
- 已构建下一步诊断镜像：`work/kbuild/boot-fuxi-stubprint.img`
  - 在 `drivers/firmware/efi/libstub/arm64.c` 的 `efi_enter_kernel()` 里强制 `efi_printk` 打印：
    `FUXI_STUB: entrypoint=0x... fdt=0x... off=0x... _text=0x...` 与 `FUXI_STUB: jumping to 0x...`
  - 刷入后拍照即可得到跳转地址，对照内核 PE 装载地址判断是否跳到错误地址。
- **设备当前状态：关机/停在固件里（boot_b 是实验固件）**。下次继续前先进入 fastboot 并恢复：
  ```
  cd /home/user/文档/deepseek-harness/default-workspace/linux-android
  tools/platform-tools/fastboot flash boot_b backups/20261024-172623/boot_b.img
  tools/platform-tools/fastboot flash init_boot_b backups/20261024-172623/init_boot_b.img
  tools/platform-tools/fastboot flash vendor_boot_b backups/20261024-172623/vendor_boot_b.img
  tools/platform-tools/fastboot reboot
  ```
  已验证该恢复流程多次有效（LineageOS 正常启动）。

### D.12 恢复后下一次的推荐路线
1. 刷 `boot-fuxi-stubprint.img`，拍照读 `FUXI_STUB` 两行地址。
2. 若 `jumping to` 地址明显不对（如 0x6xxxxx 这类链接偏移），修正驱动里手工 PE 装载的 `LoadedImage->ImageBase`/入口计算，或改用 EDK2 `LoadImage`（内核已可重定位，可能被接受）。
3. 若地址正确但仍挂：在 `primary_entry`（`arch/arm64/kernel/head.S`）前 3 条指令处插 `efi_printk` 不可行（已出 UEFI 上下文），改用绿色 `fuxi_mark` 在 head.S 之后立即打点来确认是否进入内核。
4. 备选路线：回到 vendor 内核 + kexec（kexec 跳过 EFI stub，直接把 mainline Image 当 raw kernel 启动；kexec 工具与流程本项目已备好）。

### D.13 2026-10-26 下午：直接跳内核（绕过 EFI stub）
- 背景：stub 的 `_text` 是 `0xffff800080000000`（高 VA），手工 PE 装载 + stub 重定位路径不可靠；改为按 arm64 启动协议直接跳内核物理入口。
- 实现（`FuxiLinuxBoot.c`）：
  - `FuxiJumpToKernel(Entry)`：内联汇编，`x0..x3=0`，清 SCTLR_EL1 的 M(bit0)/C(bit2)，`isb; dsb sy; br x9`。
  - `FuxiFlushCache(Base,Size)`：内联汇编按 MVA `dc cvac` + `ic iallu`（**不要用 ArmLib 的 ArmCleanDataCache()**，它内部 `ASSERT(!ArmMmuEnabled())` 在 UEFI 下必触发，见照片 `AArch64Lib.c(70)`）。
  - 跳转前调用 `FuxiFlushCache(ImageBase, SizeOfImage)`，然后 `FuxiJumpToKernel(ImageBase)`。
- 实测（`work/kbuild/boot-fuxi-directjump2.img`）：断言消失、无异常 dump，但仍**无绿色内核块** → 内核 head.S 仍未执行。
- 镜像：`boot-fuxi-directjump.img`（第一版，触发断言）、`boot-fuxi-directjump2.img`（内联 cache flush 版）。
- 下一版计划：在驱动里用 GOP 方块编码 `ImageBase/SizeOfImage/text_offset`，并在内核 `head.S` 后（`start_kernel` 前）加绿色 `fuxi_mark`，区分“跳转前 vs head.S 失败”。

### D.14 设备状态
- 已恢复原厂 `boot_b/init_boot_b/vendor_boot_b` + `vbmeta_b`(disable-verification)，**Android 已正常启动**。

### D.15 2026-10-26 傍晚：直接跳转 + DTB bootargs 注入
- 关键修复链：
  1. `ArmCleanDataCache()` 在 UEFI 下断言 → 改内联 `dc cvac` + `ic iallu`（FuxiFlushCache）。
  2. trampoline 关闭 MMU/D-cache 前加 `msr daifset, #0xf`（屏蔽中断，避免向量跳到 UEFI 处理程序）。
  3. 跳转参数：x0 = **DTB 物理地址**（此前是 0，会让内核在 `setup_machine_fdt` 解引用空指针静默崩溃）。
  4. 内核命令行：直接跳转时只能来自 DTB `/chosen/bootargs`。已在 DTS 的 bootargs 留 236 字符占位，驱动用自写 FDT walker 把
     `console=tty0 loglevel=7 fuxi.fb=<GOP base>,<stride>,<height>,<width>,32 rdinit=/init` 写入（`PatchDtbBootargs`）。
- 验证 trampoline：用测试负载（MMU off 后向 fb 写 64x64 色块）证明跳转/关 MMU/刷 cache 链路可用（屏幕顶部出现黄色带）。
- 最新结果（`work/kbuild/boot-fuxi-dtbp.img`）：屏幕出现**错位重绘/花屏**（之前是静止文字或黑屏）→ 疑似内核已开始在帧缓冲上输出但 stride/格式不匹配。
- 下一步：
  1. 修正 fuxi.fb 的 stride/bpp（可先用固定值多试几组，或从 GOP 打印值核验）。
  2. 若内核确实已跑：加 `earlycon`/USB gadget 输出，或把 `fuxi_print`（内核早期 fb 文字）重新启用验证。
  3. 设备需要长按电源回 fastboot 后刷回原厂。

### D.16 已推送 GitHub
- 仓库 `ilovecnxx/fuxi-linux-build`，脚本 `scripts/publish-progress.sh`（每次大进度自动同步 docs/research/scripts/boot-images）。

### D.17 2026-10-26 收尾：head.S 锚点已确认
- `arch/arm64/kernel/head.S` 第 219 行：`SYM_FUNC_START_LOCAL(__primary_switched)`（第 85 行是 `SYM_CODE_START(primary_entry)`）。
- 下一轮直接在该锚点后插入裸机绿色 fb 标记（读取 `boot_args`：x0=dtb, x1=fb 物理基址, x2=stride —— 需驱动侧在跳转前用 x1/x2 传入，目前 trampoline 只传了 x0；要改成 Entry/Dtb/FbBase/Stride 四参数，x0=dtb 保持内核约定，x1/x2 放 fb）。
- 实验流程已脚本化思路：patch head.S → make Image → build firmware → adb reboot bootloader → flash boot_b → 拍照。
- 设备当前：Android 正常；boot_b 为原厂备份镜像。

---

# 附录 E：2026-10-26 晚 实机重大进展（两个致命 bug + 内核执行确认）

## E.1 两个"打点永远失效"的 bug（此前所有"内核没执行"结论作废）
1. 固件 `FuxiLinuxBoot.c` 在读取 GOP 字段**之前**就保存 `mFbStride/mFbHeight/mFbWidth`，导致传给内核的
   `fuxi.fb=...,0,0,0,32` 中 stride/height 恒为 0；内核 `fuxi_fb_param` 要求 stride/height 非 0 → 打点全程禁用。
2. 内核 `fuxi_mark` 用 `early_memremap(fb, stride*height*4)` 一次性映射约 10MB，超过 arm64 早期 fixmap
   单槽上限（NR_FIX_BTMAPS=65 页 = 260KB）→ 必然返回 NULL；且 early_memremap 用 Normal 可缓存属性，写入也不上屏。
   已改为逐行 `early_ioremap`（Device 属性，小窗口），并加 `boot_command_line` 懒解析（setup_arch 末尾早于
   parse_early_param）。
3. UEFI 里 `CHAR8 Args[200]` + DTS `chosen/bootargs` 占位 236 字节，长 cmdline 被截断丢失 `fuxi.fb=`。
   已把 Args 扩到 400、DTS 占位扩到 423（约 400 空格）。

## E.2 已验证事实（实机，有照片/视频）
- 修好后内核**确实执行**：屏幕顶部出现绿色阶段块；用高清照片逐块解码得到 13 块：
  `0, 2,3,4, 6,7,8,9,10, 12,13,14,15`，即 start_kernel 全程 + kernel_init + `smp_init` 都跑到了；
  **始终缺 stage 5**（`run_init_process()` 之前），即卡在 `kernel_init_freeable()` 尾部。
- 新增两级色块编码（`fuxi_mark_level` 蓝色 = initcall 级别 0..7；`fuxi_mark_initcall` 5 位二进制 = 全局
  initcall 序号 mod 32）。实测：级别 0–7 全部进入；第三行最后停在 `1`（≈ 全局序号 449，对应 late_initcall 的
  `deferred_probe_initcall` 附近）。
- **Gunyah 引导看门狗**：vendor DTB 有 `/hypervisor/qcom,gh-watchdog`；Android 内核 dmesg 显示
  `gh-watchdog ... QCOM Apps Watchdog Initialized`，`max_timeout=32s`。主线内核没有该驱动 → 每次 boot 后约
  32–40 秒被强杀回 Android。主线 `drivers/watchdog/gunyah_wdt.c` 的 SMCCC 函数 ID 为
  `ARM_SMCCC_CALL_VAL(FAST_CALL, SMC_32, OWNER_VENDOR_HYP, 0x0005/6/7/8)`（即 0x86000005..8）。
  - 从主线内核和 UEFI 里直接发 SMC disable（0x86000005, arg=2）**没能阻止复位**（原因未查清；可能 VM 上下文不对）。
  - **PSCI SYSTEM_RESET（SMC 0x84000009）从主线内核调用是有效的**：在 mark(2) 立刻复位时，手机 ~23s 回 Android
    （对比看门狗路径 ~40s），可作为"自复位/时间编码探针"的原语。
- **屏幕会在内核启动后约 2 秒变黑**：因为某条 initcall/驱动 probe 改动了显示时钟/电源。
  用新的内核参数 `fuxi.skip=6`（跳过 device_initcall/late_initcall 两级）后**屏幕可以一直保持亮着**（实机确认），
  说明黑屏元凶在第 6/7 级 initcall。
- **pstore/ramoops 在本机不可用**：把主线 DTB 的 ramoops 节点设成和 Android 完全相同（0xa7000000, 4MB,
  console/pmsg 各 2MB），并在 Android 上用 pmsg 写入测试记录后正常重启 → `/sys/fs/pstore` 为空。
  即该机复位会清掉/重建这块 DDR，不能作为跨复位日志通道。（Android 自己的 ramoops 也读不到。）
- **UEFI 参数 `initramfs_async=0` 也不能让 stage 5 出现**（实测仍 13 块）。
- `adb root` 可用；LineageOS 内核 **CONFIG_KEXEC 未开启**，无法用 kexec 从 Android 启主线内核。

## E.3 新增调试设施（本轮已落地，可直接复用）
- 内核 `arch/arm64/kernel/fuxi_early.c`：
  - `fuxi_mark(stage)` 绿色阶段块；`fuxi_mark_level(level)` 蓝色级别块；
    `fuxi_mark_initcall(idx)` 5 位二进制序号（白=1、深灰=0）；`fuxi_show_probe(drv, dev)` 在 y=480/544 用
    2x 字号画驱动名/设备名（在 `drivers/base/dd.c` 的 `really_probe()` 里调用）。
  - `fuxi_progress(level)` + `fuxi_psci_reset()`：PSCI 自复位时间探针（`init/main.c` 的 do_initcall_level 调用）。
  - 早期 Gunyah 看门狗 disable 尝试（当前在 fuxi_mark 里被注释掉）。
- 内核新参数 `fuxi.skip=N`：跳过 `>=N` 的 initcall 级别（`init/main.c` do_initcalls），用于二分定位关屏/卡死。
- 固件 cmdline（`FuxiLinuxBoot.c`，PatchDtbBootargs）当前为：
  `loglevel=7 panic=120 clk_ignore_unused pd_ignore_unused initcall_blacklist=disp_cc_sm8550_driver_init,clk_disable_unused,genpd_power_off_unused,regulator_init_complete,deferred_probe_initcall,sync_state_resume_initcall,of_platform_sync_state_init fuxi.skip=6 initramfs_async=0 fuxi.fb=0x%lx,%u,%u,%u,32 rdinit=/init`
- 主机脚本（都在 `scripts/`）：
  - `device-watch.sh` + `watcher-ctl.sh`：USB 状态落盘 `logs/usb-state.log`、`logs/usb-poll.log`（以 adb/fastboot 实测为准）。
  - `auto-boot-tight.sh`：0.3s 轮询 fastboot，一出现立即 `fastboot boot`（ABL fastboot 每次只稳定 1–2 秒时也能抓住）。
  - `auto-boot-on-detect.sh`、`auto-back-to-android.sh`、`recover-fastboot.sh`。
  - `run-and-collect.sh`：boot 镜像 → 等回 Android → adb root → 回收 pstore/日志。
- 关键产物（work/kbuild）：`boot-fuxi-probename.img`、`boot-fuxi-skip6.img`、`boot-fuxi-skip6-sync.img`、
  `boot-fuxi-nosync.img`、`boot-fuxi-nodefer.img`、`boot-fuxi-pscitest.img`、`boot-fuxi-timer.img` 等。

## E.4 环境/硬件问题
- 手机 USB 偶发"假死"：`lsusb` 完全看不到设备，dmesg 出现 `device descriptor read/64, error -110/-71`；
  软件层 `usb1-port6/disable` 开关、整颗 xHCI `unbind/bind` 都无效；**只有物理拔插 USB 线**能恢复。
- `fastboot devices` 偶尔卡死，务必套 `timeout`。
- 不要用 `pkill -f "<含自身命令行的字符串>"`（会自杀）；watcher 用 pid 文件管理。

## E.5 下次继续的推荐顺序
1. **定位黑屏元凶**：用 `fuxi.skip=7`（只跳 late_initcall）确认元凶在 6 还是 7 级；再给内核加
   `fuxi.skip_from=N fuxi.skip_to=M`（按全局 initcall 序号跳过区间），对 471 个 initcall 做二分
   （每步只需改固件 cmdline + `build.sh`，约 1.5 分钟 + 一次 boot）。
2. **定位卡点**：屏幕能保持亮后，用 `really_probe` 的大字号驱动名 + 阶段块判断最后 probe 的驱动；
   或对 late_initcall 的 29 个候选做 `initcall_blacklist` 子集二分（名称表见下）。
3. 找到后：优先把该驱动的 DTS 节点关掉/补齐时钟电源，让内核走到 `run_init_process()`（stage 5）→
   内置 initramfs 的 `/init` 运行 → 观察 USB gadget 是否枚举（M2）。
4. 若 Gunyah 看门狗仍 32s 强杀：可先在内核里给 `gh-watchdog` 建 platform device + 使能
   `CONFIG_GUNYAH_WATCHDOG`；或在早期用 SMC PING(0x86000007) 定时喂狗（PSCI reset 已验证 SMC 通道可用）。
5. 长期日志通道仍建议走主线 USB CDC-ACM（ttyACM 落盘），pstore 路线已证伪。

## E.6 late_initcall 29 个候选（level 7，按序）
kernel_panic_sysctls_init, kernel_panic_sysfs_init, kernel_exit_sysctls_init, kernel_exit_sysfs_init,
param_sysfs_builtin_init, reboot_ksysfs_init, sched_core_sysctl_init, sched_fair_sysctl_init,
sched_rt_sysctl_init, sched_dl_sysctl_init, sched_init_debug, printk_late_init, kernel_rcu_stall_sysfs_init,
mempool_faul_inject_init, vmstat_late_init, max_swapfiles_check, check_early_ioremap_leak, pstore_init,
pstore_blk_init, blk_timeout_init, sync_state_resume_initcall, deferred_probe_initcall, efi_shutdown_init,
of_fdt_raw_init, amba_stub_drv_init, clk_disable_unused, genpd_power_off_unused, regulator_init_complete,
of_platform_sync_state_init

## E.7 2026-10-26 23:0x 二分实验结果（黑屏定位）
- `fuxi.skip=6`（跳过第 6/7 级）：屏幕**一直亮**（实机确认）；绿色 13 块、蓝色 6 块、无 stage 5。
- `fuxi.skip=7`（只跳过第 7 级 late_initcall）：第 6 级全部驱动 probe 照常跑，屏幕**保持亮**（拍照确认：
  绿色 13 块、蓝色 7 块 0..6、仍无 stage 5）→ 黑屏元凶不在第 6 级。
- `boot-fuxi-bl1.img`（把 late_initcall 前 10 个候选加入 blacklist，第 7 级仍执行）：屏幕**仍闪黑**。
- `boot-fuxi-blall.img`（把第 7 级剩余 13 个候选**全部** blacklist，理论上等价于"第 7 级不执行"）：
  屏幕**仍闪黑**，随后自动回 Android。**与 skip=7 的结果矛盾**，说明：
  1. `initcall_blacklist` 可能没有按预期生效（cmdline 长度已扩到 780 字符、DTB 占位 1623、Args 2000，理论上没截断），
     或 blacklist 匹配的函数名不对（例如 initcall 入口指向 wrapper 而非函数名）；
  2. 或者黑屏不是某个 initcall 函数造成，而是 **do_initcall_level(7) 的 parse_args / 时序**或
     **约 30 秒的 Gunyah 看门狗/硬件行为**造成。
- 注意：观测有不确定性（屏幕亮/黑的时刻取决于拍照时机；手机有时 35s 自动回 Android、有时数分钟不回）。
  下次务必先做**可重复性对照**：同一镜像连跑 2–3 次，记录"亮到黑"的准确秒数（可让用户录屏/计时或主机侧用
  PSCI 计时），再下结论。

### 下次最优先的验证（建议顺序）
1. **先验证 Gunyah 看门狗假说**：在内核里用定时器每 5 秒发 `SMC 0x86000007`（GUNYAH_WDT_PING）喂狗；
   若手机不再在 ~32–40s 被复位、屏幕保持亮，则黑屏/复位都是看门狗造成，问题即解。
   若 PING 返回错误，改为尽早建 `gunyah-wdt` platform device 并启用 `CONFIG_GUNYAH_WATCHDOG` 让驱动接管
   （驱动 probe 里会 `gunyah_wdt_stop()`）。
2. **验证 blacklist 是否生效**：用 `initcall_blacklist=populate_rootfs` 之类有可观测后果的项做对照；
   或在内核里打印 `initcall_blacklisted()` 的结果到屏幕。
3. 黑屏若确认是显示电源被关：把 `dispcc/gcc/videocc/camcc/gpucc` 等时钟控制器与 RPMh/互连驱动分别
   blacklist 做 A/B，找到具体关电的驱动，再在 DTS 里保留其 bootloader 状态（如给显示时钟加
   `assigned-clocks`/`keep` 标记，或暂时 status=disabled）。

## E.8 2026-10-26 23:00 关键突破：Gunyah 看门狗喂狗有效
- 在内核里用定时器每 5 秒发 `SMC 0x86000007`（GUNYAH_WDT_PING），实测**手机连续运行 155 秒以上不再被强制复位**
  （此前每次 ~32–40s 必然回 Android）→ 之前的自动复位确认是 Gunyah 看门狗，且 **SMCCC 通道从主线内核可用**。
  代码：`fuxi_wdt_start()`（在 `fuxi_mark(10)`/`fuxi_mark(12)` 里启动），`work/kbuild/boot-fuxi-wdtpet.img`。
- 副作用/注意：喂狗后内核卡死时**不会自动回 Android**，只能长按电源 15s 强制重启。
- **进度信标**（`fuxi_beacon(ms)`：到点 PSCI 复位）已加：mark12 → 45s；mark5 → 15s。
  实测 `work/kbuild/boot-fuxi-beacon.img` 启动后 80s+ 手机既没回 adb 也没回 Android（屏幕黑、按键无响应），
  说明**定时器回调里的 PSCI 复位没有生效**（init 上下文的 mark2 复位是有效的，已验证）；
  也可能内核在 mark10~mark12 之间就停了（但喂狗已启动，说明至少到过 mark10）。
  下次需要先确认"timer 上下文 PSCI reset 是否可用"（最简单：在 mark2 用定时器 2s 后复位做对照）。
- 黑屏问题仍然存在（与看门狗无关）：喂狗后屏幕依旧黑，说明是显示时钟/电源被某驱动关掉。

### 当前未解决问题（下次接手优先）
1. **定时器上下文自复位**不可用（影响时间编码探针）→ 改用工作队列/线程上下文（例如 kthread 里 delay 后 reset），
   或直接用 `panic("fuxi reset")` + `panic=5`（panic 路径的 PSCI reset 应该可行）。
2. **黑屏**：仍需定位关显示电源的驱动；已知"跳过第 7 级 late_initcall"时屏幕可保持亮，但把第 7 级全部
   initcall 加入 blacklist 反而仍黑（矛盾，可能是 blacklist 名称不匹配或黑屏与 `parse_args`/时序有关）。
3. **卡点**：所有证据指向 `kernel_init_freeable()` 尾部（mark12→mark5），最可能是 `wait_for_initramfs()`；
   但 `initramfs_async=0` 未改变结果。下次可用"喂狗 + 更长观察"确认内核是否其实还在慢慢跑（比如 initramfs
   解压耗时），或加 marks 到 `wait_for_initramfs` 前后精确定位。

## E.9 2026-10-26 23:0x 最后两个验证（结论要谨慎）
- `boot-fuxi-beacon2.img`（panic 信标：mark10→50s、mark12→45s、mark5→10s，panic=5）：
  启动后 150 秒内手机既没回 adb 也没回 Android → panic 发生后**没有自动重启**（panic 路径的 machine_restart
  依赖 PSCI 驱动，而我们的内核 PSCI 可能未成功初始化 → 落到不可用的 reset）。
- `boot-fuxi-timerreset.img`（mark10 布置 3 秒后由定时器发 `SMC 0x84000009` 复位）：
  **Δ=40 秒回 Android**，与看门狗路径（33–40s）一致，而不是预期的 ~23s
  → 定时器回调里的直接 SMC 复位**不可用**（或定时器没跑）。
- 但 `boot-fuxi-wdtpet.img` 曾让手机连续 155 秒不被复位 → 说明"每 5 秒 PING 的定时器"确实跑过，
  与"定时器没跑"矛盾。**因此"Gunyah 看门狗"假说不能算完全证实**：
  32–40s 的复位也可能是 ABL/其他硬件超时；PING 是否真在喂狗需要进一步验证
  （例如：喂狗时同时在屏幕/其他通道输出心跳，或让 PING 次数影响复位时间）。

### 建议下次的第一步（换可靠探针）
1. 用**内核线程（kthread）上下文**做复位探针（不是软中断/panic）：kthread 里 msleep 后直接
   `arm_smccc_1_1_smc(0x84000009)`；已验证 init 上下文可用，线程上下文大概率可用。
2. 用该探针做"时间编码"：在关键里程碑设置不同延时，主机测 Δ 反推内核进度（无需屏幕）。
3. 同时验证看门狗：喂狗 PING 的返回值（0 = 成功？）→ 把结果编码进复位延时，主机侧解码。

## E.10 2026-10-26 23:2x 自动可达性探针 bisect（结果与重要保留）
- 新增内核探针：`fuxi.probe=N` + `fuxi_probe_point(n)`（在 init/main.c 关键点调用，命中即直接 SMC 复位；
  同时暂停喂狗，未命中的点由 Gunyah 看门狗 ~32–40s 兜底复位）。脚本：`scripts/probe-bisect.sh`（自动重建固件→boot→计时）。
- 结果（Δ = fastboot boot → 重新出现 adb）：
  - probe 0（do_basic_setup 前）：Δ=46s（看门狗路径，非早期复位）
  - probe 1（do_basic_setup 后）：Δ=46s
  - probe 2（wait_for_initramfs 前）：150s 内无返回（USB 可能再次假死）
- **重要保留**：`mark5` 立即 SMC 复位也不早回，而 `mark2`（start_kernel、boot CPU 上下文）复位有效(23s)。
  因此推测 **SMC PSCI 复位只在 boot CPU/早期上下文可靠，kernel_init kthread 上下文不可靠**，
  上述 probe 0/1 的"未命中"结论**可能不成立**（需先验证 kthread 上下文复位）。
- 已有确凿证据（旧内核照片）：级别 0–7 全部画到 → do_basic_setup 跑完了；但没有 mark 5
  → 卡点在 **do_basic_setup 之后、mark 5 之前**：`wait_for_initramfs()` / `console_on_rootfs()` /
  `async_synchronize_full()` / `free_initmem()` 这几处。
- 下一步建议：先解决"kthread 上下文复位"（例如用 stop_machine 在 boot CPU 上执行 SMC，或修好 panic 重启路径：
  让内核 PSCI 驱动真正接管 SYSTEM_RESET），再继续探针；或直接把探针点加在上述 4 个函数前后（4–5 次即可定位到函数）。
- 另外：`initramfs_async=0` 与默认 async 都卡住；下一步可试 **CONFIG_INITRAMFS_SOURCE 置空** 做对照
  （若内核能走到 mark 5，说明卡点是 initramfs 解压/等待）。

## E.11 2026-10-26 23:2x–23:3x 复位原语再验证（仍然不可靠）
- 用 Gunyah 看门狗"咬人"作为复位原语（disable→set 1s→enable）：mark12 探针测试 Δ=40s（看门狗兜底路径），
  说明这三条 SMC 在 kernel_init 线程上下文里也没生效。
- 用 `smp_call_function_single(0, ...)` 把 SMC SYSTEM_RESET 投递到 CPU0：测试后 120s 内手机无任何 USB 枚举
  （既没早回也没 ~40s 回）→ 可能内核卡死，或复位后 USB 假死。
- **教训**：目前唯一 100% 验证有效的复位是 **start_kernel 早期（boot CPU、init 上下文）直接 SMC 0x84000009**；
  其它上下文/CPU 的复位都不可靠。继续做"时间编码探针"之前，必须先建立一个可靠的复位通道
  （候选：把 SYSTEM_RESET 投递到 boot CPU 后立即自旋等待；或修好内核 PSCI 驱动让 panic 重启生效；
  或直接接受"用户拔插/长按"作为复位手段）。
- **更现实的下一步（不依赖复位原语）**：利用已验证"`fuxi.skip=6/7` 时屏幕能保持亮"这一点，在
  **tail 阶段**（do_basic_setup 返回后）用 5 位色块显示流程进度：
  1=do_basic_setup 返回、2=wait_for_initramfs 进入、3=其返回、4=console_on_rootfs 后、
  5=async_synchronize_full 前、6=其后、7=free_initmem 后、8=mark5；
  屏幕一直亮 → 拍照读出最后值即可定位。这是目前最省事、最可靠的路径。

## E.12 2026-10-27 00:0x 深夜收尾状态
- 已确认：tail 色块停在 **6（async_synchronize_full 之后）**；`mark 5`（stage 5 绿块）与 11–19 号 tail 标记
  在照片里都没出现。两种可能：
  1. 内核确实卡在 mark6 之后（但中间只有 `system_state = SYSTEM_FREEING_INITMEM;` 一行赋值，可能性低）；
  2. **late 打点本身有问题**：`fuxi_mark_late`/`fuxi_mark_tail_late` 使用 mark2 时 ioremap 建立的持久映射，
     写入可能触发 fault（内核 oops/panic 后停住），导致显示永远停在 6。已把 11–15 改为可靠的 early 映射打点
     （`boot-fuxi-tailfine2.img`），等下一次拍照即可区分。
- 另已修复一个真实 bug：`fuxi_mark(5)` 是 `__init`，却在 `free_initmem()` 之后调用（use-after-free），
  改成非 init 的 `fuxi_mark_late(5)`。
- 今晚最后一轮因 USB fastboot 又"假死"（lsusb 完全无设备）未能 boot，需要物理拔插/长按电源。
- 现场：手机在 fastboot（USB 未枚举）；工作区所有镜像/脚本/文档已保存。

## E.13 2026-10-27 00:20 ★★★ M1 达成：主线内核进入用户空间 ★★★
实机照片（boot-fuxi-initok.img，skip=6）屏幕上出现：
```
Run /init as init process
FUXI_INIT_RUNNING
FUXI_USB_SERIAL_MISSING
FUXI_ALIVE 1
FUXI_ALIVE 2
...
```
即：**内核执行了 initramfs 的 /init，用户空间进程 PID 1 正常运行，并每 5 秒通过 /dev/kmsg 打印心跳。M1（进入用户空间）确认达成。**

### 达成 M1 的决定性修复（按重要性）
1. **帧缓冲在 linear map 内** → arm64 `ioremap()` 会 WARN 并返回 NULL
   （`pfn_is_map_memory` 检查）。所有"持久映射"打点/console 因此从未工作。
   改为 `phys_to_virt()` + `dcache_clean_poc()` 后一切正常，屏幕 console 也终于可用。
2. `fuxi_mark(5)` 是 `__init` 却在 `free_initmem()` 之后调用 → use-after-free 假死；改用非 init 的
   `fuxi_mark_late()`。
3. initramfs 缺 `/proc /sys /dev /tmp` 目录 → `/init` 挂载失败后退出，PID 1 退出触发
   "Attempted to kill init" panic（这是 M1 前最后一个假卡点）。补目录 + 心跳脚本后解决。
4. 之前所有"内核没执行/卡死"的假象（fuxi.fb 参数为 0、整屏 early_memremap 超限、init 内存释放后打点）
   全部属于调试脚手架自身问题。

### 当前可用的调试通道（重要）
- **屏幕 console 可用**：`fuxi_console`（8x16 字体，文本从 y=320 开始，四行色块在上方 y=0..288）。
  内核日志 + initramfs 输出都能看到，拍照即可读。
- `fuxi.skip=6`：跳过 device/late initcall，屏幕不会黑、系统稳定到用户空间。
- initramfs `/init`：挂载 proc/sys/devtmpfs、写 `FUXI_INIT_RUNNING`/`FUXI_ALIVE N` 心跳到 /dev/kmsg。
- 主机脚本不变。

### 下一步（M2）
1. USB gadget（ttyGS0 → 主机 ttyACM）：需要 dwc3/qcom glue/eusb2 PHY/UDC 的 DTS 节点与电源时钟，
   并且需要**不再 skip 6/7**（USB 驱动在 device_initcall）。届时黑屏问题需要一并解决（见 E.7/E.8）。
2. 黑屏根因：显示时钟/电源被某驱动关闭；现在有可用 console，可以直接在日志里看最后一行定位。
3. Gunyah 看门狗：`SMC 0x86000007` PING 是否真的有效仍未严格证实（见 E.8/E.9）。

## E.14 2026-10-27 00:2x ★ M1 完整确认 + 可用屏幕日志通道
新镜像 `boot-fuxi-font2.img`（3x 字号、整行清黑、按屏宽截断）屏幕上清晰显示：
```
Warning: unable to open an initial console.
Run /init as init process
FUXI_INIT_RUNNING
FUXI_USB_SERIAL_MISSING
FUXI_ALIVE 1
FUXI_ALIVE 2
...（之后还有 deferred probe 的 Fixed dependency cycle(s) 内核消息）
```
即 **/init 正常运行、用户空间每 5 秒心跳**，且屏幕日志已大到可直接目读。

### 屏幕 console 使用说明（当前）
- 文本从 y=320 开始，3x 字号（每字 24x48 px，每行 45 字符，行高 50），自动滚动；
- 顶部 y=0..288 保留四行色块（阶段/级别/initcall 序号/tail）；
- 行尾自动清黑，不再重叠；超长行按屏幕宽度截断。
- 已修复的坑：3x 字号下若按旧 150 字符缓冲绘制会写出行边界、覆盖色块与相邻行（表现为"色块挡住字/字重叠"）。

### 下一步（M2）
1. **USB gadget (ttyGS0)**：需要 dwc3/qcom glue/eusb2 PHY/UDC 节点与电源时钟，且需要不再 `fuxi.skip=6`；
   有屏幕 console 后，黑屏问题的最后一行日志可以直接读到。
2. 黑屏根因：显示时钟/电源被某驱动关闭（历史证据指向第 6/7 级 initcall）。
3. Gunyah 看门狗喂狗是否真的有效仍未严格证实（E.8/E.9）。
4. initramfs 心跳脚本已可用于验证"用户空间是否存活"。

## E.15 2026-10-27 00:3x M2（USB gadget）首轮测试结果
- `boot-fuxi-noskip-reboot.img`（去掉 skip=6，全部 initcall 都跑；init 60 秒后自动 `reboot -f` 回 Android）：
  屏幕在启动后**闪一下变黑**（已知黑屏问题），主机侧 60 秒内**没有** /dev/ttyACM*、也没有新 USB 设备；
  之后 init 的 `reboot -f` 生效，手机自动回 Android → **自动迭代通道打通**（以后不用人工断电）。
- `boot-fuxi-skip7b.img`（只跳 late_initcall，level 6 全跑）：90 秒监测内同样**没有 ttyACM/新 USB 设备**。
- 说明：USB gadget 没起来，不是单纯被 skip 挡住——dwc3/PHY 的 probe 很可能在 defer/fail。
  内核日志里能看到 `/soc@0/usb@a600000` 与 `/soc@0/phy@88e8000` 的 "Fixed dependency cycle(s)"
  （fw_devlink 的良性提示），真正的 probe 错误需要在 level 6/7 运行时读屏——而那时屏幕正好黑掉。
- DTS 已按 gadget 意图配置：`&usb_1 {dr_mode="peripheral"; phys=<&usb_1_hsphy>; status="okay"}`、
  `&usb_1_hsphy {... status="okay"}`、`&usb_dp_qmpphy {... status="okay"}`、PMIC regulator 有
  vreg_l1e_0p88/vreg_l3e_1p2/vreg_l3f_0p91。
- **下一步（M2 的钥匙）**：先用"能用的屏幕 console"定位黑屏元凶——已知 skip=7（level 6 全跑）屏幕能保持亮，
  说明元凶在 **level 7 late_initcall**；对 29 个 late_initcall 用 `initcall_blacklist` 做二分（现在 console 可用，
  每步能直接看到日志），把元凶 blacklist 掉后，让 level 6/7 正常跑，就能读到 dwc3/PHY 的真实 probe 错误并修复 USB。
- 另：`fuxi.skip=7` 时屏幕保亮这一现象与 E.7 的"level 7 元凶"一致，可先从
  clk_disable_unused / genpd_power_off_unused / regulator_init_complete / of_platform_sync_state_init /
  sync_state_resume_initcall 这 5 个开始试（它们直接关时钟/电源域/regulator，最可能关掉显示）。
