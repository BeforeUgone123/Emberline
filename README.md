# Emberline

**鸿蒙上的完整伪终端。**

Emberline(原名 FusionTerm)是一款 HarmonyOS 原生终端模拟器,内核移植自
[Ghostty](https://ghostty.org) 的终端引擎(libghostty-vt)。它不是 WebView
套壳,也不是简化的命令行玩具——从 PTY 到转义序列解析再到逐格渲染,走的都是
桌面级终端的完整链路。为 HarmonyOS 2in1 设备(键盘 + 触控板 + 触屏三形态)
设计,像桌面终端一样严肃,像移动应用一样顺手。

界面只有一种颜色会发光:标签底缘那根**余烬铜灯丝**——亮着,你的会话就活着。

> 本项目不是对上游的简单打包:渲染 HAR fork([libghostty-ohos](#1-libghostty_ohos--fork-beforeugone520libghostty-ohos基于-wiedymilibghostty-ohos))
> 经过深度重写——滚动性能三件套(scroll-damage / buffer-age / 像素级平滑滚
> 动)、完整的触控板 + 触屏 + 鼠标输入体系、系统 IME 接入以及多起内存安全
> 加固都在 fork 中完成;VM 侧 [wand-agent fork](#2-vm-agent--fork-beforeugone520wand-agent基于-ystylewand-agent-v023)
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
  按脏行上屏(buffer-age),2.5K 屏长输出不掉帧。
- 像素级平滑滚动:触屏 / 触控板逐像素跟手,松手惯性,选择拖到屏幕边缘
  自动滚动续选,跨屏长复制完整无缺。
- 字宽实测排版(非估算系数),任意字号下字距、光标、选区严格对齐;
  中文等宽(默认 Maple Mono NF CN)无缺字。
- 打字或有输出时光标保持实心,空闲才闪烁。

**连接**

- 三类会话统一多标签:本地 shell、SSH(libssh2)、WebSocket Agent
  (兼容 `wand-agent` 协议,面向 Fusion Development Engine Linux VM)。
- 断线指数退避自动重连,断开后敲任意键立即重试;taskKeeping 后台保活,
  切走 app 会话不断线。
- 标签:动态宽度、轨道内拖动重排(按住即拖、邻居实时让位)、右键菜单
  改名与关闭、自定义灯丝颜色;关闭标签不打断远端 tmux 里正在跑的任务。

**输入与剪贴板**

- 外接键盘:Ctrl+Shift+C / Ctrl+V 复制粘贴,Ctrl+C 永远是中断信号;
  纯触屏有辅助键条(Esc / Tab / ^C / 复制 / 粘贴 / 方向键)。
- 截图直达终端:任意处截图后 Ctrl+V,按会话视角粘出可用路径——本地给
  本地路径、VM 会话走共享目录零上传、SSH 经 SFTP 送达远端,支持逐标签
  覆盖粘贴视角。
- 图片「中继」视角:在 Agent 会话里 ssh 到 tailnet 上的另一台机器后,
  粘贴的图片由 wand-agent 从共享目录 `scp` 转发到该机(右键标签 →
  标签设置 → 图片粘贴视角 → 中继,填目标机与远端目录),终端里直接粘出
  目标机上的路径。前提:VM 可免交互 ssh 到目标机(Tailscale SSH ACL
  `accept` 或已装密钥);任何失败会回退为共享路径并在终端说明原因。
- 中文 IME 完整支持(native 自定义编辑框)。

**自定义**

- 458 套 Ghostty 主题(真色板预览)、五款内置等宽字体 + ttf/otf 自由导入、
  背景图与亚克力模糊、光标三态。
- 每个设置项下方标注对应的 Ghostty 配置键,熟悉桌面 Ghostty 零学习成本。

## 项目结构

```text
.
├── AppScope/                # HarmonyOS 应用级配置
├── entry/                   # 应用模块
│   ├── src/main/ets/pages/Index.ets   # 主界面:标签栏 / 终端层 / 设置抽屉
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

## 使用方法

### 环境要求

- DevEco Studio(含 HarmonyOS SDK、native 工具链 CMake/Ninja)、`ohpm`。
- 真机安装需要签名配置(DevEco 自动签名即可;`READ_PASTEBOARD` 特权直贴
  需要 AGC 手工 ACL profile,可选)。
- Agent 会话需要 VM/远端 Linux 运行 `wand-agent`(见下文 fork 说明)。

### 构建

```sh
git clone <repo-url> emberline && cd emberline

# 可选:构建 SSH/SFTP 支持需要 native 依赖(仅首次)
bash tools/fetch-third-party.sh   # 拉取 libssh2-1.11.1 与 mbedtls-3.6.6

ohpm install --all                # 安装 HarmonyOS 依赖(含本地 HAR 引用)
```

然后用 DevEco Studio 打开工程直接构建运行,或命令行:

```sh
hvigorw assembleHap --mode module -p product=default -p module=entry@default --no-daemon
```

改动 `libghostty_ohos/` 下的 C++ 后需要完整重编(HAR 会随 entry 一起构建)。

### 在融合开发引擎 Linux VM 部署 wand-agent(Agent 会话后端)

Agent 会话面向 HarmonyOS PC「融合开发引擎」(Fusion Development Engine)自带
的 Linux 虚拟机:VM 与宿主经桥接网络互通(VM 侧地址通常为
`172.16.100.2`),Emberline 通过 WebSocket PTY 直连,零上传共享目录、断线
自动重连。SSH 与本地 shell 无需任何服务端组件,可跳过本节。

**1. 安装(VM 内,二选一)**

方式 A — 从源码构建(需要 Go 1.21+):

```sh
git clone https://github.com/beforeugone520/wand-agent.git
cd wand-agent
go build -o wand-agent .
install -m 755 wand-agent /usr/local/bin/
```

方式 B — 直接部署预构建二进制:把构建好的 `wand-agent` 拷进 VM(如经共享
目录),放到 `/usr/local/bin/` 并 `chmod +x`。

**2. 运行**

```sh
wand-agent --host 172.16.100.2 --token <你的token>
```

默认监听 `8765` 端口、路径 `/ws`;`--host` 绑定 VM 桥接网卡地址,`--token`
是 Bearer 鉴权令牌(应用侧需填一致);`--shell /usr/bin/fish` 可显式指定
新会话的默认 shell(不指定时跟随启动环境的 `$SHELL`,从 ssh 一行命令或
systemd 启动时往往不是你交互用的那个,建议显式指定)。前台跑通后建议改为
systemd 常驻:

```ini
# /etc/systemd/system/wand-agent.service
[Unit]
Description=wand-agent WebSocket PTY for Emberline
After=network-online.target

[Service]
ExecStart=/usr/local/bin/wand-agent --host 172.16.100.2 --token <你的token>
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
```

```sh
systemctl daemon-reload && systemctl enable --now wand-agent
```

**3. 应用侧连接**

在 Emberline 设置抽屉「连接」页填入地址与 token(默认示例
`ws://172.16.100.2:8765/ws`),点「连接 Agent」;应用会自动记住并在下次
启动时重连。

应用内也内置了同一份部署教程:首次启动会弹出引导,之后在侧栏「帮助」页
常驻,可长按复制命令。

**安全提示**:token 鉴权面向可信的 VM 桥接网络;若把 agent 暴露到桥接网络
之外,请更换强随机 token 并配合防火墙限制来源。

### 代码质量门

`tools/check-*.mjs` 是一组结构断言脚本(node 22.7+),钉住关键代码结构与
历史修复,任何结构性改动前建议全量跑一遍:

```sh
for f in tools/check-*.mjs; do node "$f" || echo "FAIL: $f"; done
```

## Fork 说明

本项目基于两个上游仓库的 fork,修改如下:

### 1. `libghostty_ohos/` — fork [beforeugone520/libghostty-ohos](https://github.com/beforeugone520/libghostty-ohos)(基于 [wiedymi/libghostty-ohos](https://github.com/wiedymi/libghostty-ohos))

上游提供了 libghostty-vt 在 HarmonyOS 上的基础渲染 HAR;fork 仓库承载本项目
的全部渲染层改动,并以内置形式随本仓库的 `libghostty_ohos/` 演进。相对上游
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

### 2. VM Agent — fork [beforeugone520/wand-agent](https://github.com/beforeugone520/wand-agent)(基于 [ystyle/wand-agent](https://github.com/ystyle/wand-agent) v0.2.3)

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
| libghostty-ohos | fork `beforeugone520/libghostty-ohos`(上游 `wiedymi/libghostty-ohos`) | 内置于 `libghostty_ohos/` | MIT(`libghostty_ohos/LICENSE`) |
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
