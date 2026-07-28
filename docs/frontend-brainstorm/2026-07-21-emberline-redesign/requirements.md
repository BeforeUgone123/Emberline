# Emberline 全新视觉身份重设计 — Requirements

> **状态 2026-07-21:已关闭。** 三个方向(纸间/冷仪/深场)经用户评审后全部否决,不进入选定与落地。
> 本目录仅作存档;当前 UI 维持 07-18 Direction A。以下内容为探索过程记录。

> 日期:2026-07-21。本次运行目标:**完全替换视觉身份**(配色、签名元素、材质语言全部重新探索)。
> 旧方案(余烬铜灯丝,Direction A: Harmony Native Workbench)存档于
> `docs/frontend-brainstorm/2026-07-18-harmonyos-ui-ux-optimization/`,仅作历史参考,不得回抄其配色与签名元素。

## 用户决策(2026-07-21,本会话确认)

1. **视觉身份:全部推倒。** 配色、签名元素、材质语言重新探索;灯丝方案仅存档。
2. **产品约束:全部保留。** 见下「不可动约束」。
3. **交付路径:先设计探索后落地。** 三方向 HTML 预览 → 用户选定 → 设计简报 → 实现提示词 → 确认后才改 ArkTS。

## 不可动约束(产品级,重设计不得触碰)

- 终端即首屏:第一屏就是终端画布,无 dashboard / 无 onboarding / 无营销式空态。
- 48vp 顶部 rail:tabs + 连接、设置、溢出三个持久动作;系统窗控件保留自有区域。
- 无快捷键盘行(2026-07-03 决策,2-in-1 有物理键盘)。
- 右侧 inspector 为 overlay(352/400vp),三个目的地:终端 / 外观 / 连接;打开时阻断终端输入,关闭归还焦点。
- 键盘模型:F6 循环 terminal → chrome → inspector;Esc 关闭最顶层浮层;Tab/Shift+Tab 归终端。
- 帮助与 Agent 设置在溢出菜单。

## 动效红线(沿用,与新身份无关)

- 终端内容区切标签 / 调色板 / reflow 网格重排:0ms 硬切,禁补间。
- 合成层安全属性只有 opacity / translate / rotate / 颜色;禁补间 width/height/margin/padding/fontSize/borderWidth/flex。
- 含 CJK 文字组件禁 transform scale(栅格化糊字),一律 opacity + translateY。
- 无常驻循环动画;任何循环必须状态门控,离态收尾。
- 禁粒子 / 呼吸式氛围动画(除非状态驱动)/ 页面级转场特效 / 按钮悬浮放大。
- 强调色稀缺:一个签名色/签名元素,不得外扩。
- 门禁:每个动效必须能回答「它传达什么状态」。

## 成功标准

- 三个方向在「终端优先 + 同一结构骨架」下呈现**真正不同**的个性与视觉身份,而非同一方案换色。
- 每个方向给出:配色 token、签名状态元素(替代灯丝的东西)、字体角色、组件状态(连接中/已连接/失败/完成/选中)、微动效语法(仅合成层安全属性)。
- 预览必须含中文 UI(终端/外观/连接),1440×900 为主要评审视口,960 宽度不崩。
- 可翻译成 ArkUI 原生控件 + HarmonyOS Symbol,无玻璃模糊压终端、无 web 专属效果。

## 交付物

```text
docs/frontend-brainstorm/2026-07-21-emberline-redesign/
  requirements.md          ← 本文件
  project-context.md       ← 项目扫描
  image-prompts.md         ← 三方向设计规格(无图像生成环境,以文字规格代替)
  preview/
    inkfolio/index.html    ← 方向一预览
    coldframe/index.html   ← 方向二预览
    eventide/index.html    ← 方向三预览
    notes.md               ← 反馈与修订记录
  selected-direction.md    ← 用户选定后写
  design-brief.md          ← 选定后写
  final-implementation-prompt.md ← 预览确认后写
```
