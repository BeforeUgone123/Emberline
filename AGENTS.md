# Agent Handoff Instructions

## Product North Star

Emberline is the application and GitHub repository name. It was previously
called `FusionTerm`, and the earliest GitHub repository name was `HMG`.

Build a HarmonyOS developer terminal whose first useful job is connecting to the
Fusion Development Engine Linux VM through a `ystyle/wand-agent`-compatible
WebSocket PTY transport. The expected default target is the Fusion Development
Engine VM bridge at `ws://172.16.100.2:8765/ws` with token `harmonyterm`, and
terminal environment values suitable for modern CLIs:
`TERM=xterm-256color` and `COLORTERM=truecolor`.

The product should feel like a desktop-grade terminal in the spirit of Ghostty,
not a demo screen or marketing page. The first screen is the terminal surface.
App chrome should stay minimal: connection state, VM action, local fallback,
theme/settings, and later session tabs. Decision 2026-07-03: no on-screen
quick-key bar — the target device is a 2-in-1 with a physical keyboard, and
all key handling goes through the native key encoder. Do not add soft key
rows back without an explicit user request.

## Architecture Boundary

- Keep `libghostty_ohos` as the reusable renderer HAR. Do not move app session
  state, SSH profiles, VM assumptions, or UI chrome into that library.
- Keep app-specific orchestration in `entry`: ArkTS owns UI/state and
  `libfusion_terminal_driver.so` owns native fallback byte-stream transports.
- Add wand-agent-compatible WebSocket orchestration in `entry`, not in
  `libghostty_ohos`.
- Treat local PTY as opportunistic. HarmonyOS app sandbox constraints can make
  local shell execution unreliable; Fusion Agent WebSocket remote PTY to the
  Fusion VM is the primary product path.
- Treat SSH remote PTY as fallback and later advanced mode, not the default VM
  path.
- Do not persist passwords. Host-key trust and safer credential handling are
  follow-up requirements before broad SSH-client positioning.

## Key Files

- `README.md`: project overview and build notes.
- `docs/product-positioning.md`: product goals, target users, and non-goals.
- `docs/handoff.md`: current implementation state and source conversation.
- `docs/fusion-agent-protocol.md`: wand-agent-compatible WebSocket PTY
  contract.
- `docs/superpowers/specs/2026-07-02-harmony-advanced-terminal-design.md`:
  original approved design.
- `docs/superpowers/plans/2026-07-02-harmony-advanced-terminal.md`: full
  implementation plan from scaffold to device QA.
- `entry/src/main/ets/pages/Index.ets`: current first-screen workspace.
- `entry/src/main/ets/drivers/FusionTerminalDriver.ets`: ArkTS driver wrapper.
- `entry/src/main/cpp/terminal_driver.cpp`: N-API bridge.
- `entry/src/main/cpp/ssh/ssh_session.cpp`: libssh2 remote PTY path.
- `entry/src/main/cpp/pty/pty_handler.cpp`: local PTY path.
- `libghostty_ohos`: vendored renderer HAR module.

## Current Build Assumptions

This Codex workspace does not provide the full HarmonyOS runtime toolchain. Full
HAP builds must run on a DevEco/Harmony SDK machine with `ohpm`, `hvigorw`,
`hdc`, signing material, CMake, and Ninja available.

The repository vendors `libghostty_ohos/prebuilt/arm64-v8a/libghostty_vt.a` so
the renderer HAR can configure in DevEco without rebuilding Ghostty VT first.
Third-party SSH fallback sources are intentionally not vendored; fetch them
with:

```sh
bash tools/fetch-third-party.sh
```

## Next Best Work

1. Run `ohpm install --all` and a full `hvigorw` build on the DevEco machine.
2. Run `wand-agent` or a hardened project fork inside the Fusion Development
   Engine Linux VM with token `harmonyterm`.
3. Verify the app can reach the agent at `172.16.100.2:8765/ws`, or update
   `DEFAULT_FUSION_AGENT_HOST` to the actual VM bridge address.
4. If the native SSH fallback build fails, fetch `third_party/libssh2` and
   `third_party/mbedtls`, then inspect `entry/src/main/cpp/CMakeLists.txt`.
5. Implement the first safety milestone: Fusion Agent authentication hardening,
   SSH host-key fingerprint reporting for fallback, and trust UI.
6. Split the ArkUI workspace into components only after the current end-to-end
   VM connection path compiles.
7. Keep docs updated whenever product scope changes; do not let the project
   drift back into a vague "terminal emulator" label.

## Source Conversation

