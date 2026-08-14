# Project Context — Emberline(dev worktree)

> 扫描日期:2026-07-21。为重设计提供的实现边界摘要。

## 产品

Emberline:HarmonyOS 开发者终端。首要任务是通过 wand-agent 兼容 WebSocket PTY 连接
Fusion Development Engine Linux VM(默认 `ws://172.16.100.2:8765/ws`,token `harmonyterm`,
`TERM=xterm-256color`, `COLORTERM=truecolor`)。目标气质:Ghostty 式桌面级终端,不是 demo 页。
目标设备:2-in-1(MatePad Edge 类),物理键盘 + 触控,120Hz opt-in。

## 技术栈与构建

- HarmonyOS ArkTS / ArkUI(声明式),`hvigorw` 构建,SDK 5.0.0(12),bundle `com.preview.fusionterm.debug`。
- 渲染器:vendored `libghostty_ohos` HAR(XComponent + `libghostty_vt.a`),终端渲染不在 ArkUI 层。
- 本工作区无 DevEco/SDK,不能编译 HAP;结构检查:`tools/check-*.mjs`(34 个)。
- JS 包管理用 pnpm。

## 现状代码结构(entry/src/main/ets/)

- `pages/Index.ets`(4229 行):全部工作区 UI——标题 rail、tab strip、inspector、溢出菜单、
  连接流程、主题预览。旧视觉身份的 M01–M28 动效与灯丝实现都在这里,重设计落地时将被重写/替换。
- `theme/EmberMotion.ets`:动效 token 单一来源(时长/曲线/弹簧/帧率档 + 不做清单)。新身份应保留
  「token 集中 + 无裸数字」的纪律,token 值可按新身份重定。
- `common/EmberHaptics.ets`:触觉反馈(ignite/disconnect/boundary)。签名元素可换,触觉模型可留。
- `model/TerminalSession.ets`、`model/SessionRegistry.ets`:会话状态机(connecting/connected/failed/
  unread-complete 等),UI 状态语义不变。
- `settings/AppearanceStore.ets`、`settings/ConnectionStore.ets`:外观与连接配置持久化。
- `drivers/FusionAgentDriver.ets` 等:传输层,与 UI 重设计无关。

## 当前视觉身份(将被替换)

近黑 `#050507` 底 + 余烬铜 `#D08F53` 灯丝(ignite/extinguish/breathe 生命体征)。全部存档,
新方向不得复用铜色与灯丝签名。

## 实现限制(ArkUI 翻译边界)

- 终端画布上方禁玻璃模糊/渐变叠加/常驻合成动画(XComponent 渲染抢帧红线)。
- 动画仅 opacity/translate/rotate/颜色;布局属性逐帧补间禁止。
- CJK 文字组件禁 scale;字体:chrome 用 HarmonyOS Sans(系统),终端与读数用等宽。
- 图标用 HarmonyOS Symbol 资源;生产端无 web 图标库,预览可用内联 SVG 近似。
- 多窗口、后台停轮询;UI 状态更新不得被终端字节吞吐驱动。

## 既有 UX 结构(保留,重设计只换皮与签名)

- 48vp rail:左 tabs(可横向滚动/拖拽重排/中键关闭/右键菜单),右三动作(连接/设置/溢出)+ 系统窗控件。
- inspector overlay:352vp(<900vp)/400vp,三目的地 终端/外观/连接,行式设置(label 左、控件右,
  紧凑宽度下控件折行),高级项默认折叠。
- 连接状态语义:disconnected / connecting / connected / retrying / auth-failure / transport-failure;
  内联 retry + details。
- tab 状态语义:inactive/hover/focused/active/pending/connected/failed/unread-complete/dragging。
- 通知:OSC 9 → 系统通知;可见活跃 tab 显示完成 toast。
