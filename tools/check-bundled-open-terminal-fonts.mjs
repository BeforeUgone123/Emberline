import assert from 'node:assert/strict';
import { stat, readFile } from 'node:fs/promises';
import { join } from 'node:path';

const fontsDir = 'libghostty_ohos/src/main/resources/rawfile/fonts';
const expectedFonts = [
  'MapleMonoNormal-NF-CN-Regular.ttf',
  'JetBrainsMono-Regular.ttf',
  'SymbolsNerdFontMono-Regular.ttf',
  'CascadiaMono.ttf',
  'SarasaFixedSC-Regular.ttf',
];

for (const fileName of expectedFonts) {
  const info = await stat(join(fontsDir, fileName));
  assert.ok(info.size > 100_000, `${fileName} should be a real bundled font file`);
}

const renderer = await readFile('libghostty_ohos/src/main/cpp/renderer/native_drawing_renderer.cpp', 'utf8');

assert.match(renderer, /"fonts\/SarasaFixedSC-Regular\.ttf"/);
assert.match(renderer, /"fonts\/JetBrainsMono-Regular\.ttf"/);
assert.match(renderer, /"fonts\/CascadiaMono\.ttf"/);
assert.match(renderer, /"fonts\/MapleMonoNormal-NF-CN-Regular\.ttf"/);
assert.match(renderer, /"fonts\/SymbolsNerdFontMono-Regular\.ttf"/);
assert.match(
  renderer,
  /"fonts\/MapleMonoNormal-NF-CN-Regular\.ttf",\s*"FusionTerm Maple Mono"\s*\},\s*\{\s*"fonts\/JetBrainsMono-Regular\.ttf",\s*"FusionTerm JetBrains Mono"\s*\},\s*\{\s*"fonts\/SymbolsNerdFontMono-Regular\.ttf",\s*"FusionTerm Nerd Symbols"\s*\},\s*\{\s*"fonts\/CascadiaMono\.ttf",\s*"FusionTerm Cascadia Mono"\s*\},\s*\{\s*"fonts\/SarasaFixedSC-Regular\.ttf",\s*"FusionTerm Sarasa Fixed SC"/s,
  'bundled open fonts should follow the Maple-first terminal fallback order'
);
