import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const renderer = await readFile('libghostty_ohos/src/main/cpp/renderer/native_drawing_renderer.cpp', 'utf8');

assert.match(renderer, /kSystemMonoFontCandidates/);
assert.match(renderer, /NotoSansMono\[wdth,wght\]\.ttf/);
assert.match(renderer, /HarmonyOS_Sans_Mono/);
assert.match(renderer, /DroidSansMono/);
assert.match(renderer, /RegisterReadableFonts/);
assert.match(renderer, /for \(const char\* fontPath : kSystemMonoFontCandidates\)/);

assert.match(renderer, /kTerminalFontFamilies/);
assert.match(renderer, /"SF Mono"/);
assert.match(renderer, /"Menlo"/);
assert.match(renderer, /"Monaco"/);
assert.match(renderer, /"PingFang SC"/);
assert.match(renderer, /"Apple Color Emoji"/);
assert.match(renderer, /"HarmonyOS Sans Mono"/);
assert.match(renderer, /"Noto Sans Mono"/);
assert.match(renderer, /"Noto Sans CJK SC"/);
assert.match(renderer, /"monospace"/);
assert.match(renderer, /"sans-serif"/);

assert.doesNotMatch(renderer, /TextStyleAddFontFeature\(textStyle,\s*"liga",\s*1\)/);
assert.doesNotMatch(renderer, /TextStyleAddFontFeature\(textStyle,\s*"clig",\s*1\)/);
assert.doesNotMatch(renderer, /TextStyleAddFontFeature\(textStyle,\s*"calt",\s*1\)/);
assert.match(renderer, /TextStyleAddFontFeature\(textStyle,\s*"liga",\s*0\)/);
assert.match(renderer, /TextStyleAddFontFeature\(textStyle,\s*"clig",\s*0\)/);
assert.match(renderer, /TextStyleAddFontFeature\(textStyle,\s*"calt",\s*0\)/);
