import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const appearance = await readFile('entry/src/main/ets/settings/AppearanceStore.ets', 'utf8');
const index = await readFile('entry/src/main/ets/pages/Index.ets', 'utf8');
const types = await readFile('libghostty_ohos/src/main/ets/TerminalTypes.ets', 'utf8');
const controller = await readFile('libghostty_ohos/src/main/ets/TerminalController.ets', 'utf8');
const napi = await readFile('libghostty_ohos/src/main/cpp/napi_init.cpp', 'utf8');
const rendererHeader = await readFile('libghostty_ohos/src/main/cpp/renderer/renderer.h', 'utf8');
const nativeHeader = await readFile('libghostty_ohos/src/main/cpp/renderer/native_drawing_renderer.h', 'utf8');
const nativeRenderer = await readFile('libghostty_ohos/src/main/cpp/renderer/native_drawing_renderer.cpp', 'utf8');

assert.match(appearance, /fontFamily: string;/);
assert.match(appearance, /fontFamily: 'FusionTerm Maple Mono'/);
assert.match(appearance, /readString\('fontFamily', DEFAULT_APPEARANCE\.fontFamily\)/);
assert.match(appearance, /prefs\.put\('fontFamily', settings\.fontFamily\)/);

assert.match(types, /fontFamily: string;/);
assert.match(types, /fontFamily\?: string;/);
assert.match(types, /fontFamily: 'FusionTerm Maple Mono'/);
assert.match(types, /fontFamily: config\.fontFamily/);

assert.match(controller, /if \(patch\.fontFamily !== undefined\) \{\s*nextConfig\.fontFamily = patch\.fontFamily;\s*\}/s);
assert.match(controller, /this\.native\.setConfig\(this\.nativeSurfaceId, this\.config\);/);

assert.match(index, /const FONT_FAMILY_MAPLE: string = 'FusionTerm Maple Mono';/);
assert.match(index, /const FONT_FAMILY_JETBRAINS: string = 'FusionTerm JetBrains Mono';/);
assert.match(index, /const FONT_FAMILY_CASCADIA: string = 'FusionTerm Cascadia Mono';/);
assert.match(index, /const FONT_FAMILY_SARASA: string = 'FusionTerm Sarasa Fixed SC';/);
assert.match(index, /const FONT_FAMILY_SYSTEM: string = 'PingFang SC';/);
assert.match(index, /const FONT_FAMILY_CUSTOM: string = 'FusionTerm Custom';/);
assert.match(index, /@State private fontFamily: string = DEFAULT_APPEARANCE\.fontFamily;/);
assert.match(index, /fontFamily: this\.fontFamily/);
assert.match(index, /private buildFontChoiceButton\(label: string, family: string\)/);
assert.match(index, /private selectFontFamily\(family: string\): void/);
assert.match(index, /private applyFontFamilyConfig\(\): void/);
assert.match(index, /session\.controller\.updateConfig\(\{ fontFamily: this\.fontFamily \}\);/);
assert.match(index, /this\.fontFamily = FONT_FAMILY_CUSTOM;/);
assert.match(index, /private applyFontSize\(value: number, persist: boolean = false\): void/);
assert.match(index, /this\.applyFontSize\(this\.fontSize - 1, true\);/);
assert.match(index, /this\.applyFontSize\(this\.fontSize \+ 1, true\);/);
assert.match(index, /fontFamily: this\.fontFamily/);
assert.match(index, /this\.fontFamily = this\.normalizeFontFamily\(settings\.fontFamily\);/);

assert.match(napi, /std::string fontFamily = "FusionTerm Maple Mono";/);
assert.match(napi, /napi_get_named_property\(env, args\[0\], "fontFamily", &fontFamilyVal\);/);
assert.match(napi, /TryReadStringArg\(env, fontFamilyVal, fontFamily\);/);
assert.match(napi, /host->SetConfig\(fontSize, scrollbackLines, bgColor, fgColor, cursorStyle, cursorBlink, bgOpacity, fontFamily\);/);
assert.match(napi, /void SetConfig\(int fontSize, int scrollbackLines, uint32_t bgColor, uint32_t fgColor, int cursorStyle,\s*bool cursorBlink, double bgOpacity, const std::string& fontFamily\)/s);
assert.match(napi, /m_renderer->setFontFamily\(fontFamily\);/);

assert.match(rendererHeader, /virtual void setFontFamily\(const std::string& family\)/);
assert.match(rendererHeader, /virtual void onFontMetricsChanged\(\)/);
assert.match(rendererHeader, /onFontMetricsChanged\(\);/);
assert.match(nativeHeader, /void setFontFamily\(const std::string& family\) override;/);
assert.match(nativeHeader, /void onFontMetricsChanged\(\) override;/);
assert.match(nativeHeader, /std::string m_preferredFontFamily = "FusionTerm Maple Mono";/);
assert.match(nativeRenderer, /void NativeDrawingRenderer::setFontFamily\(const std::string& family\)/);
assert.match(nativeRenderer, /m_preferredFontFamily = nextFamily;/);
assert.match(nativeRenderer, /void NativeDrawingRenderer::onFontMetricsChanged\(\)\s*\{\s*destroyGlyphCache\(\);/s);
assert.match(nativeRenderer, /PushUniqueFontFamily\(families, m_preferredFontFamily\.c_str\(\)\);/);
assert.match(nativeRenderer, /for \(const char\* family : kBundledFamilyFallbackOrder\) \{\s*PushUniqueFontFamily\(families, family\);/s);
