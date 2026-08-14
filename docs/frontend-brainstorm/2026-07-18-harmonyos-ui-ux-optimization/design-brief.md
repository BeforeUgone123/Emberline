# Harmony Native Workbench Design Brief

## Visual Thesis

A quiet, opaque developer workbench in which terminal content carries the visual energy, while compact
HarmonyOS-native chrome provides orientation, state, and recovery without competing for attention.

## Content Plan

1. **Primary workspace:** full-window terminal canvas, immediately interactive.
2. **Session rail:** one 48 vp top rail containing tabs, new session, three app actions, and system window
   controls.
3. **Context inspector:** a right-side overlay for terminal, appearance, and connection settings.
4. **Transient utilities:** overflow menu, context menu, tooltip, and inline error/recovery states.

## Interaction Thesis

- Terminal/tab changes are immediate; chrome alone acknowledges the selected state.
- The right inspector enters and exits with a short opacity/translate transition that never changes the
  terminal's animated geometry.
- Hover, pressed, focus, pending, failure, and completion feedback is compact, state-driven, and ends as
  soon as the state ends.

## Layout

### Workspace

- Terminal occupies all content below the 48 vp title rail.
- No permanent status bar or bottom toolbar.
- The inspector overlays the right side; it is not a nested card and does not blur the terminal.

### Title Rail

- Tabs consume all remaining width and scroll horizontally.
- Active tab uses a slightly raised opaque face plus its state filament.
- Inactive close icons appear on hover/focus; active close remains available without widening the tab.
- The app action cluster contains connection, settings, and overflow only.
- System minimize, maximize/restore, and close controls retain their own reserved region.

### Inspector

- Width: 352 vp compact, 400 vp medium/expanded.
- Three destinations: `终端`, `外观`, `连接`.
- Header, destination selector, content, and footer actions are full-width bands separated by hairlines.
- Setting rows align label/description left and control right; long controls stack below at compact width.
- Advanced SSH/local/image-relay content is collapsed by default.

## Density And Spacing

- Base spacing: 4, 8, 12, 16, and 24 vp.
- Title rail actions: 32 vp visible bounds with at least a 40 vp response region.
- Setting row minimum height: 48 vp; dense pointer use must not make touch targets unsafe.
- Panel padding: 16 vp; group separation: 20-24 vp; no card gutters inside groups.

## Typography

- Chrome: HarmonyOS Sans/system sans, regular and medium only.
- Terminal and font preview: configured monospace family.
- Roles: 14 vp panel title, 13 vp primary row text, 12 vp tab/status text, 11 vp supporting text.
- Letter spacing is always zero.
- Long host names, CJK titles, and error text wrap or ellipsize without changing control dimensions.

## Color Roles

- App/terminal base: `#050507`.
- Title rail: `#080B10`.
- Inspector: `#10141B`.
- Selected/elevated row: `#151A22`.
- Primary text: `#D7DDEA`; secondary text: `#8D97A8`; border: `#252D39`.
- Ember: `#D08F53`, limited to the active filament, selected indicator, focus accent, and primary action.
- Success/error colors appear only in small semantic status text/icons and never replace the label.

## Radius And Elevation

- Radius tokens: 4, 6, and 8 vp.
- No pill-shaped general controls.
- Hierarchy comes from opaque surface color and hairline borders, not large shadows.
- Menus/tooltips may use one restrained elevation; sections and setting groups remain unframed.

## Components And States

### Session Tab

- States: inactive, hover, focused, active, pending, connected, failed, unread-complete, dragging.
- State filament is paired with title/status semantics so color is never the only cue.
- Click switches immediately; middle-click closes; right-click opens session actions; drag reorders.

### Icon Action

- States: default, hover, pressed, focused, selected/open, disabled.
- Familiar symbol, tooltip, accessibility description, and fixed response region.
- No hover scale or ripple expansion.

### Connection

- States: disconnected, connecting, connected, retrying, authentication failure, transport failure.
- Primary status line names the target and state. Secondary text contains endpoint or concise failure.
- Recovery stays inline: retry first, details second. Advanced transport choices remain collapsed.

### Settings

- Segmented control for short mutually exclusive modes.
- Switch for binary settings, stepper/input for font size, slider for continuous opacity/blur, and menu or
  radio row for longer option sets.
- Live preview applies immediately; persistence and failure behavior remain deterministic.

## Responsive Rules

- `720-899 vp`: 352 vp overlay inspector, compact action gaps, horizontally scrolling tabs.
- `900-1279 vp`: 400 vp overlay inspector and standard action gaps.
- `>=1280 vp`: same overlay by default; optional user-pinned inspector is a later enhancement.
- No animated width, height, margin, padding, font size, or terminal constraint changes.

## Accessibility

- Preserve terminal semantics: while the XComponent owns focus, `Tab` and `Shift+Tab` continue to reach
  the remote terminal and must not enter application chrome.
- Provide an explicit desktop focus route such as `F6` to cycle terminal -> title rail -> inspector;
  inspector controls use a logical local order and a visible focus indicator while it is open.
- `Esc` closes the topmost transient surface and restores terminal focus.
- Icon buttons expose semantic labels; status changes expose text, not color alone.
- Chrome follows system font/accessibility behavior; terminal font size remains an explicit user setting.
- Verify contrast, high-contrast/grayscale recognition, long text, and largest supported chrome font scale.

## Performance Translation

- No blur or opacity animation over the full terminal surface.
- Theme rows/previews load progressively and use a virtualized data source in production.
- Hidden/background windows stop polling and state animation while transport keep-alive continues.
- UI state updates must not be driven by terminal byte throughput.
- Validate with long tmux output, inspector open/closed, resize, multi-window, and background/foreground.
