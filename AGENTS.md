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
App chrome stays limited to session tabs plus connection, settings, and overflow;
local PTY and SSH remain secondary choices inside the connection inspector.
Decision 2026-07-03: no on-screen quick-key bar — the target device is a 2-in-1
with a physical keyboard, and all key handling goes through the native key
encoder. Do not add soft key rows back without an explicit user request.

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

## Current Implementation — 2026-07-21

- Direction A, **Harmony Native Workbench**, is implemented in the `dev`
  worktree. Launch remains terminal-first; the 48 vp rail has exactly three
  persistent app actions after the tabs: connection, settings, and overflow.
- The right inspector is an overlay, not a terminal resize. It exposes exactly
  `终端`, `外观`, and `连接`, uses 352/400 vp responsive widths, blocks native
  terminal input while open, and returns focus on close.
- Help and Agent setup remain explicit overflow actions. Decision 2026-08-01:
  the already-mounted terminal shows the wand-agent deploy/connect walkthrough
  once on first launch and persists the one-shot state. All quick-key
  UI/state/resources remain removed.
- `F6` or `Ctrl+Alt+.` cycles terminal -> chrome -> inspector without stealing
  `Tab` or `Shift+Tab` from terminal programs; `Esc` closes the topmost app
  overlay.
- Theme previews load progressively. Connection errors expose inline retry and
  details. UI loops and terminal polling stop when hidden/backgrounded where the
  current architecture allows it.
- Decision 2026-07-21: the unverified native output-consumer, hidden-surface
  render-loop, direct-byte WebSocket, and NativeWindow fence experiments were
  rolled back together. The renderer/output path is back on the last known
  stable implementation pending a device profiler trace; theme caching and
  non-rendering UI improvements remain.
- Live sessions request a `taskKeeping` continuous task through
  `KeepAliveManager.ets`; `EntryAbility.ets` requests screen-on only while the
  window is foregrounded. Both policies still require DevEco/device verification.
- Codex turn-complete reminders now use the official TUI OSC 9 notification
  channel. The native parser survives split transport chunks, Help covers tmux
  passthrough plus foreground permission/end-to-end tests, and a visible active
  tab shows a completion toast instead of discarding the event. System publication
  uses the visible `SERVICE_INFORMATION` slot, and the direct test reports whether
  HarmonyOS accepted the notification or rejected app/slot authorization. Help
  tells users to restart/resume Codex after changing its TUI config because a tmux
  reload cannot update an already-running Codex process. Watch forwarding still
  depends on system/device settings and requires device verification.
- 2026-07-27: full window & tab management is enabled -- vertical tab lift
  starts a programmatic system drag (merge on any strip / tear-off into a new
  window), and the tab menu offers split / move-to-window through the
  process-global window registry. Stability contract: "lift = unload" (the
  source window releases before the drag starts); no deferred/timed adoption
  is permitted (`check-tab-drag-handoff.mjs` pins this).
- 2026-07-27: chrome colors are fully theme-derived (`ChromeTheme.ets`
  tokens; ghostty light:/dark: dual-theme slots; system color-mode follow).
  The ember filament accent system is retired -- connection state is a
  neutral dot, and no fixed chrome hex values are permitted
  (`check-adaptive-chrome.mjs`). The tab strip is ghostty-macOS shaped:
  equal-split tabs, a floating pill capsule as the active face, and a
  solo tab collapses to a centered title.
- 2026-08-14 iteration A (source-level; DevEco/device verification pending):
  - Durable Agent sessions: the hardened wand-agent keeps PTYs alive for a
    `--session-grace-seconds` window (default 120s) after a WebSocket drop and
    rebinds on `attach=1&sessionId=`, replaying a 512 KiB ring buffer. The app
    closes the ping/pong loop (25s ping + 40s pong deadline), probes on
    foreground/network resume, and reattach never clears the renderer. This
    fixes the lock-screen-kills-tmux chain (CR-007 direction).
  - Agent auth defaults to header-only `Authorization: Bearer`; the query
    token is confined to an explicit `legacyQueryToken` flag (CR-003 partial).
  - SSH/SFTP host keys are verified against a process-wide TOFU store before
    credentials are sent; libssh2 init is process-wide `std::call_once`; the
    pin moved to immutable master commit `4f271a3b` with merge-base fix
    verification (CR-001/002/010).
  - SSH and local-PTY writes are lossless: ordered pending queue, writable
    readiness drain, failure latch with explicit error (CR-006).
  - Image-upload credentials are a per-session in-memory profile bound at
    connect time; text paste with multiple lines or C0 control characters
    requires confirmation before entering the native paste channel (CR-004).
  - The kitty keyboard protocol is wired through the vendored official key
    encoder (per-event `setopt_from_terminal`, kitty flags off = legacy
    handwritten table byte-for-byte).
  - CJK blank-glyph fix: the typography layout box gets 2x slack so
    MaxLines(1) no longer drops wrapped CJK glyphs, and render/copy/search
    paths read full grapheme clusters instead of base codepoints only.
