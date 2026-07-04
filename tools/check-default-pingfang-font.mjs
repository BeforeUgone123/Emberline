import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const renderer = await readFile('libghostty_ohos/src/main/cpp/renderer/native_drawing_renderer.cpp', 'utf8');

assert.match(
  renderer,
  /constexpr const char\* kDefaultTerminalFontFamily = "PingFang SC";/,
  'terminal renderer should declare PingFang SC as the default requested font family'
);

assert.match(
  renderer,
  /families\.push_back\(kDefaultTerminalFontFamily\);\s*families\.push_back\(m_primaryFontFamily\.c_str\(\)\);/s,
  'PingFang SC must be requested before the registered terminal fallback family'
);

const candidateArray = renderer.match(/kSystemMonoFontCandidates = \{(?<body>[\s\S]*?)\};/);
assert.ok(candidateArray?.groups?.body, 'system font candidate array should be present');
const firstCandidate = candidateArray.groups.body
  .split('\n')
  .map((line) => line.trim())
  .find((line) => line.startsWith('"'));
assert.match(firstCandidate ?? '', /PingFang/, 'PingFang font files should be tried before other system font files');
