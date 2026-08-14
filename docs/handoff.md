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
- VM setup now exposes npm, pnpm, and curl one-line installers. All three
  delegate to the fork's package CLI, which reads the minimum Go version from
  `go.mod`, downloads a checksum-verified toolchain when needed, builds the
  agent, writes a 0600 token EnvironmentFile, and enables the systemd service.
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
  `main`, bundle `com.preview.fusionterm`, label `Emberline`; SDK `6.1.0(23)`
  as well, promoted with PR #1 (decision 2026-07-28 — see the API 23 section).
- The release worktree is not a signing toggle for dev. Promote reviewed changes
  from `dev`, then build with the release identity/signing material in the
  release worktree.

## 2026-07-27 API 23 Upgrade

- The dev product now sets both `compatibleSdkVersion` and `targetSdkVersion`
  to `6.1.0(23)`. It therefore requires an API 23 device.
- `compileSdkVersion` remains implicit and follows the DevEco Studio paired SDK;
  the latest local Hvigor metadata already resolved it to API 23.
- **Promoted to `main` on 2026-07-28 (user decision, PR #1).** Both channels now
  target `6.1.0(23)`. The alternative — holding `main` at `5.0.0(12)` until an
  API 23 release build had been validated — was considered and rejected: dev has
  had a device pass on API 23, and keeping the two channels on different SDK
  targets makes every promotion a two-variable change.
- Consequence to keep in view: the release build now requires an API 23 device
  and **cannot install on anything below API 23**. Before the first release HAP
  ships, the release worktree still needs its own API 23 build, codelinter pass,
  signing/install test and device regression — those are release gates now, not
  promotion gates.
- `KeepAliveManager` now depends on API 15 `continuousTaskCancel` plus API 20
  `continuousTaskSuspend` / `continuousTaskActive` callbacks. This is intentional
  under the API 23 product target; a future downgrade would need guarded event
  registration or a lower-version implementation. The window-decor calls still
  go through an interface assertion rather than compile-time version checking.

## 2026-08-02 Long-Lock Session Loss

- Reported symptom: after a long screen lock, the foreground terminal looks like
  a fresh session and no longer scrolls through the old output.
- Root-cause chain: the current hardened wand-agent gives each WebSocket its own
  PTY and, after heartbeat/read timeout disconnect, cleans that PTY up with a
  process-group `SIGHUP` (then `SIGKILL` fallback). Losing HarmonyOS background
  protection can therefore destroy both the direct task and its scrollback; an
  app-side reconnect necessarily creates a new PTY.
- Source fix: the process-global keep-alive manager now observes continuous-task
  cancel/suspend/active events, retries system cancellation on the next lifecycle
  edge, respects explicit user notification cancellation, tracks the actual owner
  context, and generation-guards async start/stop. A stop that races a reconnect
  immediately re-protects the still-live session. Background/foreground events
  both reconcile the manager.
- Input hardening: native pointer, touch, selection and trackpad-axis state is
  reset on both sides of the background/input-block transition, so a lost
  UP/CANCEL event cannot disable scrolling after unlock.
- 2026-08-05 client hardening: the Agent driver now originates a
  stock-compatible JSON `ping` every 25 seconds, retries initial failures, and
  funnels `connect()`/`send()` errors, rejected promises and false results
  through one socket-generation-guarded failure transition. This reduces idle
  read-deadline disconnects; it does not turn reconnect into PTY reattachment.
- Remaining gate: a target-device lock longer than the agent's 90-second read
  deadline must prove that the original PID and scrollback survive. If the system
  denies/cancels `taskKeeping` or kills the process, the direct wand-agent protocol
  cannot reattach that PTY; tmux remains the operational protection until the
  agent protocol gains durable session IDs and reattachment.

## 2026-08-05 Scrollback And IME Liveness

- All terminal-creation defaults now agree on 50,000 scrollback lines, including
  the native pre-`onLoad` path that can create Ghostty before ArkTS applies app
  configuration. Live Ghostty terminals cannot resize this limit, so validation
  must use a newly created session.
- IME hide/stop, attach/show failure, and selection/cursor IPC failure now revoke
  printable-key delegation. This prevents a stale input-method proxy from
  swallowing letters while digits continue through the native key encoder; a
  later focus/tap can attach the IME again.
- Focused source gates are `check-scrollback-retention.mjs` and
  `check-ime-liveness-fallback.mjs`; device validation still needs a long-running
  physical-keyboard and Chinese-IME soak test.

## 2026-08-05 tmux Fling Damping

- Reported symptom: after a touch or touchpad swipe in tmux mouse mode, scrolling
  continues much farther than the gesture suggests.
- Root cause: local pixel scrollback and mouse-tracked wheel forwarding shared
  the same release velocity and `2.4/s` decay. The latter converts travel into
  discrete wheel events, and tmux may map each event to several content rows, so
  the same physical tail is visibly multiplied. At the 9,000 px/s clamp, the old
  exponential tail integrated to about 3,750 px before the stop threshold.
- Fix: mouse-tracked fling now keeps 20% of release velocity, decays at `9.0/s`,
  and stops at 120 px/s. Its theoretical maximum tail is about 200 px, while
  direct finger tracking and ordinary local scrollback retain their existing
  behavior. `check-tmux-fling-damping.mjs` pins the separate mode parameters and
  maximum-tail bound; final feel still needs device confirmation.

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

- Dragging the only tab out into a new window currently leaves the source alive
  with its auto-backfilled blank tab, while 「移动到窗口」 closes the emptied
  source via `terminateSelf`. Closing only after the new window has actually
  claimed the parked handle needs an explicit registry acknowledgement; do not
  substitute another launch delay.
- `applyDecorButtonMode` no-ops when `mainWindow` is still null, so a cold
  start whose `recomputeChromeTokens` lands before `getMainWindow` returns
  leaves the system decor buttons on the hardcoded dark style. Timing makes
  this unlikely (the token path awaits preferences + a rawfile read), but a
  light theme is where it would show.

## 2026-07-31 Cross-Window Review Repairs

- Tab UI IDs now come from a process-global counter in `TerminalSession.ets`,
  so a handle moved between multiton windows cannot collide with a target tab's
  `ForEach` key or `activeSessionId`.
- The 32ms adoption delay is gone. `TerminalController.unbindNative()` emits a
  dedicated one-shot hand-off detach signal after clearing the native binding;
  move, split, and drag paths adopt or launch only from that signal. The normal
  driver attachment listener remains separate, so the old surface cannot stop
  a newly bound session.
- Vertical lift again starts a programmatic system drag with a custom UDMF
  token. Every tab strip accepts that token for slot-aware merge; a failed
  strip drop tears the live session into a sibling window at the release point.
  Horizontal travel remains the zero-delay in-strip reorder path.
- Both drivers cache and replay the complete last status, including the error
  string (and native mode), preserving failed dots and connection details after
  a move.
- The shared theme value now contains the dark slot, light slot, and color-mode
  override together. Sibling windows replace all three fields before resolving
  their effective theme. Chrome raw-file reads carry a generation and theme-name
  check so an older asynchronous result cannot overwrite a newer choice.
- `check-tab-drag-handoff.mjs` and `check-adaptive-chrome.mjs` pin these
  contracts. Source checks pass; HAP compilation and the cross-window device
  matrix remain pending on a DevEco/HarmonyOS SDK machine.

## 2026-08-01 MatePad Edge Tear-off Crash

- Device build `QXS-W00 6.1.0.135` proved that `StartOptions` is not exposed as
  a runtime constructor: `new StartOptions()` attempted to load
  `@ohos:app.ability.StartOptions` and crashed with `TypeError: Constructor is
  false` after the source surface detached. Tear-off now passes an inferred
  object literal directly to `startAbility(want, options)` and calls the
  one-argument overload when no release geometry is available. The regression
  gate bans both the constructor and its runtime import.

## 2026-07-28 First Merge To `main` (PR #1)

- The whole accumulated working tree was promoted in one commit on top of the
  previously unpushed `prepare Emberline release polish`, merged as `60ca163`.
  A follow-up PR (#2, `docs/readme-refresh`) carries the README rewrite that
  missed the merge by a few minutes.
- **The dev worktree's channel identity must never ride along.** The first
  attempt swept `AppScope/app.json5`, `build-profile.json5` and
  `entry/src/main/module.json5` into the promotion — the dev tree carries a
  local, never-committed override (`.debug` bundle, `Emberline Dev` label,
  DevEco debug signing) precisely so a debug build can sit beside an installed
  release build. `tools/check-dev-worktree-identity.mjs` guards it and is
  deliberately NOT promoted to `main`, where every one of its assertions would
  fail by design (dev has 35 checks, `main` 34).
- `$string:app_name_dev` **stays in the repository** even though `main` never
  references it: the dev worktree's `build-profile.json5` does, so deleting the
  string would break the dev build.
- Verification method worth reusing: to prove a commit matches the build host
  byte-for-byte, compare git *tree* hashes. The remote side can be computed
  without touching its index via
  `GIT_INDEX_FILE=/tmp/idx git read-tree HEAD && GIT_INDEX_FILE=/tmp/idx git add -A && GIT_INDEX_FILE=/tmp/idx git write-tree`.

## 2026-07-28 Release Worktree: Two Traps Behind One Build Failure

Both bit on the first `main` build in the release worktree.

1. **`git reset --mixed` does not touch the working tree.** The release worktree
   ended up with HEAD at `60ca163` while every file still held the old `main`
   content — 73 paths showing as `M`/`D`/`??` that exactly mirrored the promotion
   diff. The build therefore compiled *old code against the old SDK config*
   (`OHOS_COMPATIBLE_SDK_VERSION=5.0.0(12)` in the CMake cache) even though the
   pull "succeeded". `--mixed` is the right tool for the *dev* worktree, where
   the files already equal the new `main`; it is the wrong tool here. Recovery
   was `git checkout -- .` after confirming none of the 73 paths was a local
   customisation.
2. **`third_party/` is gitignored, so a fresh worktree cannot build.**
   `entry/src/main/cpp/CMakeLists.txt:15` fails hard with "Run
   tools/fetch-third-party.sh from the project root before native build." Either
   run that script, or copy `third_party/{libssh2,mbedtls}` from the dev
   worktree (~56 MB, faster and avoids a re-clone). Pinning must stay
   mbedtls-3.6.6 / libssh2-1.11.1; each directory carries a `.source-version`.

Also clear `entry/.cxx` and `libghostty_ohos/.cxx` after an SDK change —
`hvigor clean` does not, and the stale CMake cache pins the old SDK version.

## 2026-07-28 Native Code Really Does Need API 23

Recorded because the opposite was asserted mid-session and was wrong. The ArkTS
side is undemanding — `KeepAliveManager` only calls
`WantAgentInfo.actionType/actionFlags` (API 11+) and `BackgroundMode.TASK_KEEPING`
(API 9); the `continuousTask*` events appear in comments as provenance only, and
the window-decor calls go through an interface assertion so they are not
compile-time version checked.

**The native side is not.** Building against deployment target 12 emits seven
`-Wunguarded-availability` warnings for symbols that would be missing at runtime
on an older device:

| Symbol | Introduced |
| --- | --- |
| `OH_NativeXComponent_GetKeyEventModifierKeyStates` | 20.0.0 |
| `OH_NativeXComponent_GetKeyEventCapsLockState` | 20.0.0 |
| `OH_Drawing_AddTextStyleDecoration` | 18.0.0 |
| `OH_ArkUI_AxisEvent_GetAxisAction` | 15.0.0 |
| `OH_AttachOptions_CreateWithRequestKeyboardReason` | 15.0.0 |
| `OH_InputMethodProxy_ShowTextInput` | 15.0.0 |
| `OH_NativeXComponent_RegisterKeyEventCallbackWithResult` | 14.0.0 |

They compile as warnings, so a downgraded build would ship and then crash. These
warnings disappearing is a useful signal that the API 23 target took effect.

## 2026-07-28 Tracked Signing Material (unresolved)

`docs/key/` (p12 private keys + CSRs) was untracked but **not ignored** — one
`git add -A` from being published. `.gitignore` now covers it plus tree-wide
`*.p12` / `*.csr` / `*.p7b` / `*.keystore` / `*.cer`.

**Still open:** `docs/material/` — a DevEco keystore material tree (hash-bucketed
`ac`/`ce`/`fd`) — is *already tracked* and was pushed in `bc19b09`, so it is in
the GitHub history. Adding it to `.gitignore` does not untrack it. The five files
are small (16–48 bytes: material indices, not full private keys) and the
repository is private, so this is not urgent, but it needs a decision:
`git rm --cached -r docs/material/` stops future changes from being recorded,
while removing it from history needs a filter-repo/BFG pass and a force-push that
would rewrite already-merged commits.

## 2026-07-28 Store Assets Rebuilt Around The New Brand Claim

The 2026-07-18 store assets were written around the ember-copper filament as the
one thing on screen that glows. That retired with the no-accent chrome, so both
files were rewritten:

- `docs/store-listing/app-description.txt` — new claim ("it has no colour of its
  own"), plus an appended change log recording exactly what was deleted and under
  which gate, so the SSH/SFTP and background-continuity copy can be restored
  verbatim once CR-001–CR-004 close and the long-lock device gate passes.
- `docs/store-listing/screenshot-prompts.txt` — replaced the 6-shot deep-space-grey
  plan; the delivered set is four 1920×1080 cards under
  `/mnt/linux_share/preview/emberline-promo/`, shot from real device captures via
  headless Chrome at 960×540 CSS × device-scale-factor 2 (vector type rasterised
  at 2x, screenshot never re-encoded).
- `docs/store-listing/release-notes.txt` — new. Holds both a first-launch and an
  incremental variant; the repo has no tags and no CHANGELOG, so 1.0.0 is a first
  submission.

Copy that must not return until its gate lifts: SSH/SFTP (CR-001–CR-004), "stays
connected in the background" until the long-lock device matrix passes, and the
on-screen accessory key bar (CR-012 — a product decision, not a gate, so it never
returns).

## Verification And Limits

- This Codex environment has no `ohpm`, Hvigor/Harmony SDK, codelinter, or `hdc`.
  It cannot prove ArkTS compilation, HAP signing/install, runtime permissions,
  device behavior, frame time, memory, or power.
- The local quality gate contains 36 source-structure checks. They protect
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

The VM backend now has a hardened fork: `BeforeUgone123/wand-agent`
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

## 2026-08-01 One-line Agent Setup

The fork now ships an npm/pnpm package CLI (`wand-agent` 0.3.0). Emberline's
`tools/install-wand-agent.sh` is deliberately a thin curl bootstrap: it checks
Node 16+, downloads the selected fork ref, and delegates to
`wand-agent service install`. Go version selection, verified toolchain
downloads, the build, stable binary copy, token storage, and `systemd
enable --now` remain owned by the agent package rather than being duplicated
in the app repository.

The README and in-app Help expose equivalent pnpm, npm, and curl one-line
commands. `tools/check-agent-setup-guide.mjs` pins those entry points and the
delegation boundary. The default examples use `harmonyterm` only for the
trusted Fusion VM bridge; omitting `--token` generates a random token.

The same decision restores a deliberately narrow first-launch prompt,
superseding Direction A's blanket automatic-onboarding removal. The terminal
surface is mounted first, then `OnboardingStore` lets one window claim the
deploy/connect walkthrough and persists the versioned setup-seen key. The
prompt opens directly on the install commands and can hand off to the
connection inspector; Help remains the permanent way to reopen the complete
walkthrough. It is not a standalone welcome page, carousel, dashboard, or
quick-key surface.

## Do Not Drift

Keep the product focused on the Fusion VM terminal path. Earlier brainstorming
included AI note apps, PPT/PDF annotation, and lifestyle products, but those are
not part of Emberline unless the user explicitly reopens that scope.
