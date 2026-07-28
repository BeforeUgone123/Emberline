# Emberline Direction A 最终实施提示

> **执行状态(2026-07-18):**本文件是已执行的实施契约,不是新的待办提示。
> Direction A 已进入 `dev` 工作树并由 33 个源码结构检查保护;完整 HAP 构建、
> codelinter、真机视口/输入/性能/功耗矩阵尚未执行。当前事实以
> [`project-context.md`](project-context.md)、根 `AGENTS.md` 和
> `docs/handoff.md` 为准。

## 目标

在 `/mnt/linux_share/preview/harmony-advanced-terminal` 的 `dev` 工作区实现已确认的
**Harmony Native Workbench**。把 Emberline 打磨成键盘、鼠标、触控板和自由窗口体验完整的
HarmonyOS 2-in-1 原生终端，同时保持稳定版终端渲染、传输和长 tmux 输出性能。

最终结果必须是实际可用的终端工作区，不是营销页、设置首页或仪表盘。启动后默认只显示
终端和紧凑顶栏，检查器默认关闭。

## 开始前必读

1. 根目录 `AGENTS.md`，尤其是产品边界、动效不做清单和无快捷键栏决定。
2. `docs/frontend-brainstorm/2026-07-18-harmonyos-ui-ux-optimization/selected-direction.md`。
3. `docs/frontend-brainstorm/2026-07-18-harmonyos-ui-ux-optimization/design-brief.md`。
4. `docs/frontend-brainstorm/2026-07-18-harmonyos-ui-ux-optimization/preview/index.html`。
5. `docs/frontend-brainstorm/2026-07-18-harmonyos-ui-ux-optimization/preview/notes.md`。

HTML 预览只用于视觉与交互校准，不允许直接把 HTML/CSS/JavaScript 搬进 ArkUI。

## 当前工程事实

- 技术栈：ArkTS、ArkUI、Stage 模型、原生 XComponent。
- 主工作区：`entry/src/main/ets/pages/Index.ets`。
- 终端渲染：`libghostty_ohos`，必须继续作为独立 HAR。
- 当前 Dev 包：`com.preview.fusionterm.debug`，标签 `Emberline Dev`。
- SDK 继续保持稳定配置 `5.0.0(12)`；不得借 UI 改造升级 compile/compatible/target SDK。
- 发布工作区 `/mnt/linux_share/preview/harmony-advanced-terminal-release` 不得修改。
- 工作区可能已有用户改动；不得还原、覆盖或格式化无关文件。

## 严格非目标

- 不修改 Fusion Agent、SSH、本地 PTY、WebSocket 协议、重连算法或终端字节流。
- 不修改 `libghostty_ohos`、C++、N-API、终端输出批处理、滚动或渲染路径。
- 不修改 `KeepAliveManager.ets`、后台连续任务、`EntryAbility` 前台常亮逻辑。
- 不修改包名、签名、`build-profile.json5`、`AppScope/app.json5` 或发布配置。
- 不添加快捷键栏、底部工具栏、首页、卡片仪表盘、玻璃背景、渐变或常驻装饰动画。
- 不以重写整个 `Index.ets`、引入新 UI 框架或大范围组件拆分作为前置条件。

## 实施范围

### 1. 终端优先启动

- 应用首帧直接进入终端工作区，检查器关闭。
- 移除首次启动自动弹出的 wand-agent 大面板；部署指南仍须从“更多 -> 帮助与诊断”访问。
- 默认 Fusion Agent 自动连接逻辑保持不变。连接失败可在失败发生后打开连接检查器一次，但
  不得用模态页替换终端。
- 删除不再需要的 onboarding 状态和测试时，先确认没有其它代码依赖；不要留下死字段和死存储。

### 2. 顶栏

- 保持 48 vp 高度和系统窗口按钮保留区。
- 标签区继续横向滚动，新建会话 `+` 紧邻标签，调用现有 `addSession(true)`。
- 标签区之后只能有三个永久应用操作：`连接`、`设置`、`更多`。
- 完整删除键盘图标、`accessoryVisible`、`buildAccessoryBar()`、`sendAccessoryKey()` 及其入口。
- 删除独立帮助按钮；帮助、诊断、部署指南和关于信息移入“更多”菜单。
- “更多”菜单中的“新建窗口”复用现有 `openNewWindow()`，不要重新实现窗口启动。
- 图标优先使用当前 SDK 支持的 HarmonyOS Symbol；若 API 12 类型不支持，再增加与现有图标
  风格一致的单色资源。所有图标必须有语义标签和悬浮提示。

### 3. 会话标签

- 保留现有连接灯丝、未读完成、拖动排序、拖出窗口、右键/长按编辑和关闭生命周期。
- 状态必须覆盖：未连接、连接中、已连接、失败、后台任务完成、选中、拖动。
- 颜色之外必须同时有文字或语义状态，灰度模式下仍可辨识。
- 切换终端内容必须保持 0 ms；只允许标签面、边框和灯丝在 chrome 内反馈。
- 关闭图标不能在 hover/选中时改变标签宽度；所有动态内容不得造成顶栏布局跳动。

