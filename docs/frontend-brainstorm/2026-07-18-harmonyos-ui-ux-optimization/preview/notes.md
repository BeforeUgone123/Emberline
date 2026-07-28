# Preview Notes

## Status

The Harmony Native Workbench calibration preview was approved on 2026-07-18
and translated into the ArkUI dev worktree. It remains a design reference, not
runtime evidence. The default preview opens directly into the terminal;
`?inspector=connection` opens the comparison inspector.

## QA Evidence

- HTML validation: `html-validate` passed with no errors.
- Playwright interaction/layout suite: 6 tests passed.
- Verified viewports: 720x820, 960x820, and 1440x900.
- Captured default-workspace and connection-inspector screenshots under `preview/qa/`.
- Checked terminal-first launch, three persistent app actions, inspector fit, no horizontal overflow,
  tab creation, font control, overflow menu, focus return, and reconnect state settlement.

## Decisions Carried Into ArkUI

- Top-rail density and the limit of three persistent app actions.
- Tab selected, pending, connected, and unread-complete signals.
- Right-inspector width, hierarchy, and the three destinations.
- Connection status and inline recovery treatment.
- Terminal/font/appearance control density.
- Compact-window behavior around 720 vp.

## Implemented Preview Interactions

- Switch and close session tabs; create a new tab.
- Open connection/settings inspectors and switch their destinations.
- Open the overflow menu and close transient surfaces with `Esc`.
- Change terminal font size, cursor segment, theme filter/theme, and opacity preview.
- Trigger the connection pending-to-connected state.

## Deliberate Limits

- This is standalone HTML for visual calibration, not an ArkUI implementation source.
- Lucide icons are loaded from a pinned CDN build; production will use native HarmonyOS symbols/resources.
- System window behavior, terminal XComponent input, and real connection state are simulated.
- Browser `Tab` traversal in this calibration preview is not the production key model. ArkUI must keep
  terminal `Tab` semantics and expose chrome through an explicit desktop focus route such as `F6`.
- Direction C's expanded session rail and telemetry are intentionally absent.

## Remaining Production Validation

- DevEco compile and codelinter at SDK `5.0.0(12)`.
- 720/960/1280/1600 vp device screenshots and long-text/accessibility checks.
- Keyboard, pointer, touchpad, touch, IME, focus return, and input-block QA.
- Long tmux output, resize, theme browsing, background, and multi-window profiling.

Current ArkUI status is maintained in [`../project-context.md`](../project-context.md).
