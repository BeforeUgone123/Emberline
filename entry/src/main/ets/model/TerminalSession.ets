import { TerminalController } from 'libghostty-ohos';
import { FusionTerminalDriver } from '../drivers/FusionTerminalDriver';
import { FusionAgentDriver } from '../drivers/FusionAgentDriver';

// ── CR-004 input trust boundary ─────────────────────────────────────────────
// Every text paste (Ctrl+V / Shift+Insert native shortcut, right-click menu,
// secure PasteButton) funnels through TerminalController.paste(). This
// subclass puts an app-layer gate on that single funnel: single-line text
// without C0 control characters passes straight through; anything riskier is
// held by the gate owner and only reaches the native paste channel through
// pasteConfirmed() after explicit user consent.
export class GuardedTerminalController extends TerminalController {
  // Installed by the owning window's Index page (wireSessionListeners), so a
  // session handed off to a sibling window re-arms against THAT window's UI.
  // Returns true to let the paste through immediately, false to hold it.
  pasteGate: ((text: string) => boolean) | null = null;

  paste(data: string): void {
    if (this.pasteGate && !this.pasteGate(data)) {
      return;
    }
    super.paste(data);
  }

  // The confirmation path: skips the gate because the user already consented
  // to this exact text.
  pasteConfirmed(data: string): void {
    super.paste(data);
  }
}

// Risky-paste predicate (Ghostty CVE-2026-26982 class): a pasted newline
// executes the pasted command line as soon as it lands, and a pasted C0
// control byte other than \n (\r, \t, ESC, ...) can drive the shell or the
// terminal parser directly. Single-line text without C0 bytes stays
// zero-prompt.
const PASTE_C0_PATTERN: RegExp = /[\x00-\x09\x0B-\x1F]/;

export function pasteTextNeedsConfirm(text: string): boolean {
  return text.includes('\n') || PASTE_C0_PATTERN.test(text);
}

export function countPasteLines(text: string): number {
  return text.split('\n').length;
}

export function pasteTextHasControlChars(text: string): boolean {
  return PASTE_C0_PATTERN.test(text);
}

// One in-app terminal tab: its renderer controller, transports, and status.
// @Observed so tab chips (@ObjectLink) re-render on title/connection changes.
// Both UI ids and native surface ids are process-global. Multiton windows share
// one ArkTS VM, so a window-local tab id can collide as soon as a live handle is
// moved into a sibling window; ForEach keys, activeSessionId, close, and lookup
// all require the UI id to remain unique after that move.
//
// Extracted from Index.ets so both the page and the process-global
// SessionRegistry (tab drag-out / merge) share one handle definition.
let nextGlobalSessionId: number = 0;
let nextGlobalSurfaceSeq: number = 0;

@Observed
export class TerminalSessionHandle {
  readonly id: number = ++nextGlobalSessionId;
  readonly controller: GuardedTerminalController;
  readonly driver: FusionTerminalDriver;
  readonly agentDriver: FusionAgentDriver;
  statusMode: string = 'demo';
  statusLabel: string = '待机';
  title: string = '新标签页';
  oscTitle: string = '';
  lastCwd: string = '';
  connected: boolean = false;
  demoRendered: boolean = false;
  attached: boolean = false;
  autoConnectAttempted: boolean = false;
  manualConnectionSelected: boolean = false;
  // User override from the tab editor (right-click a tab): a custom title
  // that beats OSC/cwd auto-naming.
  customName: string = '';
  // Image-paste path perspective: 'auto' follows the transport type; the
  // others override it for nested sessions (e.g. ssh typed inside a local
  // shell) where the app cannot know which machine the prompt lives on.
  pasteMode: string = 'auto';
  // pasteMode 'relay': the agent scp-relays the staged image to this remote
  // host (host or user@host) so a shell ssh'd into that machine can read it.
  relayTarget: string = '';
  relayDir: string = '/tmp/emberline-paste';
  // CR-004: in-memory SFTP upload identity captured at connect time, so a
  // pasted image uploads to the host THIS tab is connected to -- never to
  // whatever the shared connection draft says after a later edit or another
  // tab's connect (the old page-global draftHost/draftPassword read made that
  // cross-tab leak possible). Runtime-only per the no-persisted-password rule;
  // an unbound (local/demo) session carries an empty password and its sftp
  // paste mode degrades to pasting the sandbox path with a hint.
  uploadHost: string = '';
  uploadPort: number = 22;
  uploadUser: string = '';
  uploadPassword: string = '';
  // Rate limit for task-finished system notifications (bell storms).
  lastNotifyMs: number = 0;
  // Rising-edge guard for the error transition so a backoff retry storm does not
  // re-fire the struggle keyframe on every identical status callback.
  hadError: boolean = false;
  // A background tab that rang while unfocused; lifts its title + steadies its
  // glow until activated (M05). Cleared on activateSession.
  unread: boolean = false;
  // True while this session holds one unit of the process-global background
  // keep-alive ref count (KeepAliveManager). Driven purely by the connection
  // edge so each session contributes at most one unit no matter how many
  // identical status callbacks fire; released on close / hand-off / teardown.
  keepAliveHeld: boolean = false;

  readonly surfaceSeq: number = ++nextGlobalSurfaceSeq;

  constructor() {
    this.controller = new GuardedTerminalController();
    this.driver = new FusionTerminalDriver();
    this.agentDriver = new FusionAgentDriver();
  }

  // Bind (or rebind, on every connect) the upload identity to the endpoint
  // this session is connecting to. Called from the page's connect paths only.
  bindUploadProfile(host: string, port: number, user: string, password: string): void {
    this.uploadHost = host;
    this.uploadPort = port > 0 ? port : 22;
    this.uploadUser = user;
    this.uploadPassword = password;
  }

  clearUploadProfile(): void {
    this.uploadHost = '';
    this.uploadPort = 22;
    this.uploadUser = '';
    this.uploadPassword = '';
  }
}
