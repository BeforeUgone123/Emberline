# Selected Direction

> **Status 2026-07-18:** approved and implemented in the `dev` worktree at the
> source-structure level. DevEco compilation, device interaction, performance,
> power, and accessibility validation remain open. See
> [`project-context.md`](project-context.md) for the exact implementation and QA
> boundary.

## Selection

The approved direction is **A: Harmony Native Workbench**.

## Why It Fits Emberline

- It keeps the terminal as the product rather than wrapping it in a dashboard.
- It expresses HarmonyOS quality through adaptive windows, native control semantics, focus behavior,
  pointer behavior, and system-level polish.
- It retains the current Ghostty-like restraint and the ember filament instead of introducing a new
  decorative language.
- It can improve discoverability without adding permanent chrome or expensive rendering effects.
- It gives the Fusion VM connection flow a clear home while keeping SSH/local paths secondary.

## Signals To Preserve

- Near-black opaque terminal and chrome surfaces.
- Thin ember filament for connected, pending, failed, completed, and selected states.
- Compact session tabs integrated with the window title rail.
- True terminal typography and immediate tab/grid changes.
- Right-side contextual inspector rather than a separate settings home page.

## Borrowed From Direction B

- A strict limit on permanent chrome.
- Help and diagnostics in the overflow menu.
- Command search as a later keyboard-first enhancement.
- Context menus for expert actions rather than additional toolbar buttons.

## Explicit Rejections

- Direction C's session rail and operational telemetry are not part of the default shell.
- No on-screen quick-key row.
- No glass layer over the terminal, decorative gradients, large rounded cards, or ambient animation.
- No dashboard, onboarding carousel, or marketing-style empty state.
- No terminal canvas crossfade, animated reflow, or palette tween.

## Feasibility Notes

- The preview may use browser controls to communicate layout, but production must map them to native
  ArkUI controls and HarmonyOS Symbol resources.
- Responsive inspector widths must be implemented without animating terminal dimensions.
- UI extraction from `Index.ets` comes after interaction and lifecycle checks protect current behavior.
