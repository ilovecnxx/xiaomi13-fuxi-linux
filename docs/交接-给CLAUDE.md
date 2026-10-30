# 交接文档（给 CLAUDE）— Xiaomi 13 (fuxi / SM8550) 主线 Linux 移植

> 写于 2026-10-27 01:00。作者：前一位 AI 助手 + 用户一整晚实机调试。
> 先读本文，再读 `docs/交接-给CODEX.md`（附录 E.1–E.15 是完整实验历史，含每轮照片解码结论）。

---

## 0. 🔴 当前最紧急：手机正处于"boot_b 循环启动"状态，需要恢复

**现状**：`boot_b` 分区已被写入我们的 UEFI 镜像（`work/kbuild/boot-fuxi-nodisp.img`），
手机会不停循环：ABL → UEFI → 主线内核（跑马灯）→ 黑屏 → init 60 秒后 `reboot -f` → 再次循环。

**恢复 Android 的步骤（任选其一，推荐 A）**
A. 用 fastboot 恢复 boot_b：
   1. 手机长按电源 20 秒关机；再按住 **音量下 + 电源** 进入 FASTBOOT（屏幕显示 FASTBOOT 即成功）；
   2. 主机：`lsusb | grep 18d1` 确认枚举（没枚举就拔插一次 USB 线）；
   3. 解压备份：`gzip -dc work/backup/boot_b_orig.img.gz > /tmp/boot_b_orig.img`（192MB，含原始 Android boot 镜像）；
   4. `tools/platform-tools/fastboot flash boot_b /tmp/boot_b_orig.img`；
   5. `tools/platform-tools/fastboot reboot` → 回到 Android。
B. 如果 fastboot 一直枚举不了（本机 USB 链路不稳，见 §6），重复"拔插线/换 USB 口/长按电源再试"。

**重要文件**
- 备份：`work/backup/boot_b_orig.img.gz`（gzip 后 24MB，解压 192MB，开头是 `ANDROID!` 魔数，已验证）
- 写入工具：`tools/platform-tools/adb`、`tools/platform-tools/fastboot`
- Android 内直写（若 Android 能启动）：`adb root`；`adb push <img> /sdcard/`；
  `adb shell 'dd if=/dev/zero of=/dev/block/sde44 bs=1M count=192; dd if=/sdcard/<img> of=/dev/block/sde44 bs=1M; sync'`
  （slot b：boot_b = /dev/block/sde44；boot_a = /dev/block/sde14；当前 slot = b）

---

## 1. 项目目标与边界

- 在 Xiaomi 13（fuxi，SM8550）上跑**纯主线 Linux**（不用下游内核、不用 Halium/Droidian）。
- 当前阶段目标：M1 = 主线内核进入用户空间；M2 = USB gadget（ttyGS0/ttyACM）拿到 shell；
  M3 = UFS + rootfs；M4 = 显示/触摸；M5 = WiFi/GPU/音频。
- 调试辅助：自写 EDK2 UEFI（`build/edk2-msm`）只作为**诊断引导器**（读内核+DTB 直接跳转），不是最终启动链。
- 设备：bootloader 已解锁；Android 是 LineageOS 24（Android 17）在 slot b；Android 内 `adb root` 可用。

---

## 2. 启动链与关键数据流

```
ABL (fastboot) --fastboot boot <img> 或从 boot_b 启动--> EDK2 UEFI (我们的 boot.img)
  -> BDS -> FuxiLinuxBoot.efi 驱动
     读 FV 内嵌的内核 Image（build/linux/arch/arm64/boot/Image，构建时拷贝为 Image.tiano）
     读 FV 内嵌的 DTB（qcom/sm8550-xiaomi-fuxi-min.dtb）
     修补 DTB 的 /chosen/bootargs（fuxi.fb=... 等）
     直接跳内核（绕过 EFI stub），x0 = DTB 物理地址
  -> Linux 内核
```

