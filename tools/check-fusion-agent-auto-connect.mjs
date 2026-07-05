import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const index = await readFile('entry/src/main/ets/pages/Index.ets', 'utf8');
// The per-session connection-state flags live on TerminalSessionHandle, which was
// extracted into the shared model for the SessionRegistry (tab drag-out / merge).
const sessionModel = await readFile('entry/src/main/ets/model/TerminalSession.ets', 'utf8');

assert.match(sessionModel, /attached: boolean = false;/);
assert.match(sessionModel, /autoConnectAttempted: boolean = false;/);
assert.match(sessionModel, /manualConnectionSelected: boolean = false;/);
assert.match(index, /private connectionSettingsLoaded: boolean = false;/);

const attachmentBlock =
  index.match(/session\.controller\.setAttachmentListener\(\(attached: boolean\) => \{[\s\S]*?\n    \}\);/)?.[0] ?? '';
assert.match(attachmentBlock, /session\.attached = attached;/);
assert.match(attachmentBlock, /this\.applyCustomFontTo\(session\);/);
assert.match(attachmentBlock, /if \(!this\.tryAutoConnectSession\(session\)\) \{\s*this\.showStartupDemo\(session\);/s);

assert.match(index, /private tryAutoConnectAllSessions\(\): void \{/);
assert.match(index, /private tryAutoConnectSession\(session: TerminalSessionHandle\): boolean \{/);
assert.match(index, /if \(session\.manualConnectionSelected \|\| session\.autoConnectAttempted\) \{/);
assert.match(index, /if \(!session\.attached \|\| !session\.controller\.isAttached\(\) \|\| !this\.connectionSettingsLoaded\) \{/);
assert.match(index, /session\.autoConnectAttempted = true;/);
assert.match(index, /this\.connectFusionAgentForSession\(session, false\);/);

assert.match(index, /private connectFusionAgentForSession\(session: TerminalSessionHandle, persistSettings: boolean\): void \{/);
assert.match(index, /private markManualConnection\(session: TerminalSessionHandle\): void \{/);
assert.match(index, /session\.manualConnectionSelected = true;/);
assert.match(index, /session\.autoConnectAttempted = true;/);

assert.match(index, /private connectFusionAgent\(\): void \{\s*const session = this\.activeSession\(\);[\s\S]*?this\.markManualConnection\(session\);[\s\S]*?this\.connectFusionAgentForSession\(session, true\);/);
assert.match(index, /private connectFusionVm\(\): void \{\s*const session = this\.activeSession\(\);[\s\S]*?this\.markManualConnection\(session\);/);
assert.match(index, /private startLocalSession\(\): void \{\s*const session = this\.activeSession\(\);[\s\S]*?this\.markManualConnection\(session\);/);

const loadAppearanceBlock = index.match(/private async loadAppearance\(\): Promise<void> \{[\s\S]*?\n  \}/)?.[0] ?? '';
assert.match(loadAppearanceBlock, /finally \{/);
assert.match(loadAppearanceBlock, /this\.connectionSettingsLoaded = true;/);
assert.match(loadAppearanceBlock, /this\.tryAutoConnectAllSessions\(\);/);
