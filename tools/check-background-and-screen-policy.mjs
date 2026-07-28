import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const moduleConfig = JSON.parse(await readFile('entry/src/main/module.json5', 'utf8'));
const ability = await readFile('entry/src/main/ets/entryability/EntryAbility.ets', 'utf8');
const keepAlive = await readFile('entry/src/main/ets/common/KeepAliveManager.ets', 'utf8');
const index = await readFile('entry/src/main/ets/pages/Index.ets', 'utf8');
const appearance = await readFile('entry/src/main/ets/settings/AppearanceStore.ets', 'utf8');

const permissions = moduleConfig.module.requestPermissions.map((item) => item.name);
assert.ok(
  permissions.includes('ohos.permission.KEEP_BACKGROUND_RUNNING'),
  'continuous tasks require KEEP_BACKGROUND_RUNNING'
);

const entryAbility = moduleConfig.module.abilities.find((item) => item.name === 'EntryAbility');
assert.ok(entryAbility, 'EntryAbility must exist');
assert.ok(
  entryAbility.backgroundModes?.includes('taskKeeping'),
  'EntryAbility must declare the taskKeeping background mode'
);

assert.match(keepAlive, /backgroundTaskManager\.startBackgroundRunning\(/);
assert.match(keepAlive, /backgroundTaskManager\.BackgroundMode\.TASK_KEEPING/);
assert.match(keepAlive, /backgroundTaskManager\.stopBackgroundRunning\(/);
assert.match(index, /keepAlive\.noteSessionActive\(this\.context\);/);
assert.match(index, /keepAlive\.noteSessionInactive\(\);/);

assert.match(ability, /private windowForeground: boolean = false;/);
assert.match(ability, /private mainWindow: window\.Window \| null = null;/);
assert.match(ability, /this\.mainWindow = mainWindow;[\s\S]*?this\.applyForegroundScreenPolicy\(\);/);
assert.doesNotMatch(
  ability,
  /setWindowBackgroundColor|enableTransparentWindowBackground|TRANSPARENT_WINDOW_BACKGROUND/,
  'desktop windows must not expose the opaque ContainerModal as a white transparency backdrop'
);
assert.doesNotMatch(ability, /setBackdropBlur/, 'ordinary-signed builds must not use the system-only backdrop blur API');
assert.match(ability, /mainWindow\.setWindowKeepScreenOn\(enabled\)/);
assert.match(
  ability,
  /onForeground\(\): void \{[\s\S]*?this\.windowForeground = true;[\s\S]*?this\.applyForegroundScreenPolicy\(\);[\s\S]*?\n  onBackground\(\): void \{/,
  'foreground lifecycle must enable the keep-screen-on policy'
);
assert.match(
  ability,
  /onBackground\(\): void \{[\s\S]*?this\.windowForeground = false;[\s\S]*?this\.applyForegroundScreenPolicy\(\);[\s\S]*?\n  onWindowStageDestroy\(\): void \{/,
  'background lifecycle must restore the system screen timeout'
);
assert.match(
  ability,
  /onWindowStageDestroy\(\): void \{[\s\S]*?this\.windowForeground = false;[\s\S]*?this\.applyForegroundScreenPolicy\(\);[\s\S]*?this\.mainWindow = null;/,
  'window teardown must restore the system screen timeout and release the window reference'
);

assert.doesNotMatch(appearance, /desktopTransparency/);
assert.doesNotMatch(index, /desktopTransparency|桌面透出|window-transparency|windowBackdropColor/);
assert.match(index, /return this\.backgroundImagePath\.length > 0 \? this\.backgroundOpacity : 1;/);
assert.match(index, /return this\.backgroundImagePath\.length > 0 \? '#00000000' : this\.chrome\.appBg;/);
assert.match(index, /bgOpacity: this\.terminalBackgroundOpacity\(\)/);
assert.match(index, /const effectiveOpacity = this\.terminalBackgroundOpacity\(\);/);
assert.match(index, /\.backgroundColor\(this\.chrome\.appBg\)[\s\S]*?\.onAreaChange\(/);

console.log('Background image, keep-alive, screen policy, and desktop transparency guard checks passed.');
