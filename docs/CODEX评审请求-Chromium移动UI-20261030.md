# 给 CODEX 的评审 / 验收请求：Chromium 移动端浏览器（2026-10-30）

> 角色分工（用户指定）：**CODEX 提意见 + 验收；Lead（我）开发**。
> 本文件给 CODEX 评审用，含：做了什么、关键决策、证据、请你重点审的点、验收清单。

## 1. 背景与需求

- 环境：Xiaomi 13（fuxi）跑主线 Linux `7.3.0+`，Ubuntu 26.10 arm64，Phosh（Wayland），内核当前 `#207`。
- 用户先后两条需求：
  1. “移植一个谷歌浏览器到手机里面” → Google 官方无 arm64 Linux 版 Chrome，改用同引擎 **Chromium（Debian arm64，150.0.7871.100）**，隔离装到 `/opt/chromium`。
  2. “UI 按电脑端逻辑、没考虑手机端，要模仿 iOS/安卓浏览器、**保留 Chromium 内核**、要原生移动布局”。
- 约束（项目既有边界）：只写 Linux rootfs（`/opt`、`/home/fuxi`），不刷机、不重启、不改系统 dpkg、不动 Android/固件分区。

## 2. 关键决策（请重点评审）

| 决策 | 理由 |
|---|---|
| 用 Chromium 而非真 Chrome | 官方无 arm64 Linux 包；Chromium 同 Blink 引擎 |
| Debian `.deb` 而非 Ubuntu 包 | Ubuntu 26.10 只有 snap 转换包，手机无 snapd |
| 隔离前缀 `/opt/chromium` + 私有库 `privatelib` | 7 个 soname Ubuntu 26.10 缺（dav1d6/jpeg62/flac12/minizip1/openh264-7/double-conversion3/xnvctrl0），用 `LD_LIBRARY_PATH` 私有库优先，**不污染系统库、可整体删除** |
| **移动 UI = CDP 注入自包含外壳** | Chromium 桌面版无移动 UI；Linux 无 CEF/WebEngine/Electron 可套壳；故用 `Page.addScriptToEvaluateOnNewDocument` 向每页注入安卓-Chrome 风格顶栏+底栏 |
| 导航用页面内 `history/location`，不依赖 bridge | bridge/守护进程挂了浏览器仍可用；更稳 |
| GPU：`--use-angle=gl`（ANGLE over freedreno） | 实测 GPU 进程映射 `libEGL_mesa`（Adreno 740 硬件 GL）；Vulkan 在此不可用会自动回退 |
| 守护进程做成自愈 + systemd --user 服务 | CDP 单连接易被并发的调试连接踢断、`--app` 单例竞态；用全局锁 + 断开重连 + 重新注入 + 进程退出重启；服务跨重启自启 |

## 3. 交付物（仓库内）

- 浏览器本体：`scripts/fuxi-chromium-deploy.sh`（下载校验 SHA256→解包→启动器→桌面项；`--rollback`）。
- 移动 UI 层：`scripts/fuxi-chromium-mobile-ui.sh`（装 overlay + 自愈守护 + systemd 服务 + autostart + 桌面图标；`--rollback`）。
- 运行时：`work/chromium-mobile/{mobile-chrome.js, fuxi-mobile-shell.py, cdp.py, probe.py, selftest.py, launch-mobile.sh}`。
- 文档：`docs/Chromium浏览器移植-20261030.md`（本体 + 移动 UI 两节）。
- 回归测试：`scripts/tests/test_fuxi_chromium_deploy.py`（7 项）、`scripts/tests/test_fuxi_chromium_mobile_ui.py`（5 项）。

## 4. 实机证据（内核 #207，uptime 15min 稳定）

- `systemctl --user is-active fuxi-mobile-chromium.service` → **active**。
- bridge `/state` → `{"u":"https://www.example.com/","t":"Example Domain","b":true}`。
- `/eval` 覆盖层 → `{top:true, bottom:true, btns:5, addr:"www.example.com"}`。
- 点“主页”按钮 → 成功，状态回主页。
- **CDP 页面截图分区取样**（=`work/claude-logs/chromium-20261030/ui-final.png`）：
  顶栏 `#f1f3f4` 地址药丸 71.6% / 页面浅灰 `238` 89% / 底部白工具栏 94.7%。
- 主机回归 `python3 -m unittest discover -s scripts/tests` → **57 项全过**。
- 物理 grim 截图：页面浅灰 89.7%、底部白工具条 75.9%（顶栏区域被 Phosh 黑色状态栏覆盖，属正常）。

## 5. 请你（CODEX）重点审 / 挑刺的点

1. **安全边界**：脚本是否真不写 dpkg、不刷机、不重启、只动 `/opt` 与 `/home/fuxi`？（`test_fuxi_chromium_*.py` 已断言，但请人眼复核 shell 脚本是否有隐藏副作用）
2. **CDP 注入方案**对 `chrome://`、内网/证书页、CSP 严格页面是否会被拦；`Page.addScriptToEvaluateOnNewDocument` 在 OAuth 弹窗/新窗口是否覆盖。
3. **单例竞态**：`--user-data-dir` 单例会否在重启/双击图标时出现“新进程转交旧进程后退出→CDP 断连”的抖动；自愈循环是否足够。
4. **移动端还原度**：是否该加移动 UA（`--user-agent`）以让站点返回移动版；底部安全区 `env(safe-area-inset-*)` 在 fuxi 上是否生效。
5. **资源占用**：Chromium 常驻 ~220-260MB；是否接受；是否要改成按需启动（点图标才起）而不是 autostart。
6. **可维护性**：overlay 依赖 Chromium 150 的页面 DOM 注入，升级 Chromium 是否需回归；是否要锁定版本。

## 6. 验收清单（请你逐条勾）

- [ ] `scripts/fuxi-chromium-mobile-ui.sh` 幂等、可 `--rollback` 干净移除 UI 层（保留 Chromium 本体）。
- [ ] 服务 active，冷启动（重启 Linux）后 Phosh 会话内自动出现浏览器窗口。
- [ ] 顶栏地址药丸可点、可输入网址回车跳转；底栏 5 键功能正确。
- [ ] 触屏可滚动、可点按（需用户在屏上实际点，以物理反馈为准）。
- [ ] 主机回归 57 项全过；脚本无刷机/重启/dpkg 副作用。
- [ ] 文档 `docs/Chromium浏览器移植-20261030.md` 与 README/state 一致。

## 7. 用户现场验收（需物理操作）

请用户在手机上：点开桌面“Chromium 浏览器”图标 → 确认出现窗口 → 点地址框输入网址 → 用底栏后退/主页 → 手指滚动页面。以用户物理反馈为准判定“手机端 UI 可用”。

## 8. 已知未做 / 待办

- 未强制移动 UA（部分站点仍桌面渲染）。
- 多标签用 `window.open` 简化，非真正标签管理器。
- 密码保存用 `--password-store=basic`（不落 keyring）。
- 手机在被**外部 `systemctl reboot` 反复重启**（日志显示每次来自 root tty 会话、同一 ED25519 key、源自主机 10.42.0.1），
  疑为用户/并行会话在刷内核；这会中断部署，需协调时段。
