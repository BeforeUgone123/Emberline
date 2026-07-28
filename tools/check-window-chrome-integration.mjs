import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const ability = await readFile('entry/src/main/ets/entryability/EntryAbility.ets', 'utf8');
const index = await readFile('entry/src/main/ets/pages/Index.ets', 'utf8');

assert.match(ability, /const WINDOW_CHROME_HEIGHT: number = 48;/);
assert.match(ability, /interface WindowChromeController \{/);
assert.match(ability, /setDecorButtonStyle\(style: WindowDecorButtonStyle\): void;/);
assert.match(ability, /interface WindowDecorButtonStyle \{/);
assert.match(ability, /colorMode\?: ConfigurationConstant\.ColorMode;/);
assert.match(ability, /private enableWindowChromeImmersion\(windowStage: window\.WindowStage\): void \{/);
assert.match(ability, /windowStage\.getMainWindow\(\(err: BusinessError, mainWindow: window\.Window\) => \{/);
assert.match(ability, /const chromeWindow = mainWindow as WindowChromeController;/);
assert.match(ability, /chromeWindow\.setWindowDecorVisible\(false\);/);
assert.match(ability, /chromeWindow\.setWindowDecorHeight\(WINDOW_CHROME_HEIGHT\);/);
assert.match(
  ability,
  /chromeWindow\.setDecorButtonStyle\(\{\s*colorMode: ConfigurationConstant\.ColorMode\.COLOR_MODE_DARK\s*\}\);/s,
  'system title buttons should use the dark chrome color mode so their icons render light on the black title bar'
);
assert.match(
  ability,
  /windowStage\.loadContent\('pages\/Index', \(err: BusinessError\) => \{[\s\S]*?this\.enableWindowChromeImmersion\(windowStage\);[\s\S]*?\}\);/s,
  'window decoration must be hidden after page content is loaded so HarmonyOS keeps the system window buttons'
);

assert.match(index, /const WINDOW_CHROME_HEIGHT: number = 48;/);
assert.match(index, /const WINDOW_DECOR_BUTTON_RESERVE: number = 148;/);
assert.match(index, /\.height\(WINDOW_CHROME_HEIGHT\)/);
assert.match(index, /\.padding\(\{ left: 8, right: WINDOW_DECOR_BUTTON_RESERVE \}\)/);
assert.doesNotMatch(ability, /setWindowTitleButtonVisible|fusionTermControlsHover/,
  'window-control hiding retired 2026-07-28 (hover reveal was not workable)');
assert.match(
  index,
  /\.backgroundColor\(this\.chrome\.barBg\)/,
  'app tab strip material derives from the active terminal theme (adaptive chrome)'
);
assert.doesNotMatch(
  index,
  /'#080B10'|'#121821'|'#151A22'/,
  'no fixed near-black chrome colors may return after the adaptive-chrome cutover'
);
assert.match(
  index,
  /\.backgroundColor\(this\.active\s*\? this\.chrome\.capBg[\s\S]*?\.border\(\{[\s\S]*?color: this\.active \? this\.chrome\.capBorder : '#00000000'[\s\S]*?\}\)/s,
  'active tab is a floating pill capsule over the adaptive bar material'
);