- **内核 cmdline 由驱动拼好写进 DTB**：`loglevel=7 panic=0 clk_ignore_unused initramfs_async=0 [initcall_blacklist=...] [fuxi.skip=N] fuxi.fb=0x<phys>,<stride>,<height>,<width>,32 rdinit=/init`
- `fuxi.fb` 的值 = GOP framebuffer 物理地址 + 模式参数（驱动从 GOP 读）。内核 `fuxi_early.c` 解析后用于：
  屏幕打点、屏幕 console、读 tail 进度。
- 内核内置 initramfs（`CONFIG_INITRAMFS_SOURCE=build/initramfs`），`/init` 是 busybox shell 脚本。

---

## 3. ✅ 已达成：M1（主线内核进入用户空间）

实机证据（屏幕日志，3 倍字号可读）：
```
Run /init as init process
FUXI_INIT_RUNNING
FUXI_USB_SERIAL_MISSING
FUXI_ALIVE 1
FUXI_ALIVE 2 ...
```
- `/init` 正常执行，PID 1 存活，每 5 秒往 /dev/kmsg 写心跳；稳定跑过 4 分钟以上。
- 关键修复（按重要性排序，**这些坑别再踩**）：
  1. **帧缓冲物理地址在 linear map 内**（`pfn_is_map_memory` 为真）→ arm64 `ioremap()` 会 WARN 并返回 NULL。
     屏幕 console / 持久打点必须用 `phys_to_virt()` + `dcache_clean_poc()`（见 `fuxi_early.c`）。
  2. `fuxi_mark(5)` 原是 `__init` 函数却在 `free_initmem()` 之后调用 → use-after-free 假死；
     已改为非 init 的 `fuxi_mark_late()`。
  3. initramfs 缺 `/proc /sys /dev /tmp` 目录 → `/init` 挂载失败退出 → "Attempted to kill init" panic；
     已补目录。
  4. 固件传给内核的 `fuxi.fb` 曾因 GOP 字段读取顺序错误而 stride/height=0 → 打点全失效（已修）。
  5. 早期 `early_memremap` 整屏 10MB 超过 fixmap 单槽上限（260KB）且可缓存 → 打点不显示；
     改为逐行 `early_ioremap`（Device 属性）。

---

## 4. ❌ 未解决（按优先级）

### 4.1 黑屏（当前最大障碍）
- 现象：完整启动（所有 initcall 级别都跑）时，屏幕在跑马灯后 **约 2 秒变黑**；`fuxi.skip=6` 或 `fuxi.skip=7` 时屏幕能保持亮。
- 已试无效：
  - `initcall_blacklist=clk_disable_unused,genpd_power_off_unused,regulator_init_complete,of_platform_sync_state_init,sync_state_resume_initcall,deferred_probe_initcall,disp_cc_sm8550_driver_init`
  - DTS 里 `&mdss { status="disabled"; }; &dispcc { status="disabled"; };`
  - 二分：level 7 的 13 个剩余 late_initcall 全部 blacklist 后仍黑。
- 注意：`skip=7` 能保亮、而"level 7 全部 blacklist"却仍黑，两者矛盾 → 说明 `initcall_blacklist` 是否真正生效需要先验证
  （可用一个可观测后果的 initcall 做对照）；也可能黑屏由 **非 initcall 机制**（如 deferred probe worker、genpd/sync_state 异步）触发。
- 建议下一步：写一个"黑屏前最后一刻"的取证机制（见 §8.1），先拿到 level 6/7 运行期间的完整内核日志。

### 4.2 USB gadget（M2）
- DTS 已配置：`&usb_1 { dr_mode="peripheral"; phys=<&usb_1_hsphy>; status="okay" }`、
  `&usb_1_hsphy {...; phys=<&pm8550b_eusb2_repeater>; status="okay"}`、`&usb_dp_qmpphy {...; status="okay"}`，
  PMIC regulator 有 `vreg_l1e_0p88 / vreg_l3e_1p2 / vreg_l3f_0p91`。