Primary source thread:
`/home/user/.codex/sessions/2026/07/02/rollout-2026-07-02T15-16-20-019f21af-8a93-76b1-b60d-e2122790c83a.jsonl`

Important decision cues from that thread:

- The user asked to assess Ghostty migration feasibility for HarmonyOS.
- The recommended direction was not a full Ghostty GUI port, but a
  Ghostty-rendered HarmonyOS SSH terminal.
- The user confirmed: "do terminal emulator only", "target local shell through
  PTY", then refined the real target to the Fusion Development Engine Linux VM.
- The user asked to create the Harmony advanced terminal project under
  `/mnt/linux_share/preview`.
- The user later named the GitHub repository `HMG`, then aligned the repository
  name with the app name `Emberline`.
- The user approved using a hardened `ystyle/wand-agent`-style WebSocket PTY
  agent as the preferred VM transport, with SSH retained as fallback.

Related earlier exploration threads discussed broader HarmonyOS ecosystem gaps
and other product ideas, but they are not the current Emberline product source:

- `019e8d39-437f-7260-9b63-895bad7f4138`: HarmonyOS ecosystem and note/AI app
  exploration.
- `019ea70e-87d9-76f1-831e-414bae920875`: HarmonyOS project brainstorming,
  including education and lifestyle app branches.

## 动效不做清单

守住 ghostty 式「没有设计的设计」。以下判决与「做什么」同等,挡住未来所有「加个动画更炫」的提案。**PR 门禁:每个动效必须回答「它传达什么状态」(连接/断开/连接中/失败/完成/选中/切换),答不出即删。**

- **终端内容区切标签 → 0ms 硬切**。桌面终端(iterm/tmux)切标签必须瞬时;双 XComponent 叠化既贵又违直觉。反馈全放 chrome(tab active 底色/边框淡入)。
- **终端调色板 / 主题颜色 tween → 硬换**。libghostty 不支持调色板插值;ArkUI 侧截图叠化又重又假。主题切换只让选中灯丝淡亮,不加全局暗幕(可选项本轮不做)。
- **字号 / reflow 的终端网格重排 → 瞬切**。栅格重排动画=糊字+掉帧;只反馈控件读数(读数 Text 一次纵向 tick + ember 闪)。
- **含 CJK 文字组件的 `transform scale`(标题/读数/按钮文案)→ 禁,一律 opacity + translateY**。scale 会栅格化糊字(项目铁律)。
- **smooth caret / cursor trail / 打字期光标追随 → 不做,默认 instant**。每秒几十字符逐字追随必糊字掉帧(kitty trail 默认 0、VSCode cursorSmoothCaret 确诊追不上)。仅留「鼠标大跳」临界阻尼作**默认关闭**的配置项。
- **终端自绘 fling 之上再叠 ArkUI 持续动画 → 不做**。别在终端渲染层上再压合成动画抢帧。
- **呼吸 / 通知涌动之外的任何常驻循环动画 → 不做**。签名循环只留「呼吸」一处;任何持续动画必须状态门控,离态即收尾覆盖(withRepeat/animateTo 循环用完必停,否则整屏重绘)。
- **ArkUI 侧复制光标闪烁 → 不做**。交渲染器 `cursorBlink` 状态机,别与终端渲染抢帧。
- **按钮悬浮放大 / 涟漪扩散 / 页面级转场特效 → 不做**。严肃桌面气质,用默认按压态(唯一强调色主按钮 pressed opacity 0.82)。
- **粒子动画 `Particle` → 全局禁用**。与近黑+唯一强调色气质冲突,且 CPU 大户踩终端渲染红线。
- **geometryTransition 共享元素(标签↔分屏一镜到底)→ 延后,非默认**。仅「标签拖出成独立窗」等空间连续明确场景才评审采用,时长 ≤300ms 走 CURVE_DECEL。
- **逐帧 relayout 属性补间:`width/height/margin/padding/fontSize/borderWidth/constraintSize/flex` → 禁补间**。每帧触发 measure/layout,与终端 XComponent 抢主线程。合成层安全属性只有 `opacity / translate / rotate / 颜色`(含文字禁 scale)。必须动 width 的非终端面板配 `renderFit` 且压低 expected 帧率。
- **`setInterval` / 自建 `rAF` 常驻循环驱动动画 → 禁**。占 UI/JS 线程抢终端渲染;能用声明式 `.animation` / `keyframeAnimateTo`(合成线程)表达就别碰 `animator`,只有「进度→自绘参数」才上 `animator`。
- **强调色(余烬铜)动效只出现在灯丝与主按钮**,不外扩。
