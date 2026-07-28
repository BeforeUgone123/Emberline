import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const source = await readFile('entry/src/main/ets/drivers/FusionTerminalDriver.ets', 'utf8');
const terminal = await readFile('libghostty_ohos/src/main/cpp/terminal/terminal.cpp', 'utf8');
const renderer = await readFile('libghostty_ohos/src/main/cpp/renderer/native_drawing_renderer.cpp', 'utf8');
const nativeCmake = await readFile('libghostty_ohos/src/main/cpp/CMakeLists.txt', 'utf8');

assert.match(source, /private sessionId: number = -1;/);
assert.match(source, /private nativeInitialized: boolean = false;/);
assert.match(source, /this\.sessionId = nativeDriver\.createSession\(\);/);
assert.match(source, /nativeDriver\.initialize\(this\.sessionId,\s*this\.context\.filesDir\);\s*this\.nativeInitialized = true;/);
assert.match(source, /nativeDriver\.setOutputCallback\(this\.sessionId,\s*this\.outputListener\);/);
assert.match(source, /if \(this\.nativeInitialized && this\.sessionId >= 0\) \{/);
assert.match(source, /nativeDriver\.setOutputCallback\(this\.sessionId,\s*null\);/);
assert.match(source, /nativeDriver\.destroySession\(this\.sessionId\);/);
assert.match(source, /this\.nativeInitialized = false;/);
assert.doesNotMatch(source, /nativeDriver\.setOutputCallback\(null\);\s*if \(this\.started\)/);

assert.match(nativeCmake, /find_library\(hitrace-lib hitrace_ndk\.z\)/);
assert.match(nativeCmake, /\$\{hitrace-lib\}/);
assert.match(terminal, /#include [<"]hitrace\/trace\.h[>"]/);
assert.match(renderer, /#include [<"]hitrace\/trace\.h[>"]/);

for (const traceName of [
  'Emberline.FeedOutput',
  'Emberline.FeedOutput.LockWait',
  'Emberline.FeedOutput.Parse',
  'Emberline.DrawFrame',
  'Emberline.DrawFrame.LockWait',
  'Emberline.DrawFrame.Snapshot',
  'Emberline.DrawFrame.BeginBuffer',
  'Emberline.DrawFrame.Raster',
  'Emberline.DrawFrame.EndBuffer'
]) {
  const escapedName = traceName.replaceAll('.', '\\.');
  assert.match(terminal, new RegExp(`ScopedHiTrace\\s+\\w+\\("${escapedName}"\\)`));
}

assert.match(terminal, /OH_HiTrace_CountTrace\(\s*"Emberline\.FeedBytes",/s);
assert.match(terminal, /OH_HiTrace_CountTrace\(\s*"Emberline\.GridCells",/s);
assert.match(renderer, /OH_HiTrace_CountTrace\(\s*"Emberline\.SurfacePixels",/s);
