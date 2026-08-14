# Emberline UI/UX Direction Options

> **Status 2026-07-18:** Direction A was selected and translated into ArkUI in
> the `dev` worktree. P0/P1 source structure is present; P2 device profiling,
> accessibility, and component extraction remain open. Current status lives in
> [`project-context.md`](project-context.md).

## Decision

Recommend **Direction A: Harmony Native Workbench**, borrowing the command palette and low-chrome
discipline from Direction B. Direction C is a later expanded-window mode, not the default shell.

| Direction | HarmonyOS fit | Daily efficiency | Discoverability | Render risk | Decision |
| --- | --- | --- | --- | --- | --- |
| A. Harmony Native Workbench | High | High | High | Low | Recommended baseline |
| B. Ghostty Purist | Medium | Very high for experts | Medium | Lowest | Borrow interaction ideas |
| C. Fusion Control Desk | High on wide screens | High for many sessions | High | Medium | Defer until session core is mature |

## Recommended Information Architecture

### Persistent Top Rail

- Left/center: horizontally scrollable session tabs and new-session icon.
- Right: connection, settings, and overflow only.
- Remove the quick-key action entirely; move help and diagnostics into overflow.
- Keep connection state inside the active tab filament and accessible status text, rather than adding a
  second large status badge.

### Right Inspector

- Consolidate five destinations into three: `终端`, `外观`, `连接`.
- Put Help, diagnostics, version, and agent setup under overflow or a secondary page.
- Keep advanced SSH and image-relay settings collapsed until explicitly requested.
- Use native control semantics: segmented control for cursor style, switch for booleans, stepper for font
  size, menu/radio selection for modes, slider for continuous values, and icon buttons for commands.

### Responsive Behavior

- 720-899 vp: 340-360 vp overlay inspector; nonessential rail labels collapse; terminal remains visible.
- 900-1279 vp: 400 vp overlay inspector with two-column setting rows where they fit.
- 1280 vp and above: inspector may pin only when the user asks; default remains overlay to maximize the
  terminal. A future compact session rail is allowed only here.
- Free-window resize must never animate terminal width/height; the grid reflows immediately.

## Visual System

- Use three opaque depth levels: terminal/app background, chrome, and elevated inspector/menu.
- Keep radii at 4/6/8 vp; no pill-shaped general controls and no floating card sections.
- Use HarmonyOS Sans/system font for chrome and the selected mono font only inside terminal/font previews.
- Use 12/13/14 vp chrome typography with zero letter spacing; reserve larger type for modal titles only.
- Retain ember copper for the filament and primary action. Use neutral borders and semantic status text/icons
  so color is never the only signal.
- Prefer HarmonyOS Symbol/native icons where available; every unfamiliar icon gets a tooltip and
  accessibility description.

## Interaction Model

- Keyboard: logical focus order, visible focus indication, `Esc` closes the topmost overlay, and terminal
  focus is restored after every chrome command.
- Pointer: hover/pressed/disabled states, familiar cursor shapes, right-click menus, middle-click tab close,
  and forgiving invisible hit regions around compact icons.
- Touch: preserve long-press selection and tmux mouse behavior; do not add a competing gesture or soft-key
  layer.
- Connection errors stay inline with `重试` and `详细信息`; they do not replace the terminal with a modal.
- First launch attempts the default Fusion VM target. Failure may open the connection inspector once, but
  never shows a marketing or tutorial page.

## Motion And Performance

- Terminal tab content switches in 0 ms; palette and grid reflow also switch immediately.
- Animate only connection state, selection, overlay enter/exit, and task completion.
- Composite-only properties: opacity, translate, and color. Never animate layout dimensions or CJK scale.
- Stop breathing/looping state motion when hidden or backgrounded.
- Do not blur, dim, or animate a full-screen layer during terminal output.
- Virtualize or progressively load the theme list/previews; do not synchronously parse every theme during
  an interaction.

## Delivery Order

### P0: Correctness And Clarity

1. Remove the quick-key bar and its top-rail action.
2. Reduce persistent actions to connection, settings, and overflow; add tooltips and accessibility text.
3. Pin connection/error/pending state definitions and recovery actions.
4. Verify every overlay blocks XComponent input and returns focus correctly.
5. Add a keyboard/pointer interaction matrix before visual restyling.

### P1: Native Workbench Shell

1. Consolidate the settings information architecture into three destinations.
2. Replace improvised option buttons with appropriate ArkUI controls.
3. Add responsive inspector behavior at 720/900/1280 vp.
4. Normalize spacing, typography, radii, borders, hover, pressed, disabled, and focus states.
5. Move help/diagnostics into overflow and simplify first-run recovery.

### P2: Quality Pass

1. Virtualize theme browsing and audit UI work during long terminal output.
2. Add reduced-motion and background animation gating.
3. Complete accessibility semantics and large-font/long-text checks.
4. Profile CPU, GPU, frame time, memory, and power with long tmux tasks and multiple windows.
5. Split `Index.ets` UI components only after interaction tests protect session behavior.

## Acceptance Gate

- Launch reaches a usable terminal with no intervening page.
- No quick-key UI exists.
- No more than three persistent action icons appear after the tab strip.
- All visible actions are reachable by keyboard and pointer, with visible focus and tooltips.
- No overlap or clipped text at 720, 960, 1280, and 1600 vp.
- Drawer/modal input never reaches the terminal underneath.
- Terminal focus returns after closing a panel or completing an action.
- Connection states are understandable in grayscale and without animation.
- Long tmux output shows no regression with the inspector closed or open.
- Backgrounded windows stop visual work while the network continuous task remains active.