### 4. 右侧检查器

- 继续使用覆盖式右侧面板，不挤压或动画改变终端 XComponent 尺寸。
- 默认关闭；连接和设置按钮打开它，再次选择已打开的目标可保持或关闭，但行为必须一致。
- 顶部只保留三个目的地：`终端`、`外观`、`连接`。
- 结构使用全宽区带和细分隔线，不把设置组做成嵌套卡片。
- 面板外的终端区域可以点击关闭，但检查器打开期间所有键盘、鼠标、触控板和触摸输入都不得
  穿透到 XComponent。
- 检查器关闭后必须恢复当前终端焦点和原生 IME 状态。

目的地映射：

- `终端`：字号、字体、光标样式、光标闪烁。
- `外观`：主题搜索/列表、主题预览、背景图片、遮罩和模糊。
- `连接`：Fusion Agent 状态和端点；SSH、本地、共享目录、上传/中继等高级项默认折叠。

原 `字体`、`主题`、`帮助` 不再作为一级检查器目的地。

### 5. 控件语义

- 光标样式使用分段控件语义。
- 光标闪烁使用 Switch。
- 字号使用固定尺寸步进器和读数；终端 reflow 瞬时完成。
- 透明度/模糊使用 Slider。
- 字体、粘贴模式和较长枚举使用菜单、单选行或明确的选择组件。
- 只有命令使用文字按钮；复制、关闭、新建、设置、连接等使用熟悉图标。
- 可见控件圆角限定 4/6/8 vp；不使用通用 pill、厚阴影或浮动卡片。

### 6. 响应式规则

- 使用根工作区 `onAreaChange` 或项目 SDK 已支持的等效方式记录实际窗口宽度。
- `720-899 vp`：检查器 352 vp，缩小顶栏间距，标签继续滚动。
- `900 vp` 及以上：检查器 400 vp。
- `1280 vp` 及以上本轮仍默认覆盖，不实现永久固定侧栏或 Direction C 会话轨。
- 不对 width、height、margin、padding、fontSize、constraintSize 或 flex 做逐帧补间。
- 720、960、1280、1440/1600 vp 下不得出现重叠、横向溢出或文字遮挡。

### 7. 颜色与字体

- 基础层：`#050507`；顶栏：`#080B10`；检查器：`#10141B`；选中面：`#151A22`。
- 主文字约 `#D7DDEA`，次文字约 `#8D97A8`，边框约 `#252D39`。
- 余烬铜 `#D08F53` 只用于灯丝、选中细指示、焦点强调和主操作。
- 小型成功/失败图标或文字可使用语义色，但必须同时提供状态文案。
- 应用 chrome 使用 HarmonyOS Sans/系统字体；终端和字体预览使用用户选择的等宽字体。
- 所有应用 chrome 的 letter spacing 为 0；删除现有分组标题的非零 `letterSpacing`。

### 8. 键盘、焦点与指针

- 保留终端语义：XComponent 聚焦时，`Tab`/`Shift+Tab` 必须发送给远程终端，不能进入顶栏。
- 增加明确的桌面焦点路径，例如 `F6` 在终端、顶栏和已打开检查器之间循环。
- 检查器内部打开后才使用逻辑焦点顺序；`Esc` 关闭最上层菜单/检查器并恢复终端焦点。
- 不要简单删除所有 `.focusable(false)`；先建立不会劫持终端按键的显式焦点模型。
- 指针需具备 hover、pressed、selected/open、disabled 状态；禁止 hover scale。
- 右键标签、触屏长按、tmux 鼠标和终端选择协议必须保持现状。
- 紧凑图标可见尺寸约 32 vp，但触控响应区不得小于约 40 vp。

### 9. 状态、错误和恢复

- 连接检查器至少呈现：断开、连接中、已连接、重连、认证失败、传输失败。
- 第一行是目标和状态，第二行是端点、延迟或简短错误。
- 失败状态在同一检查器内提供“重试”和“详细信息”，不弹阻断式错误页。
- `重新连接` 的 pending 动效只在实际 pending 状态运行，完成/失败/隐藏/后台后立即停止。
- 主连接路径始终是 Fusion Agent；SSH 和本地入口保持备用层级。

### 10. 动效与性能

- 复用 `EmberMotion.ets` token，不在 builder 中散落新时长/曲线。
- 检查器进入/退出只用 opacity + translate，约 180-220 ms；不模糊终端，不做整屏渐变暗幕。
- 标签切换、主题切换、字号和栅格 reflow 全部瞬切。
- 含 CJK 文案组件禁止 scale。
- 不增加 `setInterval`、自建 rAF、粒子或常驻背景循环。
- 连接呼吸等循环必须在面板关闭、状态结束和应用后台时停止。
- 主题列表和预览改为按需/分批加载或虚拟化，打开面板时不得同步解析全部主题造成卡顿。
- 终端字节输出不得驱动 ArkUI 组件重渲染或 chrome 动效。

