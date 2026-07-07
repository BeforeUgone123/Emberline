import { TerminalController } from 'libghostty-ohos';
import { FusionTerminalDriver } from '../drivers/FusionTerminalDriver';
import { FusionAgentDriver } from '../drivers/FusionAgentDriver';

// One in-app terminal tab: its renderer controller, transports, and status.
// @Observed so tab chips (@ObjectLink) re-render on title/connection changes.
// Process-global surface numbering: session ids restart at 1 in every window
// instance (multiton shares one VM), but native indexes hosts by surfaceId
// process-wide -- per-window numbering cross-wired two windows' terminals
// (crash-family audit 2026-07-05; also tear-off groundwork).
//
// Extracted from Index.ets so both the page and the process-global
// SessionRegistry (tab drag-out / merge) share one handle definition.
let nextGlobalSurfaceSeq: number = 0;

@Observed
export class TerminalSessionHandle {
  readonly id: number;
  readonly controller: TerminalController;
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
  // User overrides from the tab editor (right-click a tab): a custom title
  // that beats OSC/cwd auto-naming, and a personal filament color.
  customName: string = '';
  filamentColor: string = '';
  // Image-paste path perspective: 'auto' follows the transport type; the
  // others override it for nested sessions (e.g. ssh typed inside a local
  // shell) where the app cannot know which machine the prompt lives on.
  pasteMode: string = 'auto';
  // pasteMode 'relay': the agent scp-relays the staged image to this tailnet
  // host (host or user@host) so a shell ssh'd into that machine can read it.
  relayTarget: string = '';
  relayDir: string = '/tmp/emberline-paste';
  // Rate limit for task-finished system notifications (bell storms).
  lastNotifyMs: number = 0;
  // Filament life-signs epochs (§2): each status edge bumps one counter and the
  // tab chip replays the matching keyframe. Monotonic so the chip can diff its
  // last-seen value and never miss/replay a beat.
  igniteEpoch: number = 0;      // connect established -> "ignite" flash+settle
  extinguishEpoch: number = 0;  // clean disconnect  -> "extinguish" hold+cool
  sparkFailEpoch: number = 0;   // connect failed    -> "struggle" glow-less stutter
  attentionEpoch: number = 0;   // background bell    -> "re-kindle" double-surge (M05)
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

  constructor(id: number) {
    this.id = id;
    this.controller = new TerminalController();
    this.driver = new FusionTerminalDriver();
    this.agentDriver = new FusionAgentDriver();
  }
}