- 内核配置：`CONFIG_USB_DWC3=y / DWC3_GADGET=y / DWC3_QCOM=y / USB_G_SERIAL=y`（CDC ACM gadget 内置）。
- 实测：无论 skip=6、skip=7 还是全开，主机都**没有** ttyACM/新 USB 设备；日志里只有
  `/soc@0/usb@a600000`、`/soc@0/phy@88e8000` 的 "Fixed dependency cycle(s)"（fw_devlink 良性提示）。
- 需要：在屏幕能保亮的前提下跑 level 6/7，读 dwc3/PHY 的真实 probe 错误（defer? fail?），再补资源。

### 4.3 Gunyah 看门狗（32–40 秒强制复位）
- vendor DT 有 `qcom,gh-watchdog`；主线 `drivers/watchdog/gunyah_wdt.c`；SMCCC ID：
  `0x86000005 CONTROL`（disable 参数 2）、`0x86000006 STATUS`、`0x86000007 PING`、`0x86000008 SET_TIME`。
- 内核里每 5 秒发 PING 的测试曾让手机连续 155 秒不复位（另一轮又没效果）→ **未严格证实**。
- 目前"60 秒自重启"是 init 脚本主动 `reboot -f`，不是看门狗。

### 4.4 复位/自动迭代通道
- 已验证：`start_kernel` 早期（boot CPU、init 上下文）直接 `SMC 0x84000009`（PSCI SYSTEM_RESET）有效。
- 不可靠：kernel_init 线程上下文/定时器上下文的 SMC 复位、看门狗"咬人"、`smp_call_function_single(0)` 投递。
- 现在可用的自动循环：**init 脚本 60 秒后 `reboot -f`**（配合 boot_b 写入可实现无 fastboot 迭代，但注意 §0 的锁死风险）。
- pstore/ramoops **不可持久**（本机复位会清 DDR，实测失败）→ 不能做跨复位日志通道。

---

## 5. 调试设施（怎么用）

### 5.1 屏幕打点（`build/linux/arch/arm64/kernel/fuxi_early.c`）
- 绿色阶段块：`fuxi_mark(stage)`，48x48，位置 `(stage*56, 0)`，绿 `0x0000ff00`。
  stage：0=setup_arch 结束、2=mm_core_init 后、3=sched_init、13/14/15、6/7/8/9/10、4=kernel_init 入口、
  12=smp_init 后、5=run_init_process 前（用 `fuxi_mark_late`）。
- 蓝色级别块：`fuxi_mark_level(level)`，`(level*64, 64)`，青 `0x0000ffff`（level 0–7）。
- initcall 序号 5 位：`fuxi_mark_initcall(idx)`，`(bit*64, 128)`，白=1/灰=0。
- tail 进度 5 位：`fuxi_mark_tail(v)`（init 版，y=240）与 `fuxi_mark_tail_late(v)`（非 init 版，y=240），
  编号：1=do_basic_setup 返回、2/3=wait_for_initramfs 前后、4=console_on_rootfs 后、5/6=async_synchronize_full 前后、
  11/12/13/14/15=kprobe/ftrace/kgdb/exit_boot_config 各步后、16=free_initmem 后、17=mark_readonly 后、
  18=pti_finalize 后、19=do_sysctl_args 后。
- 状态块：`(1000,0)` 白=帧缓冲 linear map 可用，红=不可用。
- 解码方法：手机拍照 → 找绿色块左边界/块间距定 scale → 逐块采样颜色（白/灰/绿/青）→ 读二进制。
  历史解码脚本在会话里用过，思路：`/tmp` 下 Python+PIL，按已知行高 48、间距 56/64 校准。

