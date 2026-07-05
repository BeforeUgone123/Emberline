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
assert.match(
  index,
  /\.backgroundColor\('#080B10'\)\s*\.border\(\{ width: \{ bottom: 1 \}, color: '#121821' \}\)/s,
  'app tab strip should visually become the custom window chrome instead of a separate toolbar'
);
assert.match(
  index,
  /\.backgroundColor\(this\.active \? '#151A22' : '#00000000'\)\s*\.border\(\{[\s\S]*?color: this\.active \? COLOR_BAR_BORDER : '#00000000'[\s\S]*?\}\)/s,
  'active terminal tab should be integrated into the custom window chrome rail'
);
