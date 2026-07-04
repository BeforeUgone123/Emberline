import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const terminalHeader = await readFile('libghostty_ohos/src/main/cpp/terminal/terminal.h', 'utf8');
const terminalImpl = await readFile('libghostty_ohos/src/main/cpp/terminal/terminal.cpp', 'utf8');
const napi = await readFile('libghostty_ohos/src/main/cpp/napi_init.cpp', 'utf8');

assert.match(terminalHeader, /enum class TerminalMouseAction/);
assert.match(terminalHeader, /enum class TerminalMouseButton/);
assert.match(terminalHeader, /bool isMouseTrackingEnabled\(\) const;/);
assert.match(terminalHeader, /bool sendMouseEvent\(/);
assert.match(terminalHeader, /GhosttyMouseEncoderHandle m_mouseEncoder = nullptr;/);
assert.match(terminalHeader, /GhosttyMouseEventHandle m_mouseEvent = nullptr;/);

assert.match(terminalImpl, /ghostty_mouse_encoder_new/);
assert.match(terminalImpl, /ghostty_mouse_encoder_free/);
assert.match(terminalImpl, /ghostty_mouse_encoder_setopt_from_terminal/);
assert.match(terminalImpl, /ghostty_mouse_encoder_encode/);
assert.match(terminalImpl, /ghostty_mouse_event_set_action/);
assert.match(terminalImpl, /ghostty_mouse_event_set_button/);
assert.match(terminalImpl, /ghostty_mouse_event_clear_button/);
assert.match(terminalImpl, /GHOSTTY_TERMINAL_DATA_MOUSE_TRACKING/);
assert.match(terminalImpl, /Terminal::isMouseTrackingEnabled\(\) const/);
assert.match(terminalImpl, /Terminal::sendMouseEvent/);

assert.match(napi, /TrySendTerminalMouseEvent/);
assert.match(napi, /MapMouseAction/);
assert.match(napi, /MapMouseButton/);
assert.match(napi, /TerminalMouseButton::WheelUp/);
assert.match(napi, /TerminalMouseButton::WheelDown/);
assert.match(napi, /if \(TrySendTerminalMouseEvent\(mouseEvent/);
assert.match(napi, /return;\s*\n\s*}\s*\n\s*\n\s*switch \(mouseEvent\.action\)/);
assert.match(napi, /if \(TrySendTerminalWheelEvent\(vertical/);
assert.match(napi, /m_terminal->isMouseTrackingEnabled\(\)/);
