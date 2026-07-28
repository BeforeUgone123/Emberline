# Emberline Handoff

## Source Thread

Primary discussion thread:

```text
/home/user/.codex/sessions/2026/07/02/rollout-2026-07-02T15-16-20-019f21af-8a93-76b1-b60d-e2122790c83a.jsonl
```

This is the thread where the product direction moved from Ghostty migration
research to a HarmonyOS advanced terminal project. The important decisions were:

- avoid a full desktop Ghostty GUI port;
- use `libghostty-ohos` as the HarmonyOS renderer/HAR;
- build a standalone HarmonyOS Stage app rather than bloating the renderer
  example app;
- target terminal use first, not note-taking or AI document workflows;
- prioritize connecting to the Fusion Development Engine Linux VM;
- prefer a `ystyle/wand-agent`-compatible WebSocket PTY as the default VM
  transport;
- keep SSH remote PTY as fallback rather than the first product path;
- keep local PTY as a fallback/prototype;
- create the project under `/mnt/linux_share/preview/harmony-advanced-terminal`;
- publish the repository as `HMG`, then rename it to match the app name
  `Emberline`.

Related exploratory threads:

- `019e8d39-437f-7260-9b63-895bad7f4138`: HarmonyOS ecosystem-gap discussion,
  including Obsidian-like note and AI folder-reading ideas.
- `019ea70e-87d9-76f1-831e-414bae920875`: broader HarmonyOS project
  brainstorming; those ideas are explicitly out of scope for Emberline.

## 2026-07-18 Working Decisions

- A prior experimental app pass stuttered during long tmux work while the older
  stable build did not. The user chose to return to the stable baseline rather
  than continue layering fixes onto that pass.
- Background `taskKeeping` and foreground-only screen-on were then added as
  narrowly scoped lifecycle changes. Their source checks pass; device behavior
  is still unverified.
- Development and release were split into separate folders/worktrees so dev can
  diverge safely. Stabilized changes move to release deliberately; release is
  not selected by swapping signing inside dev.
- The user approved Direction A after the preview review and asked for its full
  ArkUI implementation, including meaningful state motion but none of the
  prohibited ambient/layout animation.

## Current State — 2026-07-19

Emberline is a native HarmonyOS Stage terminal application, not a scaffold:

- `entry` owns the ArkUI workspace, session state, Fusion Agent orchestration,
  local/SSH fallbacks, image-paste routing, preferences, notifications, and
  window lifecycle.
- `libghostty_ohos` remains a reusable renderer HAR with the vendored
  `prebuilt/arm64-v8a/libghostty_vt.a` terminal core.
- The primary transport is one wand-agent-compatible WebSocket PTY per tab,
  targeting `ws://172.16.100.2:8765/ws` with development token `harmonyterm`.
- Multiple tabs/windows, drag reorder and handoff, hardware-key encoding, IME,
  terminal mouse, OSC 52, OSC 9/BEL notification, theme/font customization,
  and target-aware image paste are present in source.
- Direction A is implemented in `Index.ets`: terminal-first launch, three
  persistent top actions, a three-destination overlay inspector, no quick-key
  row, explicit help, `F6` or `Ctrl+Alt+.` focus routing, `Esc` overlay close,
  progressive theme previews, and inline connection recovery.
- Connected sessions participate in process-wide `taskKeeping`; the main window
  requests keep-screen-on only while foregrounded.
- Codex `agent-turn-complete` can reach Emberline through its official OSC 9 TUI
  notification mode. OSC sequences are retained across arbitrary transport
  chunk boundaries; Help covers notification permission, tmux passthrough, and
  end-to-end tests. A visible active tab gets a toast, while every accepted event
  still enters the system-notification path. System publication uses the visible
  `SERVICE_INFORMATION` slot; the direct test reports the active notification
  count and distinguishes denied app authorization from a disabled slot. Help
  explicitly requires restarting/resuming Codex after changing its TUI config;
  reloading tmux does not update already-running Codex processes. Paired-watch
  delivery remains controlled by HarmonyOS system settings.
- The retained parts of the 2026-07-20 stutter audit lower low-frequency UI
  event polling, avoid full-chunk OSC parser copies, and bound theme-catalogue
  mounting. Parsed native themes and the sorted catalogue are cached
  process-wide; theme row selection and previews update independently instead
  of invalidating all 458 bundled rows.
