import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const nativeBridge = await readFile('libghostty_ohos/src/main/cpp/napi_init.cpp', 'utf8');

function extractFunction(signature, nextSignature) {
  const start = nativeBridge.indexOf(signature);
  assert.notEqual(start, -1, `missing ${signature}`);
  const end = nativeBridge.indexOf(nextSignature, start + signature.length);
  assert.notEqual(end, -1, `missing boundary ${nextSignature}`);
  return nativeBridge.slice(start, end);
}

const reset = extractFunction('void ResetInterruptedInputState()', 'void SetInputBlocked(bool blocked)');
assert.match(reset, /m_isTouching = false;/);
assert.match(reset, /m_touchMouseDragActive = false;/);
assert.match(reset, /ResetLocalMouseTrackingState\(\);/);
assert.match(reset, /StopSelectionAutoScroll\(\);/);
assert.match(reset, /m_physShiftDown = false;/);
assert.match(reset, /m_axisScrollRemainderY = 0\.0;/);

const surfaceHide = extractFunction('void OnSurfaceHide()', 'void OnSurfaceDestroyed()');
assert.match(surfaceHide, /ResetInterruptedInputState\(\);/,
  'surface hide must clear pointer sequences whose UP/CANCEL event may be lost');

const surfaceDestroyed = extractFunction('void OnSurfaceDestroyed()', 'void OnFocusEvent()');
assert.match(surfaceDestroyed, /ResetInterruptedInputState\(\);/,
  'surface destruction must not carry interrupted input state into a rebound host');

const blur = extractFunction('void OnBlurEvent()', 'bool DispatchKeyEvent(');
assert.match(blur, /ResetInterruptedInputState\(\);/,
  'focus loss must clear a mouse press before later touch input is admitted');

const inputBlock = extractFunction('void SetInputBlocked(bool blocked)', 'void SetImeActive(bool active)');
assert.match(inputBlock, /ResetInterruptedInputState\(\);[\s\S]*m_inputBlocked = blocked;/,
  'both blocking and foreground unblocking must clear pointer\/axis state interrupted by lock or overlays');

console.log('Interrupted native input state reset checks passed.');
