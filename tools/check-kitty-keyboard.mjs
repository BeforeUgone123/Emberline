import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

// Kitty keyboard protocol wiring (nvim/helix/fish enhanced keys).
//
// The vendored libghostty_vt.a exports the official ghostty_key_encoder_* /
// ghostty_key_event_* API, but its headers (include/ghostty/vt/key/*.h) cannot
// share a translation unit with the legacy umbrella include/ghostty_vt.h that
// terminal/terminal.h pulls in (duplicate GHOSTTY_* enumerator names).
// napi_init.cpp therefore carries an ABI shim whose GhosttyKey enum is a
// verbatim copy of include/ghostty/vt/key/event.h — pinned here by a
// name-order comparison so a vendored-library bump cannot silently desync it.
//
// Contract:
//   1. a TUI that pushes kitty flags (CSI >u) gets officially-encoded keys,
//      with options synced from live VT state on every key event;
//   2. releases are only reported when REPORT_EVENTS is set;
//   3. while the protocol is off (or the official encoder produces nothing),
//      the hand-written BuildKeySequence table runs byte-identically;
//   4. every m_vt access stays serialized through Terminal::withVtHandleLocked.

const napi = await readFile('libghostty_ohos/src/main/cpp/napi_init.cpp', 'utf8');
const terminalH = await readFile('libghostty_ohos/src/main/cpp/terminal/terminal.h', 'utf8');
const eventH = await readFile('libghostty_ohos/src/main/cpp/include/ghostty/vt/key/event.h', 'utf8');
const encoderH = await readFile('libghostty_ohos/src/main/cpp/include/ghostty/vt/key/encoder.h', 'utf8');

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

function extractGhosttyKeyNames(source, label) {
  const start = source.indexOf('GHOSTTY_KEY_UNIDENTIFIED = 0,');
  assert.notEqual(start, -1, `${label}: missing GhosttyKey enum start`);
  const end = source.indexOf('} GhosttyKey;', start);
  assert.ok(end > start, `${label}: missing GhosttyKey enum end`);
  const body = source
    .slice(start, end)
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/\/\/[^\n]*/g, ' ');
  return body.match(/GHOSTTY_KEY_[A-Z0-9_]+/g) ?? [];
}

// ── 0. Shim enum parity with the official header. ───────────────────────────
assert.deepEqual(
  extractGhosttyKeyNames(napi, 'napi_init.cpp shim'),
  extractGhosttyKeyNames(eventH, 'include/ghostty/vt/key/event.h'),
  'the shim GhosttyKey enum must mirror include/ghostty/vt/key/event.h verbatim (order defines the ABI values)'
);

// Kitty flag constants exist on both sides of the shim, with the header values.
for (const name of [
  'GHOSTTY_KITTY_KEY_DISABLED',
  'GHOSTTY_KITTY_KEY_DISAMBIGUATE',
  'GHOSTTY_KITTY_KEY_REPORT_EVENTS',
  'GHOSTTY_KITTY_KEY_REPORT_ALTERNATES',
  'GHOSTTY_KITTY_KEY_REPORT_ALL',
  'GHOSTTY_KITTY_KEY_REPORT_ASSOCIATED',
]) {
  assert.ok(encoderH.includes(name), `encoder.h exports ${name}`);
  assert.ok(napi.includes(name), `shim declares ${name}`);
}
assert.match(napi, /GHOSTTY_KITTY_KEY_DISABLED = 0;/);
assert.match(napi, /GHOSTTY_KITTY_KEY_REPORT_EVENTS = 1 << 1;/);

// ── 1. Encoder lifecycle: lazily created per host, freed with the host. ─────
assert.match(napi, /GhosttyKeyEncoder m_keyEncoder = nullptr;/, 'TerminalHost owns one encoder slot');
assert.match(napi, /ghostty_key_encoder_new\(nullptr, &slot\)/, 'encoder is instantiated on demand');
assert.match(napi, /ghostty_key_encoder_free\(m_keyEncoder\)/, 'encoder is freed in ~TerminalHost');

// ── 2. Per-event sync from live terminal state, before encoding. ────────────
const tryEncode = extractFunction(napi, 'bool TryEncodeKittyKey(');
assert.match(tryEncode, /ghostty_terminal_get\(vt, GHOSTTY_TERMINAL_DATA_KITTY_KEYBOARD_FLAGS, &kittyFlags\)/,
  'kitty flags are read from the terminal state, never tracked locally');
assert.match(tryEncode, /kittyFlags == GHOSTTY_KITTY_KEY_DISABLED/,
  'protocol-off short-circuits to the legacy table');
