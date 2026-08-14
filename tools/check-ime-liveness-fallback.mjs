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

const showIme = extractFunction(
  'void ShowImeLocked(InputMethod_RequestKeyboardReason reason)',
  'void HideImeLocked()'
);
assert.match(showIme, /if \(!m_imeActive\.load[\s\S]*?m_wantsIme = false;[\s\S]*?return;/,
  'an inactive terminal must not leave printable keys delegated to the IME');
assert.match(showIme, /if \(!AttachImeLocked\(true, reason\)\) \{\s*m_wantsIme = false;\s*return;/,
  'failed IME attachment must restore native printable-key handling');
assert.match(showIme, /Failed to show IME[\s\S]*?m_wantsIme = false;/,
  'failed IME display must restore native printable-key handling');

const keyboardStatus = extractFunction(
  'void HandleImeKeyboardStatus(InputMethod_KeyboardStatus keyboardStatus)',
  'void HandleImeEnterKey(InputMethod_EnterKeyType)'
);
assert.match(keyboardStatus, /if \(!m_imeVisible\) \{\s*m_wantsIme = false;/,
  'a hidden or stopped IME must stop swallowing physical letter keys');

const notifyIme = extractFunction(
  'void NotifyImeStateLocked(bool force = false)',
  '// Force the next NotifyImeStateLocked'
);
assert.match(notifyIme, /!m_xComponentFocused\.load[\s\S]*?!m_wantsIme \|\|/,
  'a failed or hidden IME must not receive repeated render-loop IPC');
assert.match(notifyIme, /const InputMethod_ErrorCode selectionRc =\s*OH_InputMethodProxy_NotifySelectionChange/);
assert.match(notifyIme, /if \(HandleImeProxyErrorLocked\(selectionRc, "selection"\)\) \{\s*return;/,
  'selection IPC failure must disable stale IME delegation');
assert.match(notifyIme, /const InputMethod_ErrorCode cursorRc =\s*OH_InputMethodProxy_NotifyCursorUpdate/);
assert.match(notifyIme, /if \(HandleImeProxyErrorLocked\(cursorRc, "cursor"\)\) \{/,
  'cursor IPC failure must disable stale IME delegation');

const proxyError = extractFunction(
  'bool HandleImeProxyErrorLocked(InputMethod_ErrorCode rc, const char* operation)',
  'void ShowImeLocked(InputMethod_RequestKeyboardReason reason)'
);
assert.match(proxyError, /m_wantsIme = false;/);
assert.match(proxyError, /if \(rc == IME_ERR_DETACHED\) \{\s*ResetImeSessionLocked\(\);/,
  'a detached system IME proxy must be discarded before the next show request');

console.log('IME liveness fallback checks passed.');
