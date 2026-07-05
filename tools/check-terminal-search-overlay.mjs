import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const surface = await readFile('libghostty_ohos/src/main/ets/TerminalSurface.ets', 'utf8');

const searchOverlayBlock =
  surface.match(/private buildSearchOverlay\(\) \{[\s\S]*?\n  \}\n\n  @Builder\n  private buildSecurePasteOverlay/)?.[0] ?? '';
const closeSearchBlock =
  surface.match(/private closeSearch\(\): void \{[\s\S]*?\n  \}/)?.[0] ?? '';

assert.ok(searchOverlayBlock.length > 0, 'search overlay builder must exist');
assert.ok(closeSearchBlock.length > 0, 'closeSearch method must exist');

assert.match(
  searchOverlayBlock,
  /\.hitTestBehavior\(HitTestMode\.Default\)/,
  'search overlay must explicitly block terminal XComponent touch leakage while keeping its child controls clickable'
);
assert.match(
  searchOverlayBlock,
  /\.zIndex\(\d+\)/,
  'search overlay must sit above native terminal and scrollbar overlay hit regions'
);

for (const label of ['上一个', '下一个', '关闭']) {
  assert.match(
    searchOverlayBlock,
    new RegExp(`Button\\('${label}'\\)[\\s\\S]*?\\.focusable\\(false\\)[\\s\\S]*?\\.onClick`),
    `${label} search control must not steal keyboard focus from the search input / terminal`
  );
}

assert.match(
  closeSearchBlock,
  /try \{[\s\S]*?this\.searchInputController\.stopEditing\(\);[\s\S]*?\} catch \(err\) \{[\s\S]*?console\.error\('Failed to stop terminal search editing session/,
  'closing search must continue even if ArkUI reports no active TextInput editing controller'
);
assert.match(
  closeSearchBlock,
  /this\.searchVisible = false;/,
  'closeSearch must always clear the visible search overlay state'
);
