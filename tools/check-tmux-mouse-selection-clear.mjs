import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

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

const dispatchMouseEvent = extractFunction(napi, 'void DispatchMouseEvent(');
assert.match(
  dispatchMouseEvent,
  /m_mouseHadSelectionOnPress = m_terminal->hasSelection\(\);/
);
assert.match(
  dispatchMouseEvent,
  /if \(m_mouseHadSelectionOnPress && !m_mousePressOnSelection\) \{\s*m_terminal->clearSelection\(\);\s*\}/s,
  'local mouse clicks outside a selection should still clear that selection'
);

const trackedMouseEvent = extractFunction(napi, 'bool TrySendTerminalMouseEvent(');
const pressMatch = /if \(isPress\) \{(?<body>[\s\S]*?)\} else if \(isRelease\)/.exec(trackedMouseEvent);
assert.ok(pressMatch?.groups?.body, 'tracked mouse press block should be explicit');
const trackedPressBlock = pressMatch.groups.body;
assert.match(
  trackedPressBlock,
  /m_terminal->clearSelection\(\);/,
  'tmux/yazi mouse-tracked presses must clear stale local selection highlights before the TUI drag owns the pointer'
);
assert.ok(
  trackedPressBlock.indexOf('m_terminal->clearSelection();') <
    trackedPressBlock.indexOf('m_isMousePressed = true;'),
  'selection should be cleared before recording the tracked drag state'
);

const touchMouseEvent = extractFunction(napi, 'void SendTouchMouseEvent(');
assert.match(
  touchMouseEvent,
  /if \(action == TerminalMouseAction::Press\) \{\s*m_terminal->clearSelection\(\);\s*\}/s,
  'touch-synthesized tracked mouse presses should also clear stale selection highlights'
);
assert.ok(
  touchMouseEvent.indexOf('if (action == TerminalMouseAction::Press)') <
    touchMouseEvent.indexOf('m_terminal->sendMouseEvent('),
  'touch selection clearing should happen before sending the tracked press'
);