- Decision 2026-07-21: device testing still reported stutter after the native
  output-consumer and NativeWindow-fence experiments. Those experiments, the
  direct-byte Fusion Agent feed, and hidden-surface render-loop changes were
  rolled back as one unit to the last known stable rendering/output path. The
  NativeWindow fence review finding is therefore open again and must be solved
  separately with profiler evidence rather than another bundled optimization.

## Workspace Separation

- Dev: `/mnt/linux_share/preview/harmony-advanced-terminal`, branch `dev`, bundle
  `com.preview.fusionterm.debug`, label `Emberline Dev`, SDK `6.1.0(23)`
  (API 23).
- Release: `/mnt/linux_share/preview/harmony-advanced-terminal-release`, branch
  `main`, bundle `com.preview.fusionterm`, label `Emberline`; its SDK target is
  unchanged until the dev upgrade is reviewed and promoted.
- The release worktree is not a signing toggle for dev. Promote reviewed changes
  from `dev`, then build with the release identity/signing material in the
  release worktree.

## 2026-07-27 API 23 Upgrade

- The dev product now sets both `compatibleSdkVersion` and `targetSdkVersion`
  to `6.1.0(23)`. It therefore requires an API 23 device.
- `compileSdkVersion` remains implicit and follows the DevEco Studio paired SDK;
  the latest local Hvigor metadata already resolved it to API 23.
- The release worktree was deliberately left unchanged. A fresh API 23 HAP
  build, codelinter pass, signing/install test, and device regression run remain
  required before promotion.

## 2026-07-27 Fullscreen tmux Freeze Root Cause

- Reported symptom: with a tmux session fullscreen and the window focused,
  idle-screen updates (for example the Codex per-second timer row) freeze;
  a small window or an unfocused window behaves normally.
- Analysis: the app has no focus- or window-size-dependent behavior anywhere
  (renderer loop, polling, data path all identical across the three cases),
  so the differentiator is the system compositor. Fullscreen + focused, the
  opaque XComponent SURFACE is eligible for hardware direct composition, and
  on that path FlushBuffer frames carrying a small partial dirtyRegion do not
  refresh the display; full-damage frames (scrolling output) present fine.
  The pre-buffer-age stable build (git `db78676` era) always flushed
  whole-surface damage and never froze, matching the 2026-07-18 comparison;
  the 2026-07-20/21 experiments never touched the damage report, which is why
  they failed.
- Fix in dev: `endFrame` now always reports whole-surface damage while
  keeping the incremental row blit; partial rect collection stays in place
  for a future direct-composition-aware re-enable
  (`native_drawing_renderer.cpp`, md5 `964e5be5`).
- Device verification pending: fullscreen + focused tmux timer must tick
  every second, and cursor blink must stay alive in that state (it was
  frozen by the same mechanism, a useful confirmation signal). The
  NativeWindow fence finding remains open and untouched, per the 2026-07-21
  isolation decision.

## 2026-07-27 Ghostty-Style Adaptive Chrome (prepared, pending device QA)

- The chrome has no fixed colors any more. A derivation layer
  (`entry/src/main/ets/theme/ChromeTheme.ets`) computes every chrome token
  (bar/capsule/panel materials, text ramp, borders, status dots, primary
  button) from the effective terminal theme's background/foreground plus its
  ANSI red, published as one immutable AppStorage token object.
- Ghostty `theme = light:...,dark:...` parity: `AppearanceStore` persists
  `darkThemeName`/`lightThemeName` (the legacy `themeName` migrates into the
  dark slot), `EntryAbility.onConfigurationUpdate` publishes the system color
  mode, and the page swaps the effective theme and re-derives the chrome in
  one pass. The theme pane edits one slot at a time; the system decor buttons
  restyle through the `fusionTermChromeMode` event.
- The tab strip is ghostty-macOS shaped: equal-split tabs (touch floor only,
  no maximum), the active tab is a floating pill capsule (radius 999,
  theme-derived material + border + soft shadow), inactive tabs are bare text
  with a hover face, and a single tab collapses to a centered title with the
  same context menu / long-press reachability.
