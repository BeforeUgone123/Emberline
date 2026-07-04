import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const napi = await readFile('libghostty_ohos/src/main/cpp/napi_init.cpp', 'utf8');

assert.match(
  napi,
  /vertical > 0\.0 \? TerminalMouseButton::WheelDown : TerminalMouseButton::WheelUp/,
  'terminal mouse wheel reporting must preserve ArkUI touchpad axis direction: positive vertical -> WheelDown, negative vertical -> WheelUp'
);

assert.match(
  napi,
  /m_terminal->scrollView\(vertical > 0\.0 \? scrollLines : -scrollLines\)/,
  'local mouse-axis fallback direction should remain unchanged'
);
