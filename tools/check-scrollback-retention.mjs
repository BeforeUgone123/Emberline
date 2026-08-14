import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const [types, index, terminalHeader, terminalSource, nativeBridge] = await Promise.all([
  readFile('libghostty_ohos/src/main/ets/TerminalTypes.ets', 'utf8'),
  readFile('entry/src/main/ets/pages/Index.ets', 'utf8'),
  readFile('libghostty_ohos/src/main/cpp/terminal/terminal.h', 'utf8'),
  readFile('libghostty_ohos/src/main/cpp/terminal/terminal.cpp', 'utf8'),
  readFile('libghostty_ohos/src/main/cpp/napi_init.cpp', 'utf8')
]);

assert.match(types, /DEFAULT_TERMINAL_CONFIG[\s\S]*?scrollbackLines: 50000,/,
  'the public ArkTS default must match the native pre-surface default');
assert.match(index, /scrollbackLines: DEFAULT_TERMINAL_CONFIG\.scrollbackLines,/,
  'app sessions must use the shared retention default instead of another magic number');
assert.match(terminalHeader, /static constexpr int kDefaultMaxScrollback = 50000;/);
assert.match(terminalSource, /opts\.max_scrollback = static_cast<size_t>\(m_maxScrollback\);/,
  'Ghostty must receive the requested line limit when the VT is created');
assert.match(nativeBridge, /m_terminal = new Terminal\(cols, rows, m_scrollbackLines\);/,
  'the native host must apply the saved limit during pre-onLoad surface creation');
assert.match(nativeBridge, /int m_scrollbackLines = Terminal::kDefaultMaxScrollback;/);
assert.match(nativeBridge, /int32_t scrollbackLines = Terminal::kDefaultMaxScrollback;/);

console.log('Scrollback retention checks passed.');
