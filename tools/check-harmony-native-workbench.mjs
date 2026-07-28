import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

// Direction A: Harmony Native Workbench. Keep the first viewport terminal-first,
// reserve the persistent chrome for three app actions, and put all configuration
// in a responsive, non-relayout inspector.
const index = await readFile('entry/src/main/ets/pages/Index.ets', 'utf8');
const moreIcon = await readFile('entry/src/main/resources/base/media/ic_more.svg', 'utf8');

const tabBar = index.match(/private buildTabBar\(\)[\s\S]*?\n  @Builder\n  private buildWorkspaceMenu/)?.[0] ?? '';
const workspaceMenu = index.match(/private buildWorkspaceMenu\(\)[\s\S]*?\n  @Builder\n  private buildDrawerScrim/)?.[0] ?? '';
const drawer = index.match(/private buildDrawer\(\)[\s\S]*?\n  @Builder\n  private buildDrawerNavItem/)?.[0] ?? '';
const drawerScrim = index.match(/private buildDrawerScrim\(\)[\s\S]*?\n  @Builder\n  private buildDrawer/)?.[0] ?? '';

assert.match(index, /const INSPECTOR_COMPACT_WIDTH: number = 352;/);
assert.match(index, /const INSPECTOR_DEFAULT_WIDTH: number = 400;/);
assert.match(index, /const INSPECTOR_BREAKPOINT: number = 900;/);
assert.match(index, /@State private workspaceWidth: number = 960;/);
assert.match(index, /private inspectorWidth\(\): number \{/);
assert.match(index, /this\.workspaceWidth < INSPECTOR_BREAKPOINT/);
assert.match(index, /\.onAreaChange\([^]*?this\.workspaceWidth = width;/);

assert.match(index, /@State private drawerPane: string = 'terminal';/);
for (const [label, pane] of [['终端', 'terminal'], ['外观', 'appearance'], ['连接', 'conn']]) {
  assert.match(drawer, new RegExp(`buildDrawerNavItem\\('${label}', '${pane}'\\)`));
}
for (const legacyPane of ["'字体', 'font'", "'主题', 'theme'", "'帮助', 'help'"]) {
  assert.doesNotMatch(drawer, new RegExp(legacyPane), 'inspector must expose exactly three destinations');
}
assert.match(drawer, /\.width\(this\.inspectorWidth\(\)\)/);
assert.match(drawer, /\.opacity\(this\.drawerShown \? 1 : 0\)/);
assert.match(drawer, /\.translate\(\{ x: this\.drawerShown \? 0 : this\.inspectorWidth\(\) \}\)/);
assert.match(drawer, /\.animation\(\{ duration: DUR_STANDARD, curve: CURVE_DECEL \}\)[\s\S]*?\.width\(this\.inspectorWidth\(\)\)/,
  'responsive inspector width must sit outside the animated opacity/translate layer');
assert.doesNotMatch(drawerScrim, /#80020305/, 'inspector must not dim or blur the terminal');

for (const icon of ['ic_link', 'ic_gear', 'ic_more']) {
  assert.match(tabBar, new RegExp(icon));
}
assert.equal(
  (tabBar.match(/\.id\('workbench(?:Connection|Settings|More)Action'\)/g) ?? []).length,
  3,
  'tabs must be followed by exactly three persistent workbench actions'
);
for (const label of ['连接', '设置', '更多']) {
  assert.match(tabBar, new RegExp(`accessibilityText\\('${label}'\\)`));
  assert.match(tabBar, new RegExp(`message: '${label}'`));
}
assert.match(
  tabBar,
  /this\.drawerShown && this\.drawerPane === 'conn'[\s\S]*?this\.closeDrawer\(\);[\s\S]*?this\.openDrawer\('conn'\);/,
  'clicking the active connection action again must close the inspector'
);
assert.match(
  tabBar,
  /this\.drawerShown && this\.drawerPane !== 'conn'[\s\S]*?this\.closeDrawer\(\);[\s\S]*?this\.openDrawer\('terminal'\);/,
  'clicking the active settings action again must close the inspector'
);
assert.ok((tabBar.match(/\.onHover\(\(isHover: boolean\)/g) ?? []).length >= 3,
  'persistent icon actions need hover tooltips on 2-in-1 pointer devices');
assert.ok((tabBar.match(/\.height\(40\)\s*\.width\(40\)/g) ?? []).length >= 3,
  'persistent icon actions need stable 40vp touch targets');
for (const removedIcon of ['ic_keyboard', 'ic_help']) {
  assert.doesNotMatch(tabBar, new RegExp(removedIcon));
}
assert.match(tabBar, /\.bindMenu\(this\.buildWorkspaceMenu\(\)\)/);
assert.match(workspaceMenu, /MenuItem\(\{ content: '新建窗口' \}\)[\s\S]*?this\.openNewWindow\(\);/);
assert.match(workspaceMenu, /MenuItem\(\{ content: '帮助与诊断' \}\)[\s\S]*?this\.agentGuideOpen = true;/);
assert.match(workspaceMenu, /MenuItem\(\{ content: '关于 Emberline' \}\)/);

for (const removed of [
  /accessoryVisible/,
  /buildAccessoryBar/,
  /sendAccessoryKey/,
  /OnboardingStore/,
  /loadOnboarding/,
  /onboardingStore/
]) {
  assert.doesNotMatch(index, removed);
}

assert.match(
  index,
  /active: session\.id === this\.activeSessionId &&\s*!this\.drawerOpen &&\s*!this\.tabEditOpen/s,
  'the inspector must keep native terminal input blocked while it is open'
);
assert.match(index, /@State private appInBackground: boolean = false;/);
assert.match(index, /this\.drawerShown && this\.drawerPane === 'conn' && !this\.appInBackground/);
assert.match(index, /private closeDrawer\(\): void \{[\s\S]*?this\.drawerShown = false;[\s\S]*?setTimeout\([\s\S]*?this\.drawerOpen = false;/);
assert.match(index, /private closeDrawer\(\): void \{[\s\S]*?this\.cancelThemePreviewWork\(\);[\s\S]*?this\.drawerPane = 'terminal';/,
  'closing the inspector must stop preview work and unmount the hidden theme catalogue');
assert.match(index, /private switchDrawerPane\(pane: string\): void \{[\s\S]*?this\.drawerTransitionEpoch !== epoch \|\| !this\.drawerShown/,
  'an interrupted pane transition must not mount appearance work after close');
assert.match(index, /@Prop @Watch\('onAppBackgroundedChanged'\) appBackgrounded: boolean;/);
assert.ok((index.match(/\.focusable\(this\.drawerShown\)/g) ?? []).length >= 10,
  'inspector controls must join keyboard traversal only while the inspector is shown');
assert.doesNotMatch(index, /\.scale\(/, 'CJK workbench content must never use transform scale');
assert.doesNotMatch(index, /\.letterSpacing\((?!0(?:\D|$))[^)]*\)/, 'workbench text must use zero letter spacing');
assert.match(index, /private activeConnFailed\(\): boolean \{/);
assert.match(index, /private agentActionLabel\(\): string \{[\s\S]*?'连接中…'[\s\S]*?'重试 Agent'[\s\S]*?'重新连接 Agent'/);
assert.match(index, /Button\(this\.agentActionLabel\(\)\)[\s\S]*?\.enabled\(!this\.activeConnPending\(\)\)/);
assert.match(index, /Button\(this\.connectionErrorDetailsOpen \? '收起详细信息' : '详细信息'\)/);

assert.match(index, /private async loadThemePreviews\(themes: string\[\]\): Promise<void>/);
assert.match(index, /this\.renderedThemeOptions\(\)\.map\(\(option: ThemeOptionState\) => option\.name\)/);
assert.match(index, /@ObjectLink option: ThemeOptionState;/,
  'theme preview and selection updates must stay isolated to their visible row');
assert.match(index, /private themePreviewGeneration: number = 0;/);
assert.match(index, /generation !== this\.themePreviewGeneration/,
  'queued theme preview reads must be cancellable when the inspector closes');
assert.match(moreIcon, /<svg[\s\S]*?<circle[\s\S]*?<circle[\s\S]*?<circle/);

console.log('check-harmony-native-workbench: OK');
