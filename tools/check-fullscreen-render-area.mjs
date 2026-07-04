import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const index = await readFile('entry/src/main/ets/pages/Index.ets', 'utf8');

assert.doesNotMatch(index, /TERMINAL_PADDING_[XY]/, 'terminal renderer must not be inset by page chrome padding');
assert.match(index, /private buildTerminalLayer\(\)/, 'Index should keep the terminal renderer in its own edge-to-edge content layer');
assert.doesNotMatch(index, /private buildChromeOverlay\(\)/, 'chrome must reserve layout space so it does not cover terminal rows');

const terminalLayer = index.match(/  @Builder\n  private buildTerminalLayer\(\) \{[\s\S]*?\n  \}/)?.[0] ?? '';
assert.match(terminalLayer, /TerminalSurface\(/, 'terminal layer should contain the native TerminalSurface');
assert.match(terminalLayer, /\.width\('100%'\)/, 'terminal layer should span the full width');
assert.match(terminalLayer, /\.layoutWeight\(1\)/, 'terminal layer should fill only the available height below the top bar');
assert.doesNotMatch(terminalLayer, /\.padding\(/, 'terminal layer should not add margins around the renderer');

const buildBody = index.match(/  build\(\) \{[\s\S]*?\n  \}\n\n  @Builder/)?.[0] ?? '';
const terminalIndex = buildBody.indexOf('this.buildTerminalLayer();');
const tabIndex = buildBody.indexOf('this.buildTabBar();');
assert.ok(terminalIndex >= 0, 'root build should render the terminal layer');
assert.ok(tabIndex >= 0, 'root build should render the top tab bar');
assert.ok(tabIndex < terminalIndex, 'top tab bar should be laid out before the terminal layer, not over it');
assert.match(buildBody, /Column\(\) \{[\s\S]*?this\.buildTabBar\(\);[\s\S]*?this\.buildTerminalLayer\(\);/s,
  'terminal should live in a column below the top bar');
assert.doesNotMatch(buildBody, /this\.buildTerminalLayer\(\);[\s\S]*?this\.buildTabBar\(\);/s,
  'terminal layer must not be drawn first as a background behind the top bar');