### 5.2 屏幕 console（已可用，3x 字号）
- 注册：`fuxi_console_init()`（`fuxi_mark(2)` 时调用）；文本区从 y=320 开始，行高 50，每行 45 字符，自动滚动。
- 绘制：`fuxi_draw_line()` 逐扫描行写 linear map + `dcache_clean_poc()`；整行先清黑（防重叠）、按屏宽截断（防越界）。
- 也就是：**内核日志和 /init 的输出会直接显示在屏幕上**，拍照即可读。

### 5.3 内核参数
- `fuxi.skip=N`：跳过 initcall 级别 >= N（`init/main.c` 的 `do_initcalls`）。skip=6 或 7 时屏幕保亮、系统稳定到用户空间。
- `fuxi.fb=0x<phys>,<stride>,<height>,<width>,<bpp>`：由 UEFI 驱动自动拼接。
- `fuxi.probe=N`：可达性探针（在 init/main.c 关键点调用 `fuxi_probe_point(n)`，命中即复位）；
  **复位原语不可靠，此功能基本废弃**。
- `initcall_blacklist=...`：内核标准参数，注意验证是否真正生效。

### 5.4 initramfs（`build/initramfs/init`）
- 挂载 proc/sys/devtmpfs，写 `FUXI_INIT_RUNNING`；
- 等 10 秒 ttyGS0，没有则写 `FUXI_USB_SERIAL_MISSING`，然后每 5 秒写 `FUXI_ALIVE N`，**第 12 次（60 秒）后 `reboot -f`**；
- 修改 initramfs 后必须删 `build/linux/usr/initramfs_data.cpio*` 再 make，否则不会重新打包。

### 5.5 主机脚本（`scripts/`）
- `auto-boot-tight.sh <img> <timeout>`：0.3 秒轮询 fastboot，出现即 `fastboot boot`（fastboot 只稳定 1–2 秒时也能抓住）。
- `recover-fastboot.sh`：adb → `adb reboot bootloader`。
- `device-watch.sh` + `watcher-ctl.sh`：USB 状态落盘 `logs/usb-state.log`。
- `probe-bisect.sh`：自动探针 bisect（复位原语不可靠，已废弃）。

---

## 6. 环境与硬件坑（很关键）

- 主机：Linux，工作区 `/home/user/文档/deepseek-harness/default-workspace/linux-android`；
  工具：`tools/platform-tools/adb|fastboot`、`tools/ccwrap`（EDK2 构建包装）、aarch64-linux-gnu- 工具链。
- **USB 链路极不稳定**：dmesg 常见 `device descriptor read/all, error -110`、`device not accepting address, error -71`；
  - fastboot 枚举常常只持续 0.5–2 秒就消失；
  - 软件层 xHCI 复位/unbind-bind/端口 disable 都无效；**只有物理拔插 USB 线（换口/换线）能恢复**；
  - 今晚后期换线后一度完全不枚举（疑似充电线），最后换回可用线才恢复。
- 不要用 `pkill -f "<含自身命令行的串>"`（会自杀）；watcher 用 pid 文件管理。
- 手机侧：`adb root` 可用；slot b 是当前槽；boot_a/boot_b = sde14/sde44；备份在 `work/backup/`。

---

## 7. 构建与运行

**内核**
```
cd build/linux
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j12 Image
```
initramfs 改了要先 `rm -f usr/initramfs_data.cpio usr/initramfs_data.cpio.gz`。

**DTB**
```
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- qcom/sm8550-xiaomi-fuxi-min.dtb
```

**固件**（把内核拷进去后编）
```
cp build/linux/arch/arm64/boot/Image build/edk2-msm/Silicon/Qualcomm/sm8550/Drivers/FuxiLinuxBoot/Image.tiano
cd build/edk2-msm
PATH="$PWD/../../tools/ccwrap:$PWD/../../tools:$PATH" ./build.sh --device fuxi --toolchain GCC5 -r DEBUG
# 产物：build/edk2-msm/boot-fuxi.img（约 4MB，fastboot boot 或 dd 到 boot_b 用）
```
- 改 cmdline：`build/edk2-msm/Silicon/Qualcomm/sm8550/Drivers/FuxiLinuxBoot/FuxiLinuxBoot.c` 第 ~499 行的字符串。
- cmdline 缓冲区：`CHAR8 Args[2000]`；DTS `chosen/bootargs` 占位 1623 字节；两者任一截断都会**静默丢失 fuxi.fb=**（打点/console 全没了）。