- The source-level quality gate currently contains 46 `tools/check-*.mjs`
  scripts. These are structural checks, not a substitute for HAP compilation,
  profiler evidence, or device QA.

## Key Files

- `README.md`: project overview and build notes.
- `docs/product-positioning.md`: product goals, target users, and non-goals.
- `docs/handoff.md`: current implementation state and source conversation.
- `docs/code-review-2026-07-10.md`: release blockers and the 2026-07-18 status
  reconciliation for the security/correctness review.
- `docs/fusion-agent-protocol.md`: wand-agent-compatible WebSocket PTY
  contract.
- `docs/frontend-brainstorm/2026-07-18-harmonyos-ui-ux-optimization/`:
  approved Direction A design source, preview, implementation contract, and
  current UI status.
- `docs/frontend-brainstorm/2026-07-21-emberline-redesign/`: archived
  full-redesign exploration (three rejected directions, closed 2026-07-21;
  Direction A remains the current UI).
- `docs/superpowers/specs/2026-07-02-harmony-advanced-terminal-design.md`:
  original approved design.
- `docs/superpowers/plans/2026-07-02-harmony-advanced-terminal.md`: full
  implementation plan from scaffold to device QA.
- `entry/src/main/ets/pages/Index.ets`: current first-screen workspace.
- `entry/src/main/ets/drivers/FusionTerminalDriver.ets`: ArkTS driver wrapper.
- `entry/src/main/cpp/terminal_driver.cpp`: N-API bridge.
- `entry/src/main/cpp/ssh/ssh_session.cpp`: libssh2 remote PTY path.
- `entry/src/main/cpp/pty/pty_handler.cpp`: local PTY path.
- `entry/src/main/ets/common/KeepAliveManager.ets`: process-wide continuous-task
  accounting for connected sessions.
- `tools/check-harmony-native-workbench.mjs`: Direction A structural gate.
- `libghostty_ohos`: vendored renderer HAR module.

## Current Build Assumptions

This Codex workspace does not provide the full HarmonyOS runtime toolchain. Full
HAP builds must run on a DevEco/Harmony SDK machine with `ohpm`, `hvigorw`,
`hdc`, signing material, CMake, and Ninja available.

Development and release are intentionally separate worktrees:

- `/mnt/linux_share/preview/harmony-advanced-terminal` is branch `dev`, bundle
  `com.preview.fusionterm.debug`, label `Emberline Dev`, SDK `6.1.0(23)`, and a
  local debug signing profile.
- `/mnt/linux_share/preview/harmony-advanced-terminal-release` is branch `main`
  and retains the release identity `com.preview.fusionterm` plus release signing.
- Do not test release by merely swapping signing in the dev tree. Stabilize on
  `dev`, promote reviewed changes deliberately, and build/sign in the release
  worktree. Bundle identity and signing profile must match an installed app;
  otherwise uninstall the conflicting package before reinstalling.

The repository vendors `libghostty_ohos/prebuilt/arm64-v8a/libghostty_vt.a` so
the renderer HAR can configure in DevEco without rebuilding Ghostty VT first.
Third-party SSH fallback sources are intentionally not vendored; the current
development fetch command is:

```sh
bash tools/fetch-third-party.sh
```

That script still pins `libssh2-1.11.1`. Use it only to reproduce the current
build against isolated disposable test endpoints; do not enter valuable SSH
credentials and do not ship it. Release must compile SSH/SFTP out or use a
verified patched revision and shared SSH/SFTP host-key verification.

