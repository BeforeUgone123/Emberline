# Emberline HarmonyOS UI/UX Optimization Requirements

## Goal

Define a UI/UX direction that can reach the quality bar of a strong HarmonyOS
desktop/2-in-1 productivity application without turning Emberline into a generic
mobile app or a decorative terminal mockup.

## Primary Surface

- First-screen terminal workspace.
- Session tabs and custom window chrome.
- Fusion VM connection flow and connection states.
- Appearance, font, theme, connection, and help settings.
- Keyboard, mouse, touchpad, touch, free-window, split-screen, and multi-window behavior.

## Product Constraints

- The terminal remains the first and dominant surface; no home dashboard or landing page.
- Fusion Agent to the Fusion Development Engine VM remains the primary path.
- Physical keyboard and pointer are the primary inputs on the target 2-in-1 device.
- Do not add an on-screen quick-key bar.
- Do not change terminal rendering/output behavior as part of visual optimization.
- Preserve the Ghostty-like restrained dark shell and the ember filament state language.
- Motion must communicate a real state and must not compete with terminal rendering.

## Success Criteria

- The main terminal remains immediately usable after launch.
- Primary connection, session, and settings actions are discoverable without adding chrome clutter.
- All chrome workflows work with keyboard only and pointer only.
- Layout remains coherent at 720, 960, 1280, and 1600 vp widths.
- No overlay leaks input into the terminal XComponent.
- Long tmux output, window resizing, and opening settings do not introduce visible stutter.
- Connection, pending, failure, completion, unread, selection, and focus states are distinguishable
  without relying on color alone.
- DevEco accessibility, performance, power, and multi-window checks have explicit acceptance cases.

## Non-Goals

- No marketing-style hero, card dashboard, bottom navigation, or mobile-first shell.
- No full-screen glass/blur treatment, gradients, glow fields, bokeh, or cyberpunk decoration.
- No page-level spectacle, terminal crossfades, animated reflow, or persistent ambient loops.
- No renderer migration or transport redesign in the UI phase.
