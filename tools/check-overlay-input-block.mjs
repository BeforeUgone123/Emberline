import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

// With the settings drawer or tab editor open, the terminal must go deaf.
// The ArkUI hit-test (drawer HitTestMode.Default while open) only shields
// touch and mouse dispatch; two XComponent channels bypass sibling occlusion
// entirely and leaked overlay interactions into the terminal:
//   - key events route by focus (the XComponent keeps focus under an overlay),
//   - UIInput axis events (trackpad two-finger scroll) ignore occlusion.
// Fix: a native m_inputBlocked gate on ALL four dispatch entries, driven by
// the ETS `active` prop (false while drawer / tab editor is open) through
// controller.setInputBlocked.

const napi = await readFile('libghostty_ohos/src/main/cpp/napi_init.cpp', 'utf8');
const controller = await readFile('libghostty_ohos/src/main/ets/TerminalController.ets', 'utf8');
const surface = await readFile('libghostty_ohos/src/main/ets/TerminalSurface.ets', 'utf8');

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

// (1) Native gate state + setter that parks sticky input state.
assert.match(napi, /bool m_inputBlocked = false;/, 'native needs the overlay input gate flag');
const setInputBlocked = extractFunction(napi, 'void SetInputBlocked(bool blocked)');
assert.match(
  setInputBlocked,
  /m_physShiftDown = false;[\s\S]*?m_axisScrollRemainderY = 0\.0;[\s\S]*?m_axisVelocityY = 0\.0f;/,
  'blocking input must park held-Shift and the trackpad accumulator so nothing sticks'
);

// (2) All four dispatch entries check the gate before doing anything with the event.
const keyDispatch = extractFunction(napi, 'bool DispatchKeyEvent(');
assert.match(
  keyDispatch,
  /if \(m_inputBlocked\) \{\s*return false;\s*\}/,
  'key events route by focus and bypass hit-test occlusion: DispatchKeyEvent must gate'
);
assert.ok(
  keyDispatch.indexOf('m_inputBlocked') < keyDispatch.indexOf('IsShiftKeyCode'),
  'key gate must sit before any key handling'
);
for (const fn of ['void DispatchTouchEvent(', 'void DispatchMouseEvent(', 'void DispatchAxisEvent(']) {
  const body = extractFunction(napi, fn);
  assert.match(
    body,
    /if \(m_inputBlocked\) \{\s*return;\s*\}/,
    `${fn}...) must gate on m_inputBlocked while an overlay is open`
  );
}

// (3) Exported through napi and wrapped by the controller.
assert.match(
  napi,
  /\{"setInputBlocked", nullptr, SetInputBlocked, nullptr, nullptr, nullptr, napi_default, host\},/,
  'setInputBlocked must be exported on the native surface binding'
);
assert.match(
  controller,
  /setInputBlocked: \(surfaceId: string, blocked: boolean\) => void;/,
  'controller native interface must declare setInputBlocked'
);
assert.match(
  controller,
  /setInputBlocked\(blocked: boolean\): void \{\s*this\.native\?\.setInputBlocked\(this\.nativeSurfaceId, blocked\);\s*\}/,
  'controller must forward setInputBlocked to native'
);

// (4) The surface drives the gate from `active` on BOTH edges and at bind time.
const onActiveChanged = extractFunction(surface, 'private onActiveChanged()');
assert.match(
  onActiveChanged,
  /this\.controller\.setInputBlocked\(false\);/,
  'regaining active must unblock native input'
);
assert.match(
  onActiveChanged,
  /this\.controller\.setInputBlocked\(true\);/,
  'losing active (drawer / tab editor open) must block native input'
);
assert.match(
  surface,
  /this\.controller\.setImeActive\(this\.active\);\s*this\.controller\.setInputBlocked\(!this\.active\);/,
  'onLoad must seed the gate from the initial active value'
);

console.log('check-overlay-input-block: OK');
