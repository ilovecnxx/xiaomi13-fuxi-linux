# 任务：重新设计 Clash Fuxi 的 UI（交给 CODEX）

> 日期：2026-10-30　工作目录：`/home/user/文档/deepseek-harness/default-workspace/linux-android`
> 目标文件：`work/mihomo-gui/app/clash_fuxi.py`（部署到手机 `/usr/local/bin/clash-fuxi`）
> 设备：Xiaomi 13 `fuxi`，主线 Linux 7.3 + Phosh（aarch64 Ubuntu 26.10），屏幕 1080×2400，合成器 phoc `scale=2.5`（逻辑分辨率 **432×960**）

## 用户原话（要解决的问题）

1. **“UI 太丑了”** —— 需要整体视觉重新设计，简洁、现代、手机观感。
2. **“右上角也不需要电脑的关闭放大按钮”** —— 当前 `Adw.HeaderBar` 带了桌面窗口控制按钮（最小化/最大化/关闭），手机上不该出现。
3. **“UI 都没占满全屏”** —— 内容挤在顶部，下半屏大片空白。
4. **（2026-10-30 追加）“上级顶栏不要遮住啊，顶栏都遮住了”** —— 应用顶栏与 Phosh 系统状态栏（时间/信号/电量）重叠，应用自己的顶栏被系统顶栏压住/遮住。

## 已确认的根因（供 CODEX 定位）

- 窗口本身确实已是全屏：运行日志 `[ui] window 432x960 fullscreened=True`（432×960 逻辑 = 1080×2400 / 2.5）。**不是窗口没满，是内容没铺满。**
- `MainWindow.__init__`（约 166 行起）：`root = Gtk.Box(VERTICAL)`，里面依次 append 4 张卡（hero / 模式 / 开关 / 订阅），**卡片都 `vexpand=False` 自然高度**，总高约 450 逻辑 px，导致下半屏空。
- `header = Adw.HeaderBar()`（178 行）：**默认显示 start/end title buttons**（关闭/最大化/最小化），这就是用户说的"电脑的按钮"。
- **顶栏被遮的根因**：`_go_fullscreen()` 调用了 `self.fullscreen()`（约 204 行）。**全屏模式会让窗口盖住 Phosh 系统状态栏区域**，于是应用顶栏正好被系统顶栏压住。正解是**普通应用不要 fullscreen，改用 `self.maximize()`**——Phosh 会自动把窗口限制在"系统顶栏之下的可用区域"，应用顶栏和系统顶栏各就各位。参考：系统自带 Epiphany 等普通应用都是 maximize，不是 fullscreen。
- 主题：当前是深色主题下的默认样式，配色平淡。

## 🔴 顶栏 / 全屏规则（CODEX 必读，最容易再踩）

- **用 `self.maximize()`，不要用 `self.fullscreen()`**。fullscreen 会与 Phosh 顶栏打架（被遮/互相覆盖）。
- 若确要全屏，必须自己给内容顶部留出系统顶栏高度（Phosh 顶栏约 32–36 逻辑 px）的安全区，但**更简单的正解是 maximize**。
- **不要**在应用里自绘一条和系统顶栏竞争的标题栏；顶栏可选做法：去掉 `Adw.HeaderBar` 的窗口控制按钮并让它成为 `Adw.ToolbarView` 的 top bar（maximize 下它会自动落在系统顶栏下方），或用 `Gtk.WindowHandle`。
- 验收时必须确认：应用自己的顶栏/内容**完整可见，没有被系统顶栏遮住**。

## 设计目标（务必满足）

### 布局
- **真正的手机单屏**：在 `maximize` 下（可用区约 432×924，系统顶栏占顶部），内容纵向铺满可用区域，不出现半屏空白、不出现滚动、**不被系统顶栏遮挡**。
- 建议把整屏分成有呼吸感的分区，例如：
  - **顶部**：去掉桌面窗口控制按钮（`HeaderBar` 设 `set_show_start_title_buttons(False)` 和 `set_show_end_title_buttons(False)`，或干脆不用 HeaderBar，自定义一个极简顶栏 / 或 `Gtk.WindowHandle`）。**注意顶部不要与系统顶栏重叠。**
  - **中部主视觉**：一个居中醒目的大号启停控件（圆形电源键或大卡片），运行/停止状态配色区分明显。
  - **实时流量**：上下行速率用醒目的数字 + 小图标，可放在主视觉卡内。
  - **功能区**：模式分段（规则/全局/直连）、TUN、系统代理，做成整齐的分栏/网格。
  - **订阅**：底部或折叠区，输入 + 导入。
