import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

// Tab drag = in-window reorder only (cross-window merge and tear-off are
// DISABLED by decision 2026-07-05; the handoff plumbing -- registry, adopt/
// release, softDetach/rebind -- stays in place for a future re-enable).

const index = readFileSync('entry/src/main/ets/pages/Index.ets', 'utf8');

assert.match(index, /import \{ common, Want \} from '@kit\.AbilityKit';/,
  'AbilityKit import stays lean: StartOptions left with the disabled tear-off');
assert.match(index, /import \{ unifiedDataChannel, uniformTypeDescriptor \} from '@kit\.ArkData';/,
  'UDMF drag payload imports');

const chipBuild = index.slice(index.indexOf('struct TerminalTabChip'), index.indexOf('@Entry'));
assert.match(chipBuild, /\.draggable\(true\)/, 'chip must be draggable');
assert.match(chipBuild, /\.onDragStart\(\(event: DragEvent\): DragItemInfo => \{/);
assert.match(chipBuild, /const token: string = sessionRegistry\.generateToken\(\);/,
  'drag start parks the handle under a fresh token');
assert.match(chipBuild, /sessionRegistry\.park\(token, this\.session,/,
  'park keeps the handle recoverable while the drag is in flight');
assert.match(chipBuild, /event\.setData\(new unifiedDataChannel\.UnifiedData\(record\)\)/,
  'token travels as UDMF plain text');
assert.match(chipBuild, /const preview: DragItemInfo = \{ builder: \(\): void => \{ this\.buildDragPreview\(\); \} \};/,
  'custom drag preview');
assert.match(chipBuild, /\.onDragEnd\(\(event: DragEvent\): void => \{\s*this\.onHandoffEnd\(this\.handoffToken, event\.getResult\(\)\);/s,
  'drag end routes through the handoff bookkeeping');
assert.doesNotMatch(chipBuild, /\.attach\(|\.detach\(|\.rebind\(|\.softDetach\(/,
  'the chip never touches transport lifecycles directly');
assert.doesNotMatch(chipBuild, /bindContextMenu|onTearOff|onDragMove/,
  'tear-off menu and drag-move tracking removed with the disabled tear-off');

const stripDrop = index.slice(index.indexOf('private handleTabStripDrop'), index.indexOf('private handleTerminalBodyDrop'));
assert.match(stripDrop, /const handle: TerminalSessionHandle \| null = sessionRegistry\.claim\(token\);/,
  'drop claims the parked handle');
assert.match(stripDrop, /this\.reorderSession\(localIndex, insertIndex\);/,
  'same-window drop reorders in place');
assert.match(stripDrop, /this\.handledHandoffTokens\.add\(token\);/,
  'reorder marks the token so onDragEnd leaves the handle alone');
assert.match(stripDrop, /sessionRegistry\.park\(token, handle, \(\): void => \{\}\);/,
  'foreign handles are parked straight back (cross-window merge disabled)');
assert.doesNotMatch(stripDrop, /adoptSession|setTimeout/,
  'no deferred adopt while cross-window merge is disabled');
assert.match(stripDrop, /event\.setResult\(DragResult\.DRAG_SUCCESSFUL\);/);

const bodyDrop = index.slice(index.indexOf('private handleTerminalBodyDrop'), index.indexOf('private readHandoffToken'));
assert.match(bodyDrop, /event\.setResult\(DragResult\.DRAG_SUCCESSFUL\);/,
  'terminal body still eats stray drops so they read as cancel');
assert.match(index, /\.allowDrop\(\[uniformTypeDescriptor\.UniformDataType\.PLAIN_TEXT\]\)/,
  'drop targets accept the plain-text token');

const handoffEnd = index.slice(index.indexOf('private handleHandoffEnd'), index.indexOf('private activateSession'));
assert.match(handoffEnd, /if \(this\.handledHandoffTokens\.has\(token\)\) \{\s*this\.handledHandoffTokens\.delete\(token\);\s*return;/s,
  'own reorder: nothing further to do');
assert.match(handoffEnd, /sessionRegistry\.claim\(token\);/,
  'all other outcomes clean up the park and keep the tab in place');
assert.doesNotMatch(handoffEnd, /tearOffHandle|startAbility/,
  'tear-off disabled: FAILED must not launch windows');
assert.doesNotMatch(index, /tearOffHandle|tearOffFromMenu|TEAR_OFF_/,
  'tear-off implementation fully removed');

// Handoff plumbing must SURVIVE (future re-enable): registry, adopt, release.
assert.match(index, /private adoptSession\(/, 'adoptSession plumbing retained');
assert.match(index, /private releaseSessionForHandoff\(/, 'release plumbing retained');
assert.match(index, /emberHandoffToken/, 'handoff token key retained for window bootstrap');

console.log('check-tab-drag-handoff: OK');