- The ember/filament accent system is retired: per-tab filament colors,
  life-signs epochs and keyframes, `FILAMENT_PALETTE`, and the copper primary
  buttons are gone. Connection state is a neutral dot (solid = connected,
  breathing = connecting, hollow = disconnected, theme ANSI red = failed);
  unread lifts the title to the primary text color. Primary buttons are
  neutral fg-face/bg-label.
- Structural gates: `check-window-chrome-integration`, `check-tab-drag-handoff`
  and `check-background-and-screen-policy` evolved with the cutover; the new
  `check-adaptive-chrome.mjs` pins the derivation layer, the dual theme
  slots, the color-mode plumbing, the pill strip, and the retirement (no
  fixed chrome hex values, no filament fields).
- Device QA pending: light theme end to end (chrome + decor buttons), a
  system light/dark flip while running, pill-tab reorder, the solo-tab menu,
  theme-pane slot switching, and the notification button styling.

## 2026-07-27 Full Window & Tab Management (prepared, pending device QA)

- Cross-window tab management is re-enabled in its complete form: vertical
  lift on a pill tab converts the in-track reorder into a programmatic system
  drag (`dragController.executeDrag`, capsule preview, UDMF token payload);
  dropping on any window's strip merges at the drop slot (WebSocket survives,
  zero reconnect); dropping nowhere tears off into a new window at the release
  point (StartOptions geometry, best-effort); the tab context menu adds
  「拆分为新窗口」and「移动到窗口…」(live sibling list) as the touch path.
- Stability model vs the 2026-07-05 attempt: "lift = unload" -- the source
  window releases the session BEFORE the system drag starts, so the
  same-surfaceId double-mount race cannot exist; menu moves deliver the live
  handle directly on the shared heap (same JS thread, no parking). Cancel,
  launch failure and 15s expiry all re-adopt; a canceled solo-tab lift also
  removes the auto-backfilled blank placeholder.
- `SessionRegistry` gains a process-global window registry
  (register/unregister/list/deliverTo); each Index registers on mount.
- `check-tab-drag-handoff.mjs` was rewritten from the reorder-only guard into
  the full-mode guard (programmatic-pipeline pins, lift=unload ordering,
  merge/tear-off/menu/registry pins; component drag pipeline and deferred
  adoption stay banned).
- Device QA pending: reorder still smooth on pills, vertical lift threshold
  feel, cross-window merge drop, tear-off placement, menu split/move, cancel
  restore (incl. solo-tab placeholder cleanup), 15s expiry fallback, and the
  known behavior that dropping onto another window's terminal body (not its
  strip) opens a new window rather than merging.

## 2026-07-28 Tear-off Restoration And Hand-off Fixes

- An overwrite incident (freshness check and push ran in one command) briefly
  reverted the tear-off/merge/move-to-window implementation in `Index.ets` and
  its check. It is restored from the build cache's transpiled output and merged
  with the pill-tab gesture fix: long-press now picks the chip up (feeding the
  same all-direction pan), double-tap renames, and vertical travel past
  `TAB_PICKUP_THRESHOLD_VP` lifts the reorder into the system drag.
- Two hand-off bugs fixed at the root, from device testing. (1) Both drivers'
  `setStatusListener` replayed a hardcoded idle status, repainting a moved
  live session as disconnected; they now replay the last real state. (2)
  "Move to window" delivered on the same JS thread, so the source unmount and
  target mount of the SAME surfaceId landed in one vsync -- the documented
  tear-off-plan native-ordering race. Adoption now defers
  `TAB_MOVE_ADOPT_DELAY_MS` past the source unmount. This deliberately
  overturns the previous section's "deferred adoption stays banned" pin:
  the direct same-thread deliver is the exact path that broke on device
  (moving a tab back = instant dead terminal).
- Known deviation from the pre-incident build: a strip drop currently adopts
  at the end of the strip instead of the drop slot; restore slot-accurate
  insertion later if it matters in practice.
- Device QA pending: split to new window, move to window (both directions,
  repeatedly), drag-merge across windows, drag-out tear-off, cancel/expiry
  recovery incl. solo placeholder cleanup, and a moved live codex session
  keeping its true status and title.