## Next Best Work

1. Read `docs/code-review-2026-07-10.md`; unresolved findings (CR-008 native
   EOF propagation, CR-009 final renderer-host disposal, CR-003 pairing/secure
   storage remainder) remain the engineering queue.
2. Verify the 2026-08-14 iteration A source-level fixes on the DevEco machine
   and on device: SSH/SFTP host-key TOFU flow, lossless writes under backpressure,
   kitty keyboard disambiguation in nvim/helix/fish, CJK rendering in long
   Chinese TUIs, and lock-screen/session reattach survival.
3. Harden Fusion Agent pairing and credential storage (random per-instance
   token, secure-element storage); wire the `legacyQueryToken` stock-agent
   fallback into the settings UI.
4. Fix native EOF propagation, final renderer-host disposal, and process-level
   native cleanup.
5. Repair the clean-clone gate and make signing inputs reproducible without
   committing machine-specific material.
6. On the DevEco machine, run all 46 structural checks, `ohpm install --all`, a
   full `hvigorw` build, codelinter, and the Direction A device/profiler matrix,
   including long tmux output, background keep-alive, and foreground screen-on.
7. Split `Index.ets` only after the primary VM path and release blockers are
   verified end to end.
8. Keep docs updated whenever product scope changes; do not let the project
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
- **终端调色板 / 主题颜色 tween → 硬换**。libghostty 不支持调色板插值;ArkUI 侧截图叠化又重又假。主题切换只让选中项底色淡亮,不加全局暗幕(可选项本轮不做)。
- **字号 / reflow 的终端网格重排 → 瞬切**。栅格重排动画=糊字+掉帧;只反馈控件读数(读数 Text 一次纵向 tick + 一次颜色闪)。
- **含 CJK 文字组件的 `transform scale`(标题/读数/按钮文案)→ 禁,一律 opacity + translateY**。scale 会栅格化糊字(项目铁律)。
- **smooth caret / cursor trail / 打字期光标追随 → 不做,默认 instant**。每秒几十字符逐字追随必糊字掉帧(kitty trail 默认 0、VSCode cursorSmoothCaret 确诊追不上)。仅留「鼠标大跳」临界阻尼作**默认关闭**的配置项。
- **终端自绘 fling 之上再叠 ArkUI 持续动画 → 不做**。别在终端渲染层上再压合成动画抢帧。
- **呼吸 / 通知涌动之外的任何常驻循环动画 → 不做**。签名循环只留「呼吸」一处;任何持续动画必须状态门控,离态即收尾覆盖(withRepeat/animateTo 循环用完必停,否则整屏重绘)。
- **ArkUI 侧复制光标闪烁 → 不做**。交渲染器 `cursorBlink` 状态机,别与终端渲染抢帧。
- **按钮悬浮放大 / 涟漪扩散 / 页面级转场特效 → 不做**。严肃桌面气质,用默认按压态(主按钮 pressed opacity 0.82;按钮面取主题派生的中性色,见下条)。
- **粒子动画 `Particle` → 全局禁用**。与克制的中性气质冲突,且 CPU 大户踩终端渲染红线。
- **geometryTransition 共享元素(标签↔分屏一镜到底)→ 延后,非默认**。仅「标签拖出成独立窗」等空间连续明确场景才评审采用,时长 ≤300ms 走 CURVE_DECEL。
- **逐帧 relayout 属性补间:`width/height/margin/padding/fontSize/borderWidth/constraintSize/flex` → 禁补间**。每帧触发 measure/layout,与终端 XComponent 抢主线程。合成层安全属性只有 `opacity / translate / rotate / 颜色`(含文字禁 scale)。必须动 width 的非终端面板配 `renderFit` 且压低 expected 帧率。
- **`setInterval` / 自建 `rAF` 常驻循环驱动动画 → 禁**。占 UI/JS 线程抢终端渲染;能用声明式 `.animation` / `keyframeAnimateTo`(合成线程)表达就别碰 `animator`,只有「进度→自绘参数」才上 `animator`。
- **固定强调色已整体退役(2026-07-27 自适应 chrome 裁决)**:chrome 唯一的非中性色是主题自带的 ANSI red(连接失败圆点)。不得再引入任何固定强调色或固定 chrome 色值。
