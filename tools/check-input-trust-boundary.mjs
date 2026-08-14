import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

// CR-004 input trust boundary. Two pins live here:
//
// 1) Per-session upload identity. Image-paste SFTP uploads must read the
//    TerminalSessionHandle's in-memory upload profile captured at connect
//    time -- never the page-global draftHost/draftUser/draftPassword draft,
//    which made a paste in tab A upload with tab B's credentials. Passwords
//    stay runtime-only (ConnectionStore must not persist them).
//
// 2) Paste sanitization (Ghostty CVE-2026-26982 class). Every text paste
//    (Ctrl+V / Shift+Insert native shortcut, right-click menu, secure
//    PasteButton) funnels through GuardedTerminalController.paste(), where an
//    app-layer gate holds multi-line text or text with C0 control characters
//    (other than \n) behind a confirmation overlay. Single-line clean text
//    stays zero-prompt. The overlay is a hard cut (no animation) and recolors
//    purely from theme-derived chrome tokens.

const model = await readFile('entry/src/main/ets/model/TerminalSession.ets', 'utf8');
const index = await readFile('entry/src/main/ets/pages/Index.ets', 'utf8');
const connectionStore = await readFile('entry/src/main/ets/settings/ConnectionStore.ets', 'utf8');

function extractFunction(source, signature) {
  const start = source.indexOf(signature);
  assert.notEqual(start, -1, `missing function signature: ${signature}`);
  const braceStart = source.indexOf('{', start);
  assert.notEqual(braceStart, -1, `missing function body: ${signature}`);

  let depth = 0;
  for (let i = braceStart; i < source.length; i += 1) {
    const char = source[i];
    if (char === '{') {
      depth += 1;
    } else if (char === '}') {
      depth -= 1;
      if (depth === 0) {
        return source.slice(start, i + 1);
      }
    }
  }

  assert.fail(`unterminated function body: ${signature}`);
}