## 2026-07-28 System Drag Retired (user decision)

- Device testing could not get the programmatic drag session to start, so the
  system-drag pipeline is removed end to end (vertical lift, drag preview,
  strip drop acceptance, drop-geometry tear-off). The context menu is the
  only cross-window path:「拆分为新窗口」(hand-off token launch) and
  「移动到窗口…」(direct deliver with deferred adoption). The registry /
  park / claim infrastructure stays.
- Moving the ONLY tab to another window now closes the emptied window
  (terminateSelf) instead of leaving a blank disconnected shell; the solo-tab
  menu accordingly offers move but not split.
- Cold-start stuck "正在连接" title report: not reproducible from source-level
  reasoning alone; a temporary `[EmberStatus]` probe traces every agent status
  edge. Capture `hdc hilog | grep EmberStatus` across one cold start and one
  move-to-window round trip, then remove the probe with the fix.
- Device QA pending: menu split/move matrix (including only-tab move closing
  its window), long-press pick-up + horizontal reorder, double-tap rename.

## 2026-07-28 Solo-Tab Deep Observation Fix

- Root cause of the stuck "正在连接" title (device log confirmed the driver
  emitting connected=true while the title froze): the solo-tab strip mode was
  a page-level @Builder reading `this.sessions[0].title` directly. ArkUI gives
  no deep observation of an @Observed handle accessed that way, so
  title/status edges only rendered when an unrelated page @State happened to
  change. The earlier moved-tab stale-title report was the same hole (a moved
  tab lands in solo mode).
- Fix: solo mode is the `SoloTabTitle` component with @ObjectLink (plus the
  same status-gated breathing dot as capsule tabs). ArkUI pitfall for the
  record: @Observed fields rendered anywhere must go through
  @ObjectLink/@Prop components, never be read straight inside a page builder.
- The temporary `[EmberStatus]` probe is removed with the fix.

## 2026-07-28 Pre-Merge Code Review (3 fixed, 3 logged)

A read of every path touched by the adaptive-chrome / floating-tab /
cross-window work, ahead of the first PR into `main`. Three defects were
fixed; three smaller ones are logged below rather than fixed, to keep the
merge candidate close to the build the user validated on device.

**Fixed**

1. *Cross-window move lost background keep-alive.* `releaseSessionForHandoff`
   drops the session's keep-alive unit, but the adopting window could never
   re-request it: the status replay reports `connected=true` while
   `session.connected` is already `true`, so `syncSessionKeepAlive` sees no
   `false->true` edge and both of its branches fall through. A moved tab that
   was the only live session took the process ref count to zero, so
   `stopBackgroundRunning` fired ~3s later and the app lost background
   protection exactly in the "move the codex tab to its own window, then go do
   something else" flow. `adoptSession` now claims a unit directly for a
   session that arrives already connected. Pinned by check-tab-drag-handoff.
2. *Theme changes tore the fused top bar apart across windows.* Chrome tokens
   are shared process-wide through AppStorage, but `controller.setTheme` is
   per-window and `applyEffectiveTheme` only walked its own `sessions`. With
   two windows open, a theme or light/dark change in A re-tinted B's tab bar
   while B's terminal kept the old palette — the exact seam the fused bar
   exists to remove. The effective theme name is now published under
   `EFFECTIVE_THEME_KEY`; sibling windows observe it and re-colour their own
   grids. Deliberately narrow: it does NOT sync the slot fields
   (`darkThemeName` / `colorModeOverride`), so a second window's settings pane
   still shows its own last-loaded selection until restart. Every other
   appearance setting (font, cursor, background) has always been per-window;
   only the theme was *half* shared, which is what produced the visible tear.
3. *Tab reorder could commit twice.* The chip binds a pan via `.gesture` and a
   long-press via `.parallelGesture`, and both fire their end callback on
   finger-up — the ordinary "press and hold, drag, release" gesture. The
   idempotence guard (`draggingSessionId < 0`) only closes inside the settle
   animation's `onFinish`, leaving the whole settle window unguarded, so the
   second entry queued a duplicate `reorderSession` with now-stale indices and
   scrambled the strip. A `dragSettling` flag now guards both `endTabDrag` and
   `cancelTabDrag`, which return early *without* resetting (a reset there would
   clear the guard itself). Not device-reproduced — whether ArkUI fires
   `onFinish` for a no-op `animateTo` decides between "scrambled order" and
   "one wasted animation" — but the guard is correct either way.

