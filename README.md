# Emberline

**鸿蒙上的完整伪终端。**

Emberline(原名 FusionTerm)是一款 HarmonyOS 原生终端模拟器,内核移植自
[Ghostty](https://ghostty.org) 的终端引擎(libghostty-vt)。它不是 WebView
套壳,也不是简化的命令行玩具——从 PTY 到转义序列解析再到逐格渲染,走的都是
桌面级终端的完整链路。为 HarmonyOS 2in1 设备(键盘 + 触控板 + 触屏三形态)
设计,像桌面终端一样严肃,像移动应用一样顺手。

界面只有一种颜色会发光:标签底缘那根**余烬铜灯丝**——亮着,你的会话就活着。

> 本项目不是对上游的简单打包:渲染 HAR fork([libghostty-ohos](#fork-说明))
> 经过深度重写——滚动性能三件套(scroll-damage / buffer-age / 像素级平滑滚
> 动)、完整的触控板 + 触屏 + 鼠标输入体系、系统 IME 接入以及多起内存安全
> 加固都在 fork 中完成;VM 侧 [wand-agent fork](#fork-说明)
> 则补齐了鉴权、会话治理与进程生命周期语义。细目见「Fork 说明」一节。

## 功能

**终端仿真**

- 真 PTY 本地会话(POSIX 语义:进程组 / 信号 / SIGWINCH)。
- 完整 VT/xterm 兼容:256 色与真彩、DECCKM、bracketed paste、OSC 窗口标题、
  Shift+Tab 反向补全,vim / htop / tmux 开箱即用。
- 鼠标协议:tmux/vim 开鼠标模式后,触屏轻点是点击、长按拖动可直接拖 tmux
  分栏、滑动是滚轮;鼠标与触控板各行其道。
- OSC 52 远程复制(远端 tmux/vim 直写系统剪贴板)、OSC 9 与 BEL 桥接为
  HarmonyOS 系统通知(后台标签任务完成会喊你,标签灯丝同步"复燃"提醒)。

**渲染与手感**

- C++ 原生渲染:脏行级重绘 + 持久离屏 + 滚动位移复用(scroll-damage)+
  按脏行上屏(buffer-age),以 2.5K 屏长输出为优化目标;当前 dev 变更仍需
  真机 Profiler 回归。
- 像素级平滑滚动:触屏 / 触控板逐像素跟手,松手惯性,选择拖到屏幕边缘
  自动滚动续选,跨屏长复制完整无缺。
- 字宽实测排版(非估算系数),任意字号下字距、光标、选区严格对齐;
  中文等宽(默认 Maple Mono NF CN)无缺字。
- 打字或有输出时光标保持实心,空闲才闪烁。

**连接**

- 三类会话统一多标签:WebSocket Agent 是 Fusion VM 主路径;本地 shell 是
  沙箱允许时的机会性能力;SSH/SFTP 是尚未达到发布安全门槛的开发回退。
- 已连接 Agent 意外断开后使用指数退避,等待期间敲键可立即重试;首次连接
  失败和半开连接超时仍是发布阻塞项。源码已接入 `taskKeeping`,后台与熄屏
  连续性须由真机矩阵确认。
- 前台窗口请求常亮,进入后台或销毁窗口时恢复系统休眠策略;这一生命周期
  同样须在目标设备验证。
- 标签:动态宽度、轨道内拖动重排(按住即拖、邻居实时让位)、右键菜单
  改名与关闭、自定义灯丝颜色;关闭标签不打断远端 tmux 里正在跑的任务。

**输入与剪贴板**

- 物理键盘是主输入:Ctrl+Shift+C / Ctrl+V 复制粘贴,Ctrl+C 永远是
  中断信号;Tab、Esc、方向键与功能键统一走原生按键编码器,不叠加屏幕
  快捷键栏。触控负责滚动、选择、链接与中文 IME。
- 截图直达终端:任意处截图后 Ctrl+V,按会话视角粘出可用路径——本地给
  本地路径、VM 会话走共享目录零上传,支持逐标签覆盖粘贴视角。SSH/SFTP
  上传仍受主机密钥与跨标签凭据阻塞项约束,不作为当前发布承诺。
- 图片「中继」视角:在 Agent 会话里 ssh 到 tailnet 上的另一台机器后,
  粘贴的图片由 wand-agent 从共享目录 `scp` 转发到该机(右键标签 →
  标签设置 → 图片粘贴视角 → 中继,填目标机与远端目录),终端里直接粘出
  目标机上的路径。前提:VM 可免交互 ssh 到目标机(Tailscale SSH ACL
  `accept` 或已装密钥);任何失败会回退为共享路径并在终端说明原因。
- 中文 IME 完整支持(native 自定义编辑框)。

**自定义**

- 首屏始终是终端;顶栏只有连接、设置、更多三个常驻应用操作,右侧检查器
  只分「终端 / 外观 / 连接」三类,覆盖打开而不挤压终端网格。
- 458 套 Ghostty 主题(真色板预览)、五款内置等宽字体 + ttf/otf 自由导入、
  背景图与亚克力模糊、终端遮罩、光标三态。
- 每个设置项下方标注对应的 Ghostty 配置键,熟悉桌面 Ghostty 零学习成本。

## 项目结构

```text
.
├── AppScope/                # HarmonyOS 应用级配置
├── entry/                   # 应用模块
│   ├── src/main/ets/pages/Index.ets   # 主界面:标签栏 / 终端层 / 右侧检查器
│   ├── src/main/ets/drivers/          # WebSocket Agent 与 native driver 桥接
│   ├── src/main/ets/model/            # 会话句柄与跨窗口会话仓库
│   └── src/main/cpp/                  # N-API:本地 PTY、libssh2 SSH、SFTP
├── libghostty_ohos/         # 终端渲染 HAR(fork,见下文 Fork 说明)
│   ├── src/main/cpp/        # 渲染器 / 输入 / IME / 终端核心包装
│   └── prebuilt/            # libghostty-vt 预编译静态库
├── third_party/             # 按需拉取的 native 依赖(libssh2 / mbedTLS)
├── docs/                    # 协议、产品与维护文档
└── tools/                   # 依赖拉取与结构断言检查脚本
```

## 开发版与发布版

本项目不用同一目录反复切包名和签名,而是把开发与发布分成两个 Git worktree:

| 用途 | 目录 / 分支 | 应用标识 | 应用名称 |
| --- | --- | --- | --- |
| 日常开发与真机调试 | `/mnt/linux_share/preview/harmony-advanced-terminal` / `dev` | `com.preview.fusionterm.debug` | `Emberline Dev` |
| 稳定发布 | `/mnt/linux_share/preview/harmony-advanced-terminal-release` / `main` | `com.preview.fusionterm` | `Emberline` |

要选择 dev 版,在 DevEco Studio 直接打开第一个目录,并确认安装/启动日志中的
bundle 是 `com.preview.fusionterm.debug`。它可以和正式版并存,不会覆盖正式版。

发布时不要只在 dev 目录换一份签名。先在 `dev` 验证稳定,再把经过审查的提交
合入 `main`,到 release worktree 使用正式 bundle 与正式签名构建。设备上同一
bundle 若已由另一证书签名,会报 `install sign info inconsistent`;应确认构建
目录和签名身份,必要时卸载冲突安装后再装,而不是混用两套签名材料。

当前两个 `build-profile.json5` 都含本机绝对签名路径,不具备干净机器可复现性。
换 DevEco 主机时应生成/注入该主机或 CI 的签名配置,不得把真实密钥或口令
继续写进仓库;正式发布前必须关闭 CR-014。

## 使用方法

### 环境要求

- DevEco Studio(含 HarmonyOS SDK、native 工具链 CMake/Ninja)、`ohpm`。
- 真机安装需要签名配置(DevEco 自动签名即可;`READ_PASTEBOARD` 特权直贴
  需要 AGC 手工 ACL profile,可选)。
- Agent 会话需要 VM/远端 Linux 运行 `wand-agent`(见下文 fork 说明)。

### 构建

```sh
git clone <repo-url> emberline && cd emberline

# 当前 native 模块仍要求这些依赖(仅开发/验证;不要把此版本 SSH 带入发布)
bash tools/fetch-third-party.sh

ohpm install --all                # 安装 HarmonyOS 依赖(含本地 HAR 引用)
```

`tools/fetch-third-party.sh` 仍固定到 `libssh2-1.11.1`。根据
[`docs/code-review-2026-07-10.md`](docs/code-review-2026-07-10.md),发布前必须
将 SSH/SFTP 编译出包,或换成已审计的修复版本并补齐 SSH/SFTP 共用的主机密钥
校验。当前 SSH 入口只按开发原型处理。
复现时只连接隔离、可丢弃的测试端点,不要输入有价值的 SSH 凭据。

然后用 DevEco Studio 打开工程直接构建运行,或命令行:

```sh
hvigorw assembleHap --mode module -p product=default -p module=entry@default --no-daemon
```

工程的 `compatibleSdkVersion` 与 `targetSdkVersion` 固定为
`6.1.0(23)`(API 23);`compileSdkVersion` 不显式配置,跟随 DevEco Studio
配套 SDK。DevEco Sync 若提示 SDK version 无效,先确认本机已安装 HarmonyOS
6.1.0(API 23)SDK。该配置不再支持安装到 API 23 以下的设备。

改动 `libghostty_ohos/` 下的 C++ 后需要完整重编(HAR 会随 entry 一起构建)。

### 在融合开发引擎 Linux VM 部署 wand-agent(Agent 会话后端)

Agent 会话面向 HarmonyOS PC「融合开发引擎」(Fusion Development Engine)自带
的 Linux 虚拟机:VM 与宿主经桥接网络互通(VM 侧地址通常为
`172.16.100.2`),Emberline 通过 WebSocket PTY 直连,零上传共享目录、断线
自动重连。SSH 与本地 shell 无需任何服务端组件,可跳过本节。

**1. 一行安装并启动(VM 内)**

需要 Node.js 16 或以上。任选一个入口;三条命令都会识别已安装的 Go 版本,
版本过旧或未安装时自动下载带 SHA-256 校验的 Go 工具链,编译 agent,写入
systemd 服务并立即启动。示例 token 与 Emberline 默认值一致,只适用于可信的
虚拟机桥接网络:

```sh
# pnpm(推荐)
pnpm add -g github:BeforeUgone123/wand-agent && wand-agent service install --host 172.16.100.2 --token harmonyterm

# npm
npm install -g github:BeforeUgone123/wand-agent && wand-agent service install --host 172.16.100.2 --token harmonyterm

# curl
curl -fsSL https://raw.githubusercontent.com/BeforeUgone123/Emberline/main/tools/install-wand-agent.sh | sh -s -- --host 172.16.100.2 --token harmonyterm
```

安装器会把 agent 二进制复制到稳定目录,把 token 存入权限为 `0600` 的
EnvironmentFile,并输出 Emberline 要填写的端点和 token。省略 `--host` 会
自动探测融合开发引擎桥接地址;省略 `--token` 会生成随机 token。可先给任一
入口末尾加 `--dry-run` 预览,不写文件也不启动服务。

通用的服务检查命令:

```sh
sudo systemctl status wand-agent --no-pager
sudo journalctl -u wand-agent -f
```

npm/pnpm 全局安装还可用 `wand-agent doctor` 检查 Go、桥接
地址、缓存和 systemd。curl 入口只把服务所需二进制复制到稳定
目录,引导脚本退出后服务仍会继续运行。

**2. 手动源码构建(备用)**

不使用一行安装器时,按 `go.mod` 声明的 Go 版本手动构建:

```sh
git clone https://github.com/BeforeUgone123/wand-agent.git
cd wand-agent
go build -buildvcs=false -o wand-agent .
sudo install -m 755 wand-agent /usr/local/bin/
wand-agent --host 172.16.100.2 --token harmonyterm
```

默认监听 `8765` 端口、路径 `/ws`;`--host` 绑定 VM 桥接网卡地址。前台手动
运行时可用 `--shell /usr/bin/fish` 显式指定新会话的 shell。不指定时跟随
启动环境的 `$SHELL`。

**3. 手动配置 systemd(备用)**

先把 token 写入只有 root 可读的环境文件:

```sh
sudo install -d -m 755 /etc/wand-agent
printf 'WAND_AGENT_TOKEN=%s\n' 'harmonyterm' | sudo tee /etc/wand-agent/wand-agent.env >/dev/null
sudo chmod 600 /etc/wand-agent/wand-agent.env
```

```ini
# /etc/systemd/system/wand-agent.service
[Unit]
Description=wand-agent WebSocket PTY for Emberline
After=network-online.target

[Service]
EnvironmentFile=/etc/wand-agent/wand-agent.env
ExecStart=/usr/local/bin/wand-agent --host 172.16.100.2
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
```

```sh
sudo systemctl daemon-reload && sudo systemctl enable --now wand-agent
```

**4. 应用侧连接**

在 Emberline 右侧检查器「连接」页填入地址与 token(默认示例
`ws://172.16.100.2:8765/ws`),点「连接 Agent」;应用会自动记住并在下次
启动时重连。

应用内也内置了同一份部署教程。首次打开 Emberline 时会在已挂载的
终端上方弹出一次,可直接复制 pnpm/npm/curl 安装命令并进入连接
设置;关闭后不再自动弹出。以后可从顶栏「更多 → 帮助与诊断」重新打开,
命令可长按复制。

### 启用 Codex 任务完成提醒

Emberline 接收 OSC 9/BEL 后会让后台标签灯丝复燃,并发布 HarmonyOS 系统
通知。Codex CLI 不保证默认开启这条终端通知通道,因此需在运行 Codex 的
Linux VM 中把以下配置合并进 `~/.codex/config.toml`。如果文件里已有
`[tui]`,只添加三个键,不要再写一个同名表头:

```toml
[tui]
notifications = ["agent-turn-complete"]
notification_method = "osc9"
notification_condition = "always"
```

保存后退出正在运行的 Codex,再从 shell 执行 `codex resume --last` 恢复最近
会话。已经启动的 Codex 不会因为重载 tmux 配置而获得后来新增的 TUI 通知设置。
`always` 避免 Codex 的终端焦点判断吞掉完成事件。然后在 Emberline 顶栏
「更多 → 帮助与诊断 → Codex 任务提醒」点击「启用并测试」,在应用前台完成
系统通知授权和一次测试。测试使用可显示横幅的服务提醒通知渠道;提交成功后,
应用内会弹出确认,状态行会显示系统当前保留的通知数。若系统已接收但没有横幅,
请检查 Emberline 的通知渠道、横幅和免打扰设置;若授权或渠道已被关闭,状态行会
给出对应提示。当前标签在前台时会显示短暂的应用内完成提示;后台标签会复燃
灯丝并标为未读。两种情况都会进入系统通知链路。系统已启用跨设备通知且配对
手表支持时,通知可由 HarmonyOS 同步到手表;应用本身不绕过系统设置强制投递。
Codex 配置项以
[官方通知配置说明](https://developers.openai.com/codex/config-advanced#notifications)
为准。

如果在 tmux 内运行 Codex,还要允许 tmux 转发 Codex 使用的 passthrough
序列。在 `~/.tmux.conf` 中加入并重新加载:

```tmux
set -g allow-passthrough on
```

```sh
tmux source-file ~/.tmux.conf
```

系统通知测试通过后,还可在 Emberline 终端里运行下面的延迟命令,并在 5 秒内
切到其他标签或把应用退到后台。它不依赖 Codex,专门验证
`终端输出 → OSC 9 解析 → Emberline 系统通知` 这一段:

```sh
(sleep 5; if [ -n "$TMUX" ]; then printf '\033Ptmux;\033\033]9;Emberline Codex notification test\007\033\\'; else printf '\033]9;Emberline Codex notification test\007'; fi) &
```

如果按钮测试成功而该命令不提醒,应检查终端输出链路;如果两项都成功但 Codex
完成时不提醒,应检查运行 Codex 的那台机器所用的 `~/.codex/config.toml`。

**安全提示**:当前 token 鉴权只面向可信的 VM 桥接网络。更换随机 token 和
限制防火墙来源仍不足以把明文 `ws://` 安全暴露到公网;桥接网络外必须完成
配对、系统安全存储、Authorization-only 和 `wss://`/受保护隧道。

### 代码质量门

`tools/check-*.mjs` 是一组结构断言脚本(node 22.7+),钉住关键代码结构与
历史修复,任何结构性改动前建议全量跑一遍:

```sh
for f in tools/check-*.mjs; do node "$f" || exit 1; done
```

这些脚本只检查源码结构,不能替代 ArkTS 编译、codelinter、真机交互和
Profiler。Direction A 界面、后台 `taskKeeping` 与前台常亮策略在
2026-07-18 已进入 dev 工作树,但仍须在 DevEco 机器完成完整 HAP 构建及
720/960/1280/1600 vp、长 tmux 输出、后台、熄屏和多窗口真机矩阵。

当前已准备的 dev 工作树可通过全部 34 项;干净 clone 仍会因被忽略的
`docs/粘贴板Debug.p7b` 让 `check-terminal-paste.mjs` 失败。不要用 `|| echo`
吞掉它,应按 CR-013 修复测试夹具后再把这条命令作为 CI/发布门禁。

当前工程状态见 [`docs/handoff.md`](docs/handoff.md);发布阻塞项见
[`docs/code-review-2026-07-10.md`](docs/code-review-2026-07-10.md);已确认的
界面方向见
[`docs/frontend-brainstorm/2026-07-18-harmonyos-ui-ux-optimization/selected-direction.md`](docs/frontend-brainstorm/2026-07-18-harmonyos-ui-ux-optimization/selected-direction.md)。

## Fork 说明

本项目基于两个上游仓库的 fork,修改如下:

### 1. `libghostty_ohos/` — fork 自 [wiedymi/libghostty-ohos](https://github.com/wiedymi/libghostty-ohos)

上游提供了 libghostty-vt 在 HarmonyOS 上的基础渲染 HAR;本项目不再维护独立
fork 仓库,全部渲染层改动以内置形式随本仓库的 `libghostty_ohos/` 演进。相对上游
的大规模重写与扩展主要包括:

- **渲染器**:脏行级重绘 + 持久离屏缓冲;视口滚动改 scroll-damage(离屏
  memmove 位移复用,只重绘新露出的行);endFrame 按轮转缓冲的脏行差量上屏
  并向合成器上报真实 dirtyRegion;像素级平滑滚动(blit 亚行偏移 + 输入线
  程像素池);字形缓存与生命周期加固(修复多起 UAF 崩溃);字宽由排版引擎
  实测(消除整数取整的累计漂移);光标活动门控。
- **输入**:触控板双指滚动(ToolType 正向路由 / 惯性 / 120Hz 节拍);触屏
  fling、长按选择、选择拖拽边缘自动滚动;鼠标拖选 / 双击选词 / 三击选行;
  tmux/vim 鼠标协议桥(触屏合成鼠标);物理键盘快捷键与 DECCKM 应用光标键。
- **IME**:基于 InputMethod C API 的自定义编辑框接入,含焦点管理、
  生命周期加固(proxy 退休列表)与跨进程调用节流。
- **终端核心包装**:选区视口位移补偿与绝对坐标跨屏文本提取;OSC 52 剪贴板
  捕获;OSC 9 / BEL 通知事件;回看搜索;滚动条状态;标题与通知事件 drain。
- **ETS 层**:TerminalController / TerminalSurface 重做(输出直连跨 so
  投递、后台标签轮询门控、滚动条 overlay、安全粘贴)。

### 2. VM Agent — fork [BeforeUgone123/wand-agent](https://github.com/BeforeUgone123/wand-agent)(基于 [ystyle/wand-agent](https://github.com/ystyle/wand-agent) v0.2.3)

推荐使用加固 fork,相对上游的修改:WebSocket frame routing、Bearer 鉴权、
Origin 检查、会话数限制、进程组清理、`exit` 事件与心跳行为、PTY 环境净化
(剔除启动环境泄漏的 `NO_COLOR`)与 `--shell` 显式默认 shell,以及新增的
`upload-relay` 控制消息(把共享目录里的文件 `scp` 转发到 tailnet 主机,
供图片「中继」粘贴使用;源文件限定共享目录内 ≤64MB,目标与目录严格校验、
参数按 argv 传递不经 shell)。应用同时保持对 stock 协议的兼容。

## 开源协议

本项目以 **MIT 协议**发布,见根目录 [LICENSE](./LICENSE)。

第三方组件保留各自协议:

| 组件 | 来源 | 引入方式 | 协议 |
| --- | --- | --- | --- |
| libghostty-ohos | fork 自 `wiedymi/libghostty-ohos` | 内置于 `libghostty_ohos/` | MIT(`libghostty_ohos/LICENSE`) |
| libghostty-vt | `ghostty-org/ghostty` | 预编译静态库 `libghostty_ohos/prebuilt/` | MIT |
| wand-agent | `ystyle/wand-agent` 及其 fork | VM 侧独立部署,不随应用分发 | MIT |
| libssh2 | `libssh2/libssh2` `libssh2-1.11.1` | 脚本拉取到 `third_party/` | BSD-3-Clause |
| mbedTLS | `Mbed-TLS/mbedtls` `mbedtls-3.6.6` | 脚本拉取到 `third_party/` | Apache-2.0 |
| Maple Mono 等内置字体 | 各自上游 | 打包于 HAR rawfile | 各自开源字体协议(OFL 等) |

## 致谢

- [Ghostty](https://ghostty.org) — 世界级的终端仿真内核与 458 套主题。
- [wiedymi/libghostty-ohos](https://github.com/wiedymi/libghostty-ohos) —
  HarmonyOS 移植的起点。
- [ystyle/wand-agent](https://github.com/ystyle/wand-agent) — 轻量 WebSocket
  PTY agent。
