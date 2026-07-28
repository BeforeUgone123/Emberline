import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const index = await readFile('entry/src/main/ets/pages/Index.ets', 'utf8');

// ── Reorder: equal-split pills with an in-track horizontal pan. ─────────────
assert.match(index, /@Prop chipWidth: number;/);
assert.match(index, /private tabChipWidth\(\): number \{/);
assert.match(index, /TAB_NEW_BUTTON_WIDTH_VP \+ count \* TAB_STRIP_GAP_VP/);
assert.match(index, /return Math\.max\(TAB_CHIP_MIN_WIDTH_VP, sharedWidth\);/,
  'equal-split width keeps only the touch-safe floor');
assert.match(index, /PanGesture\(\{ fingers: 1, direction: PanDirection\.Horizontal, distance: 8 \}\)/,
  'chip pan is horizontal in-track reorder only (system drag retired 2026-07-28)');

// ── Touch language: long-press picks up, double-tap renames. ────────────────
assert.match(index, /LongPressGesture\(\{ fingers: 1, repeat: false \}\)\s*\.onAction\(\(_event: GestureEvent\): void => \{\s*this\.onReorderStart\(\);/s,
  'long-press picks the chip up into the in-track drag');
assert.match(index, /TapGesture\(\{ count: 2 \}\)\s*\.onAction\(\(_event: GestureEvent\): void => \{\s*this\.onEdit\(\);/s,
  'double-tap opens the tab editor');

// ── Cross-window: context-menu split/move only; the drag pipeline stays gone.
assert.match(index, /MenuItem\(\{ content: '拆分为新窗口' \}\)/);
assert.match(index, /MenuItem\(\{ content: '移动到窗口…', builder: /);
assert.match(index, /private splitSessionToNewWindow\(sessionId: number\): void \{/);
assert.match(index, /private moveSessionToWindow\(sessionId: number, stamp: number\): void \{/);
assert.match(index, /private tearOffParkedSession\(token: string\): void \{/,
  'split launches the sibling window with no drop-geometry plumbing');
assert.match(index, /sessionRegistry\.registerWindow\(/);
assert.match(index, /sessionRegistry\.unregisterWindow\(this\.windowStamp\)/);
assert.match(index, /sessionRegistry\.deliverTo\(stamp, handle\)/);
assert.match(index, /sessionRegistry\.park\(token, handle/);
assert.match(index, /private recoverParkedSession\(token: string, originIndex: number\): void \{/,
  'expiry / launch failure re-adopt the live session');
assert.doesNotMatch(index, /executeDrag|dragController|unifiedDataChannel|uniformTypeDescriptor|allowDrop|TAB_PICKUP_THRESHOLD_VP|handleTabStripDrop|pickUpSessionForSystemDrag/,
  'retired system-drag pipeline must not return (user decision 2026-07-28)');

// ── The only tab moving out closes its window; solo menu offers move, not
//    split (splitting the only tab would just relocate the window). ──────────
assert.match(index, /const wasOnlyTab: boolean = this\.sessions\.length === 1/,
  'move-to-window detects the last-tab case');
assert.match(index, /if \(wasOnlyTab && this\.context\) \{\s*this\.context\.terminateSelf\(\)/s,
  'an emptied window closes itself instead of lingering disconnected');
const soloMenu = index.slice(index.indexOf('private buildSoloTabContextMenu'),
  index.indexOf('private buildSoloMoveMenu'));
assert.ok(!soloMenu.includes('拆分为新窗口'),
  'solo menu must not offer split (it IS the only tab)');
assert.ok(soloMenu.includes('移动到窗口…'), 'solo menu still offers move');

// ── Hand-off safety: adoption defers past the source unmount; drivers replay
//    the truthful status so a moved live session never fake-drops. ───────────
assert.match(index, /setTimeout\(\(\): void => \{\s*this\.adoptSession\(handle\);\s*\}, TAB_MOVE_ADOPT_DELAY_MS\)/s,
  'move-to-window adoption waits out the same-surfaceId mount/unmount race');
assert.match(index, /releaseSessionForHandoff/);

const agent = await readFile('entry/src/main/ets/drivers/FusionAgentDriver.ets', 'utf8');
const term = await readFile('entry/src/main/ets/drivers/FusionTerminalDriver.ets', 'utf8');
assert.match(agent, /this\.emitStatus\(this\.lastEmittedConnected, this\.lastEmittedLabel, ''\);/,
  'agent driver replays the current truth to a newly attached status listener');
assert.doesNotMatch(agent, /this\.statusListener = listener;\s*this\.emitStatus\(false, 'Agent 待机', ''\);/s,
  'hardcoded idle replay must not return');
assert.match(term, /this\.emitStatus\(this\.lastEmittedConnected,/,
  'terminal driver replays the current truth too');

// ── Retired plumbing stays gone. ────────────────────────────────────────────
assert.doesNotMatch(index, /handleHandoffEnd|readHandoffToken|handledHandoffTokens|onHandoffEnd/);

// ── Review 2026-07-28: an adopted LIVE session re-claims its keep-alive unit.
// The releasing window drops the unit, and the status replay carries no
// false->true edge, so syncSessionKeepAlive can never re-request it. Without
// this a moved tab that is the only live session loses background protection.
assert.match(index, /handle\.connected && !handle\.keepAliveHeld && this\.context/,
  'adoptSession re-claims the keep-alive unit for an already-connected session');

// ── Review 2026-07-28: the settle guard. Pan and long-press both end on
// finger-up, and draggingSessionId only clears in the settle onFinish, so a
// second entry would queue a duplicate reorderSession.
assert.match(index, /private dragSettling: boolean = false;/,
  'the tab-reorder settle guard exists');
assert.match(index, /if \(this\.dragSettling\) \{\s*return;\s*\}/,
  'endTabDrag / cancelTabDrag return early while a settle is in flight');

// ── Review 2026-07-28: sibling windows re-colour their own grids. Chrome
// tokens travel via AppStorage, but controller.setTheme is per-window, so
// without this the tab bar re-tints while the terminal keeps the old palette.
assert.match(index, /@StorageProp\(EFFECTIVE_THEME_KEY\) @Watch\('onSharedThemeChanged'\)/,
  'windows observe the shared effective theme');
assert.match(index, /AppStorage\.setOrCreate\(EFFECTIVE_THEME_KEY, theme\);/,
  'applyEffectiveTheme publishes the effective theme for sibling windows');

console.log('check-tab-drag-handoff: OK');
