import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const surface = await readFile('libghostty_ohos/src/main/ets/TerminalSurface.ets', 'utf8');
const controller = await readFile('libghostty_ohos/src/main/ets/TerminalController.ets', 'utf8');
const types = await readFile('libghostty_ohos/src/main/ets/TerminalTypes.ets', 'utf8');
const terminalHeader = await readFile('libghostty_ohos/src/main/cpp/terminal/terminal.h', 'utf8');
const terminalImpl = await readFile('libghostty_ohos/src/main/cpp/terminal/terminal.cpp', 'utf8');
const nativeBridge = await readFile('libghostty_ohos/src/main/cpp/napi_init.cpp', 'utf8');
const scrollbarOverlayBlock =
  surface.match(/private buildScrollbarOverlay\(\) \{[\s\S]*?\n  \}/)?.[0] ?? '';

assert.match(
  types,
  /export interface TerminalScrollbarState \{\s*total: number;\s*offset: number;\s*visible: number;\s*\}/s,
  'ArkTS should expose complete scrollbar geometry, not only scrollback length'
);

assert.match(controller, /getScrollbarState: \(surfaceId: string\) => TerminalScrollbarState;/);
assert.match(controller, /scrollToOffset: \(surfaceId: string, offset: number\) => void;/);
assert.match(controller, /getScrollbarState\(\): TerminalScrollbarState \{/);
assert.match(controller, /return this\.native\.getScrollbarState\(this\.nativeSurfaceId\);/);
assert.match(controller, /scrollToOffset\(offset: number\): void \{/);

assert.match(terminalHeader, /struct TerminalScrollbarState \{/);
assert.match(terminalHeader, /TerminalScrollbarState getScrollbarState\(\) const;/);
assert.match(terminalHeader, /void scrollToOffset\(int offset\);/);
assert.match(terminalImpl, /TerminalScrollbarState Terminal::getScrollbarState\(\) const\s*\{/);
assert.match(terminalImpl, /void Terminal::scrollToOffset\(int offset\)\s*\{/);
assert.match(terminalImpl, /getScrollbarLocked\(\)/);
assert.match(terminalImpl, /determineScrollStepTowardsBottomLocked\(\)/);
assert.match(
  terminalImpl,
  /if \(stepTowardsBottom != 0\) \{\s*scrollViewportLocked\(GHOSTTY_SCROLL_VIEWPORT_TOP\);[\s\S]*?if \(originalOffset > 0\)/,
  'detecting the Ghostty scroll delta sign must restore the original viewport even when it started at the top'
);

assert.match(nativeBridge, /TerminalScrollbarState GetScrollbarState\(\) const \{/);
assert.match(nativeBridge, /void ScrollToOffset\(int offset\) \{/);
assert.match(nativeBridge, /static napi_value GetScrollbarState\(napi_env env, napi_callback_info info\)/);
assert.match(nativeBridge, /static napi_value ScrollToOffset\(napi_env env, napi_callback_info info\)/);
assert.match(nativeBridge, /napi_set_named_property\(env, result, "total", totalVal\);/);
assert.match(nativeBridge, /napi_set_named_property\(env, result, "offset", offsetVal\);/);
assert.match(nativeBridge, /napi_set_named_property\(env, result, "visible", visibleVal\);/);
assert.match(nativeBridge, /\{"getScrollbarState", nullptr, GetScrollbarState/);
assert.match(nativeBridge, /\{"scrollToOffset", nullptr, ScrollToOffset/);

assert.match(surface, /private scrollbarTimer: number = -1;/);
assert.match(surface, /@State private scrollbarTotal: number = 0;/);
assert.match(surface, /@State private scrollbarOffset: number = 0;/);
assert.match(surface, /@State private scrollbarVisible: number = 0;/);
assert.match(surface, /@State private scrollbarTrackHeight: number = 0;/);
assert.match(surface, /@State private scrollbarDragging: boolean = false;/);
assert.match(
  surface,
  /Stack\(\{ alignContent: Alignment\.TopEnd \}\) \{[\s\S]*?this\.buildTerminalXComponent\(\);/,
  'terminal surface root Stack should place the narrow scrollbar child at the top-right instead of default-centering it'
);
assert.match(surface, /this\.buildScrollbarOverlay\(\);/);
assert.match(surface, /private buildScrollbarOverlay\(\)/);
assert.doesNotMatch(
  scrollbarOverlayBlock,
  /Stack\(\) \{[\s\S]*?Blank\(\)/,
  'ArkUI Blank cannot be nested directly under Stack; scrollbar track/thumb should use Stack-safe components'
);
assert.doesNotMatch(
  scrollbarOverlayBlock,
  /\.align\(Alignment\.End\)/,
  'scrollbar placement must be controlled by the parent Stack alignContent, not a child align modifier that defaults to center placement'
);
assert.match(surface, /PanGesture\(\{ direction: PanDirection\.Vertical/);
assert.match(surface, /private handleScrollbarDrag\(deltaY: number\): void \{/);
assert.match(surface, /this\.controller\.scrollToOffset\(desiredOffset\);/);
assert.match(surface, /private syncScrollbarState\(\): void \{/);
assert.match(surface, /this\.controller\.getScrollbarState\(\);/);
assert.match(surface, /private startScrollbarPolling\(\): void \{/);
assert.match(surface, /private stopScrollbarPolling\(\): void \{/);

// M24: the auto-hiding scrollbar overlay fades in/out rather than hard
// mounting, and the polled thumb position is tweened (only while not dragging)
// with height/color changes frozen so no relayout tween ever fires.
assert.match(
  scrollbarOverlayBlock,
  /\.transition\(TransitionEffect\.OPACITY\.animation\(\{ duration: DUR_OVERLAY_FADE, curve: CURVE_DECEL_LOCAL \}\)\)/,
  'M24: scrollbar overlay must fade with its auto-hide instead of a hard mount/unmount'
);
assert.match(
  scrollbarOverlayBlock,
  /\.animation\(\{ duration: 0 \}\)\s*\.position\(\{[\s\S]*?\}\)\s*\.animation\(\{ duration: this\.scrollbarDragging \? 0 : DUR_THUMB_TWEEN, curve: Curve\.Linear \}\)/,
  'M24: thumb position must tween (non-drag only) with height/color frozen ahead of it so the poll never triggers a relayout animation'
);

// M21: a rising-edge boundary flash paints a thin ember edge line when the
// scrollback reaches the very top/bottom; content itself must never move.
assert.match(surface, /const EMBER_BOUNDARY_COLOR: string = '#D08F53';/);
assert.match(surface, /@State private topBoundaryGlow: number = 0;/);
assert.match(surface, /@State private bottomBoundaryGlow: number = 0;/);
assert.match(surface, /this\.buildBoundaryGlow\(\);/);
assert.match(surface, /private buildBoundaryGlow\(\)/);
assert.match(surface, /\.hitTestBehavior\(HitTestMode\.None\)/);
assert.match(surface, /private detectBoundaryEdges\(offset: number, maxOffset: number\): void \{/);
assert.match(surface, /private flashBoundary\(top: boolean\): void \{/);
assert.match(
  surface,
  /this\.detectBoundaryEdges\(clampedOffset, maxOffset\);/,
  'M21: boundary edges must be evaluated from the same clamped offset the scrollbar uses'
);