**Logged, not fixed**

- `setStatusListener` replays with a hardcoded empty `error`, so moving a
  *failed* session across windows downgrades its red failed dot to the grey
  hollow one (`hadError` is cleared by the replay).
- 「拆分为新窗口」on a window's *only* tab leaves the source window alive with
  a blank tab, while 「移动到窗口」 closes it via `terminateSelf`. The two
  cross-window paths should agree; `moveSessionToWindow`'s `wasOnlyTab`
  handling is the model.
- `applyDecorButtonMode` no-ops when `mainWindow` is still null, so a cold
  start whose `recomputeChromeTokens` lands before `getMainWindow` returns
  leaves the system decor buttons on the hardcoded dark style. Timing makes
  this unlikely (the token path awaits preferences + a rawfile read), but a
  light theme is where it would show.

## Verification And Limits

- This Codex environment has no `ohpm`, Hvigor/Harmony SDK, codelinter, or `hdc`.
  It cannot prove ArkTS compilation, HAP signing/install, runtime permissions,
  device behavior, frame time, memory, or power.
- The local quality gate contains 34 source-structure checks. They protect
  established shapes but are not executable integration tests.
- Direction A, background keep-alive, foreground screen-on, responsive widths,
  external keyboard/IME, Codex background/system/watch
  notifications, and long tmux output still need a single DevEco/device
  verification matrix.
- Local PTY can be blocked or degraded by the HarmonyOS sandbox.
- `third_party/libssh2` and `third_party/mbedtls` are fetched, not committed.
  The current fetch pin `libssh2-1.11.1` must not ship.
- SSH/SFTP host-key trust, Fusion Agent production pairing/storage/transport,
  native write/EOF lifecycle, final renderer-host disposal, and several
  connection-generation races remain release blockers.

The complete review and current disposition are in
[`code-review-2026-07-10.md`](code-review-2026-07-10.md).

The 2026-07-21 stable-renderer rollback is source-checked locally, but still
requires a new HAP and device profiler run before its hardware behavior is
known.

Local reconciliation on 2026-07-18 passed all 33 `tools/check-*.mjs` scripts,
`git diff --check`, JSON parsing for the changed Harmony profiles/resources,
`xmllint` for `ic_more.svg`, project-local Markdown link/path checks, and the
relative-time scan. The separate release worktree remained clean. These results
do not change the DevEco/device limits above.

## Build Handoff

Open the dev worktree in DevEco Studio, then run on a Harmony SDK machine:

```sh
bash tools/fetch-third-party.sh
ohpm install --all
for check in tools/check-*.mjs; do node "$check" || exit 1; done
hvigorw assembleHap --mode module -p product=default -p module=entry@default --no-daemon
```

The 34 checks pass in the prepared dev worktree. A clean clone still fails the
paste check because its ignored signing-profile fixture is absent (CR-013); do
not suppress that failure when turning the loop into CI.

Before release, disable SSH/SFTP or replace the reviewed vulnerable pin and add
shared host-key verification. Confirm the vendored renderer core exists at:

```text
libghostty_ohos/prebuilt/arm64-v8a/libghostty_vt.a
```

If native configuration fails, inspect `entry/src/main/cpp/CMakeLists.txt`, the
two `third_party` source trees, and the DevEco CMake/Ninja toolchain output.

## Recommended Next Steps

1. Resolve the Critical and High items in the dated code review, starting with
   SSH dependency/trust and Fusion Agent production authentication.
2. Fix per-session upload credentials, lossless native writes, native EOF,
   renderer-host disposal, keep-alive races, and connection generations.
3. Make the clean-clone quality gate and signing inputs reproducible.
4. Run the full DevEco build, codelinter, signing/install, Direction A viewport,
   multi-input, multi-window, background/screen, and long-output profiler matrix.
5. Split `Index.ets` only after the primary VM path and release blockers are
   protected by executable tests.

## 2026-07-18 Direction A / Lifecycle Pass

The dev worktree now contains:

