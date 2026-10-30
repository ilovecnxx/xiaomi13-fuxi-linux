# 交接给 CODEX —— Clash Fuxi 图形客户端验收（2026-10-30）

## 一句话

手机（Xiaomi 13 `fuxi` 主线 Linux + Phosh，aarch64 Ubuntu 26.10）上已装好一个**原生 GTK4/libadwaita 的 Clash/Mihomo 图形客户端**，采用 **Clash Meta 风格单屏分栏**布局。核心后端逻辑已实机验证通过；UI 布局需人工目视验收（见下"为什么截图不可靠"）。

## 用户最新诉求（本轮的）

1. UI 美化、简化，**尽量一屏操作**；
2. 实在不行就**模仿 Clash Meta 的分栏**。

本轮已按"单屏 + 分栏"实现，见 `work/mihomo-gui/app/clash_fuxi.py` 的 `MainWindow`。

## 文件与部署位置

| 主机路径 | 手机路径 | 说明 |
|---|---|---|
| `work/mihomo-gui/app/clash_fuxi.py` | `/usr/local/bin/clash-fuxi` | GUI 主程序（单文件） |
| `work/mihomo-gui/app/clash-fuxi.desktop` | `/usr/share/applications/clash-fuxi.desktop` | 桌面图标 |
| — | `~fuxi/.config/autostart/clash-fuxi.desktop` | 登录自启 |
| `work/mihomo-gui/host-dl/mihomo` | `/usr/local/bin/mihomo` | Mihomo v1.19.33 arm64 静态二进制，已 `setcap cap_net_admin,cap_net_raw+ep` |
| — | `~fuxi/.config/mihomo/config.yaml` | 配置（mixed-port 7890 / controller 9090 / geodata-mode） |

新增 apt 包（additive）：`gir1.2-gtk-4.0` `gir1.2-adw-1` `gir1.2-graphene-1.0` `nftables`。

## 新 UI 结构（单屏，432×960 逻辑 = 满屏）

顶部 HeaderBar（标题 + 右侧"日志"按钮），下面 4 张卡片顺序堆叠，无滚动：

1. **Hero 卡**：左侧大圆形电源按钮（启停内核，运行时变主题色实心）；右侧两行实时"下载/上传"速率。
2. **模式卡**：`Adw.ToggleGroup` 分段控件「规则 | 全局 | 直连」——对应 Clash Meta 顶部分段。
3. **开关卡**：`Gtk.Grid` 两列并排——左「TUN」开关，右「系统代理」开关。
4. **订阅卡**：单行输入框 + 「导入」按钮。

估算高度约 420–470 逻辑 px，远小于 960，**一屏放得下且有余量**。

## 实机验证结果（客观证据）

在手机上以 `su fuxi` + Wayland 环境启动 `/usr/local/bin/clash-fuxi`：

```
[ui] window 432x960 fullscreened=True      # 432×960 逻辑 = 1080×2400 / scale 2.5 = 满屏
```

- 进程存活、无 Python 异常（仅 a11y/portal 无害警告）。
- 内核启停：`/usr/local/bin/mihomo -d ~/.config/mihomo` → 7890/9090 监听正常。
- API：`/version` 返回 v1.19.33；`PATCH /configs {"mode":"global"}` 返回 204，回读 mode=global。
- HTTP 代理：经 `127.0.0.1:7890` 访问 `gstatic.com/generate_204` 返回 204。
- TUN：默认开关会 PATCH `/configs {"tun":{"enable":true}}`，当前内核因缺策略路由选项失败，GUI 会在 ~0.9s 后回读并回滚开关 + toast 提示"需 FUXI_NET=1 镜像"。已编好 `work/kbuild/abl-fuxi-net1.img`（未刷，用户选择暂不刷）。

## ⚠️ 为什么本轮的 grim 截图不可靠（给 CODEX 的重要提示）

在本机 `grim` 截图里，**本应用和系统自带 Epiphany 浏览器都只在屏幕中央约 y960–1440 一条窄带出现内容，其余全黑**——两者表现完全一致。这说明是 **grim 在 freedreno/GPU + scale=2.5 合成下的抓帧缺陷**，不是应用布局问题。`get_width/get_height` 与 `fullscreened=True` 证明窗口实际是满屏的。

**因此：UI 验收请以人工现场目视 / 手机实机为准，不要只用 grim 截图判定布局。**

## 请 CODEX 验收的清单

1. 重新部署并启动（手机已在 Linux，SSH 可用）：
   ```bash
   scp -i work/ssh/fuxi_root -o UserKnownHostsFile=work/ssh/known_hosts \
     work/mihomo-gui/app/clash_fuxi.py root@10.42.0.2:/usr/local/bin/clash-fuxi
   scripts/fuxi-ssh.sh 'for p in $(pgrep -f "python3 /usr/local/bin/clash-fuxi"); do kill $p; done'
   scripts/fuxi-ssh.sh 'su fuxi -c "env XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 \
     XDG_SESSION_TYPE=wayland DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
     GDK_BACKEND=wayland nohup /usr/local/bin/clash-fuxi >/tmp/g.log 2>&1 &"'
   ```
2. **目视**确认一屏显示：电源按钮 + 上下行速率 + 模式分段 + 两个开关 + 订阅输入，无滚动、无溢出。
3. 点电源按钮 → 状态变"运行中"，速率开始跳动；再点停止。
4. 切换「规则/全局/直连」→ toast + 实际 mode 改变（可 `scripts/fuxi-ssh.sh` 查 `curl` API）。
5. 填订阅链接 → 导入 → config.yaml 更新；重开内核生效。
6. 系统代理开关 → `gsettings get org.gnome.system.proxy mode` 应为 `manual`/`none`。
7. TUN 开关在旧内核应"失败回滚 + 提示"，**不崩**。

## 已知限制

- TUN 需刷 `work/kbuild/abl-fuxi-net1.img`（`FUXI_NET=1` 编出）。用户当前选择不刷。
- grim 截图在本机不可用于布局判定（见上）。
- 订阅下载依赖手机网络；首次启动若残留损坏 metadb，`ensure_dirs()` 会自动清理。

## 回滚

只删新增文件即恢复，不动内核/分区：
`/usr/local/bin/{mihomo,clash-fuxi}`、两个 `.desktop`、`~fuxi/.config/{mihomo,autostart/clash-fuxi.desktop}`、
`~fuxi/.local/state/clash-fuxi/`。
