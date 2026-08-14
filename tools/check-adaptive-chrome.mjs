import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const theme = await readFile('entry/src/main/ets/theme/ChromeTheme.ets', 'utf8');
const index = await readFile('entry/src/main/ets/pages/Index.ets', 'utf8');
const store = await readFile('entry/src/main/ets/settings/AppearanceStore.ets', 'utf8');
const ability = await readFile('entry/src/main/ets/entryability/EntryAbility.ets', 'utf8');
const model = await readFile('entry/src/main/ets/model/TerminalSession.ets', 'utf8');

// Derivation layer: every chrome color comes from the theme's bg/fg (+ red).
assert.match(theme, /export function deriveChromeTokens\(bgHex: string, fgHex: string, redHex: string\): ChromeTokens/);
assert.match(theme, /export const CHROME_TOKENS_KEY/);
assert.match(theme, /export const SYS_DARK_KEY/);
assert.match(theme, /export const DEFAULT_CHROME_TOKENS/);

// Ghostty light/dark pairing persists both slots and migrates the legacy key.
assert.match(store, /darkThemeName: string;/);
assert.match(store, /lightThemeName: string;/);
assert.match(store, /readString\('themeName'/,
  'legacy single-theme installs must migrate into the dark slot');

// System color-mode plumbing: ability publishes, page resolves + re-derives.
assert.match(ability, /onConfigurationUpdate\(newConfig: Configuration\)/);
assert.match(ability, /AppStorage\.setOrCreate\(SYS_DARK_KEY/);
assert.match(index, /@StorageProp\(SYS_DARK_KEY\) @Watch\('onSystemColorModeChanged'\)/);
assert.match(index, /colorModeOverride !== 'system'/,
  'a manual appearance override must ignore OS color-mode flips');
assert.match(store, /colorModeOverride: string;/,
  'the appearance override persists');
assert.match(index, /private async recomputeChromeTokens\(themeName: string = this\.effectiveThemeName\(\)\)/);
assert.match(index, /SHARED_THEME_CONFIG_KEY/,
  'both theme slots and the color mode must synchronize across windows');
assert.match(index, /generation !== this\.chromeThemeGeneration \|\|\s*themeName !== this\.effectiveThemeName\(\)/s,
  'an older raw-file read cannot overwrite a newer effective theme');
assert.match(index, /eventHub\.emit\(CHROME_MODE_EVENT/,
  'system decor buttons must restyle when the chrome flips light/dark');
assert.match(index, /red: slots\[1\]/,
  'theme parsing must surface ANSI red for the failed connection dot');

// Pill tab strip: equal split, floating capsule, solo-tab title mode.
assert.match(index, /@StorageLink\(CHROME_TOKENS_KEY\) chrome: ChromeTokens/);
assert.match(index, /\.borderRadius\(999\)/);
assert.match(index, /struct SoloTabTitle \{/,
  'solo mode is a deep-observing component (@ObjectLink), never a page builder');
assert.match(index, /@ObjectLink @Watch\('onSessionSignal'\) session: TerminalSessionHandle;/,
  'session handles are always deep-observed where their fields render');
assert.match(index, /if \(this\.sessions\.length === 1\)/);
assert.match(index, /return Math\.max\(TAB_CHIP_MIN_WIDTH_VP, sharedWidth\);/);

// Retirement: the fixed palette and the filament accent system stay gone.
assert.doesNotMatch(index, /COLOR_EMBER|FILAMENT_PALETTE|COLOR_APP_BG|COLOR_PANEL_2|COLOR_TEXT_PRIMARY/);
assert.doesNotMatch(model, /filamentColor|igniteEpoch|attentionEpoch/);

console.log('check-adaptive-chrome OK');