## 文件边界

优先允许修改：

- `entry/src/main/ets/pages/Index.ets`
- `entry/src/main/ets/theme/EmberMotion.ets`，仅在确实缺少共享 token 时
- `entry/src/main/resources/base/media/`，仅增加必要的更多菜单图标资源
- `entry/src/main/resources/base/element/string.json`，仅增加实际 UI 文案
- `entry/src/main/ets/settings/OnboardingStore.ets`，仅在移除自动 onboarding 后清理
- `tools/check-*.mjs`，增加方向 A 门禁并更新被有意改变的旧断言

禁止因本任务修改：

- `libghostty_ohos/**`
- `entry/src/main/cpp/**`
- `entry/src/main/ets/drivers/**`
- `entry/src/main/ets/common/KeepAliveManager.ets`
- `entry/src/main/ets/entryability/EntryAbility.ets`
- `entry/src/main/module.json5`
- `build-profile.json5`、`AppScope/app.json5` 和任何签名材料
- release 工作区

在交互测试稳定前不要把整个 `Index.ets` 拆成新架构。后续若抽组件，只抽纯 UI 与回调契约，
会话状态、驱动和 renderer 仍由 `entry` 现有边界持有。

## 测试先行

先新增一个会失败的 `tools/check-harmony-native-workbench.mjs`，至少覆盖：

- 不存在 `accessoryVisible`、`buildAccessoryBar`、`sendAccessoryKey` 和 `ic_keyboard` 引用。
- 顶栏中标签/新建之后只有连接、设置、更多三个永久应用操作。
- 帮助与部署指南仍可从更多菜单到达，`openNewWindow()` 被复用。
- 检查器只有 `终端/外观/连接` 三个一级目的地。
- 默认工作区不自动打开 onboarding 或检查器。
- 352/400 vp 宽度分支存在且不通过布局动画实现。
- inspector 打开时 TerminalSurface `active` 为 false，关闭后恢复焦点。
- chrome 没有非零 letter spacing、CJK scale、全屏 blur 或快捷键栏。

同步更新旧检查：

- `tools/check-terminal-ime-anchor.mjs`：删除快捷键栏存在性断言，改为验证快捷键栏不存在；保留
  XComponent 焦点、IME、输入阻断和恢复断言。
- `tools/check-agent-setup-guide.mjs`：从“首次启动覆盖层 + 帮助页”改为“更多菜单中的帮助/部署入口”；
  仍验证完整安装、systemd、连接步骤和可复制命令只维护一份。
- `tools/check-window-chrome-integration.mjs`：继续保护 48 vp 顶栏、系统窗口按钮保留区和标题栏融合。
- 其它已有检查不得为了通过而删除真实功能保护。

实施完成后运行：

```sh
for check in tools/check-*.mjs; do node "$check" || exit 1; done
git diff --check
```

## DevEco 与真机验证

在具有 HarmonyOS SDK 的 DevEco 主机完成：

1. Sync 后构建 `product=default`、`entry@default`、`buildMode=debug`。
2. 确认安装日志启动的是 `com.preview.fusionterm.debug`，不得覆盖正式版。
3. 在 720、960、1280、1440/1600 vp 自由窗口宽度截图。
4. 验证全屏、分屏、自由窗口、最小化恢复和多个 Emberline 窗口。
5. 用键盘、鼠标、触控板、触屏分别走完标签、检查器、连接和关闭流程。
6. 验证终端聚焦时 `Tab`、方向键、Ctrl 组合、tmux 鼠标和 IME 没有回归。
7. 打开长 tmux 输出，同时反复打开/关闭检查器、切换标签和缩放窗口。
8. 用 DevEco Profiler 比较改造前后 CPU、GPU、帧时间、内存和功耗；不能接受稳定版不存在的卡顿。
9. 连接任务运行时进入后台和熄屏，确认会话保活；回前台确认常亮和焦点恢复。

## 完成标准

- 启动直接进入可用终端，默认无检查器和 onboarding 模态页。
- 完全不存在快捷键栏和键盘入口。
- 标签区后恰好三个永久应用操作：连接、设置、更多。
- 右侧检查器只有终端、外观、连接三类，信息层级与已确认预览一致。
- 720/960/1280/1440/1600 vp 无重叠、裁切或横向溢出。
- 面板、菜单和编辑器输入不穿透 XComponent，关闭后终端焦点恢复。
- 终端 Tab 语义、IME、tmux 鼠标、复制粘贴、标签拖动和多窗口行为不回归。
- 所有连接状态有文本、恢复动作和停止条件，颜色/动画不是唯一信息。
- 所有静态检查、完整 HAP 构建和真机矩阵均通过。
- 长 tmux 输出性能不低于回归前稳定版。
- diff 不包含 renderer、驱动、签名、保活或发布工作区的无关修改。

交付时报告：修改文件、视觉/交互变化、测试命令与结果、DevEco 构建结果、真机矩阵结果、
已知剩余风险。不要在未运行相应验证时声称构建、性能或真机体验已经通过。
