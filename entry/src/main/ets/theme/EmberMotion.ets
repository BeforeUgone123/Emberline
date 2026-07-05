// entry/src/main/ets/theme/EmberMotion.ets
//
// Emberline Motion Tokens — the single source of truth for every animation
// duration / curve / spring / frame-rate in the app. Builders import these
// constants only; no raw numbers in view code. This is the geodesic base every
// motion entry (M01-M28) stands on.
//
// ── 不做清单(护栏:守住 ghostty 式「没有设计的设计」,挡住「加个动画更炫」)──
//  · 终端内容区切标签 / 调色板 tween / reflow 网格重排:0ms 硬切,绝不补间。
//  · 含 CJK 文字组件禁 `transform scale`(栅格化糊字)→ 一律 opacity + translateY。
//  · 合成层安全属性只有 opacity / translate / rotate / 颜色。禁补间
//    width / height / margin / padding / fontSize / borderWidth / constraintSize / flex。
//  · `setInterval` / 自建 rAF 常驻循环禁用;能用声明式 .animation / keyframeAnimateTo
//    (走 RenderService 合成线程)表达就别碰 animator。
//  · 呼吸 / 通知涌动之外的常驻循环动画不做;任何循环必须状态门控,离态即收尾覆盖。
//  · 粒子 / smooth-caret / cursor trail / 页面级转场特效 / 按钮悬浮放大:不做。
//  · 强调色(余烬铜 #D08F53)动效只出现在灯丝与主按钮。
//  · PR 门禁:每个动效必须能回答「它传达什么状态」,答不出即删。

import { curves } from '@kit.ArkUI';

/* ── 时长档 (ms) ─────────────────────────────── */
export const DUR_INSTANT: number  = 0;    // 瞬切:终端切标签 / reflow / 高频输入。禁补间。
export const DUR_FAST: number     = 120;  // 即时应答:选中面/边框、chrome 交接、边界反馈、色板选中环
export const DUR_STANDARD: number = 220;  // 容器级转场:抽屉、面板 crossfade、辅助键、scrim、浮层(收编旧 200/240)
export const DUR_AMBIENT: number  = 250;  // 环境层:背景图淡入淡出(略慢,宜缓)

/* 灯丝签名专用(刻意非对称:亮得快、灭得慢)*/
export const DUR_IGNITE_FLASH: number    = 90;   // 点燃猛闪
export const DUR_IGNITE_SETTLE: number   = 300;  // 点燃弹簧回落
export const DUR_EXTINGUISH_HOLD: number = 120;  // 熄灭:余温滞留
export const DUR_EXTINGUISH_COOL: number = 700;  // 熄灭:慢慢冷透
export const DUR_BREATHE_HALF: number    = 1300; // 呼吸半周期(整周期 2.6s)

/* ── 曲线档 ─────────────────────────────────── */
export const CURVE_DECEL: ICurve = curves.cubicBezierCurve(0.2, 0, 0, 1); // 进场/转场默认:快起慢停、零回弹
export const CURVE_ACCEL: ICurve = curves.cubicBezierCurve(0.4, 0, 1, 1); // 退场:加速离开、干脆无残留
export const CURVE_SHARP: ICurve = curves.cubicBezierCurve(0.33, 0, 0, 1);// 微反馈(FAST 档):即时应答
export const CURVE_SINE: Curve   = Curve.EaseInOut;                       // 呼吸/ambient:正弦感

/* ── 弹簧档(全项目仅两处,专款专用)──────────── */
export const SPRING_DRAG: ICurve   = curves.responsiveSpringMotion(0.25, 0.92); // 手势跟手:过阻尼、零回弹
export const SPRING_SETTLE: ICurve = curves.springMotion(0.34, 0.84);           // 点燃回落:临界略欠阻尼、极小 overshoot

/* ── 帧率档(MatePad Edge 120Hz opt-in)──────── */
export const FRAME_120: ExpectedFrameRateRange = { min: 60, max: 120, expected: 120 }; // fling/手势跟手
export const FRAME_60: ExpectedFrameRateRange  = { min: 30, max: 60,  expected: 60 };  // 呼吸等 ambient,省电
