import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const surface = await readFile('libghostty_ohos/src/main/ets/TerminalSurface.ets', 'utf8');
const controller = await readFile('libghostty_ohos/src/main/ets/TerminalController.ets', 'utf8');
const types = await readFile('libghostty_ohos/src/main/ets/TerminalTypes.ets', 'utf8');
const nativeBridge = await readFile('libghostty_ohos/src/main/cpp/napi_init.cpp', 'utf8');

assert.match(types, /export type TerminalCopyRequestListener = \(text: string\) => void;/);
assert.match(controller, /drainPendingCopyRequest: \(surfaceId: string\) => string;/);
assert.match(controller, /private copyRequestListener: TerminalCopyRequestListener \| null = null;/);
assert.match(controller, /setCopyRequestListener\(listener: TerminalCopyRequestListener \| null\): void/);
assert.match(controller, /private dispatchCopyRequest\(pendingCopy: string\): void/);
assert.match(controller, /if \(pendingCopy\.startsWith\('T'\)\) \{\s*this\.copyRequestListener\(pendingCopy\.slice\(1\)\);/s);
assert.match(controller, /this\.copyRequestListener\(''\);/);

assert.match(surface, /this\.controller\.setCopyRequestListener\(\(text: string\): void => \{\s*this\.copyTerminalTextToClipboard\(text\);\s*\}\);/s);
assert.match(surface, /this\.controller\.setCopyRequestListener\(null\);/);
assert.match(surface, /private copyTerminalTextToClipboard\(text: string\): void/);
assert.match(surface, /if \(text\.length > 0\) \{\s*this\.copyToClipboard\(text\);/s);
assert.match(surface, /private copySelectionToClipboard\(\): void/);
assert.match(surface, /const selectedText = this\.controller\.getSelectedText\(\);/);
assert.match(surface, /this\.copyToClipboard\(selectedText\);/);
assert.match(surface, /clipboard\.setDataSync\(pasteboard\.createPlainTextData\(text\)\);/);
assert.match(
  surface,
  /MenuItem\(\{ content: '复制' \}\)[\s\S]*?this\.copySelectionToClipboard\(\);/s,
  'copy context menu should write the selected terminal text to the system pasteboard'
);

assert.match(nativeBridge, /bool IsCopyShortcut\(OH_NativeXComponent_KeyCode code, uint64_t modifiers\)/);
assert.match(nativeBridge, /const bool isCtrlShiftCopy = ctrl && shift && !alt && \(code == LINUX_KEY_C \|\| code == KEY_C\);/);
assert.match(nativeBridge, /const bool isCtrlInsertCopy = ctrl && !shift && !alt && \(code == LINUX_KEY_INSERT \|\| code == KEY_INSERT\);/);
assert.doesNotMatch(
  nativeBridge,
  /const bool isCtrlCopy = ctrl && !shift && !alt && \(code == LINUX_KEY_C \|\| code == KEY_C\);/,
  'plain Ctrl-C must remain a terminal interrupt, not a copy shortcut'
);
assert.match(
  nativeBridge,
  /if \(IsCopyShortcut\(code, modifiers\)\) \{\s*QueueCopyRequest\(\);\s*return true;\s*\}/s,
  'native key path must route Ctrl-Shift-C/Ctrl-Insert to system copy instead of the remote PTY'
);
assert.match(nativeBridge, /void QueueCopyRequest\(\) \{[\s\S]*?m_pendingCopyRequest = "copy";[\s\S]*?\}/);
assert.match(nativeBridge, /void QueueCopyText\(const std::string& text\) \{[\s\S]*?m_pendingCopyRequest = "T" \+ text;[\s\S]*?\}/);
assert.match(nativeBridge, /std::string DrainPendingCopyRequest\(\) \{[\s\S]*?drained\.swap\(m_pendingCopyRequest\);[\s\S]*?\}/);
assert.match(nativeBridge, /static napi_value DrainPendingCopyRequest\(napi_env env, napi_callback_info info\)/);
assert.match(nativeBridge, /\{"drainPendingCopyRequest", nullptr, DrainPendingCopyRequest,/);
assert.match(
  nativeBridge,
  /case IME_EXTEND_ACTION_COPY:\s*QueueCopyRequest\(\);\s*break;/,
  'system IME copy action should copy selected terminal text to the system pasteboard'
);
assert.match(nativeBridge, /void CaptureOsc52ClipboardRequests\(const std::string& data\)/);
assert.ok(nativeBridge.includes('const std::string osc52Prefix = "\\x1b]52;";'));
assert.match(nativeBridge, /HandleOsc52Payload\(payload\);/);
assert.match(nativeBridge, /std::string DecodeBase64\(const std::string& encoded\)/);
assert.match(nativeBridge, /QueueCopyText\(decoded\);/);
assert.match(nativeBridge, /CaptureOsc52ClipboardRequests\(data\);\s*CaptureOsc9Notifications\(data\);\s*m_terminal->feedOutput/s);
