# Emberline 动效规范 v1

> 2026-07-18:本文保留为第一版动效研究与编号来源,不是待办清单。当前实现
> 以根 `AGENTS.md` 的动效不做清单、Direction A
> `docs/frontend-brainstorm/2026-07-18-harmonyos-ui-ux-optimization/design-brief.md`
> 和源码为准。
> M13(屏幕快捷键条)、全屏 dim scrim、抽屉推挤终端、主题暗幕、布局尺寸补间
> 已被明确否决;看到下文旧方案不得重新实现。所有现有动效仍待真机长 tmux
> 输出与后台功耗验证。

> 适用:HarmonyOS 原生终端模拟器 Emberline / MatePad Edge(2in1,120Hz,键盘+触控板+触屏)
> 气质基线:近黑三层(#07090C/#0D1117/#1C232E)、唯一强调色「余烬铜」#D08F53、签名隐喻=灯丝(亮/半亮/灰烬)。
> **裁决五原则**:①每个动效必须传达一个状态(连接/断开/连接中/失败/完成/选中/切换),答不出即砍;②高频路径宁快勿花;③终端渲染层(XComponent/reflow)动效从严,默认瞬切;④含 CJK 文字组件禁 `transform scale`,一律 `opacity + translateY`;⑤强调色动效只出现在灯丝与主按钮。

本规范对四路调研做了去重与冲突裁决,关键归并点:
- **时长收敛**:散落的 200/240 全部并入 `DUR_STANDARD = 220`;灯丝的非对称档单列。
- **灯丝分两类**:①「连接态灯丝」(标签底缘 2px)享全套签名(点燃/呼吸/熄灭/失败);②「选中态灯丝」(抽屉导航/主题行/字体卡/连接面)只做统一的颜色+辉光补间,不呼吸。此前四路把两类混谈,本规范拆开。
- **弹簧只留两处**:手势跟手(过阻尼零回弹)、点燃回落(唯一允许极小 overshoot)。禁止 ambient 循环用弹簧。
- **粒子/smooth-caret/终端调色板 tween/geometryTransition** 归入不做或延后。

---

## 1. Motion Tokens

新建 `entry/src/main/ets/theme/EmberMotion.ets`,所有 builder 只引常量,禁止再写裸数字。这是后续所有条目的地基。

### 1.1 时长档 + 曲线档 + 弹簧档 + 帧率档

```typescript
// entry/src/main/ets/theme/EmberMotion.ets
import curves from '@ohos.curves'

/* ── 时长档 (ms) ─────────────────────────────── */
export const DUR_INSTANT  = 0    // 瞬切:终端切标签 / reflow / 高频输入。禁补间。
export const DUR_FAST     = 120  // 即时应答:选中面/边框、chrome 交接、边界反馈、色板选中环
export const DUR_STANDARD = 220  // 容器级转场:抽屉、面板 crossfade、辅助键、scrim、浮层(收编旧 200/240)
export const DUR_AMBIENT  = 250  // 环境层:背景图淡入淡出(略慢,宜缓)

/* 灯丝签名专用(刻意非对称:亮得快、灭得慢)*/
export const DUR_IGNITE_FLASH    = 90   // 点燃猛闪
export const DUR_IGNITE_SETTLE   = 300  // 点燃弹簧回落
export const DUR_EXTINGUISH_HOLD = 120  // 熄灭:余温滞留
export const DUR_EXTINGUISH_COOL = 700  // 熄灭:慢慢冷透
export const DUR_BREATHE_HALF    = 1300 // 呼吸半周期(整周期 2.6s)

/* ── 曲线档 ─────────────────────────────────── */
export const CURVE_DECEL = curves.cubicBezierCurve(0.2, 0, 0, 1) // 进场/转场默认:快起慢停、零回弹
export const CURVE_ACCEL = curves.cubicBezierCurve(0.4, 0, 1, 1) // 退场:加速离开、干脆无残留
export const CURVE_SHARP = curves.cubicBezierCurve(0.33, 0, 0, 1)// 微反馈(FAST 档):即时应答
export const CURVE_SINE  = Curve.EaseInOut                       // 呼吸/ambient:正弦感

/* ── 弹簧档(全项目仅两处,专款专用)──────────── */
export const SPRING_DRAG   = curves.responsiveSpringMotion(0.25, 0.92) // 手势跟手:过阻尼、零回弹
export const SPRING_SETTLE = curves.springMotion(0.34, 0.84)           // 点燃回落:临界略欠阻尼、极小 overshoot

/* ── 帧率档(MatePad Edge 120Hz opt-in)──────── */
export const FRAME_120: ExpectedFrameRateRange = { min: 60, max: 120, expected: 120 } // fling/手势跟手
export const FRAME_60:  ExpectedFrameRateRange = { min: 30, max: 60,  expected: 60  } // 呼吸等 ambient,省电
```

**曲线裁决**:进/退场刻意非对称(桌面级「来时轻声、走时利落」)——进场 `CURVE_DECEL` 减速停靠,退场 `CURVE_ACCEL` 加速消失。微反馈用 `CURVE_SHARP`。呼吸用 `CURVE_SINE`。默认转场不用弹簧、不用 `EaseInOut`(那是给氛围的)。

**弹簧裁决**:`SPRING_DRAG` 阻尼系数 0.92(过阻尼、零 overshoot)是本项目区别于 Material 弹跳风的分水岭——弹跳=玩具感,与桌面严肃冲突。`SPRING_SETTLE` 是全项目唯一允许极小 overshoot 的地方,因为它服务「火苗被引着又稳下来」的物理感,专款专用。

**帧率裁决**:不无脑全 120。只有高速位移(fling 惯性、手势跟手抽屉)挂 `FRAME_120`;呼吸等慢速氛围动画压到 `FRAME_60` 省电。其余交系统默认。

### 1.2 触觉配对

新建 `entry/src/main/ets/common/EmberHaptics.ets`,收敛全部触觉调用(呼应「haptics 走 util」的架构铁律)。只在有「完成/失败/越界」离散语义节点时配一次预置触觉,连续动画不配触觉,禁连续/长振。

```typescript
// entry/src/main/ets/common/EmberHaptics.ets
import vibrator from '@ohos.vibrator'

async function fire(effectId: string) {
  try {
    if (await vibrator.isSupportEffect(effectId)) {
      vibrator.startVibration({ type: 'preset', effectId, count: 1, intensity: 60 },
                              { usage: 'touch' })
    }
  } catch (_) {}
}
export const hapticCopy       = () => fire('haptic.effect.sharp')   // 复制成功(沿用现有)
export const hapticIgnite     = () => fire('haptic.notice.success') // 连接建立,配「点燃」
export const hapticDisconnect = () => fire('haptic.effect.hard')    // 断开,配「熄灭」(一次厚重)
export const hapticClose      = () => fire('haptic.effect.soft')    // 标签关闭
export const hapticBoundary   = () => fire('haptic.effect.sharp')   // 字号/滚动到边界
```

### 1.3 三件套选型铁律(写进规范,防同一交互三种写法打架)

| API | 何时用 | 例 |
|---|---|---|
| `getUIContext().animateTo(param, cb)` | 改**已存在**组件状态、需精确 `onFinish`、一次驱动多个 `@State` | 抽屉开合(位移+scrim opacity 联动)、呼吸循环 |
| `.animation({duration,curve})` 隐式 | 单属性绑一个 `@State` 自动补间 | 灯丝颜色/辉光、选中底色 |
| `.transition(TransitionEffect)` | 组件**挂载/卸载**出入场 | 新建标签滚入、浮层、面板 crossfade |
| `keyframeAnimateTo(...)` | 一个状态内「起→中→止」多段不等时编排 | 点燃 flash→settle、熄灭 hold→cool、通知双涌 |

判断口诀:**改状态→ animateTo / .animation();组件生死→ transition;多段编排→ keyframe。** 推荐 `getUIContext().animateTo`(API10,不受全局 UIContext 影响)。

---

## 2. 签名动效详设:灯丝生命体征系统

灯丝是整个产品的签名语言。现状它只有「200ms 对称颜色渐变」,浪费了隐喻。本规范把标签底缘 2px 连接态灯丝升级成**四态各有专属体态**的活物:

| 态 | 隐喻 | 动效语气 |
|---|---|---|
| 连接建立 | 灰烬 → 活着 | **点燃**:猛闪过亮再回落(非线性、有 overshoot) |
| 连接/重连中 | 活着但未就绪 | **呼吸**:半亮带内极缓正弦循环 |
| 断开 | 余温冷却成灰烬 | **熄灭**:先滞留余温再慢慢冷透(灭比亮慢) |
| 连接失败 | 打火机点不着 | **挣扎**:2–3 下顿挫无辉光闪烁后落灰 |

四态共用一套 epoch 基建:在 `TerminalSessionHandle` 上加 `igniteEpoch / extinguishEpoch / sparkFailEpoch / attentionEpoch`,在 `addSession` 的两个 status listener(Index.ets L288–300)里按状态跃迁 `++`,Chip 用 `@Prop … @Watch` 触发对应 keyframe。下面详设两个 hero 态。

### 2.1 点燃(逐帧)

**落点**:`TerminalTabChip`(Index.ets L139–191)。把 L161–172 的灯丝 `Row` 包进 `Stack`:底层 = 现有 base 灯丝(color/opacity/glow 走 `DUR_STANDARD` 的 ash↔ember 补间);叠一层 **bloom** `Row`(同 2px、`hitTestBehavior = None`、`color = #F1C79A` 更亮的余烬白金、`opacity = @State bloomOpacity`(初 0)、`shadow.radius = @State bloomGlow`(初 4))。

触发:listener 里 `if(!was && status.connected) session.igniteEpoch++`,Chip `@Watch('onIgnite')`:

```typescript
this.getUIContext().keyframeAnimateTo({ iterations: 1 }, [
  { duration: DUR_IGNITE_FLASH,  curve: CURVE_SHARP,
    event: () => { this.bloomOpacity = 0.85; this.bloomGlow = 11 } },
  { duration: DUR_IGNITE_SETTLE, curve: SPRING_SETTLE,
    event: () => { this.bloomOpacity = 0;    this.bloomGlow = 4  } },
])
hapticIgnite()  // t=0 同步一次 success 触觉
```

逐帧时间线:
- **t=0**:base 已在 ash(或刚从呼吸切出);bloom opacity=0、glow=4。同帧 base 层独立启动 ash→ember 的 `DUR_STANDARD` 颜色补间。
- **0→90ms(CURVE_SHARP)**:bloom opacity 0→0.85、glow 4→11。灯丝一下窜亮**超过工作亮度**——「火苗被引着」的过冲。
- **90→390ms(SPRING_SETTLE,300ms)**:bloom opacity 0.85→0、glow 11→4,带极小 overshoot 回落。此时 base 层已稳定在 ember 工作亮度。
- **结束**:只剩 base ember 稳亮。

**性能论证**:全程只动 2px ArkUI 节点的 `opacity` + `shadow`——二者都是合成层属性,不触发 measure/layout;bloom 与 XComponent 分属两张合成层,零终端重绘。keyframe 走 RenderService 合成线程,不占 UI/JS 线程,不与终端输入抢帧。一次性 `iterations:1`,播完即静,无常驻负担。

### 2.2 呼吸(逐帧)

**落点**:`TerminalTabChip` 的 `isPending` 分支(现 L166 静态 `opacity 0.45`)。加 `@State breatheOpacity = 0.6` 与 `@State breathing = false`。灯丝 opacity 绑 `isPending() ? this.breatheOpacity : 1`。

```typescript
// 进入 pending
this.getUIContext().animateTo(
  { duration: DUR_BREATHE_HALF, curve: CURVE_SINE,
    iterations: -1, playMode: PlayMode.Alternate,
    expectedFrameRateRange: FRAME_60 },
  () => { this.breatheOpacity = 0.34 })

// 离开 pending(成功/失败/断开三条出口都先走这句收尾,再触发对应 epoch)
this.getUIContext().animateTo({ duration: DUR_STANDARD, curve: CURVE_DECEL },
  () => { this.breatheOpacity = 1 /* 或落 ash */ })
```

- 幅度**锁死在 0.34↔0.6 这条半亮带**:永不到 1.0(与 connected 拉开)、永不熄到 ash(与 dead 拉开)。整周期 2.6s,慢到近乎察觉不到才对——「还在试、有戏」。
- glow 保持低位(~3,无点燃热量)。
- **门控铁律**:仅 pending 态存在时循环,握手成功/失败/断开立即用收尾 `animateTo` 覆盖(隐含 cancel 前一个),再触发点燃/挣扎/熄灭。呼应「withRepeat 用完必 cancel、否则整屏重绘」的血泪。

**性能论证**:必须走 ArkUI 声明式属性动画(RenderService 合成线程),**绝不用 `setInterval`/`requestAnimationFrame` 逐帧驱动**(会占 UI/JS 线程抢终端输入)。2px 节点 opacity 循环在 GPU 上≈免费,`FRAME_60` 进一步省电。与 XComponent 分属两层,不碰终端渲染。

> 熄灭(2.1 表第三态)与失败(第四态)复用同一 epoch/keyframe 基建,详设见第 3 节方案表 M03/M04——非对称编排是关键:熄灭首段 120ms 先 hold 住余温、再 700ms 慢慢冷透(色相 ember→过渡橙 #C56B3A→ash),读作「此前还活着、现在慢慢凉了」;失败做 2–3 下**无辉光**的顿挫闪烁后落灰,与呼吸的「平滑+有辉光+循环」刻意拉开,不看文字也能分「在连」与「连不上」。

---

## 3. 逐时刻方案表

> 落点行号沿用四路调研审计的 Index.ets 坐标。工作量:S=一行到数行 / M=一个 builder 改造或轻重构。

### 3.1 灯丝签名(连接态)

| # | 时刻 | 现状 | 方案 | 参数 | 落点 | 量 | 优 |
|---|---|---|---|---|---|---|---|
| M01 | 连接建立·点燃 | 200ms 对称渐变 | 双层 Stack + bloom flash→settle(§2.1) | 90ms `CURVE_SHARP` → 300ms `SPRING_SETTLE`;`hapticIgnite` | `TerminalTabChip` L139–191 / listener L288–300 | M | **P0** |
| M02 | 连接中·呼吸 | 静态 opacity 0.45 | 半亮带正弦循环(§2.2) | 1300ms `CURVE_SINE` Alternate `iterations:-1` `FRAME_60`;门控 | 同上 pending 分支 L166 | M | **P0** |
| M03 | 断开·熄灭 | 硬变灰 | 非对称:hold 余温→慢冷透,色相 ember→#C56B3A→ash | keyframe 120ms `Friction`(hold)→700ms `CURVE_SINE`;`hapticDisconnect` | `TerminalTabChip` + listener | S | P1 |
| M04 | 连接失败·挣扎 | 无(仅报错文字) | 2–3 下无辉光顿挫闪后落灰,glow 全程 0 | keyframe 低幅 opacity 抖 5 段~480ms `EaseIn` 收灰 | 同上,`status.error` 触发 | S | P1 |
| M05 | 后台标签通知·复燃+未读抬升 | 只发系统通知、标签零视觉 | 已 connected 用「亮度涌动」双涌,非循环;+ 未读时标题 fontColor secondary→primary、glow 稳定 6,`activateSession` 清零 | keyframe 4 段×350ms `EaseInOut`(涌两下即停);`attentionEpoch` at L423 | `handleTerminalNotification` L415 / `activateSession` L352 | M | **P0** |

> M05 是**最高信息价值**一条:多标签跑 claude/codex,哪个后台完事了现在只能看通知栏——答案直接长在标签上。文字只改 fontColor 不 scale,灯丝改 shadow,零终端成本。

### 3.2 选中态灯丝与选中面(非连接语义,统一但不呼吸)

| # | 时刻 | 现状 | 方案 | 参数 | 落点 | 量 | 优 |
|---|---|---|---|---|---|---|---|
| M06 | 选中灯丝一致化 | 仅 tab 灯丝有动画,其余 4 处硬跳 | 补齐抽屉导航竖灯丝 / 主题行 14×2 / 字体卡 2px / 连接面 22×2:color(ember↔ash)+shadow 补间 | `.animation({duration: DUR_STANDARD, curve: CURVE_DECEL})` | L796–803 / L1160–67 / L2096–103 / L1188–96 | S | **P0** |
| M07 | 选中面/边框渐变 | 底色/边框硬切 | 抽屉导航 bg、主题行 bg、字体卡 border、tab active bg 加颜色补间。**比灯丝快**,形成「面先稳(120)、灯丝后亮(220)」两拍点亮 | `.animation({duration: DUR_FAST, curve: CURVE_SHARP})` 仅颜色/边框补间,禁 scale | L812 / L1172 / L2109 / L178–182 | S | **P0** |
| M08 | 标签切换·chrome 交接 | active bg/border 硬切;终端内容瞬切 | **终端内容坚决瞬切**(见不做清单);只给 chip active bg/border 淡入淡出 | `DUR_FAST` `CURVE_SHARP`,同 M07 | `TerminalTabChip` L178–182 | S | P1 |
| M09 | 连接面 22×2 灯丝·连接中呼吸 | 静态 | 连接过程时同 §2.2 呼吸,连上/失败即停 | 复用 M02 | 连接面 L1188–96 | S | P2 |

### 3.3 容器级转场

| # | 时刻 | 现状 | 方案 | 参数 | 落点 | 量 | 优 |
|---|---|---|---|---|---|---|---|
| M10 | 抽屉五面板切换 | if/else 内容瞬换(最扎眼负动效) | `@State paneT`:先 100ms 淡出→onFinish 换 pane→140ms 淡入;容器绑 `.opacity(paneT).translate({x:(1-paneT)*10})` 小幅右滑,无 scale | 出 100ms `CURVE_ACCEL` / 入 140ms `CURVE_DECEL` | `buildDrawer` L738–761;navItem onClick L814 | M | P1 |
| M11 | 抽屉手势·甩动接管 | 固定 240ms EaseOut,拖一半松手突兀 | 拖拽跟手,松手取 velocity 交弹簧续接;点击开合仍走 `DUR_STANDARD` bezier | `SPRING_DRAG`(0.25/0.92 过阻尼零回弹)+ `FRAME_120` | 抽屉手势控制器(与 workspaceDrawerGesturePolicy 同层) | M | P1 |
| M12 | 抽屉/scrim 开合 | 240ms EaseOut / scrim 240 | token 化收敛 | `DUR_STANDARD` `CURVE_DECEL`;scrim opacity 与本体联动 | L768 / L701 | S | P1 |
| M13 | 辅助键条·出现 | if 挂载,44px 硬插+内容硬现 | 终端**只重排一次**(保持 if 挂载),键条根 Row 从下淡入 | `.transition(OPACITY.combine(translate({y:12})).animation({duration:DUR_STANDARD,curve:CURVE_DECEL}))` | `buildAccessoryBar` 根 Row L1859;挂载 L521–523 | S | P1 |
| M14 | renderFit·resize 防糊字 | 抽屉推挤/分屏改宽高时字被横向拉伸 | 终端及可 resize 面板设 TOP_LEFT,尺寸动画中字形不变 | `.renderFit(RenderFit.TOP_LEFT)` | `TerminalView` XComponent 外层容器 | S | P1 |

### 3.4 浮层与出入场

| # | 时刻 | 现状 | 方案 | 参数 | 落点 | 量 | 优 |
|---|---|---|---|---|---|---|---|
| M15 | 标签增删 | 新 chip 硬现、关闭后余者瞬移填空 | 非对称 transition:入场淡入+侧移、出场更快更简 | 入 `OPACITY+translate({x:12})` `DUR_STANDARD` `CURVE_DECEL` / 出 `DUR_FAST` `CURVE_ACCEL`,禁 scale | `TerminalTabChip` 根 Column L139;ForEach L579 | M | P1 |
| M16 | 新标签滚入视野 | `scrollEdge(Edge.End)` 瞬移 | 改动画滚动 | `tabScroller.scrollTo({xOffset, animation:{duration:200, curve:CURVE_DECEL}})` | `scrollTabStripToEnd` L318–326 | S | P1 |
| M17 | 搜索栏 / 安全粘贴浮层 | if 硬弹 | 锚在 TopEnd,从顶部下滑淡入、反向淡出 | `.transition(OPACITY.combine(translate({y:-8})).animation({duration:180,curve:CURVE_DECEL}))` | 搜索 L262 / 安全粘贴 L322;挂载 L107–112 | S | P1 |
| M18 | 标签编辑弹层 | opacity+translateY(12) 200ms(已有) | token 化 + 非对称:入场沿用、出场缩短纯 opacity | 入 `DUR_STANDARD` / 出 150ms 仅 opacity `CURVE_ACCEL` | `buildTabEditor`;转场 L1566、scrim L1445 | S | P2 |
| M19 | 编辑色板选中环 | 白边硬切 | 选中环柔和套上 | `.animation({duration:DUR_FAST, curve:CURVE_SHARP})` 仅 border 补间 | L1491–1504(选中 L1497–1500) | S | P2 |

### 3.5 终端渲染层(从严)

| # | 时刻 | 现状 | 方案 | 参数 | 落点 | 量 | 优 |
|---|---|---|---|---|---|---|---|
| M20 | Fling 惯性衰减 | 「渲染线程 11ms 节拍指数衰减」(隐含 ~90fps 假设,120Hz 下同一甩动滚更远) | 改**时间基**:`v *= exp(-dt/τ)`,τ≈130ms,dt 取真实帧间隔;停止阈值用速度非帧数 | τ=130ms;挂 `FRAME_120` | XComponent 滚动/fling native 回路 | M | P1 |
| M21 | 滚动到历史顶/底 | (若有)iOS 橡皮筋回弹 | 内容不位移,到边缘那帧画 1–2px 余烬铜辉光线;唯一强调色用在「边界」语义 | opacity 0→0.5 120ms 淡入 / 200ms `CURVE_ACCEL` 淡出 | XComponent 边界检测叠 ArkUI 边缘线 | S | P2 |
| M22 | 多 pane 焦点指示 | 缺失(键盘输入去哪不可辨) | 失焦 pane 光标 fill→stroke(空心),叠 #07090C@4% dim 层;重聚焦反向 | 光标 120ms opacity 切;dim animateTo 160ms `CURVE_DECEL` | pane 容器 builder + XComponent 光标绘制 | M | P1 |
| M23 | 光标闪烁 | 渲染器 `cursorBlink` L225 | 仅「聚焦且空闲」闪,打字/输出立即停;闪烁走 EaseInOut 半周期~530ms。**ArkUI 侧不复制,改渲染器状态机** | 半周期 530ms `EaseInOut` | XComponent 光标 blink 状态机 | S | P2 |

### 3.6 环境层与控件反馈

| # | 时刻 | 现状 | 方案 | 参数 | 落点 | 量 | 优 |
|---|---|---|---|---|---|---|---|
| M24 | 滚动条 overlay | 硬挂载 + thumb 每 100ms poll 一格格跳 | ①overlay auto-hide 淡入淡出;②thumb 仅非拖动时 100ms Linear 补间(拖动 duration:0)把离散跳补成连续 | overlay 150ms `CURVE_DECEL`;thumb 100ms Linear | overlay 根 Column L191;thumb `.position()` L203–206 | S | P2 |
| M25 | 背景图切换 | 整屏硬现/瞬灭 | Image 淡入淡出(环境层宜缓) | `.transition(OPACITY.animation({duration:DUR_AMBIENT,curve:CURVE_DECEL}))` | Image L510–516;surfaceBackdrop L2185 | S | P2 |
| M26 | 字号读数反馈 | Text 数字瞬变;终端 reflow 不可动画 | **终端 reflow 保持瞬切**;仅读数 Text 一次纵向 tick + 闪一下 ember | translateY(±3) 一来一回 120ms + fontColor 闪 ember,禁 scale;边界配 `hapticBoundary` | `buildFontPane` Text L1022 | S | P2 |
| M27 | 主按钮/连接按钮按压 | 无反馈 | 唯一强调色按钮按下铜色微沉,强化「余烬铜=可执行」;次级按钮保持素净 | `.stateStyles({pressed:{opacity:0.82}})` 隐式 ~120ms,禁 scale | 连接 Agent L1317–28 / 完成 L1542–52 | S | P2 |
| M28 | 主题切换收口 | 终端整屏重绘调色板 | 终端**瞬时硬换**(见不做);仅主题行选中灯丝淡亮(已含 M06);可选一次性 180ms 暗幕掩过硬换 | 选中灯丝 `DUR_STANDARD`;可选暗幕 opacity 0.14→0 180ms `CURVE_DECEL` | `buildThemeRow` L1160–67;`applyTheme` L2054 | S | P2 |

---

## 4. 不做清单

把「不做什么」当作与「做什么」同等的交付物钉进 `AGENTS.md` + `EmberMotion.ets` 顶部,守住 ghostty 式「没有设计的设计」,挡住未来所有「加个动画更炫」的提案。

| 时刻 | 判决 | 理由 |
|---|---|---|
| 终端内容区切标签(`buildTerminalLayer.visibility` L566) | **0ms 硬切** | 桌面终端(iterm/tmux)切标签必须瞬时;双 XComponent 叠化既贵又违直觉。反馈全放 chrome(M08)。 |
| 终端调色板/主题颜色 tween | **硬换** | 渲染器(libghostty)不支持调色板插值;ArkUI 侧截图叠化又重又假。 |
| 字号/reflow 的终端网格重排 | **瞬切** | 栅格重排动画=糊字+掉帧;只反馈控件读数(M26)。 |
| 任何含 CJK 文字组件的 `transform scale`(标题/读数/按钮文案) | **禁,一律 opacity+translateY** | 项目铁律:栅格化糊字。 |
| smooth caret / cursor trail / smear(打字期光标追随) | **不做**;默认 instant | kitty trail 默认 0、Neovide 社区嫌「太抢眼」、VS Code cursorSmoothCaret 确诊「追不上渲染穿过字母」;每秒几十字符逐字追随必糊字掉帧。仅留「鼠标大跳」40–60ms 临界阻尼作**默认关闭的配置项**。 |
| 终端滚动惯性/像素平滑之外再叠 ArkUI 层持续动画 | **不做** | 终端自绘层已有 fling,别在其上再压合成动画抢帧。 |
| 呼吸/通知涌动之外的任何常驻循环动画 | **不做** | 每多一个 ambient 循环就多一份 RenderService 负担与注意力税;签名循环只留「呼吸」一处。持续动画必须状态门控,离态即 `cancelAnimation`。 |
| 光标闪烁在 ArkUI 侧复制 | **不做** | 交渲染器 `cursorBlink`(M23),别与终端渲染抢帧。 |
| 按钮悬浮放大 / 涟漪扩散 / 页面级转场特效 | **不做** | 严肃桌面气质,用默认按压态。 |
| 粒子动画 `Particle` | **全局禁用** | 与近黑三层+唯一强调色的严肃气质冲突,且是 CPU 大户踩终端渲染红线。唯一极克制备选(默认不做):断开时灯丝「飘灰烬」一次性 ≤6 粒、400ms 即销毁。 |
| geometryTransition 共享元素(标签↔分屏一镜到底) | **延后,非默认** | 克制气质下慎用大范围飞行;仅当「标签拖出成独立窗」等空间连续明确场景才评审采用,时长 ≤300ms 走 `CURVE_DECEL`。 |
| 逐帧 relayout 属性补间:`width/height/margin/padding/fontSize/borderWidth/constraintSize/flex` | **禁补间** | 每帧触发 measure/layout,与终端 XComponent 抢主线程。必须动 width 的非终端面板配 `renderFit` 且压低 expected 帧率。合成层安全属性只有:`opacity / translate / rotate / 颜色渐变`(含文字禁 scale)。 |
| `setInterval` / 自建 `rAF` 常驻循环驱动动画 | **禁** | 占 UI/JS 线程抢终端渲染;能用声明式 `.animation` / `keyframeAnimateTo`(合成线程)表达就别碰 `animator`,只有「进度→自绘参数」才上 `animator`。 |

**PR 门禁**:每个动效 PR 必须回答「它传达什么状态」,答不出就删。

---

## 5. 实施批次建议

### 第一批(收益最高的 8 件,建成即立住品牌+地基)

1. **Motion Tokens + Haptics 收敛**(§1,P0/S)——所有其它条目的地基,先落地才能引用;顺手把现有 200/240 call site 逐步替换。
2. **M01 灯丝·点燃**(P0/M)——品牌记忆点,连接从灰烬到活着的复燃,把「点着了」焊死在最关键一刻。
3. **M02 灯丝·呼吸**(P0/M)——把「连接中」从静态半亮升级成生命体征,一眼区分「在试/活着/死了」。
4. **M05 后台标签通知复燃+未读抬升**(P0/M)——信息价值最高、补真实功能缺口,多标签跑 agent 时「哪个后台完事了」直接长在标签上。
5. **M06+M07 选中灯丝统一 + 选中面 FAST 渐变**(P0/S)——消除「像两套设计」的硬跳,「面先稳、灯丝后亮」两拍点亮全 app 一致。
6. **M10 抽屉五面板 crossfade**(P1/M)——去掉当前最扎眼的负动效(内容凭空替换)。
7. **M20 Fling 惯性时间基修正**(P1/M)——最实打实的一处:修 120Hz 下同一甩动滚更远的隐形手感 bug。
8. **不做清单钉进 AGENTS.md**(§4,P0/S)——护栏,让「克制」成为默认而非靠自律。

### 第二批(签名闭环 + 转场柔化)

M03 熄灭、M04 失败挣扎(灯丝四态收口)、M11 抽屉手势 spring 接管、M13 辅助键条滑入、M14 renderFit 防糊字、M15+M16 标签增删/滚入、M17 搜索/粘贴浮层、M22 多 pane 焦点指示。

### 第三批(P2 打磨,收尾细节)

M08 tab chrome 交接、M09 连接面呼吸、M12 抽屉 token 化、M18 编辑弹层非对称、M19 色板环、M21 边缘辉光、M23 光标闪烁门控、M24 滚动条、M25 背景图、M26 字号 tick、M27 按压态、M28 主题收口。

**延后/存疑**:geometryTransition 共享元素(需分屏拖出场景评审)、粒子飘灰烬品牌时刻备选(默认不做)。

---

*规范总纲:一个动效若不传达状态信息(连接/断开/连接中/失败/完成/切换),砍掉。强调色动效只出现在灯丝与主按钮。含文字禁 scale。终端渲染层默认瞬切。*
