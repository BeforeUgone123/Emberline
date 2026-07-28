# Visual Direction Prompts

These prompts are prepared for later project-aware mockup generation. They are not production UI
instructions and must not be copied literally into ArkUI.

## Direction A: Harmony Native Workbench

Use case: ui-mockup
Asset type: high-fidelity desktop/2-in-1 terminal application concept
Primary request: Design Emberline as a restrained HarmonyOS productivity workbench. The terminal fills
almost the entire window. A compact 48 vp top rail combines native window chrome and terminal tabs. The
right side has only connection, settings, and overflow icon actions. Show a narrow right inspector open
for connection settings, with clear connected/pending/error states and one primary action.
Style: near-black opaque surfaces, HarmonyOS Sans for chrome, monospace terminal, 4/8/12/16 spacing,
4-8 px radii, hairline borders, one ember-copper accent used only for the state filament and primary action.
Constraints: keyboard/mouse-first, free-window layout, no cards inside cards, no quick-key bar, no blur
over the terminal, no gradients, no neon, no oversized headings, no marketing copy.

## Direction B: Ghostty Purist

Use case: ui-mockup
Asset type: high-fidelity minimal terminal application concept
Primary request: Design Emberline with the least possible chrome. Tabs and a single compact status/action
cluster sit in the title rail; most actions live in right-click menus and a command palette. Settings open
as a focused utility panel without covering more terminal than necessary.
Style: almost-black flat surfaces, neutral typography, zero decorative elevation, thin dividers, instant
terminal switching, tiny ember state filament.
Constraints: preserve discoverability through tooltips, focus rings, and command search; no hidden
gesture-only actions; no soft keys; no visual spectacle.

## Direction C: Fusion Control Desk

Use case: ui-mockup
Asset type: high-fidelity developer operations terminal concept
Primary request: Design Emberline for users managing several Fusion VM sessions. Keep the terminal as the
center surface, add an optional compact session rail on expanded windows, and show an optional right-side
connection/task inspector with host, transport, latency, task state, and recovery actions.
Style: dense native desktop utility, opaque dark layers, compact rows, status typography plus small
semantic icons, ember accent only for active/primary state.
Constraints: side rails collapse completely below expanded width; never turn the first screen into a
dashboard; no KPI cards, charts, gradients, or persistent animation.

## Shared Avoid List

- On-screen quick-key row.
- Mobile bottom navigation or floating action button.
- Hero layout, onboarding carousel, or card dashboard.
- Glassmorphism across the terminal, background blobs, gradients, scanlines, or cyberpunk neon.
- Rounded rectangles with text where a familiar symbol or native control is clearer.
- CJK text scaling, animated terminal reflow, crossfading terminal canvases, or ambient loops.