// ── Model: guarded paste funnel ─────────────────────────────────────────────
assert.match(model, /export class GuardedTerminalController extends TerminalController \{/,
  'the app-owned controller subclass must guard the single paste funnel');
assert.match(model, /pasteGate: \(\(text: string\) => boolean\) \| null = null;/,
  'the gate is an app-installed callback, not renderer-HAR state');
const guardedPaste = extractFunction(model, 'paste(data: string): void');
assert.match(guardedPaste, /if \(this\.pasteGate && !this\.pasteGate\(data\)\) \{\s*return;\s*\}/,
  'a held paste must return before touching the native channel');
assert.match(guardedPaste, /super\.paste\(data\);/);
const confirmedPaste = extractFunction(model, 'pasteConfirmed(data: string): void');
assert.match(confirmedPaste, /super\.paste\(data\);/,
  'the confirmation path bypasses the gate straight into the native paste channel');

// Risk predicate: multi-line (any \n) or a C0 control byte other than \n.
assert.match(model, /const PASTE_C0_PATTERN: RegExp = \/\[\\x00-\\x09\\x0B-\\x1F\]\/;/,
  'the C0 set must exclude \n (0x0A) but keep \r, \t, ESC, etc.');
assert.match(model, /export function pasteTextNeedsConfirm\(text: string\): boolean \{/);
const needsConfirm = extractFunction(model, 'export function pasteTextNeedsConfirm(text: string): boolean');
assert.match(needsConfirm, /text\.includes\('\\n'\)/, 'multi-line text must require confirmation');
assert.match(needsConfirm, /PASTE_C0_PATTERN\.test\(text\)/, 'C0 control bytes must require confirmation');

// ── Model: per-session in-memory upload identity ────────────────────────────
assert.match(model, /readonly controller: GuardedTerminalController;/);
assert.match(model, /this\.controller = new GuardedTerminalController\(\);/);
assert.match(model, /uploadHost: string = '';/);
assert.match(model, /uploadPort: number = 22;/);
assert.match(model, /uploadUser: string = '';/);
assert.match(model, /uploadPassword: string = '';/);
assert.match(model, /bindUploadProfile\(host: string, port: number, user: string, password: string\): void \{/);
assert.match(model, /clearUploadProfile\(\): void \{/);

// ── Index: the upload path reads ONLY the session profile ───────────────────
const upload = extractFunction(index, 'private uploadPastedImage(session: TerminalSessionHandle, localPath: string): void');
assert.match(upload, /session\.uploadPassword\.length === 0/,
  'an unbound session (no password captured at connect) must degrade to the local path');
assert.match(upload, /session\.uploadHost,/);
assert.match(upload, /session\.uploadPort,/);
assert.match(upload, /session\.uploadUser,/);
assert.match(upload, /session\.uploadPassword,/);
assert.doesNotMatch(upload, /this\.draft(Host|User|Password|SshPort)/,
  'cross-tab leak: the upload path must never read the shared connection draft');

// Binding happens on every (re)connect of each transport; local drops it.
const bindHelper = extractFunction(index, 'private bindSessionUploadProfile(session: TerminalSessionHandle): ConnectionProfile');
assert.match(bindHelper, /createFusionVmProfile\(/, 'upload identity reuses the same normalization as SSH connect');
assert.match(bindHelper, /session\.bindUploadProfile\(profile\.host, profile\.port, profile\.user, profile\.password\);/);
assert.match(extractFunction(index, 'private connectFusionVm(): void'), /this\.bindSessionUploadProfile\(session\);/,
  'SSH connect must bind the upload identity to this session');
assert.match(
  extractFunction(index, 'private connectFusionAgentForSession(session: TerminalSessionHandle, persistSettings: boolean): void'),
  /this\.bindSessionUploadProfile\(session\);/,
  'agent connect must bind the upload identity to this session');
assert.match(extractFunction(index, 'private startLocalSession(): void'), /session\.clearUploadProfile\(\);/,
  'a local PTY has no remote host: the upload identity must be dropped');

// ── Index: gate install + confirmation overlay ──────────────────────────────
assert.match(
  extractFunction(index, 'private wireSessionListeners(session: TerminalSessionHandle): void'),
  /session\.controller\.pasteGate = \(text: string\): boolean => this\.gateTextPaste\(session, text\);/,
  'every session (fresh or adopted from a sibling window) must arm the gate against THIS window');

const gate = extractFunction(index, 'private gateTextPaste(session: TerminalSessionHandle, text: string): boolean');
assert.match(gate, /if \(!pasteTextNeedsConfirm\(text\)\) \{\s*return true;\s*\}/,
  'single-line clean text must pass through with zero interruption');
assert.match(gate, /this\.pasteConfirmOpen = true;/);
assert.match(gate, /return false;/, 'risky text is held; nothing reaches the PTY before consent');

assert.match(index, /@State private pasteConfirmOpen: boolean = false;/);
const confirm = extractFunction(index, 'private confirmPendingPaste(): void');
assert.match(confirm, /session\.controller\.pasteConfirmed\(text\);/,
  'only an explicit confirm may release the held text into the native paste channel');
const dismiss = extractFunction(index, 'private dismissPasteConfirm(): void');
assert.match(dismiss, /this\.pendingPasteText = '';/, 'cancel must drop the held text');
assert.match(dismiss, /this\.focusActiveTerminalSoon\(\);/, 'closing the dialog returns focus to the terminal');

// Overlay integration: blocks native terminal input, participates in Esc.
assert.match(extractFunction(index, 'private terminalInputActive(): boolean'), /!this\.pasteConfirmOpen/,
  'the confirm overlay must deafen the terminal like the other overlays');
assert.match(extractFunction(index, 'private workbenchOverlayOpen(): boolean'), /this\.pasteConfirmOpen/);
const closeTopmost = extractFunction(index, 'private closeTopmostOverlay(): void');
assert.match(closeTopmost, /if \(this\.pasteConfirmOpen\) \{[\s\S]*?this\.dismissPasteConfirm\(\);/,
  'Esc on a paste confirmation cancels, it never pastes');
assert.ok(
  closeTopmost.indexOf('this.pasteConfirmOpen') < closeTopmost.indexOf('this.agentGuideOpen'),
  'the paste confirmation sits topmost: Esc resolves it before any other overlay');
assert.match(index, /if \(this\.pasteConfirmOpen\) \{\s*this\.buildPasteConfirmScrim\(\);\s*this\.buildPasteConfirmDialog\(\);/s,
  'build() must mount the scrim + dialog while a paste is held');

// The dialog itself: hard cut (no animation), theme-derived neutral colors.
const dialog = extractFunction(index, 'private buildPasteConfirmDialog()');
assert.doesNotMatch(dialog, /transition\(|animateTo|animation\(|keyframeAnimateTo/,
  'paste confirmation is a hard cut: no enter/exit animation');
assert.match(dialog, /this\.chrome\.panelBg\b/);
assert.match(dialog, /this\.chrome\.primaryBtnBg/);
assert.match(dialog, /this\.chrome\.primaryBtnText/);
assert.match(dialog, /this\.confirmPendingPaste\(\);/);
assert.match(dialog, /this\.dismissPasteConfirm\(\);/);
assert.match(dialog, /this\.pendingPastePreview\(\)/,
  'the held text is previewed so the user sees what they are about to paste');

// ── Passwords stay runtime-only ─────────────────────────────────────────────
assert.doesNotMatch(connectionStore, /password\s*:\s*string/i,
  'no-persisted-password rule: ConnectionSettings must never gain a password field');
assert.doesNotMatch(connectionStore, /prefs\.put\('password'/,
  'no-persisted-password rule: the store must never write a password key');
const persist = extractFunction(index, 'private persistConnection(): void');
assert.doesNotMatch(persist, /password/i,
  'no-persisted-password rule: the persisted connection snapshot must not carry the password');

console.log('check-input-trust-boundary: OK');
