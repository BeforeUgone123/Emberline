import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const nativeBridge = await readFile('libghostty_ohos/src/main/cpp/napi_init.cpp', 'utf8');

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

const captureOsc52 = extractFunction(nativeBridge, 'void CaptureOsc52ClipboardRequests(');
const rememberTail = extractFunction(nativeBridge, 'void RememberOsc52PrefixTail(');

assert.match(
  nativeBridge,
  /static constexpr size_t kMaxOsc52SequenceBytes = \d+ \* 1024 \* 1024;/,
  'chunked OSC 52 capture must have a bounded pending-sequence buffer'
);
assert.match(
  nativeBridge,
  /std::string m_pendingOsc52Sequence;/,
  'OSC 52 parser must persist incomplete sequences across PTY/WebSocket chunks'
);
assert.match(
  captureOsc52,
  /if \(!m_pendingOsc52Sequence\.empty\(\)\) \{[\s\S]*?joinedData = std::move\(m_pendingOsc52Sequence\);[\s\S]*?joinedData \+= data;[\s\S]*?scanData = &joinedData;/,
  'OSC 52 parser must prepend a saved partial sequence to the next output chunk'
);
assert.match(
  captureOsc52,
  /if \(end == std::string::npos\) \{[\s\S]*?m_pendingOsc52Sequence = scanData->substr\(start\);[\s\S]*?return;/,
  'OSC 52 parser must save an unterminated sequence instead of dropping long tmux copies'
);
assert.match(
  captureOsc52,
  /RememberOsc52PrefixTail\(\*scanData\);/,
  'OSC 52 parser must remember a split ESC ] 52 ; prefix at a chunk boundary'
);
assert.match(
  rememberTail,
  /osc52Prefix\.compare\(0, len, data, index, len\) == 0/,
  'split-prefix tail detection must compare the end of the chunk with the OSC 52 prefix'
);
assert.match(
  captureOsc52,
  /HandleOsc52Payload\(payload\);[\s\S]*?searchPos = end \+ terminatorLen;/,
  'complete OSC 52 payloads must still be decoded and queued before scanning following output'
);