- a terminal-first Harmony Native Workbench shell with exactly connection,
  settings, and overflow as persistent app actions;
- a 352/400 vp right overlay inspector with `终端`, `外观`, and `连接` only;
- explicit overflow access to help/diagnostics and no automatic onboarding;
- complete removal of quick-key state, builder code, icons, and onboarding
  storage;
- `F6` or `Ctrl+Alt+.` terminal/chrome/inspector routing, `Esc` close/terminal
  focus return, overlay input blocking, hover tips, fixed 40 vp action targets,
  and semantic labels;
- connection failure retry/details, background-gated connection motion, and
  progressive theme preview loading;
- source gates in `tools/check-harmony-native-workbench.mjs` plus updates to
  affected integration checks;
- `taskKeeping` session accounting and foreground-only screen-on policy from the
  preceding stability pass.

No HAP/device/performance claim is attached to this pass until the DevEco matrix
above is run.

## 2026-07-20 Desktop Transparency Device Finding

- The attempted `桌面透出` mode rendered the transparent area white on the
  target 2-in-1. It has been removed, including its persisted setting, rather
  than leaving a broken appearance option enabled.
- Root cause: on API 12 PC/2-in-1, ArkUI wraps the application Stage in an
  opaque system-themed `ContainerModal` when window decoration is enabled.
  `setWindowBackgroundColor('#00000000')` clears the inner Stage and ability
  background alpha, but it does not clear that outer container.
- API 12 exposes `WindowStage.disableWindowDecor()` for removing the wrapper,
  but only as a system API. The later `setWindowContainerColor()` route is also
  permission-gated and is not available to this API 12, ordinary-signed app.
- The supported appearance path remains an app-owned background image plus
  Ghostty `background-opacity`; image blur still applies only to that image.
  Revisit cross-application transparency only if HarmonyOS exposes a public,
  permission-free main-window container API for the release target.

## 2026-07-03 Font / UI / Terminal-Correctness Pass

An uncommitted working-tree pass (Claude Code session over SSH) changed:

- **Default font now Maple Mono Normal NF CN** (`v7.9`, OFL), bundled at
  `libghostty_ohos/src/main/resources/rawfile/fonts/MapleMonoNormal-NF-CN-Regular.ttf`
  to mirror the developer's desktop Ghostty font stack. The renderer now
  registers every bundled font under its own family and walks a ghostty-style
  fallback chain (Maple → JetBrains Mono → Nerd Symbols → Cascadia → Sarasa →
  optional private fallback → platform). Text style locale switched from
  `en-US` to `zh-Hans` so CJK glyph variants resolve to Simplified Chinese
  forms. Font extraction now skips rewriting unchanged files on startup.
- **Physical keyboard encoding** (`napi_init.cpp BuildKeySequence`): arrows and
  Home/End honor DECCKM application cursor mode and xterm modifier codes
  (`CSI 1;m X`); Delete/Insert/PgUp/PgDn/F5-F12 carry modifiers (`CSI n;m ~`);
  Shift+Tab sends backtab `CSI Z`; Ctrl-Space/[/\/]/6/-//" map to C0 controls;
  Alt prefixes ESC including Ctrl+Alt chords, Alt+Enter/Backspace.
- **Bracketed paste**: new `Terminal::pasteText` uses `ghostty_paste_encode`
  (strips unsafe bytes, wraps in `ESC[200~..201~` when mode 2004 is set),
  exposed as `pasteText` through the N-API bridge and
  `TerminalController.paste`; the context-menu paste path uses it.
- **UTF-8 stream integrity**: both output paths no longer corrupt multi-byte
  characters split across read chunks — `FusionAgentDriver.decodeUtf8` buffers
  the incomplete tail between WebSocket frames, and the native driver's
  `EmitOutput` holds back trailing partial sequences before crossing the
  N-API string boundary.
- **Fusion Agent session state**: WebSocket handlers are guarded per socket
  instance (late events from a replaced socket can no longer pollute a new
  session); `exit` now tears the socket down before reporting, so input cannot
  be written into a dead shell. The 2026-07-03 jscrash
  (`status.label`/`error` undefined at `Index.ets:51`) was already fixed in
  the working tree by null-safe `formatStatusLabel`/`emitStatus`.