assert.match(tryEncode, /ghostty_key_encoder_setopt_from_terminal\(encoder, vt\)/,
  'encoder options (kitty flags, DECCKM, keypad, modifyOtherKeys) sync from the VT per key event');
assert.ok(
  tryEncode.indexOf('ghostty_key_encoder_setopt_from_terminal') < tryEncode.indexOf('EncodeGhosttyKeyEvent('),
  'setopt_from_terminal must run before every encode'
);
assert.match(tryEncode, /terminal->withVtHandleLocked\(\[&\]\(ghostty_terminal_t vt\)/,
  'all VT access in the kitty path stays serialized with feedOutput/drawFrame');

// ── 3. Event encoding with the official API. ────────────────────────────────
const encode = extractFunction(napi, 'bool EncodeGhosttyKeyEvent(');
assert.match(encode, /ghostty_key_event_new\(nullptr, &event\)/);
assert.match(encode, /ghostty_key_event_set_action\(event, keyAction\)/);
assert.match(encode, /ghostty_key_event_set_key\(event, key\)/);
assert.match(encode, /ghostty_key_event_set_mods\(event, mods\)/);
assert.match(encode, /ghostty_key_encoder_encode\(\s*encoder, event, stackBuffer, sizeof\(stackBuffer\), &written\)/s);
assert.match(encode, /GHOSTTY_OUT_OF_SPACE/, 'oversized sequences get the documented buffer retry');
assert.ok(
  encode.indexOf('ghostty_key_encoder_encode') < encode.indexOf('ghostty_key_event_free(event)'),
  'the event is freed after encoding'
);
assert.match(napi, /GhosttyKey GhosttyKeyFromOhKeyCode\(OH_NativeXComponent_KeyCode code\)/,
  'OH key codes map to physical GhosttyKey values');
assert.match(napi, /default: return GHOSTTY_KEY_UNIDENTIFIED;/,
  'unmapped keys keep the caller on the legacy table');

// ── 4. Dispatch: official encoding first, hand-written table as fallback. ───
const keyDispatch = extractFunction(napi, 'bool DispatchKeyEvent(');
assert.match(
  keyDispatch,
  /TryEncodeKittyKey\(m_terminal, m_keyEncoder, code, modifiers, capsLock,\s*GHOSTTY_KEY_ACTION_PRESS, GHOSTTY_KITTY_KEY_DISABLED, sequence\)/s,
  'presses prefer the official encoder whenever any kitty flag is set'
);
assert.ok(
  keyDispatch.indexOf('GHOSTTY_KEY_ACTION_PRESS') <
    keyDispatch.indexOf('BuildKeySequence(code, modifiers, capsLock, appCursorKeys, sequence)'),
  'the hand-written table remains the fallback after the kitty path'
);
assert.match(
  keyDispatch,
  /action == OH_NATIVEXCOMPONENT_KEY_ACTION_UP[\s\S]*?GHOSTTY_KEY_ACTION_RELEASE, GHOSTTY_KITTY_KEY_REPORT_EVENTS/,
  'releases are only reported when the TUI pushed REPORT_EVENTS'
);
assert.ok(
  keyDispatch.indexOf('IsShiftKeyCode') < keyDispatch.indexOf('OH_NATIVEXCOMPONENT_KEY_ACTION_UP'),
  'the physical-shift bypass bookkeeping still runs before any kitty release handling'
);
assert.match(keyDispatch, /m_terminal->writeInput\(sequence\.data\(\), sequence\.size\(\)\);/,
  'the encoded sequence flows through the existing terminal input sink');

// ── 5. Locked VT access exists on Terminal. ─────────────────────────────────
assert.match(terminalH, /void withVtHandleLocked\(const std::function<void\(ghostty_terminal_t\)>& fn\) const/,
  'Terminal exposes the m_vt handle only under m_stateMutex');

// ── 6. Legacy table behaviors the kitty wiring must not disturb. ────────────
assert.match(napi, /sequence = shift \? "\\x1b\[Z" : "\\t";/, 'Shift-Tab keeps CSI Z');
assert.match(napi, /case KEY_F1: BuildSs3FunctionKey\(sequence, 'P', modCode\); return true;/, 'F1 keeps SS3 P');
assert.match(napi, /case KEY_F12: BuildTildeKey\(sequence, 24, modCode\); return true;/, 'F12 keeps CSI 24~');
assert.match(napi, /BuildCursorKey\(sequence, 'A', modCode, appCursorKeys\)/,
  'arrow keys still honor DECCKM application cursor mode');
assert.match(napi, /cursorKeysApplicationMode\(\)/, 'DECCKM still feeds the legacy cursor-key path');

console.log('check-kitty-keyboard: OK');
