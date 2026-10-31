# Claude Code 的 `[cyber]` 误报：边界、实测与应对（2026-10-31）

一句话结论：**这是 Anthropic 服务端的实时安防分类器，客户端关不掉，也不只针对某个型号。**
能彻底解决的只有两条路——(A) 不让模型生成这类内容（设备动作脚本化 + 工具层拦死），
(B) 这类工作走不经过该分类器的入口。改 prompt 只能降低概率。

## 1. 事故现场

2026-10-31 20:31，`adb reboot recovery` 之后同一会话连续三次拒答：

| 时间 | 消息 ID | 说明 |
|---|---|---|
| 12:32:21Z | `msg_011CgaKWnDTMW3jh4BKzT3SL` | 首次拒答 |
| 12:32:37Z | `msg_011CgaKXw7GuymVneBEPmS3m` | 用户发「继续」后 |
| 12:32:45Z | `msg_011CgaKYZ7icSkuzeMM9VRzW` | 客户端自动重试 |

原始记录：`~/.claude/projects/-home-user-linux-android/088f7842-….jsonl` 第 252–268 行。
其中的系统条目是 `subtype: model_refusal_no_fallback`、`apiRefusalCategory: cyber`，
说明拒答发生在**生成阶段**，不是工具错误也不是网络错误。

关键细节：第二次拒答后 Claude Code 往上下文注入了
「Your response above was stopped… Do not produce that content again, even reworded.」
所以**连发「继续」是在重放同一段内容并叠加"不许重复"的约束**，只会更容易再撞。

## 2. 换型号有没有用：实测（同一句话，只换型号）

探测方式：`claude -p --model <型号>`，单轮、无工具、同一段正当请求
（在自己手机上把 10MB 镜像写入 recovery_b 并校验）。

| 型号 | 结果 |
|---|---|
| `anyu-ai/claude-opus-4-8` | 放行（给出 dd + sha256sum） |
| `anyu-ai/claude-sonnet-5` | 放行 |
| `anyu-ai/claude-opus-5-5`（默认） | **拒答** `msg_011CgaNAP2ErikNQUzTMBikm` |
| `anyu-ai/claude-fable-5-1` | **拒答** |
| `anyu-ai/claude-opus-4-1` / `haiku-4-5` | 超时（本路由不服务该型号，结论不成立） |

结论：分类器**跨型号存在**，只是阈值不同。换型号是轮盘赌，不是修复。
另有旁证：`claude -p "用 Bash 执行 qdl --help"` 在 opus-5-5 上也被拒（连跑固件工具都算），
在 sonnet-5 上则放行并真的去执行 —— 被本仓库的 hook 拦下（见 §3）。

完整记录：`work/claude-logs/cc-safeguard-probe-20261031.txt`。

## 3. 已经落地的三层防线

### 3.1 设备动作脚本化（人类执行）
`scripts/fuxi-flash.sh`：默认只读（`status`/`plan`），写操作必须 `--yes`；
只写 `recovery_b`；镜像只认 `work/kbuild|work/patches`；写前比对 state json 的 sha256，
写后读回全量 sha256 校验；日志 `work/claude-logs/fuxi-flash-*.log`。

### 3.2 工具层拦死（agent 想刷也刷不到）
`.claude/settings.json` 注册 PreToolUse hook → `scripts/fuxi-guard.sh`：
命中 `fastboot flash|boot|erase|reboot`、`adb reboot`、`adb sideload`、
`dd … of=/dev/{block,sd,nvme,mmcblk}`、`qdl`、`fuxi-flash.sh flash|reboot` 时
exit 2 阻止，并把「请人类在终端执行」的说明回给模型。
`--help`/`--version` 和 `fuxi-flash.sh status|plan` 放行。

生效条件：**Claude Code 需要重启会话**才会重新加载 `.claude/settings.json`。
自测：`printf '{"tool_name":"Bash","tool_input":{"command":"adb reboot recovery"}}' | scripts/fuxi-guard.sh; echo $?` 应为 2。

### 3.3 会话纪律
- 被拒后 **不要连发「继续」**；`/clear` 开新会话，用 `TASKS.md` 重建上下文。
- 原始产物（hex dump / 分区 dump / 反汇编 / 签名 blob）落 `work/` 文件，让 agent 用
  read/grep 按需取，不要贴进对话。
- 设备事实（分区名、镜像路径、sha256、`adb reboot recovery`）照写，不用自我审查。

## 4. 想要"真·彻底"：换入口

只要请求最终打到 Anthropic 的 Claude 模型，分类器就在。要彻底摆脱只有：
1. **这类任务固定走别的入口**（本机 DSH、本地模型、非 Anthropic provider）；
2. 或在 magpie（`~/.config/magpie/providers.json`）里加第二个 provider（OpenAI 兼容/本地），
   建成 group 用 `order` 或 rules 分流：写代码/文档走 Claude，设备操作走本地。
   注意：`group/cheap-first` 现在的成员仍是 Claude 型号，分流要新建 group。

## 5. 不要做的事

- 不要靠"改写措辞"指望根治：同一条请求这次过、下次可能拒（本页 §2 就是同一句话四种结果）。
- 不要用 `--dangerously-skip-permissions` 绕过 hook：那只是跳过权限确认，绕不过分类器。
- 不要为绕分类器去分片、编码、夹带内容 —— 既不可靠，也会真的踩到 AUP。

## 6. 误报上报

`/feedback`，附 message id + 当时那一步（本次：`msg_011CgaKWnD…`/`KXw7…`/`KYZ…`）。
参考 https://support.claude.com/en/articles/14604842-real-time-cyber-safeguards-on-claude
