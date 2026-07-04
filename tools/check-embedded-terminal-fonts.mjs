import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const renderer = await readFile('libghostty_ohos/src/main/cpp/renderer/native_drawing_renderer.cpp', 'utf8');

assert.match(
  renderer,
  /constexpr const char\* kPrivateFallbackFontFamily = "FusionTerm Private Fallback";/,
  'renderer should define a dedicated family for optional private fallback fonts'
);

assert.match(renderer, /kPrivateFallbackFontRawFiles/);
assert.match(renderer, /"fonts\/PingFangSC-Regular\.otf"/);
assert.match(renderer, /"fonts\/PingFangSC-Regular\.ttf"/);
assert.match(renderer, /"fonts\/PingFangSC\.ttf"/);
assert.match(renderer, /"fonts\/PingFang\.ttc"/);
assert.match(renderer, /"fonts\/SF-Pro-Text-Regular\.otf"/);
assert.match(renderer, /"fonts\/SFProText-Regular\.otf"/);
assert.match(renderer, /"fonts\/FusionTerm-Regular\.otf"/);

assert.match(renderer, /RegisterPrivateFallbackFontIfPresent/);
assert.match(renderer, /ExtractFirstAvailableRawFileToPath/);
assert.match(
  renderer,
  /OH_Drawing_RegisterFont\(\w+,\s*kPrivateFallbackFontFamily,\s*privateFontPath\.c_str\(\)\)/,
  'private fallback font file should be registered with the dedicated family'
);

assert.match(
  renderer,
  /"FusionTerm Sarasa Fixed SC",\s*kPrivateFallbackFontFamily/s,
  'private fallback family should come after bundled open terminal fonts'
);