**镜像清单**（`work/kbuild/`）
- `boot-fuxi-stable.img`：skip=6 + 屏幕 console + 心跳 + 60 秒自重启（**M1 稳定版，推荐起点**）
- `boot-fuxi-clean.img`、`boot-fuxi-font2.img`：console 逐步完善版
- `boot-fuxi-nodisp.img`：当前写入 boot_b 的那版（DTS 关 mdss/dispcc + 黑名单 7 个，仍黑屏）
- `boot-fuxi-noskip-reboot.img`：全驱动 + 60 秒自重启（USB 测试用，仍黑屏）
- 其它历史镜像见目录。

---

## 8. 建议的下一步（给接手者）

### 8.1 先解决"黑屏期间拿不到日志"
三个候选思路（按性价比）：
1. **initramfs 时间编码通道**：/init 用 `dmesg | tail -1` 取最后一行，算 hash，把 hash 编码成"reboot 延迟"
   （例如 delay = 30 + hash % 45 秒），主机测"boot → 回 adb 的秒数"反推最后一条日志。
   这样即使黑屏也能知道内核最后在哪个驱动/消息处。
2. **A/B 槽恢复 + 全黑屏循环**：用 `dd` 写 boot_b 迭代（已建立写入方法），但注意锁死风险（§0），
   建议让 init 在 N 秒后 `reboot bootloader`（进 fastboot）而不是 `reboot -f`，保证能用 fastboot 恢复。
3. **确认 initcall_blacklist 是否生效**：用可观测后果的项（例如 blacklist `populate_rootfs`）做对照实验。

### 8.2 修黑屏
- 拿到日志后，看 level 6/7 最后一条驱动 probe 日志；优先怀疑：
  dispcc/DSI/PHY 驱动、genpd/sync_state、regulator、以及 `simple-framebuffer`/`simpledrm`。
- 也可以试试：把 `CONFIG_DRM_SIMPLEDRM`、`CONFIG_FB` 关掉/保留的对照。

### 8.3 M2 USB gadget
- 屏幕保亮后（skip=6 或修好黑屏），跑全驱动，读 dwc3/PHY 的 probe 错误；
  常见缺口：PMIC eusb2 repeater 驱动、SPMI/PMIC regulator 是否 probe、dwc3 的 clocks/interconnects/power-domains。

### 8.4 长期
- UFS（ufs-qcom）→ 挂 rootfs；显示面板（三星 DSC command-mode，主线无驱动，硬骨头）；
- 触摸（ST FTS V521）；WiFi/GPU/音频；modem 不保证。
- 真正产品化：把自写 UEFI 直跳换成"UEFI 读存储 + 标准 EFI stub"或现成 Mu-Silicium UEFI。

---

## 9. 重要文件索引
- 内核调试代码：`build/linux/arch/arm64/kernel/fuxi_early.c`
- 内核打点调用点：`build/linux/init/main.c`、`arch/arm64/kernel/setup.c`
- 固件驱动：`build/edk2-msm/Silicon/Qualcomm/sm8550/Drivers/FuxiLinuxBoot/FuxiLinuxBoot.c`
- 板级 DTS：`build/linux/arch/arm64/boot/dts/qcom/sm8550-xiaomi-fuxi-min.dts`
- initramfs：`build/initramfs/`（`init` 脚本）
- 历史记录：`docs/交接-给CODEX.md`（E.1–E.15，含每轮照片解码与结论）
- 备份：`work/backup/boot_b_orig.img.gz`
- 主机脚本：`scripts/*.sh`，日志：`logs/`