- 尽量用 `Adw.Clamp`、`Gtk.CenterBox`、`Gtk.Grid`、`Adw.PreferencesGroup` 等 libadwaita 原生组件，保持 GNOME/Phosh 风格一致。
- 用 `vexpand` / spacer 让关键区块分摊纵向空间，确保铺满。

### 视觉
- 去除桌面窗口关闭/最大化按钮。
- 配色、圆角、间距现代化；运行状态（连接中/已连接）有明确视觉反馈（颜色、图标、文字）。
- 大触控目标（手机点按），字号适中。

## 必须保留的后端逻辑（不要改坏）

`clash_fuxi.py` 里这些**已实机验证可用**，重做 UI 时请保留其行为（可重构调用方式，但功能不能丢）：

- 内核启停：`_start_core()` / `_stop_core()`（`subprocess.Popen([MIHOMO,"-d",CONF_DIR])` + pid 文件 + 等 `/version` API）。
- 订阅导入：`_on_import()`（下载 http/https 订阅 → 写 `config.yaml` → `PUT /configs {"path":...}`）。
- 模式切换：`PATCH /configs {"mode": rule|global|direct}`。
- TUN 开关：`PATCH /configs {"tun":{"enable":bool}}`，~0.9s 后 `_verify_tun()` 回读，失败则回滚开关 + toast 提示“需 FUXI_NET=1 镜像”（当前内核不支持 TUN）。
- 系统代理：`gsettings set org.gnome.system.proxy ...`（127.0.0.1:7890）。
- 实时速率：`_tick()` 每 1s 读 `/connections` 累计值算速率（**不要用 `/traffic`，它是无限流会卡死**）。
- 配置初始化：`ensure_dirs()`（写默认 config，含 `geodata-mode: true`；清理 <1MB 的损坏 `geoip.metadb`）。
- API 常量：`API_HOST=127.0.0.1 API_PORT=9090 API_SECRET=clashfuxi`。
- CSS 通过 `Gtk.CssProvider` 注入（`do_startup`），改样式走这里。

## 部署与验证

手机当前在 Linux，SSH 可用（`scripts/fuxi-ssh.sh`）。部署：

```bash
scp -i work/ssh/fuxi_root -o UserKnownHostsFile=work/ssh/known_hosts \
  work/mihomo-gui/app/clash_fuxi.py root@10.42.0.2:/usr/local/bin/clash-fuxi
scripts/fuxi-ssh.sh 'python3 -m py_compile /usr/local/bin/clash-fuxi && echo OK'
# 重启（PID 会变，别用 pgrep -f 匹配含 clash-fuxi 的 ssh 命令行以免误杀）
scripts/fuxi-ssh.sh 'for p in $(ps -eo pid,args | grep "python3 /usr/local/bin/clash-fuxi" | grep -v grep | awk "{print \$1}"); do kill $p; done'
scripts/fuxi-ssh.sh 'su fuxi -c "env XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 \
  XDG_SESSION_TYPE=wayland DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  GDK_BACKEND=wayland GTK_A11Y=none nohup /usr/local/bin/clash-fuxi >/tmp/gui.log 2>&1 &"'
```

### ⚠️ 截图陷阱（必读）
本机 **`grim` 截图不可信**：在 freedreno + scale=2.5 下抓帧异常，本应用和系统自带 Epiphany 都只在屏幕中央一条窄带出内容、其余漆黑。**不要用 grim 截图判定"是否铺满/是否好看"**——那会误导。判断窗口尺寸用程序内 `get_width()/get_height()` + `fullscreened`（已有 `[ui] window ...` 日志）或让用户目视。

如果确实需要截图，可试 `grim -s 2.5` 或换 `gnome-screenshot`；但以用户目视为准。

## 验收标准（交给用户确认）

1. 屏幕顶部**没有**最小化/最大化/关闭按钮。
2. 内容**纵向铺满**可用区域（maximize 下约 432×924），无明显大片空白，无滚动。
3. **应用顶栏/内容不被 Phosh 系统状态栏遮挡**（时间/信号/电量那条），两者不重叠。
4. 视觉整洁、现代，运行/停止状态一目了然。
5. 电源启停、模式切换、订阅导入、系统代理、TUN 失败回滚 **功能全部照旧可用**（见上"必须保留"）。
6. 崩溃率 0：启动无 Python 异常（a11y/portal 警告无害）。

## 参考

- 现有实现：`work/mihomo-gui/app/clash_fuxi.py`
- 背景与历史：`docs/Clash客户端-20261030.md`
- 上一版验收清单：`docs/交接-给CODEX-Clash客户端-20261030.md`
