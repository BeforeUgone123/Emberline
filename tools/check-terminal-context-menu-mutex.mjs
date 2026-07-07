import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

// The terminal right-click menu must be mutually exclusive with the shell's own
// mouse tracking (fish 4.1+ kitty click_events, tmux mouse mode):
//   1. ArkUI must NOT open the app menu unconditionally on right-click; the menu
//      is driven by the native controlled path (setContextMenuListener), which
//      only fires when the right-click was not forwarded to a tracking program.
//   2. TerminalSurface must use the isShown-controlled bindContextMenu overload
//      and register the context-menu listener.
//   3. native must implement the xterm Shift-bypass (m_physShiftDown): while
//      Shift is held, mouse/wheel events skip the tracking program and fall into
//      the local path (drag-select / QueueContextMenuRequest -> app menu).

const surface = await readFile('libghostty_ohos/src/main/ets/TerminalSurface.ets', 'utf8');
const napi = await readFile('libghostty_ohos/src/main/cpp/napi_init.cpp', 'utf8');

function extractFunction(source, signature) {
  const start = source.indexOf(signature);
  assert.notEqual(start, -1, `missing function signature: ${signature}`);
  const braceStart = source.indexOf('{', start);
  assert.notEqual(braceStart, -1, `missing function body: ${signature}`);

  let depth = 0;
  for (let index = braceStart; index < source.length; index += 1) {
    const char = source[index];
    if (char === '{') {
      depth += 1;
    } else if (char === '}') {
      depth -= 1;
      if (depth === 0) {
        return source.slice(start, index + 1);
      }
    }
  }

  assert.fail(`unterminated function body: ${signature}`);
}

// (1) No unconditional right-click menu. This assertion may only tighten.
assert.doesNotMatch(
  surface,
  /\.bindContextMenu\([^;]*ResponseType\.RightClick\)/,
  'right-click must not unconditionally open the app menu (it races the shell mouse menu)'
);

// (2) Controlled isShown overload + native listener registration.
assert.match(
  surface,
  /\.bindContextMenu\(this\.contextMenuVisible, this\.buildTerminalContextMenu\(\),/,
  'terminal context menu must use the isShown-controlled overload bound to a @State flag'
);

// The menu must bind to a movable 1x1 anchor, NOT the XComponent: placement is
// resolved against the bound component, and against the full-screen surface
// every side overflows, so ArkUI falls back to centering the menu on screen
// (menu opened mid-screen instead of at the pointer).
const xComponentBuilder = extractFunction(surface, 'private buildTerminalXComponent()');
assert.doesNotMatch(
  xComponentBuilder,
  /bindContextMenu/,
  'bindContextMenu must not sit on the full-screen XComponent (placement overflows every side and the menu centers on screen)'
);
const anchorBuilder = extractFunction(surface, 'private buildContextMenuAnchor()');
assert.match(
  anchorBuilder,
  /\.position\(\{ x: this\.contextMenuAnchorX, y: this\.contextMenuAnchorY \}\)/,
  'menu anchor must track the right-click point via .position'
);
assert.match(
  anchorBuilder,
  /\.hitTestBehavior\(HitTestMode\.None\)/,
  'menu anchor must not intercept touches meant for the terminal'
);
assert.match(
  anchorBuilder,
  /placement: Placement\.BottomLeft/,
  'menu opens below-left of the pointer anchor (desktop convention, auto-flips at edges)'
);
assert.match(
  surface,
  /this\.buildContextMenuAnchor\(\);/,
  'anchor must be mounted in the surface Stack so the controlled menu can open'
);
assert.match(
  surface,
  /@State private contextMenuVisible: boolean = false;/,
  'controlled menu needs an @State visibility flag'
);
assert.match(
  surface,
  /this\.controller\.setContextMenuListener\(\(x: number, y: number\): void => \{\s*this\.showContextMenuAtPixel\(x, y\);\s*\}\);/s,
  'surface must register the native context-menu listener so the controlled path is consumed'
);
assert.match(
  surface,
  /this\.controller\.setContextMenuListener\(null\);/,
  'surface must unregister the context-menu listener on teardown'
);
assert.match(
  surface,
  /onDisappear: \(\) => \{[\s\S]*?this\.contextMenuVisible = false;[\s\S]*?\}/,
  'menu must reset contextMenuVisible on dismiss or it can never reopen'
);
assert.match(
  surface,
  /private showContextMenuAtPixel\(pxX: number, pxY: number\): void \{[\s\S]*?this\.contextMenuVisible = true;[\s\S]*?\}/,
  'surface must convert the native px point and open the controlled menu'
);

// (3) Native Shift-bypass state.
assert.match(napi, /bool m_physShiftDown = false;/, 'native needs a persistent physical-shift flag');
assert.match(
  napi,
  /bool IsShiftKeyCode\(OH_NativeXComponent_KeyCode code\)/,
  'native needs a helper that recognises the Shift key in both code schemes'
);
assert.match(
  napi,
  /code == KEY_SHIFT_LEFT \|\| code == KEY_SHIFT_RIGHT \|\|\s*code == LINUX_KEY_LEFT_SHIFT \|\| code == LINUX_KEY_RIGHT_SHIFT/,
  'shift detection must cover HarmonyOS KEY_SHIFT_* and Linux evdev codes'
);

// DispatchKeyEvent maintains the flag on DOWN/UP.
const dispatchKeyEvent = extractFunction(napi, 'bool DispatchKeyEvent(');
assert.match(
  dispatchKeyEvent,
  /if \(IsShiftKeyCode\(code\)\) \{[\s\S]*?m_physShiftDown = true;[\s\S]*?m_physShiftDown = false;[\s\S]*?return false;\s*\}/,
  'DispatchKeyEvent must set m_physShiftDown on DOWN and clear it on UP'
);

// Mouse bypass sits at the entry, before the mouse-tracking gate.
const trySendMouse = extractFunction(napi, 'bool TrySendTerminalMouseEvent(');
assert.match(
  trySendMouse,
  /if \(m_physShiftDown\) \{\s*return false;\s*\}/,
  'TrySendTerminalMouseEvent must bypass tracking while Shift is held'
);
assert.ok(
  trySendMouse.indexOf('m_physShiftDown') <
    trySendMouse.indexOf('isMouseTrackingEnabled'),
  'shift bypass must run before the mouse-tracking check so it truly short-circuits forwarding'
);

// Wheel bypass (xterm: Shift+wheel scrolls local scrollback).
const trySendWheel = extractFunction(napi, 'bool TrySendTerminalWheelEvent(');
assert.match(
  trySendWheel,
  /if \(m_physShiftDown\) \{\s*return false;\s*\}/,
  'TrySendTerminalWheelEvent must bypass tracking while Shift is held'
);
assert.ok(
  trySendWheel.indexOf('m_physShiftDown') <
    trySendWheel.indexOf('isMouseTrackingEnabled'),
  'wheel shift bypass must run before the mouse-tracking check'
);

// Reset on focus loss so a missed key-up cannot leave the bypass stuck on.
const setImeActive = extractFunction(napi, 'void SetImeActive(');
assert.match(
  setImeActive,
  /m_physShiftDown = false;/,
  'losing input focus must reset the held-shift flag'
);

console.log('check-terminal-context-menu-mutex: OK');