- **UI baseline**: aligned with desktop Ghostty — near-black chrome (`#050507`
  surface via the adjusted Catppuccin_Mocha theme file), ghostty-style window
  padding (14/12), bar cursor without blink, font-size 13, and per-tab status
  filaments. The later 2026-07-18 Direction A pass supersedes this pass's
  top-bar/drawer composition.
- **Box drawing**: corner strokes overlap at the cell center so `┌`-style
  joints no longer show a notch.

Everything above still needs a DevEco build + on-device pass (font rendering,
IME, external keyboard, tmux mouse) — this workspace has no HarmonyOS
toolchain.

## 2026-07-03 Customization / Multi-Window / Mouse-Drag Pass

A second uncommitted pass (same Claude Code session) added:

- **Custom font import**: Settings panel imports a user `.ttf`/`.otf` via
  DocumentViewPicker into `filesDir/fonts/`, registered at runtime as
  `FusionTerm Custom` at the head of the renderer fallback chain
  (`registerCustomFont` through renderer -> N-API -> `TerminalController`);
  glyph cache is rebuilt and the grid re-measured. Reset requires an app
  restart to fully drop the registered family.
- **Background image + acrylic blur + opacity**: PhotoViewPicker copies the
  image into the sandbox; it renders behind the terminal with adjustable
  ArkUI `blur` (0-60) and the terminal surface honors ghostty
  `background-opacity` semantics — only default-background cells go
  translucent (`bgOpacity` through TerminalConfig -> renderer; opaque when no
  image is set). Chrome/panel colors stay opaque. NOTE: relies on
  XComponent SURFACE alpha compositing; if the device shows black instead of
  the image, switch the XComponent to TEXTURE type and re-verify.
- **Appearance persistence**: `entry/src/main/ets/settings/AppearanceStore.ets`
  (`@ohos.data.preferences`) stores font size, theme, custom font path,
  background path, opacity, and blur; restored on launch.
- **Multi-window**: `EntryAbility` is now `launchType: multiton` with a `+`
  button (startAbility on self) so each window is an independent terminal,
  matching desktop Ghostty windows. The entry native driver was de-globalized
  into a session registry (`createSession`/`destroySession`, all N-API calls
  take a sessionId) so concurrent windows cannot stomp each other's PTY/SSH.
- **tmux mouse drag**: external-mouse drag motions now report the held button
  (xterm button-motion encoding) so tmux pane splitters can be dragged; while
  an app tracks the mouse, touch is synthesized as a mouse — tap = left
  click, long-press then drag = button drag (pane resize), plain swipe =
  wheel scrolling.
- At that date, the settings panel replaced the theme toggle and the top bar was
  `+ / VM / Local / Cfg`. The 2026-07-18 Direction A section above is the current
  chrome contract.

All of it still needs the DevEco build + on-device pass; the multi-window
path additionally needs a check that windows share the process cleanly and
the surface-alpha check above.

## 2026-07-03 Hardened wand-agent Fork

The VM backend now has a hardened fork: `beforeugone520/wand-agent`
(commit `2974ee3`, upstream `ystyle/wand-agent` v0.2.3). Fixes: frame-type
routing (binary -> PTY, text -> control), single serialized WebSocket writer,
Bearer auth + constant-time compare + Origin allowlist + default bind
127.0.0.1, process-group teardown with an explicit `exit` event,
real `--host/--port/--max-sessions`, no agent-side bracketed paste,
protocol-level ping/pong heartbeat with read deadlines, `fork` removed.
End-to-end Go tests live in `main_test.go` (auth / shell round-trip /
frame routing / session limit / exit event) and pass on the openEuler VM.
The binary is installed at `/usr/local/bin/wand-agent` on the VM; run it as:

```sh
wand-agent --host 172.16.100.2 --token harmonyterm
```

`FusionAgentDriver.connect` now also sends `Authorization: Bearer <token>`
(query token kept for stock-agent compatibility).

## Do Not Drift

Keep the product focused on the Fusion VM terminal path. Earlier brainstorming
included AI note apps, PPT/PDF annotation, and lifestyle products, but those are
not part of Emberline unless the user explicitly reopens that scope.
