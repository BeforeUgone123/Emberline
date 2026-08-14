# Project Context

## Implementation Status — 2026-07-18

Direction A, **Harmony Native Workbench**, is implemented in the `dev` worktree
at `/mnt/linux_share/preview/harmony-advanced-terminal`. The standalone HTML
preview remains a calibration reference; production behavior lives in ArkUI.

Implemented in source:

- terminal-first launch with the inspector closed;
- a 48 vp custom title/tab rail;
- exactly three persistent app actions after the tabs: connection, settings,
  and overflow;
- a right overlay inspector with exactly `终端`, `外观`, and `连接`;
- 352 vp inspector width below 900 vp and 400 vp from 900 vp upward;
- no quick-key row and no automatic onboarding;
- help/diagnostics and new-window actions in overflow;
- `F6` or `Ctrl+Alt+.` terminal -> chrome -> inspector focus routing and `Esc`
  close/focus return;
- input blocking for inspector, tab editor, help panel, and background state;
- inline connection retry/details and pending animation gating;
- progressive theme preview loading;
- background-aware terminal visibility/polling and chrome motion gates.

The implementation is protected by `tools/check-harmony-native-workbench.mjs`
and the updated integration checks. All 33 source-structure scripts passed in
the current dev worktree on 2026-07-18.

## Architecture Boundary

- `libghostty_ohos` owns the reusable XComponent renderer.
- `entry/src/main/ets/pages/Index.ets` owns the current workbench and most UI
  orchestration.
- Direction A did not modify renderer, native C++, N-API, transports,
  `KeepAliveManager.ets`, signing, SDK versions, or the release worktree.
- Component extraction remains deferred until executable interaction/lifecycle
  tests protect the current single-page orchestration.

## Remaining Validation

The current Codex environment has no HarmonyOS toolchain, so none of these are
closed by the source implementation:

1. ArkTS/Hvigor compilation and codelinter on SDK `5.0.0(12)`.
2. 720, 960, 1280, and 1600 vp free-window, split-screen, and multi-window QA.
3. Physical keyboard, mouse, touchpad, touch, IME, terminal Tab semantics, and
   focus-return QA.
4. Long tmux output with inspector open/closed, resize, multiple tabs/windows,
   and theme browsing under Profiler.
5. Background `taskKeeping`, screen-off continuity, foreground screen-on, and
   resume focus behavior.
6. Largest supported chrome font scale, long CJK/host/error text, grayscale,
   contrast, and accessibility semantics.

No document in this folder should claim device performance or completion until
that matrix has been recorded.

## HarmonyOS Interpretation

HarmonyOS quality is expressed here through adaptive layout, native control
semantics, multi-input interaction, multi-window continuity, performance, and
power behavior. It is not expressed by adding translucent material over the
terminal. The workspace remains opaque and terminal-led.

Official design references used during the direction phase:

- https://developer.huawei.com/consumer/cn/design/devstart/
- https://developer.huawei.com/consumer/cn/multidevice/pc/get-started/
- https://developer.huawei.com/consumer/cn/best-practices/multidevice/
- https://developer.huawei.com/consumer/cn/best-practices/
