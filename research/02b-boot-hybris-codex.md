# 小米13（fuxi）直接启动 Linux 评估（2026-10）

基线：LineageOS 24/Android 17、5.15.211 GKI、A/B 动态分区、已解锁。结论：A（hybris）数月级可行；B（全 mainline）数月到一年。先备份，再试 `fastboot boot`。

## 路线对比

| |A：Droidian/Ubuntu Touch 式|B：postmarketOS mainline|
|---|---|---|
|用户态/内核|Debian/Ubuntu+Halium/libhybris；复用 Lineage 5.15、vendor_dlkm|Alpine+Mesa；自建 kernel+DTS|
|驱动|现成 gralloc/composer、音频、RIL、Wi‑Fi blob|上游 DRM/UFS/USB；面板/触摸/modem 自补|
|结果/工期|显示触摸可争取，通话不保证；30–60 人日到 GUI|先亮屏可行；60–120 人日到日用|

Droidian 当前为 101（Debian sid 快照），官方设备站无 fuxi（https://devices.droidian.org/）。libhybris 对 Android 13+/GKI 不会自动兼容，仍需 Halium 用户态、匹配 blob、binder/binderfs、模块和内核配置；指南用 `mer_verify_kernel_config` 检查（https://docs.droidian.org/porting-guide/kernel-compilation/）。Android 17/fuxi 成功案例未查证，RIL/音频是主阻塞。

postmarketOS 端口要 device 包、kernel 包、`deviceinfo`、DTS；参考 https://wiki.postmarketos.org/wiki/Porting_to_a_new_device ：

```bash
pmbootstrap init
pmbootstrap aportgen device-xiaomi-fuxi
pmbootstrap aportgen linux-xiaomi-fuxi
pmbootstrap install
pmbootstrap export
pmbootstrap flasher boot
# 验证后才考虑 pmbootstrap flasher flash_rootfs
```

最小闭环：DTB、内核、USB/ADB、DRM 亮屏；触摸/Wi‑Fi/音频/modem 后做。

## 引导与风险

PBL→XBL→ABL→vbmeta/AVB→`boot`/`init_boot`/`vendor_boot`。Android 13 起通用 ramdisk 在 `init_boot`（https://source.android.com/docs/core/architecture/partitions/generic-boot），动态分区在 `super`。禁验签常用：

```bash
fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img
```

先 `fastboot getvar current-slot`、`getvar all`。AOSP 有 `fastboot boot`；小米是否在 fuxi ABL 封锁，未找到官方说明。社区有临时启动记录（https://mi.fiime.cn/Recovery/3458.html），必须实机验证。

|操作|恢复/等级|
|---|---|
|`fastboot boot`、`set_active`|不写盘/可切槽；低|
|刷 boot/init_boot/vendor_boot/dtbo/recovery、vbmeta|官方包或另一槽；中|
|fastbootd 刷 `super`|整包恢复且可能丢数据；高|
|擦 `persist/modemst/fsg`|可能永久丢 IMEI/校准；**高、不可逆数据风险**|
|刷 `abl/xbl/tz/hyp/devcfg`、分区表、efuse；回锁/低版本|可能只剩 9008，efuse 永久；**致命、不可逆风险**|

官方 fastboot ROM+MiFlash 是首选救援；fuxi 的 9008 是否必须授权账号，未查证到小米公开机型政策，社区普遍称 Qualcomm 小米 EDL 受授权限制。A/B 回切：`fastboot set_active a|b`。

## 安全准备

```bash
adb root; mkdir -p bk; adb shell 'mkdir -p /data/local/tmp/bk'
P='persist modemst1 modemst2 fsg fsc boot_a boot_b init_boot_a init_boot_b vendor_boot_a vendor_boot_b vbmeta_a vbmeta_b vbmeta_system_a vbmeta_system_b dtbo_a dtbo_b metadata abl_a abl_b xbl_a xbl_b'; for p in $P; do adb shell "test -e /dev/block/by-name/$p && dd if=/dev/block/by-name/$p of=/data/local/tmp/bk/$p.img bs=4M"; adb pull /data/local/tmp/bk/$p.img bk/ 2>/dev/null || true; done
sha256sum bk/*.img > bk/SHA256SUMS; adb shell 'ls -l /dev/block/by-name' > bk/by-name.txt
```

备份放电脑和离线介质，核对 SHA256；`super` 可按磁盘空间另备；另备当前版本官方 fastboot ROM；禁止 `erase persist/modemst`、回锁。

## 最小无损验证与结论

```bash
adb reboot bootloader
fastboot getvar current-slot
fastboot boot boot-test.img
```

镜像须匹配当前 KMI、`vendor_boot`/DTB；按“内核→USB/ADB→DRM→触摸→Wi‑Fi”观察，失败回 bootloader 后 `fastboot reboot`。首选先做 A 的临时启动，B 作长期主线。只做一件事：**先备份，再实测 `fastboot boot`**。
