import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

// Tab reorder = APPLICATION-LEVEL in-track drag (Chrome / ghostty style: the chip
// follows the finger inside the strip, neighbours make room, a spring lands it in
// the target slot). The old ArkUI SYSTEM drag pipeline (draggable + onDragStart +
// UDMF token + floating preview + allowDrop/onDrop) was ripped out because the
// floating snapshot felt wrong; rename moved from double-tap to a right-click menu
// (long-press is the touch fallback). Cross-window merge / tear-off stay DISABLED,
// but their session plumbing -- SessionRegistry, adopt/release, wireSessionListeners
// -- is retained for a future re-enable.

const index = readFileSync('entry/src/main/ets/pages/Index.ets', 'utf8');

// AbilityKit import stays (Want/common still used elsewhere).
assert.match(index, /import \{ common, Want \} from '@kit\.AbilityKit';/,
  'AbilityKit import stays lean');

// ── The system drag pipeline must be entirely gone. ──────────────────────────
assert.doesNotMatch(index, /@kit\.ArkData/,
  'UDMF ArkData import removed with the system drag payload');
assert.doesNotMatch(index, /unifiedDataChannel|uniformTypeDescriptor/,
  'no UDMF drag payload types remain');
assert.doesNotMatch(index, /\.draggable\(true\)/,
  'no chip is system-draggable any more');
assert.doesNotMatch(index, /onDragStart|onDragEnd/,
  'system drag start/end handlers removed');
assert.doesNotMatch(index, /allowDrop|onDrop\(/,
  'no drop targets on the tab strip or terminal body');
assert.doesNotMatch(index, /handleTabStripDrop|handleTerminalBodyDrop|handleHandoffEnd|readHandoffToken|computeDropInsertIndex/,
  'system-drag drop/handoff plumbing removed');
assert.doesNotMatch(index, /handledHandoffTokens|handoffToken|onHandoffEnd|buildDragPreview/,
  'handoff token bookkeeping + floating preview removed');

// ── Rename: right-click context menu, NOT double-tap. ────────────────────────
assert.doesNotMatch(index, /TapGesture\(\{\s*count:\s*2\s*\}\)/,
  'double-tap-to-rename gesture removed');
assert.match(index, /@Builder\s*\n\s*private buildTabContextMenu\(\)/,
  'chip owns a context-menu builder');
assert.match(index, /MenuItem\(\{ content: '标签设置' \}\)/,
  'context menu has a tab-settings (rename) item');
assert.match(index, /MenuItem\(\{ content: '关闭标签' \}\)/,
  'context menu has a close item');
assert.match(index, /\.bindContextMenu\(this\.buildTabContextMenu\(\), ResponseType\.RightClick\)/,
  'menu is bound on right-click');
assert.match(index, /LongPressGesture\(\{ fingers: 1, repeat: false \}\)/,
  'long-press is the touch fallback for rename');

// ── In-track drag: horizontal PanGesture on the chip + page reorder state. ───
assert.match(index, /PanGesture\(\{ fingers: 1, direction: PanDirection\.Horizontal, distance: 8 \}\)/,
  'chip drives an as-you-move horizontal pan (distance 8) for reorder');
assert.match(index, /this\.onReorderUpdate\(Number\(event\.offsetX \?\? 0\)\)/,
  'pan forwards the cumulative finger offset up to the page');
assert.match(index, /@Prop translateX: number;/,
  'chip takes its live drag offset as a plain-value @Prop (parent re-syncs it)');
assert.match(index, /@Prop lifted: boolean;/,
  'chip takes a lifted flag (zIndex + active face, never a scale transform)');
assert.match(index, /onChipWidth: \(width: number\) => void/,
  'chip reports its measured width so the page can map an offset to a slot');
assert.match(index, /\.translate\(\{ x: this\.translateX \}\)/,
  'the offset is applied as a translate (compositor-safe, no relayout)');

// Page-side reorder methods.
assert.match(index, /private tabShiftFor\(i: number\): number \{/,
  'page computes each chip offset (finger follow for the dragged chip, ±advance for a displaced one)');
assert.match(index, /private beginTabDrag\(sessionId: number\): void \{/, 'drag begin');
assert.match(index, /private updateTabDrag\(offsetX: number\): void \{/, 'drag move');
assert.match(index, /private endTabDrag\(\): void \{/, 'drag end');
assert.match(index, /private cancelTabDrag\(\): void \{/, 'drag cancel');
assert.match(index, /translateX: this\.tabShiftFor\(index\)/,
  'buildTabBar hands each chip its live offset by array index');
// The neighbours' let-position and the settle both use the shared SPRING_SETTLE
// spring, and the drop reorders the live session array in place.
assert.match(index, /curve: SPRING_SETTLE/,
  'let-position + drop settle ride the shared spring token');
assert.match(index, /this\.reorderSession\(from, fullInsert\)/,
  'drop splices the session array into its new order');

// ── Cross-window handoff plumbing must SURVIVE (future re-enable). ───────────
assert.match(index, /import \{ sessionRegistry \}/, 'SessionRegistry import retained');
assert.match(index, /private adoptSession\(/, 'adoptSession plumbing retained');
assert.match(index, /private releaseSessionForHandoff\(/, 'release plumbing retained');
assert.match(index, /private wireSessionListeners\(/, 'listener wiring retained');
assert.match(index, /emberHandoffToken/, 'handoff token key retained for window bootstrap');

console.log('check-tab-drag-handoff: OK');
