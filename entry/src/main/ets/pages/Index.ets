import { common, Want } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { fileIo as fs, fileShare, fileUri, picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { unifiedDataChannel, uniformTypeDescriptor } from '@kit.ArkData';
import { DEFAULT_TERMINAL_CONFIG, TerminalSurface } from 'libghostty-ohos';
import { buildAnsi256ColorDemo } from '../demo/Ansi256ColorDemo';
import {
  DEFAULT_FUSION_AGENT_HOST,
  DEFAULT_FUSION_AGENT_PATH,
  DEFAULT_FUSION_AGENT_PORT,
  DEFAULT_FUSION_AGENT_TOKEN,
  DEFAULT_FUSION_ENGINE_VM_LABEL
} from '../drivers/FusionAgentProtocol';
import { FusionTerminalDriver } from '../drivers/FusionTerminalDriver';
import { createFusionVmProfile } from '../models/ConnectionProfile';
import { TerminalSessionHandle } from '../model/TerminalSession';
import { sessionRegistry } from '../model/SessionRegistry';
import { AppearanceSettings, AppearanceStore, DEFAULT_APPEARANCE } from '../settings/AppearanceStore';
import { ConnectionSettings, ConnectionStore } from '../settings/ConnectionStore';
import {
  CURVE_ACCEL,
  CURVE_DECEL,
  CURVE_SHARP,
  CURVE_SINE,
  DUR_AMBIENT,
  DUR_BREATHE_HALF,
  DUR_EXTINGUISH_COOL,
  DUR_EXTINGUISH_HOLD,
  DUR_FAST,
  DUR_IGNITE_FLASH,
  DUR_IGNITE_SETTLE,
  DUR_STANDARD,
  FRAME_60,
  SPRING_SETTLE
} from '../theme/EmberMotion';
import { hapticBoundary, hapticDisconnect, hapticIgnite } from '../common/EmberHaptics';
import { keepAlive } from '../common/KeepAliveManager';

// Chrome palette tuned to match the desktop Ghostty profile
// (near-black background, Catppuccin Mocha foreground tones).
const COLOR_APP_BG: string = '#050507';
const COLOR_BAR_BG: string = '#0C0F14';
const COLOR_BAR_BORDER: string = '#1B222E';
const COLOR_TEXT_PRIMARY: string = '#CDD6F4';
const COLOR_TEXT_SECONDARY: string = '#8B95A7';
const COLOR_ACCENT: string = '#1E6FFF';
const COLOR_KEY_BG: string = '#161B24';
const COLOR_KEY_TEXT: string = '#C4CEE0';
const COLOR_PANEL_BG: string = '#10141B';
const COLOR_PANEL_BORDER: string = '#273042';
const COLOR_FIELD_BG: string = '#171D28';
const COLOR_STATUS_ON: string = '#A6E3A1';
const COLOR_STATUS_OFF: string = '#6C7086';
const MIN_TERMINAL_FONT_SIZE: number = 10;
const MAX_TERMINAL_FONT_SIZE: number = 26;
const MIN_BACKGROUND_OPACITY_PCT: number = 0;
const MAX_BACKGROUND_BLUR: number = 60;
const FOREGROUND_FOCUS_EVENT: string = 'fusionTermForeground';
const BACKGROUND_EVENT: string = 'fusionTermBackground';
// The tab strip doubles as the custom window chrome: EntryAbility hides the
// system decor bar and reserves its height, so the strip must match it and
// keep the top-right corner free for the floating system window buttons.
const WINDOW_CHROME_HEIGHT: number = 48;
const WINDOW_DECOR_BUTTON_RESERVE: number = 148;
// Design tokens: near-black chrome layers plus a single accent. The accent
// (ember copper) only ever appears as thin "filaments" and the primary
// action button - never as a large fill; color belongs to the terminal.
const COLOR_EMBER: string = '#D08F53';
const COLOR_EMBER_GLOW: string = '#59D08F53';
// Filament life-signs accents: the ignite over-bright bloom (a whiter gold that
// overshoots working brightness for ~90ms) and the extinguish transition orange
// the filament passes through on its way from ember to ash as it cools.
const COLOR_EMBER_BLOOM: string = '#F1C79A';
const COLOR_EMBER_COOL: string = '#C56B3A';
const COLOR_ASH: string = '#3A424E';
const COLOR_PANEL_2: string = '#111722';
// Faint helper text (ghostty config keys, hints): kept muted but lifted to a
// >= 4.5:1 contrast ratio against the near-black panels so it stays legible.
const COLOR_TEXT_FAINT: string = '#8A94A6';
const DRAWER_WIDTH: number = 400;
// Choreography-specific durations (ms) that are deliberately NOT part of the
// shared EmberMotion token set: these are the asymmetric micro-timings the spec
// calls out per moment, distinct from the folded 200/240 -> DUR_STANDARD family.
const DUR_PANE_OUT: number = 100;    // M10 drawer pane crossfade: fade current pane out (CURVE_ACCEL)
const DUR_PANE_IN: number = 140;     // M10 drawer pane crossfade: fade next pane in (CURVE_DECEL)
const DUR_EDITOR_EXIT: number = 150; // M18 tab-editor exit: shortened opacity-only leave (CURVE_ACCEL)
const DUR_READOUT_TICK_HALF: number = 60; // M26 font readout: half of the 120ms up-and-back tick
// M16 animated scroll-to-end: a value larger than any realistic tab-strip width;
// the Scroller clamps a past-the-end xOffset back to the true content edge, so
// this animates from the current offset to the end rather than a fixed target.
const TAB_STRIP_END_OFFSET_VP: number = 100000;
// Per-tab filament colors the user can pick in the tab editor; the first is
// the default ember.
const FILAMENT_PALETTE: string[] = [
  '#D08F53', '#7FB4E8', '#9A8FE8', '#7FC98F', '#E8899A', '#E8C97F', '#7FD8D0', '#B0B8C8'
];
// Bundled terminal font families registered by the renderer; the custom slot
// is filled by a user-imported ttf/otf.
const FONT_FAMILY_MAPLE: string = 'FusionTerm Maple Mono';
const FONT_FAMILY_JETBRAINS: string = 'FusionTerm JetBrains Mono';
const FONT_FAMILY_CASCADIA: string = 'FusionTerm Cascadia Mono';
const FONT_FAMILY_SARASA: string = 'FusionTerm Sarasa Fixed SC';
const FONT_FAMILY_SYSTEM: string = 'PingFang SC';
const FONT_FAMILY_CUSTOM: string = 'FusionTerm Custom';
// Approximate per-chip horizontal advance (chip body ~150vp + 4vp gap) used to
// turn a drop's window-x into a tab insert index. Chips actually hug their
// title width, so this is a deliberate approximation; the strip scroll offset
// is also ignored (few tabs, rarely scrolled). See computeDropInsertIndex.
const TAB_CHIP_ADVANCE_VP: number = 154;
const TAB_STRIP_LEFT_INSET_VP: number = 12;
// The UDMF plain-text record dragged with a tab carries only the hand-off token
// string; the live controller/driver/agent handle is claimed from the process-
// global SessionRegistry (same-VM shared heap), never serialized into UDMF.
const HANDOFF_TOKEN_KEY: string = 'emberHandoffToken';

interface ThemePreview {
  bg: string;
  fg: string;
  ansi: string[];
}

// A desktop-terminal style tab. Connection state is a 2px "filament" along
// the bottom edge instead of a status dot: lit copper = connected, dim =
// reconnecting, ash = dead. Width hugs the title. Double-tap opens the tab
// editor (rename + filament color).
@Component
struct TerminalTabChip {
  // Deep-observed so any session field change re-renders the chip; the @Watch
  // fires the life-signs keyframes. @Prop cannot be used for the epochs because
  // ArkUI does not re-sync a @Prop from a nested @Observed member without a
  // parent re-render, so the chip diffs the observed epochs itself instead.
  @ObjectLink @Watch('onSessionSignal') session: TerminalSessionHandle;
  @Prop active: boolean;
  onSelect: () => void = () => {};
  onClose: () => void = () => {};
  onEdit: () => void = () => {};
  // Tab drag-out wiring back to the page: split into a new window (context menu),
  // and the two drag-lifecycle callbacks. onDragStart is handled locally (the chip
  // owns its title/preview + the shared SessionRegistry), but the drag MOVE (grab
  // coordinates for the tear-off window position) and END (reorder / merge / tear-
  // off decision) belong to the page that owns the session list and the context.
  onHandoffEnd: (token: string, result: number) => void = () => {};

  // Base filament opacity. 1.0 when connected/dead; the breathing loop drives it
  // inside the 0.34-0.6 half-lit band while pending (§2.2). Bound after the
  // base layer's .animation() so only the explicit animateTo drives it.
  @State private breatheOpacity: number = 1;
  private breathing: boolean = false;
  // Bloom overlay: an independent 2px layer that plays the ignite flash, the
  // extinguish cool-down and the M05 double-surge without ever touching the base
  // filament or the terminal XComponent (§2.1). Idle at opacity 0.
  @State private bloomOpacity: number = 0;
  @State private bloomGlow: number = 4;
  @State private bloomColor: string = COLOR_EMBER_BLOOM;
  // Last-seen epoch snapshot for edge detection across session re-renders.
  private lastIgnite: number = 0;
  private lastExtinguish: number = 0;
  private lastSparkFail: number = 0;
  private lastAttention: number = 0;
  private lastPending: boolean = false;
  // The hand-off token minted in onDragStart; onDragEnd hands it back to the page
  // so the page can tell reorder / cross-window-merge / tear-off / cancel apart.
  private handoffToken: string = '';

  private filament(): string {
    if (this.session.connected || this.isPending()) {
      return this.session.filamentColor.length > 0 ? this.session.filamentColor : COLOR_EMBER;
    }
    return COLOR_ASH;
  }

  // Half-lit filament while a first connect or a reconnect is in flight, so
  // "connecting" is visually distinct from "dead" (which stays ash).
  private isPending(): boolean {
    return !this.session.connected &&
      (this.session.statusLabel.includes('重连') || this.session.statusLabel.includes('正在连接'));
  }

  // Unread lifts an inactive tab's title to the primary text color so a
  // finished background task reads at a glance (M05).
  private titleColor(): string {
    if (this.active || this.session.unread) {
      return COLOR_TEXT_PRIMARY;
    }
    return COLOR_TEXT_SECONDARY;
  }

  // Steady-state base glow radius: unread steadies at 6, a live connection at 4,
  // a dead/pending filament carries none (its own layers add heat).
  private baseGlowRadius(): number {
    if (this.session.unread) {
      return 6;
    }
    if (this.session.connected) {
      return 4;
    }
    return 0;
  }

  // Single reactive entry point: diff the observed epochs and the pending level
  // to drive the life-signs. Runs on every session field change (title/cwd/...),
  // so it stays cheap — five integer/bool compares and no allocation.
  private onSessionSignal(): void {
    if (this.session.igniteEpoch !== this.lastIgnite) {
      this.lastIgnite = this.session.igniteEpoch;
      this.playIgnite();
    }
    if (this.session.extinguishEpoch !== this.lastExtinguish) {
      this.lastExtinguish = this.session.extinguishEpoch;
      this.playExtinguish();
    }
    if (this.session.sparkFailEpoch !== this.lastSparkFail) {
      this.lastSparkFail = this.session.sparkFailEpoch;
      this.playSparkFail();
    }
    if (this.session.attentionEpoch !== this.lastAttention) {
      this.lastAttention = this.session.attentionEpoch;
      this.playAttention();
    }
    const pendingNow: boolean = this.isPending();
    if (pendingNow !== this.lastPending) {
      this.lastPending = pendingNow;
      if (pendingNow) {
        this.startBreathing();
      } else {
        this.stopBreathing();
      }
    }
  }

  // M01 点燃:bloom 猛闪超过工作亮度(90ms CURVE_SHARP)再弹簧回落(300ms
  // SPRING_SETTLE,唯一允许极小 overshoot),base 层同帧独立 ash->ember 补间。
  private playIgnite(): void {
    if (this.session.igniteEpoch <= 0) {
      return;
    }
    this.stopBreathing();
    this.bloomColor = COLOR_EMBER_BLOOM;
    hapticIgnite();
    this.getUIContext().keyframeAnimateTo({ iterations: 1 }, [
      {
        duration: DUR_IGNITE_FLASH,
        curve: CURVE_SHARP,
        event: () => {
          this.bloomOpacity = 0.85;
          this.bloomGlow = 11;
        }
      },
      {
        duration: DUR_IGNITE_SETTLE,
        curve: SPRING_SETTLE,
        event: () => {
          this.bloomOpacity = 0;
          this.bloomGlow = 4;
        }
      }
    ]);
  }

  // M03 熄灭:非对称。先 120ms hold 住余温(过渡橙 #C56B3A、无辉光),再 700ms
  // 慢慢冷透到 0;base 层已在 DUR_STANDARD 内 crossfade 到 ash,合成读作「刚刚
  // 还活着、现在慢慢凉了」。
  private playExtinguish(): void {
    if (this.session.extinguishEpoch <= 0) {
      return;
    }
    this.stopBreathing();
    this.bloomColor = COLOR_EMBER_COOL;
    this.bloomGlow = 0;
    hapticDisconnect();
    this.getUIContext().keyframeAnimateTo({ iterations: 1 }, [
      {
        duration: DUR_EXTINGUISH_HOLD,
        curve: Curve.Friction,
        event: () => {
          this.bloomOpacity = 0.7;
        }
      },
      {
        duration: DUR_EXTINGUISH_COOL,
        curve: CURVE_SINE,
        event: () => {
          this.bloomOpacity = 0;
        }
      }
    ]);
  }

  // M04 失败挣扎:打火机点不着。2-3 下无辉光顿挫闪烁(glow 全程 0)后落灰,与
  // 呼吸的「平滑+有辉光+循环」刻意拉开,不看文字也能分「在连」与「连不上」。
  private playSparkFail(): void {
    if (this.session.sparkFailEpoch <= 0) {
      return;
    }
    this.stopBreathing();
    this.bloomColor = COLOR_EMBER;
    this.bloomGlow = 0;
    this.getUIContext().keyframeAnimateTo({ iterations: 1 }, [
      { duration: 90, curve: Curve.EaseIn, event: () => { this.bloomOpacity = 0.5; } },
      { duration: 90, curve: Curve.EaseIn, event: () => { this.bloomOpacity = 0.1; } },
      { duration: 90, curve: Curve.EaseIn, event: () => { this.bloomOpacity = 0.45; } },
      { duration: 90, curve: Curve.EaseIn, event: () => { this.bloomOpacity = 0.08; } },
      { duration: 120, curve: Curve.EaseIn, event: () => { this.bloomOpacity = 0; } }
    ]);
  }

  // M05 复燃:后台标签任务完成。已连接标签用「亮度双涌」涌两下即停(非循环),
  // glow 稳定 6;未读的持续抬升由 titleColor()/baseGlowRadius() 承担。
  private playAttention(): void {
    if (this.session.attentionEpoch <= 0) {
      return;
    }
    this.bloomColor = this.session.filamentColor.length > 0 ? this.session.filamentColor : COLOR_EMBER;
    this.bloomGlow = 6;
    this.getUIContext().keyframeAnimateTo({ iterations: 1 }, [
      { duration: 350, curve: Curve.EaseInOut, event: () => { this.bloomOpacity = 0.9; } },
      { duration: 350, curve: Curve.EaseInOut, event: () => { this.bloomOpacity = 0.25; } },
      { duration: 350, curve: Curve.EaseInOut, event: () => { this.bloomOpacity = 0.9; } },
      { duration: 350, curve: Curve.EaseInOut, event: () => { this.bloomOpacity = 0; } }
    ]);
  }

  // M02 呼吸:半亮带极缓正弦循环,严格门控。锁死在 0.34<->0.6(永不到 1.0、永
  // 不熄到 ash),整周期 2.6s,FRAME_60 省电,声明式属性动画走合成线程。
  private startBreathing(): void {
    if (this.breathing) {
      return;
    }
    this.breathing = true;
    // Establish the top of the band before the alternating loop so it oscillates
    // 0.6<->0.34 and never reaches the connected 1.0.
    this.breatheOpacity = 0.6;
    this.getUIContext().animateTo(
      {
        duration: DUR_BREATHE_HALF,
        curve: CURVE_SINE,
        iterations: -1,
        playMode: PlayMode.Alternate,
        expectedFrameRateRange: FRAME_60
      },
      () => {
        this.breatheOpacity = 0.34;
      });
  }

  // Leaving pending (success/fail/disconnect) — a single settle animateTo that
  // implicitly cancels the infinite loop before the epoch keyframe takes over.
  private stopBreathing(): void {
    if (!this.breathing) {
      return;
    }
    this.breathing = false;
    this.getUIContext().animateTo(
      { duration: DUR_STANDARD, curve: CURVE_DECEL },
      () => {
        this.breatheOpacity = 1;
      });
  }

  aboutToDisappear(): void {
    // Never leave a filament breathing after the chip is gone.
    this.breathing = false;
  }

  build() {
    Column() {
      Row({ space: 6 }) {
        Text(this.session.title)
          .fontSize(12.5)
          .fontColor(this.titleColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .flexShrink(1)
          // Hard cap: the chip sizes to content, so the Row has no fixed
          // width and flexShrink never engages -- a long title would push
          // the close button past maxWidth(210) and clip it. 210 - chip
          // padding(18) - close button w/ margins(18) = 174, minus slack.
          .constraintSize({ maxWidth: 170 })
        Image($r('app.media.ic_close_faint'))
          .width(12)
          .height(12)
          .margin({ left: 4, right: 2 })
          // Keep the 12vp glyph but expand the touch target to 26x26 so the
          // close affordance is comfortably tappable on a phone.
          .responseRegion({ x: -7, y: -7, width: 26, height: 26 })
          .onClick(() => {
            this.onClose();
          })
      }
      .layoutWeight(1)

      // Two-layer filament: base carries the steady lit/half-lit/ash state and
      // its glow; the bloom overlay plays the transient life-signs on top.
      Stack() {
        Row()
          .height(2)
          .width('100%')
          .borderRadius(1)
          .backgroundColor(this.filament())
          .shadow(this.baseGlowRadius() > 0
            ? { radius: this.baseGlowRadius(), color: COLOR_EMBER_GLOW, offsetX: 0, offsetY: 0 }
            : { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 })
          // Fade the filament color / glow between lit / ash instead of a hard
          // cut as the connection state changes (§2.1 base layer).
          .animation({ duration: DUR_STANDARD, curve: CURVE_DECEL })
          // Opacity sits after .animation() so only the explicit breathing /
          // settle animateTo drives it — no implicit double-animation.
          .opacity(this.breatheOpacity)

        Row()
          .height(2)
          .width('100%')
          .borderRadius(1)
          .backgroundColor(this.bloomColor)
          .shadow({ radius: this.bloomGlow, color: COLOR_EMBER_GLOW, offsetX: 0, offsetY: 0 })
          .opacity(this.bloomOpacity)
          .hitTestBehavior(HitTestMode.None)
      }
      .height(2)
      .width('100%')
    }
    .height(34)
    .constraintSize({ minWidth: 64, maxWidth: 210 })
    .padding({ left: 12, right: 6, top: 6 })
    .borderRadius(8)
    .backgroundColor(this.active ? '#151A22' : '#00000000')
    .border({
      width: 1,
      color: this.active ? COLOR_BAR_BORDER : '#00000000'
    })
    // M07/M08 chrome hand-off: fade the active face + border rather than a hard
    // cut. Fast (120) so the face settles a beat before the filament brightens.
    .animation({ duration: DUR_FAST, curve: CURVE_SHARP })
    .clip(true)
    .focusable(false)
    .onClick(() => {
      this.onSelect();
    })
    .parallelGesture(TapGesture({ count: 2 }).onAction(() => {
      this.onEdit();
    }))
    // M15 asymmetric add/remove: a new chip fades + slides in from the right
    // (opacity + translateX, no scale so the CJK title never rasterizes);
    // closing is quicker and plainer so remaining tabs settle without fuss.
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.OPACITY
        .combine(TransitionEffect.translate({ x: 12 }))
        .animation({ duration: DUR_STANDARD, curve: CURVE_DECEL }),
      TransitionEffect.OPACITY
        .animation({ duration: DUR_FAST, curve: CURVE_ACCEL })
    ))
    // Tab drag-out: one system drag pipeline serves reorder, cross-window merge
    // and tear-off. On drag start we mint a token, park the LIVE session handle in
    // the process-global registry (the tab stays visible in place -- the actual
    // hand-off happens at drop/end), and carry ONLY the token in the UDMF payload.
    // draggable(true) is required: a Column is not draggable by default.
    .draggable(true)
    .onDragStart((event: DragEvent): DragItemInfo => {
      const token: string = sessionRegistry.generateToken();
      // Harmless expiry: the tab is still in its origin window's list, so if the
      // drag somehow never ends within the timeout there is nothing to roll back.
      sessionRegistry.park(token, this.session, (_handle: TerminalSessionHandle): void => {});
      this.handoffToken = token;
      const record: unifiedDataChannel.PlainText = new unifiedDataChannel.PlainText();
      record.textContent = token;
      event.setData(new unifiedDataChannel.UnifiedData(record));
      const preview: DragItemInfo = { builder: (): void => { this.buildDragPreview(); } };
      return preview;
    })
    .onDragEnd((event: DragEvent): void => {
      this.onHandoffEnd(this.handoffToken, event.getResult());
    })
  }

  // 160x34 dark rounded pill with the tab title over a 2px filament-color base,
  // so the dragged tab reads at a glance and matches the chip's own ember chrome.
  @Builder
  private buildDragPreview() {
    Column() {
      Row() {
        Text(this.session.title)
          .fontSize(12.5)
          .fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 140 })
      }
      .layoutWeight(1)
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row()
        .height(2)
        .width('100%')
        .borderRadius(1)
        .backgroundColor(this.session.filamentColor.length > 0 ? this.session.filamentColor : COLOR_EMBER)
        .shadow({ radius: 4, color: COLOR_EMBER_GLOW, offsetX: 0, offsetY: 0 })
    }
    .width(160)
    .height(34)
    .padding({ left: 12, right: 12, top: 6 })
    .borderRadius(8)
    .backgroundColor('#151A22')
    .border({ width: 1, color: COLOR_BAR_BORDER })
    .clip(true)
  }

}

@Entry
@Component
struct Index {
  @State private sessions: TerminalSessionHandle[] = [];
  @State private activeSessionId: number = 0;
  private nextSessionId: number = 1;
  // Drives the horizontal tab strip so a newly added tab can be scrolled into
  // view past the right edge.
  private tabScroller: Scroller = new Scroller();
  private context: common.UIAbilityContext | null = null;
  // Tab drag bookkeeping. handledHandoffTokens records tokens whose drop THIS
  // window's own tab strip already consumed (a reorder), so the source chip's
  // onDragEnd knows to leave the handle alone. (Cross-window merge and
  // tear-off are currently disabled; the handoff plumbing stays for later.)
  private handledHandoffTokens: Set<string> = new Set<string>();
  @State private drawerOpen: boolean = false;
  @State private drawerPane: string = 'appearance';
  @State private tabEditOpen: boolean = false;
  @State private tabEditDraft: string = '';
  @State private editingFilament: string = '';
  @State private editingPasteMode: string = 'auto';
  private editingSession: TerminalSessionHandle | null = null;
  @State private themePreviews: Map<string, ThemePreview> = new Map();
  private themePreviewsLoading: boolean = false;
  @State private draftHost: string = DEFAULT_FUSION_AGENT_HOST;
  @State private draftPort: string = String(DEFAULT_FUSION_AGENT_PORT);
  @State private draftAgentToken: string = DEFAULT_FUSION_AGENT_TOKEN;
  @State private draftSshPort: string = '22';
  @State private draftUser: string = 'user';
  @State private draftPassword: string = '';
  @State private fontSize: number = 13;
  @State private fontFamily: string = DEFAULT_APPEARANCE.fontFamily;
  @State private themeName: string = 'Catppuccin_Mocha';
  @State private themeFilter: string = '';
  @State private themeList: string[] = [];
  @State private cursorStyle: number = DEFAULT_APPEARANCE.cursorStyle;
  @State private cursorBlink: boolean = DEFAULT_APPEARANCE.cursorBlink;
  @State private accessoryVisible: boolean = false;
  @State private customFontPath: string = '';
  @State private backgroundImagePath: string = '';
  @State private backgroundOpacity: number = DEFAULT_APPEARANCE.backgroundOpacity;
  @State private backgroundBlur: number = DEFAULT_APPEARANCE.backgroundBlur;
  @State private pasteDirUri: string = DEFAULT_APPEARANCE.pasteDirUri;
  @State private foregroundFocusEpoch: number = 0;
  // Connection-pane 22x2 filament breathing (M09): reuses the §2.2 half-lit
  // loop while the active session is connecting, strictly gated so the infinite
  // animateTo only runs while the conn pane is actually on screen.
  @State private connBreatheOpacity: number = 1;
  private connBreathing: boolean = false;
  // M10 drawer pane crossfade: the shared content container binds its opacity and
  // a small right-slide to this scalar (1 = settled, 0 = fully faded/offset). A
  // pane switch drives it out then in around the actual `drawerPane` swap.
  @State private paneT: number = 1;
  // M26 font-size readout feedback: a one-shot vertical tick + ember color flash
  // on the readout Text only (the terminal reflow itself stays an instant cut).
  @State private fontReadoutTickY: number = 0;
  @State private fontReadoutColor: string = COLOR_TEXT_PRIMARY;
  private connectionSettingsLoaded: boolean = false;
  private appearanceStore: AppearanceStore = new AppearanceStore();
  private connectionStore: ConnectionStore = new ConnectionStore();
  private demoRendered: boolean = false;
  private notifyPermissionRequested: boolean = false;
  private appInBackground: boolean = false;
  private foregroundFocusListener: () => void = (): void => {
    this.appInBackground = false;
    this.foregroundFocusEpoch += 1;
  };
  private backgroundListener: () => void = (): void => {
    this.appInBackground = true;
  };

  aboutToAppear(): void {
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.context.eventHub.on(FOREGROUND_FOCUS_EVENT, this.foregroundFocusListener);
    this.context.eventHub.on(BACKGROUND_EVENT, this.backgroundListener);
    // A tab dragged out of another window arrives via a hand-off token parked in
    // the process-global SessionRegistry; adopt that live session instead of
    // spawning a blank tab. Fall back to a fresh tab on an ordinary launch.
    if (!this.tryAdoptHandoffSession()) {
      this.addSession();
    }
    void this.loadAppearance();
  }

  aboutToDisappear(): void {
    this.context?.eventHub.off(FOREGROUND_FOCUS_EVENT, this.foregroundFocusListener);
    this.context?.eventHub.off(BACKGROUND_EVENT, this.backgroundListener);
    for (const session of this.sessions) {
      // Window teardown: release any held keep-alive unit so a closed window
      // never leaks the process-global background-running ref count.
      this.releaseSessionKeepAlive(session);
      session.controller.setAttachmentListener(null);
      session.agentDriver.detach();
      session.driver.detach();
    }
  }

  private activeSession(): TerminalSessionHandle {
    for (const session of this.sessions) {
      if (session.id === this.activeSessionId) {
        return session;
      }
    }
    return this.sessions[0];
  }

  // Bind this window's Index-level renderer/transport listeners to a session's
  // controller and drivers. Shared by addSession (a fresh tab) and adoptSession
  // (a tab torn off another window) so a rebound session gets the exact same
  // title / notification / status / attachment wiring, closured over THIS
  // window's Index instance. Idempotent: each set*Listener replaces the prior.
  private wireSessionListeners(session: TerminalSessionHandle): void {
    session.controller.setTitleListener((title: string) => {
      session.oscTitle = title;
      session.title = this.composeTabTitle(session, session.lastCwd);
    });
    session.controller.setNotificationListener((text: string) => {
      this.handleTerminalNotification(session, text);
    });
    session.driver.setStatusListener((status) => {
      const wasConnected: boolean = session.connected;
      const hadError: boolean = session.hadError;
      const errText: string = status.error || '';
      session.connected = status.connected;
      session.statusMode = status.mode || 'local';
      session.statusLabel = this.formatStatusLabel(status.label, status.error);
      session.hadError = errText.length > 0;
      session.title = this.composeTabTitle(session, '');
      this.applyFilamentTransition(session, wasConnected, hadError, session.hadError);
      this.syncConnPaneBreathing();
      this.syncSessionKeepAlive(session, wasConnected);
    });
    session.agentDriver.setStatusListener((status) => {
      const wasConnected: boolean = session.connected;
      const hadError: boolean = session.hadError;
      const errText: string = status.error || '';
      session.connected = status.connected;
      session.statusMode = status.mode || 'agent';
      session.statusLabel = this.formatStatusLabel(status.label, status.error);
      session.lastCwd = status.cwd || '';
      session.hadError = errText.length > 0;
      session.title = this.composeTabTitle(session, session.lastCwd);
      this.applyFilamentTransition(session, wasConnected, hadError, session.hadError);
      this.syncConnPaneBreathing();
      this.syncSessionKeepAlive(session, wasConnected);
    });
    session.controller.setAttachmentListener((attached: boolean) => {
      session.attached = attached;
      if (attached) {
        this.applyCustomFontTo(session);
        if (!this.tryAutoConnectSession(session)) {
          this.showStartupDemo(session);
        }
      }
    });
  }

  private addSession(refocus: boolean = false): void {
    const session = new TerminalSessionHandle(this.nextSessionId);
    this.nextSessionId += 1;
    session.controller.setConfig({
      fontSize: this.fontSize,
      fontFamily: this.fontFamily,
      scrollbackLines: 50000,
      bgColor: DEFAULT_TERMINAL_CONFIG.bgColor,
      fgColor: DEFAULT_TERMINAL_CONFIG.fgColor,
      cursorStyle: this.cursorStyle,
      cursorBlink: this.cursorBlink,
      bgOpacity: this.backgroundImagePath.length > 0 ? this.backgroundOpacity : 1
    });
    session.controller.setTheme(this.themeName);
    this.wireSessionListeners(session);
    this.sessions.push(session);
    this.activateSession(session.id, refocus);
    this.scrollTabStripToEnd();
  }

  // Claim a session parked by another window (tab drag-out hand-off) if the
  // launch Want carried a token. Returns true when a live session was adopted
  // so aboutToAppear can skip the default addSession(). Consumes the AppStorage
  // key either way so a stale token can never re-fire on a later cold launch.
  private tryAdoptHandoffSession(): boolean {
    const token = AppStorage.get<string>('emberHandoffToken');
    if (token === undefined || token.length === 0) {
      return false;
    }
    AppStorage.delete('emberHandoffToken');
    const handle = sessionRegistry.claim(token);
    if (handle === null) {
      return false;
    }
    this.adoptSession(handle);
    return true;
  }

  // Adopt a live handle handed off from another window. It already owns a
  // running controller / native driver / agent socket and a process-global
  // surfaceSeq, so we only re-wire it to THIS window's Index listeners and
  // rebind the drivers to this window's controller/context. Never attach/detach
  // (that would destroySession / drop the WebSocket) -- softDetach + rebind keep
  // the PTY and remote shell alive across the move.
  private adoptSession(handle: TerminalSessionHandle, insertIndex: number = -1): void {
    // Keep per-window tab numbering ahead of the adopted id so a later
    // addSession cannot mint a colliding id (ids are per-window; surfaceSeq is
    // process-global and stays unique on its own).
    if (handle.id >= this.nextSessionId) {
      this.nextSessionId = handle.id + 1;
    }
    // A drop that lands mid-strip inserts at that index; a hand-off token launch
    // (no drop target position) appends. Only append scrolls the strip to the end
    // so a mid-strip insert does not jump the view away from the drop point.
    const appended: boolean = insertIndex < 0 || insertIndex >= this.sessions.length;
    if (appended) {
      this.sessions.push(handle);
    } else {
      this.sessions.splice(Math.max(0, insertIndex), 0, handle);
    }
    this.wireSessionListeners(handle);
    if (this.context) {
      handle.driver.rebind(handle.controller, this.context);
    }
    handle.agentDriver.rebind(handle.controller);
    this.activateSession(handle.id, true);
    if (appended) {
      this.scrollTabStripToEnd();
    }
  }

  // Bring a freshly appended tab into view: the strip scrolls horizontally and
  // a new tab can land past the right edge. Deferred a frame so the tab has
  // been laid out before scrollEdge measures the content width.
  private scrollTabStripToEnd(): void {
    setTimeout(() => {
      try {
        // M16: a newly appended tab slides into view instead of snapping. A
        // past-the-end xOffset clamps to the true content edge, so this glides
        // from the current offset to the end over DUR_STANDARD / CURVE_DECEL.
        this.tabScroller.scrollTo({
          xOffset: TAB_STRIP_END_OFFSET_VP,
          yOffset: 0,
          animation: { duration: DUR_STANDARD, curve: CURVE_DECEL }
        });
      } catch (err) {
        console.error('Failed to scroll tab strip to end: ' + JSON.stringify(err));
      }
    }, 60);
  }

  private closeSession(id: number): void {
    const index = this.sessions.findIndex((session: TerminalSessionHandle) => session.id === id);
    if (index < 0) {
      return;
    }
    const session = this.sessions[index];
    session.controller.setTitleListener(null);
    session.controller.setNotificationListener(null);
    session.controller.setAttachmentListener(null);
    // Balance the process-global keep-alive ref count for a tab the user
    // explicitly closes before its transports are torn down.
    this.releaseSessionKeepAlive(session);
    // Closing a tab must stay passive on the agent side: detach only, never
    // terminate, so tmux/codex keep running on the remote.
    session.agentDriver.detach();
    session.driver.detach();
    this.sessions.splice(index, 1);
    if (this.sessions.length === 0) {
      this.addSession(true);
      return;
    }
    if (this.activeSessionId === id) {
      const fallback = this.sessions[Math.min(index, this.sessions.length - 1)];
      this.activateSession(fallback.id, true);
    }
  }

  // Remove a tab from THIS window so it can be re-adopted by another window,
  // WITHOUT the closeSession teardown. Deliberately NOT closeSession: no
  // detach() / destroySession() / socket close, so the native PTY and the agent
  // WebSocket keep running for the window that picks the session back up. The
  // drivers softDetach (listeners off, transports alive) and the Index-level
  // listeners are unhooked so the parked handle carries no stale closures.
  // Returns the removed handle (or null if the id was unknown) for the caller to
  // park in the SessionRegistry.
  private releaseSessionForHandoff(id: number): TerminalSessionHandle | null {
    const index = this.sessions.findIndex((session: TerminalSessionHandle) => session.id === id);
    if (index < 0) {
      return null;
    }
    const session = this.sessions[index];
    session.controller.setTitleListener(null);
    session.controller.setNotificationListener(null);
    session.controller.setAttachmentListener(null);
    session.driver.setStatusListener(null);
    session.agentDriver.setStatusListener(null);
    // This window stops driving the session, so drop its keep-alive unit; the
    // adopting window re-requests protection on the next live status edge.
    this.releaseSessionKeepAlive(session);
    // Passive hand-off: keep the native PTY and the agent socket alive so the
    // adopting window can rebind the exact same live session.
    session.driver.softDetach();
    session.agentDriver.softDetach();
    this.sessions.splice(index, 1);
    if (this.sessions.length === 0) {
      this.addSession(true);
    } else if (this.activeSessionId === id) {
      const fallback = this.sessions[Math.min(index, this.sessions.length - 1)];
      this.activateSession(fallback.id, true);
    }
    return session;
  }

  // Approximate the tab insert index from a drop's window-x. Chips hug their
  // title width and the strip can scroll, so this uses a fixed per-chip advance
  // and ignores the scroll offset -- a deliberate approximation (see notes).
  private computeDropInsertIndex(windowX: number): number {
    const raw: number = Math.round((windowX - TAB_STRIP_LEFT_INSET_VP) / TAB_CHIP_ADVANCE_VP);
    return Math.max(0, Math.min(raw, this.sessions.length));
  }

  // Move a tab already in THIS window to a new position (drop-to-reorder). Remove
  // then insert; a target to the right of the old slot shifts left by one once the
  // tab is pulled out. No transport churn -- the same controller stays live.
  private reorderSession(fromIndex: number, insertIndex: number): void {
    if (fromIndex < 0 || fromIndex >= this.sessions.length) {
      return;
    }
    const moved: TerminalSessionHandle = this.sessions[fromIndex];
    this.sessions.splice(fromIndex, 1);
    let dest: number = insertIndex > fromIndex ? insertIndex - 1 : insertIndex;
    dest = Math.max(0, Math.min(dest, this.sessions.length));
    this.sessions.splice(dest, 0, moved);
  }

  // Tab strip drop target: claim the parked handle, then either reorder it (it is
  // already ours) or merge it in from another window. A cross-window merge is
  // DEFERRED to a setTimeout(0) macrotask so the source window's onDragEnd releases
  // its copy first: the two windows share one process-global surfaceId per handle,
  // and mounting the same XComponent id in two windows at once is the crash-family
  // double-activation this ordering exists to prevent.
  private handleTabStripDrop(event: DragEvent): void {
    const token: string = this.readHandoffToken(event);
    if (token.length === 0) {
      return;
    }
    const handle: TerminalSessionHandle | null = sessionRegistry.claim(token);
    if (handle === null) {
      return;
    }
    const insertIndex: number = this.computeDropInsertIndex(event.getWindowX());
    const localIndex: number =
      this.sessions.findIndex((session: TerminalSessionHandle) => session.id === handle.id);
    if (localIndex >= 0) {
      // Reorder within this window. Mark the token so the origin chip's onDragEnd
      // (which fires right after, still SUCCESSFUL) knows we handled it in place
      // and must NOT release the handle.
      this.reorderSession(localIndex, insertIndex);
      this.activateSession(handle.id);
      this.handledHandoffTokens.add(token);
    } else {
      // Cross-window merge is currently disabled: hand the token straight
      // back so the source window's onDragEnd finds it parked and keeps the
      // tab in place (adopt/release plumbing stays for a future re-enable).
      sessionRegistry.park(token, handle, (): void => {});
    }
    event.setResult(DragResult.DRAG_SUCCESSFUL);
  }

  // Terminal-body drop target: a no-op that still reports success. This "eats"
  // any drop that lands inside the app (on the terminal instead of the strip) so
  // it counts as a cancel; only a drop OUTSIDE every window stays DRAG_FAILED and
  // becomes a tear-off, keeping the tear-off trigger crisp.
  private handleTerminalBodyDrop(event: DragEvent): void {
    event.setResult(DragResult.DRAG_SUCCESSFUL);
  }

  private readHandoffToken(event: DragEvent): string {
    try {
      const records: Array<unifiedDataChannel.UnifiedRecord> = event.getData().getRecords();
      if (records.length === 0) {
        return '';
      }
      const text: string | undefined = (records[0] as unifiedDataChannel.PlainText).textContent;
      return text ?? '';
    } catch (err) {
      console.error('Failed to read hand-off token from drag data: ' + JSON.stringify(err));
      return '';
    }
  }

  // Source-chip drag end. On SUCCESSFUL: distinguish (a) our own reorder -- flagged
  // in handledHandoffTokens, nothing to do; (b) another window claimed the handle
  // -- registry.claim now returns null, so release our copy immediately, before the
  // adopting window's deferred adopt runs; (c) a cancel drop on some terminal body
  // -- the token is still parked, so claim() cleans it up and the tab stays put.
  // FAILED means the drop left every window: tear the tab off into its own window.
  private handleHandoffEnd(session: TerminalSessionHandle, token: string, result: number): void {
    if (result === DragResult.DRAG_SUCCESSFUL) {
      if (this.handledHandoffTokens.has(token)) {
        this.handledHandoffTokens.delete(token);
        return;
      }
      const stillParked: TerminalSessionHandle | null = sessionRegistry.claim(token);
      if (stillParked === null) {
        this.releaseSessionForHandoff(session.id);
      }
      return;
    }
    // FAILED / DRAG_CANCELED / anything else: tear-off is currently disabled,
    // so just clean up the park and keep the tab in place.
    sessionRegistry.claim(token);
  }

  private activateSession(id: number, refocus: boolean = false): void {
    this.activeSessionId = id;
    // Activating a tab clears its "task finished while backgrounded" mark (M05).
    for (const session of this.sessions) {
      if (session.id === id && session.unread) {
        session.unread = false;
      }
    }
    if (refocus) {
      this.focusActiveTerminalSoon();
    }
  }

  // Turn raw connection-status edges into the filament's life-signs epochs
  // (§2). Ignite on connect, extinguish on a clean disconnect, spark-fail only
  // on the rising edge of an error so a backoff retry storm never re-fires the
  // struggle keyframe on every identical callback.
  private applyFilamentTransition(session: TerminalSessionHandle,
                                  wasConnected: boolean, hadError: boolean, hasError: boolean): void {
    if (!wasConnected && session.connected) {
      session.igniteEpoch += 1;
    } else if (wasConnected && !session.connected) {
      session.extinguishEpoch += 1;
    } else if (!session.connected && hasError && !hadError) {
      session.sparkFailEpoch += 1;
    }
  }

  // Background keep-alive accounting, driven by the connection edge. A session
  // that just went live -- agent connected, SSH connected, or the native local
  // PTY started (the native driver reports a started PTY as connected, so this
  // one edge covers all three transports) -- requests one unit of process-global
  // background protection so backgrounding the app never freezes/drops the
  // session or swallows its task-finished notification. A session that dropped
  // releases it. keepAliveHeld makes each session contribute at most one unit no
  // matter how many identical status callbacks fire, and only flips true once a
  // note actually landed (so a missing context can never desync the ref count).
  private syncSessionKeepAlive(session: TerminalSessionHandle, wasConnected: boolean): void {
    if (!wasConnected && session.connected && !session.keepAliveHeld) {
      if (this.context) {
        session.keepAliveHeld = true;
        keepAlive.noteSessionActive(this.context);
      }
    } else if (wasConnected && !session.connected && session.keepAliveHeld) {
      session.keepAliveHeld = false;
      keepAlive.noteSessionInactive();
    }
  }

  // Release any held keep-alive unit for a session leaving this window (close,
  // hand-off, or window teardown) so the process-global ref count never leaks a
  // unit for a session this window no longer drives.
  private releaseSessionKeepAlive(session: TerminalSessionHandle): void {
    if (session.keepAliveHeld) {
      session.keepAliveHeld = false;
      keepAlive.noteSessionInactive();
    }
  }

  // Shared pending predicate (a first connect or a reconnect in flight) so the
  // conn pane and the tab chip read the exact same "connecting" truth.
  private isSessionPending(session: TerminalSessionHandle): boolean {
    return !session.connected &&
      (session.statusLabel.includes('重连') || session.statusLabel.includes('正在连接'));
  }

  private activeConnPending(): boolean {
    return this.sessions.length > 0 && this.isSessionPending(this.activeSession());
  }

  // M09: start/stop the conn-pane filament breathing. Gated on the pane being
  // visible AND the active session connecting; stopped on connect / fail /
  // disconnect / drawer close / pane switch so no loop survives off screen.
  private syncConnPaneBreathing(): void {
    const shouldBreathe: boolean =
      this.drawerOpen && this.drawerPane === 'conn' && this.activeConnPending();
    if (shouldBreathe && !this.connBreathing) {
      this.connBreathing = true;
      this.connBreatheOpacity = 0.6;
      this.getUIContext().animateTo(
        {
          duration: DUR_BREATHE_HALF,
          curve: CURVE_SINE,
          iterations: -1,
          playMode: PlayMode.Alternate,
          expectedFrameRateRange: FRAME_60
        },
        () => {
          this.connBreatheOpacity = 0.34;
        });
    } else if (!shouldBreathe && this.connBreathing) {
      this.connBreathing = false;
      this.getUIContext().animateTo(
        { duration: DUR_STANDARD, curve: CURVE_DECEL },
        () => {
          this.connBreatheOpacity = 1;
        });
    }
  }

  private terminalInputActive(): boolean {
    return this.sessions.length > 0 && !this.drawerOpen && !this.tabEditOpen;
  }

  private openDrawer(pane: string): void {
    this.drawerPane = pane;
    this.drawerOpen = true;
    // Opening the drawer reveals the target pane at full opacity: the drawer
    // slide itself carries the entrance, so reset the crossfade scalar in case a
    // prior in-drawer pane switch was interrupted mid-animation.
    this.paneT = 1;
    if (pane === 'theme') {
      this.prepareThemePane();
    }
    this.syncConnPaneBreathing();
  }

  // M10: crossfade the drawer's pane content on an in-drawer nav switch. Fade the
  // current pane out (100ms accelerate away), swap `drawerPane` at the trough,
  // then fade the next pane in (140ms decelerate to rest). Clicking the pane you
  // are already on is a no-op so the visible content never blinks.
  private switchDrawerPane(pane: string): void {
    if (this.drawerPane === pane) {
      return;
    }
    this.getUIContext().animateTo(
      {
        duration: DUR_PANE_OUT,
        curve: CURVE_ACCEL,
        onFinish: () => {
          this.drawerPane = pane;
          if (pane === 'theme') {
            this.prepareThemePane();
          }
          this.syncConnPaneBreathing();
          this.getUIContext().animateTo(
            { duration: DUR_PANE_IN, curve: CURVE_DECEL },
            () => {
              this.paneT = 1;
            });
        }
      },
      () => {
        this.paneT = 0;
      });
  }

  private closeDrawer(): void {
    this.drawerOpen = false;
    this.syncConnPaneBreathing();
    this.focusActiveTerminalSoon();
  }

  private openTabEditor(session: TerminalSessionHandle): void {
    this.editingSession = session;
    this.tabEditDraft = session.customName.length > 0 ? session.customName : session.title;
    this.editingFilament = session.filamentColor;
    this.editingPasteMode = session.pasteMode;
    this.tabEditOpen = true;
  }

  private commitTabEditor(): void {
    const session = this.editingSession;
    if (session) {
      session.customName = this.tabEditDraft.trim();
      session.title = this.composeTabTitle(session, session.lastCwd);
    }
    this.tabEditOpen = false;
    this.editingSession = null;
    this.focusActiveTerminalSoon();
  }

  private resetTabName(): void {
    const session = this.editingSession;
    if (session) {
      session.customName = '';
      session.title = this.composeTabTitle(session, session.lastCwd);
      this.tabEditDraft = session.title;
    }
  }

  private pickFilament(color: string): void {
    const session = this.editingSession;
    if (session) {
      session.filamentColor = color === COLOR_EMBER ? '' : color;
      this.editingFilament = session.filamentColor;
    }
  }

  // BEL / OSC 9 from a background tab means "task finished, look at me"
  // (claude code and codex both ring on completion). The visible tab shows
  // its own output, so it never notifies.
  private handleTerminalNotification(session: TerminalSessionHandle, text: string): void {
    // Notify unless the user is actually looking at this tab: a background
    // tab always qualifies, and the ACTIVE tab qualifies too while the whole
    // app is hidden (agent finished after the user switched away).
    if (session.id === this.activeSessionId && !this.appInBackground) {
      return;
    }
    const now = Date.now();
    if (now - session.lastNotifyMs < 5000) {
      return;
    }
    session.lastNotifyMs = now;
    // M05: the answer lives on the tab itself — mark it unread (title lifts,
    // glow steadies) and bump attentionEpoch so the chip plays the re-kindle
    // double-surge, on top of the system notification.
    session.attentionEpoch += 1;
    session.unread = true;
    void this.publishTerminalNotification(session, text);
  }

  private async publishTerminalNotification(session: TerminalSessionHandle, text: string): Promise<void> {
    try {
      const enabled = await notificationManager.isNotificationEnabled();
      if (!enabled) {
        if (this.notifyPermissionRequested || !this.context) {
          return;
        }
        this.notifyPermissionRequested = true;
        await notificationManager.requestEnableNotification(this.context);
      }
      const request: notificationManager.NotificationRequest = {
        id: session.id,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: session.title.length > 0 ? session.title : 'Emberline',
            text: text.length > 0 ? text : '任务完成,终端在等你'
          }
        }
      };
      await notificationManager.publish(request);
    } catch (err) {
      console.error('Failed to publish terminal notification: ' + JSON.stringify(err));
    }
  }

  private focusActiveTerminalSoon(): void {
    const sessionId = this.activeSessionId;
    this.requestTerminalFocusAt(sessionId, 80);
    // Retry once after the tab switch has fully rendered: the first attempt
    // can race the Visibility change of the freshly shown surface.
    this.requestTerminalFocusAt(sessionId, 260);
  }

  private requestTerminalFocusAt(sessionId: number, delayMs: number): void {
    setTimeout(() => {
      if (sessionId !== this.activeSessionId || !this.terminalInputActive()) {
        return;
      }
      const session = this.activeSession();
      try {
        focusControl.requestFocus(`fusionTermSurface-g${session.surfaceSeq}`);
      } catch (err) {
        console.error('Failed to restore terminal focus: ' + JSON.stringify(err));
      }
      session.controller.setImeActive(true);
    }, delayMs);
  }

  // Desktop-terminal tab title: cwd basename when connected, transport name
  // otherwise; unconnected fresh tabs read as a new tab, failures show the
  // status text so the tab itself is the status surface.
  private composeTabTitle(session: TerminalSessionHandle, cwd: string): string {
    if (session.customName.length > 0) {
      return session.customName;
    }
    if (session.connected && session.oscTitle.length > 0) {
      return session.oscTitle;
    }
    if (session.connected) {
      if (cwd.length > 0) {
        const base = this.fileDisplayName(cwd);
        return base.length > 0 ? base : cwd;
      }
      switch (session.statusMode) {
        case 'agent':
          return 'VM';
        case 'ssh':
          return 'SSH';
        case 'local':
          return '本地';
        default:
          return '终端';
      }
    }
    if (session.statusMode === 'demo') {
      return '新标签页';
    }
    return session.statusLabel.length > 0 ? session.statusLabel : '已断开';
  }

  build() {
    Stack() {
      if (this.backgroundImagePath.length > 0) {
        Image(`file://${this.backgroundImagePath}`)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .blur(this.backgroundBlur)
          // M25: ambient layer, so it eases rather than snaps when a wallpaper is
          // set or cleared.
          .transition(TransitionEffect.OPACITY.animation({ duration: DUR_AMBIENT, curve: CURVE_DECEL }))
      }

      Column() {
        this.buildTabBar();
        this.buildTerminalLayer();
        if (this.accessoryVisible) {
          this.buildAccessoryBar();
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.surfaceBackdropColor())

      this.buildDrawerScrim();
      this.buildDrawer();

      if (this.tabEditOpen) {
        this.buildTabEditScrim();
        this.buildTabEditor();
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLOR_APP_BG)
  }

  @Builder
  private buildTerminalLayer() {
    Stack() {
      ForEach(this.sessions, (session: TerminalSessionHandle) => {
        Stack() {
          TerminalSurface({
            controller: session.controller,
            surfaceId: `fusionTermSurface-g${session.surfaceSeq}`,
            searchInputId: `fusionTermSearch-g${session.surfaceSeq}`,
            surfaceColor: this.surfaceBackdropColor(),
            active: session.id === this.activeSessionId &&
              !this.drawerOpen &&
              !this.tabEditOpen,
            // Polling / scrollbar follow raw tab visibility: a translucent
            // drawer must not throttle the terminal still showing behind it.
            visible: session.id === this.activeSessionId,
            foregroundFocusEpoch: this.foregroundFocusEpoch,
            onImagePasted: (localPath: string): void => {
              this.handleImagePasted(session, localPath);
            }
          })
        }
        .width('100%')
        .height('100%')
        .visibility(session.id === this.activeSessionId ? Visibility.Visible : Visibility.Hidden)
      }, (session: TerminalSessionHandle) => String(session.id))
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor(this.surfaceBackdropColor())
    // Swallow any tab drop that lands on the terminal body (own or another
    // window) as a silent cancel: accept the token type and report success
    // without acting. This makes "dropped anywhere inside the app" a no-op so
    // only a drop OUTSIDE every window stays DRAG_FAILED and triggers tear-off.
    // DND drop events are distinct from touch, so this does not disturb the
    // terminal's native selection/scroll or the drawer overlay pass-through.
    .allowDrop([uniformTypeDescriptor.UniformDataType.PLAIN_TEXT])
    .onDrop((event?: DragEvent): void => {
      if (event) {
        this.handleTerminalBodyDrop(event);
      }
    })
  }

  @Builder
  private buildTabBar() {
    Row({ space: 8 }) {
      Scroll(this.tabScroller) {
        Row({ space: 4 }) {
          ForEach(this.sessions, (session: TerminalSessionHandle) => {
            TerminalTabChip({
              session: session,
              active: session.id === this.activeSessionId,
              onSelect: (): void => {
                this.activateSession(session.id, true);
              },
              onClose: (): void => {
                this.closeSession(session.id);
              },
              onEdit: (): void => {
                this.openTabEditor(session);
              },
              onHandoffEnd: (token: string, result: number): void => {
                this.handleHandoffEnd(session, token, result);
              }
            })
          }, (session: TerminalSessionHandle) => `tab-${session.id}`)

          Button() {
            Image($r('app.media.ic_plus'))
              .width(16)
              .height(16)
          }
          .height(30)
          .width(34)
          .padding(0)
          .backgroundColor('#00000000')
          .borderRadius(8)
          .focusable(false)
          .onClick(() => {
            this.addSession(true);
          })
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .align(Alignment.Start)
      .layoutWeight(1)
      // Tab strip is the drop target for reorder + cross-window merge. It accepts
      // the plain-text hand-off token payload; handleTabStripDrop claims the live
      // handle from the process-global registry and reorders or merges it.
      .allowDrop([uniformTypeDescriptor.UniformDataType.PLAIN_TEXT])
      .onDrop((event?: DragEvent): void => {
        if (event) {
          this.handleTabStripDrop(event);
        }
      })

      Button() {
        Image(this.accessoryVisible ? $r('app.media.ic_keyboard_ember') : $r('app.media.ic_keyboard'))
          .width(17)
          .height(17)
      }
      .height(30)
      .width(34)
      .padding(0)
      .backgroundColor('#00000000')
      .borderRadius(8)
      .focusable(false)
      .onClick(() => {
        this.accessoryVisible = !this.accessoryVisible;
        this.focusActiveTerminalSoon();
      })

      Button() {
        Image(this.drawerOpen && this.drawerPane === 'conn' ? $r('app.media.ic_link_ember') : $r('app.media.ic_link'))
          .width(17)
          .height(17)
      }
      .height(30)
      .width(34)
      .padding(0)
      .backgroundColor('#00000000')
      .borderRadius(8)
      .focusable(false)
      .onClick(() => {
        this.openDrawer('conn');
      })

      Button() {
        Image(this.drawerOpen && this.drawerPane !== 'conn' && this.drawerPane !== 'help'
          ? $r('app.media.ic_gear_ember') : $r('app.media.ic_gear'))
          .width(17)
          .height(17)
      }
      .height(30)
      .width(34)
      .padding(0)
      .backgroundColor('#00000000')
      .borderRadius(8)
      .focusable(false)
      .onClick(() => {
        this.openDrawer('appearance');
      })

      Button() {
        Image(this.drawerOpen && this.drawerPane === 'help' ? $r('app.media.ic_help_ember') : $r('app.media.ic_help'))
          .width(17)
          .height(17)
      }
      .height(30)
      .width(34)
      .padding(0)
      .backgroundColor('#00000000')
      .borderRadius(8)
      .focusable(false)
      .onClick(() => {
        this.openDrawer('help');
      })
    }
    .height(WINDOW_CHROME_HEIGHT)
    .width('100%')
    .padding({ left: 8, right: WINDOW_DECOR_BUTTON_RESERVE })
    .backgroundColor('#080B10')
    .border({ width: { bottom: 1 }, color: '#121821' })
  }

  // Kept mounted so the tint can cross-fade in step with the 240ms drawer
  // slide instead of snapping on/off. Closed, the dark layer is fully
  // transparent to touches (HitTestMode.None) so the terminal underneath stays
  // interactive; the drawer body owns the tap-outside-to-close logic.
  @Builder
  private buildDrawerScrim() {
    Column() {
      Row()
        .width('100%')
        .height(WINDOW_CHROME_HEIGHT)
        .hitTestBehavior(HitTestMode.None)
      Column()
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('#80020305')
        .opacity(this.drawerOpen ? 1 : 0)
        .animation({ duration: DUR_STANDARD, curve: CURVE_DECEL })
        .hitTestBehavior(this.drawerOpen ? HitTestMode.Default : HitTestMode.None)
        .onClick(() => {
          this.closeDrawer();
        })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }

  // Right-hand settings drawer: appearance / font / theme / connection.
  // Kept mounted so the slide animation plays both ways; when closed it is
  // translated off-screen and the transparent hit-test lets touches through.
  // A non-interactive spacer keeps the window-chrome row (tabs + system
  // window buttons) usable while the drawer is open.
  @Builder
  private buildDrawer() {
    Column() {
      Row()
        .width('100%')
        .height(WINDOW_CHROME_HEIGHT)
        .hitTestBehavior(HitTestMode.None)
    Row() {
      Row() {
        Column({ space: 2 }) {
          this.buildDrawerNavItem('外观', 'appearance')
          this.buildDrawerNavItem('字体', 'font')
          this.buildDrawerNavItem('主题', 'theme')
          this.buildDrawerNavItem('连接', 'conn')
          this.buildDrawerNavItem('帮助', 'help')
        }
        .width(92)
        .height('100%')
        .padding({ top: 18, left: 8, right: 8 })
        .border({ width: { right: 1 }, color: COLOR_PANEL_BORDER })

        // M10 crossfade container: only the pane content fades + slides on a
        // nav switch (the nav rail stays put). opacity + translateX, never
        // scale, so CJK labels never rasterize.
        Column() {
          if (this.drawerPane === 'theme') {
            this.buildThemePane()
          } else {
            Scroll() {
              Column() {
                if (this.drawerPane === 'appearance') {
                  this.buildAppearancePane()
                } else if (this.drawerPane === 'font') {
                  this.buildFontPane()
                } else if (this.drawerPane === 'help') {
                  this.buildHelpPane()
                } else {
                  this.buildConnPane()
                }
              }
              .width('100%')
              .padding({ left: 20, right: 20, top: 4, bottom: 24 })
              .alignItems(HorizontalAlign.Start)
            }
            .scrollBar(BarState.Off)
            .align(Alignment.Top)
            .layoutWeight(1)
            .width('100%')
            .height('100%')
          }
        }
        .layoutWeight(1)
        .height('100%')
        .opacity(this.paneT)
        .translate({ x: (1 - this.paneT) * 10 })
      }
      .width(DRAWER_WIDTH)
      .height('100%')
      .backgroundColor(COLOR_PANEL_BG)
      .border({ width: { left: 1 }, color: COLOR_PANEL_BORDER })
      .translate({ x: this.drawerOpen ? 0 : DRAWER_WIDTH })
      .animation({ duration: DUR_STANDARD, curve: CURVE_DECEL })
      // Swallow taps on non-interactive panel areas so they never bubble to
      // the close-on-outside-tap handler below.
      .onClick(() => {})
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.End)
    // Open: block the layers underneath. The terminal XComponent receives raw
    // touch/axis callbacks whenever HitTestMode.Transparent keeps it in the
    // hit-test chain, so drawer taps and scrolls were leaking into the
    // terminal. Closed: stay transparent so the always-mounted (translated
    // off-screen) drawer never eats terminal input.
    .hitTestBehavior(this.drawerOpen ? HitTestMode.Default : HitTestMode.Transparent)
    .onClick(() => {
      if (this.drawerOpen) {
        this.closeDrawer();
      }
    })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  private buildDrawerNavItem(label: string, pane: string) {
    Row({ space: 8 }) {
      Row()
        .width(2)
        .height(16)
        .borderRadius(1)
        .backgroundColor(this.drawerPane === pane ? COLOR_EMBER : '#00000000')
        .shadow(this.drawerPane === pane
          ? { radius: 4, color: COLOR_EMBER_GLOW, offsetX: 0, offsetY: 0 }
          : { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 })
        // M06 selected-filament: fade the copper + glow instead of a hard jump.
        .animation({ duration: DUR_STANDARD, curve: CURVE_DECEL })
      Text(label)
        .fontSize(12.5)
        .fontColor(this.drawerPane === pane ? COLOR_TEXT_PRIMARY : COLOR_TEXT_SECONDARY)
    }
    .width('100%')
    .height(36)
    .padding({ left: 8 })
    .borderRadius(8)
    .backgroundColor(this.drawerPane === pane ? COLOR_PANEL_2 : '#00000000')
    // M07 selected-face: settles fast (120) so the face lands a beat before the
    // filament brightens — "面先稳、灯丝后亮".
    .animation({ duration: DUR_FAST, curve: CURVE_SHARP })
    .clip(true)
    .onClick(() => {
      this.switchDrawerPane(pane);
    })
  }

  @Builder
  private buildGroupTitle(title: string) {
    Row() {
      Text(title)
        .fontSize(11)
        .fontColor(COLOR_TEXT_SECONDARY)
        .letterSpacing(1)
    }
    .width('100%')
    .padding({ bottom: 8 })
    .margin({ top: 16 })
    .border({ width: { bottom: 1 }, color: COLOR_PANEL_BORDER })
  }

  // Setting-row label: plain name on top, the matching ghostty config key
  // below in faint type. The key is structure, not decoration - it documents
  // the ghostty vocabulary and paves the way for config import/export.
  @Builder
  private buildRowLabel(name: string, key: string) {
    Column({ space: 2 }) {
      Text(name)
        .fontSize(13)
        .fontColor(COLOR_TEXT_PRIMARY)
      Text('= ' + key)
        .fontSize(10.5)
        .fontColor(COLOR_TEXT_FAINT)
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  @Builder
  private buildAppearancePane() {
    this.buildGroupTitle('光标')
    Row() {
      this.buildRowLabel('光标样式', 'cursor-style')
      Row({ space: 2 }) {
        ForEach([2, 0, 1] as number[], (style: number) => {
          Button(style === 2 ? '竖线' : style === 0 ? '方块' : '下划线')
            .height(28)
            .fontSize(11.5)
            .backgroundColor(this.cursorStyle === style ? '#1A212C' : '#00000000')
            .fontColor(this.cursorStyle === style ? COLOR_TEXT_PRIMARY : COLOR_TEXT_SECONDARY)
            .borderRadius(6)
            .focusable(false)
            .onClick(() => {
              this.cursorStyle = style;
              this.applyCursorConfig();
            })
        }, (style: number) => `cursor-${style}`)
      }
      .padding(2)
      .backgroundColor(COLOR_PANEL_2)
      .borderRadius(8)
      .border({ width: 1, color: COLOR_PANEL_BORDER })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })

    Row() {
      this.buildRowLabel('光标闪烁', 'cursor-style-blink')
      Toggle({ type: ToggleType.Switch, isOn: this.cursorBlink })
        .selectedColor(COLOR_EMBER)
        .onChange((isOn: boolean) => {
          this.cursorBlink = isOn;
          this.applyCursorConfig();
        })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })

    this.buildGroupTitle('背景')
    Row({ space: 10 }) {
      this.buildRowLabel('背景图片', 'background-image')
      if (this.backgroundImagePath.length > 0) {
        Button('清除')
          .height(30)
          .fontSize(11.5)
          .backgroundColor(COLOR_PANEL_2)
          .fontColor(COLOR_KEY_TEXT)
          .borderRadius(8)
          .border({ width: 1, color: COLOR_PANEL_BORDER })
          .focusable(false)
          .onClick(() => {
            this.clearBackgroundImage();
          })
      }
      Button('选择…')
        .height(30)
        .fontSize(11.5)
        .backgroundColor(COLOR_PANEL_2)
        .fontColor(COLOR_KEY_TEXT)
        .borderRadius(8)
        .border({ width: 1, color: COLOR_PANEL_BORDER })
        .focusable(false)
        .onClick(() => {
          void this.pickBackgroundImage();
        })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })

    if (this.backgroundImagePath.length > 0) {
      Row() {
        this.buildRowLabel(`终端遮罩 ${Math.round(this.backgroundOpacity * 100)}%`, 'background-opacity')
        Slider({
          value: Math.round(this.backgroundOpacity * 100),
          min: MIN_BACKGROUND_OPACITY_PCT,
          max: 100,
          step: 1
        })
          .width(150)
          .selectedColor(COLOR_EMBER)
          .onChange((value: number, mode: SliderChangeMode) => {
            this.backgroundOpacity = value / 100;
            this.applyBackgroundConfig();
            if (mode === SliderChangeMode.End) {
              this.persistAppearance();
            }
          })
      }
      .width('100%')
      .padding({ top: 8, bottom: 8 })

      Row() {
        this.buildRowLabel(`亚克力模糊 ${Math.round(this.backgroundBlur)}`, 'background-blur')
        Slider({
          value: this.backgroundBlur,
          min: 0,
          max: MAX_BACKGROUND_BLUR,
          step: 2
        })
          .width(150)
          .selectedColor(COLOR_EMBER)
          .onChange((value: number, mode: SliderChangeMode) => {
            this.backgroundBlur = value;
            if (mode === SliderChangeMode.End) {
              this.persistAppearance();
            }
          })
      }
      .width('100%')
      .padding({ top: 8, bottom: 8 })
    }

    this.buildGroupTitle('图片粘贴')
    Row({ space: 10 }) {
      this.buildRowLabel(this.pasteDirLabel(), 'linux-share-folder')
      if (this.pasteDirUri.length > 0) {
        Button('恢复默认')
          .height(30)
          .fontSize(11.5)
          .backgroundColor(COLOR_PANEL_2)
          .fontColor(COLOR_KEY_TEXT)
          .borderRadius(8)
          .border({ width: 1, color: COLOR_PANEL_BORDER })
          .focusable(false)
          .onClick(() => {
            this.clearPasteDirectory();
          })
      }
      Button('选择共享文件夹…')
        .height(30)
        .fontSize(11.5)
        .backgroundColor(COLOR_PANEL_2)
        .fontColor(COLOR_KEY_TEXT)
        .borderRadius(8)
        .border({ width: 1, color: COLOR_PANEL_BORDER })
        .focusable(false)
        .onClick(() => {
          void this.pickPasteDirectory();
        })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    Text('选择与 Linux 模拟机共享的目录(share 下的一级文件夹)。粘贴的截图会存入该文件夹,远端会话直接粘贴 /mnt/linux_share/<文件夹> 路径,无需上传')
      .fontSize(10.5)
      .fontColor(COLOR_TEXT_FAINT)
      .lineHeight(15)
      .margin({ top: 2 })
  }

  @Builder
  private buildFontPane() {
    this.buildGroupTitle('字号')
    Row() {
      this.buildRowLabel('终端字号', 'font-size')
      Row({ space: 2 }) {
        Button('−')
          .width(28)
          .height(28)
          .padding(0)
          .fontSize(14)
          .backgroundColor('#00000000')
          .fontColor(COLOR_TEXT_SECONDARY)
          .borderRadius(6)
          .focusable(false)
          .onClick(() => {
            this.applyFontSize(this.fontSize - 1, true);
          })
        Text(`${this.fontSize}`)
          .fontSize(12.5)
          // M26: fontColor + translateY are driven by the one-shot readout tick
          // (keyframeAnimateTo), so they flash ember and nudge up-and-back on a
          // size change. No .animation() here — the imperative tick owns them.
          .fontColor(this.fontReadoutColor)
          .width(30)
          .textAlign(TextAlign.Center)
          .translate({ y: this.fontReadoutTickY })
        Button('+')
          .width(28)
          .height(28)
          .padding(0)
          .fontSize(14)
          .backgroundColor('#00000000')
          .fontColor(COLOR_TEXT_SECONDARY)
          .borderRadius(6)
          .focusable(false)
          .onClick(() => {
            this.applyFontSize(this.fontSize + 1, true);
          })
      }
      .padding(2)
      .backgroundColor(COLOR_PANEL_2)
      .borderRadius(8)
      .border({ width: 1, color: COLOR_PANEL_BORDER })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })

    this.buildGroupTitle('字体家族')
    Row({ space: 8 }) {
      this.buildFontChoiceButton('Maple', FONT_FAMILY_MAPLE)
      this.buildFontChoiceButton('JetBrains', FONT_FAMILY_JETBRAINS)
    }
    .width('100%')
    .margin({ top: 10 })
    Row({ space: 8 }) {
      this.buildFontChoiceButton('Cascadia', FONT_FAMILY_CASCADIA)
      this.buildFontChoiceButton('更纱', FONT_FAMILY_SARASA)
    }
    .width('100%')
    .margin({ top: 8 })
    Row({ space: 8 }) {
      this.buildFontChoiceButton('系统', FONT_FAMILY_SYSTEM)
      if (this.customFontPath.length > 0) {
        this.buildFontChoiceButton('自定义', FONT_FAMILY_CUSTOM)
      }
    }
    .width('100%')
    .margin({ top: 8 })

    Row({ space: 10 }) {
      this.buildRowLabel('导入自定义字体', 'ttf / otf')
      if (this.customFontPath.length > 0) {
        Button('重置')
          .height(30)
          .fontSize(11.5)
          .backgroundColor(COLOR_PANEL_2)
          .fontColor(COLOR_KEY_TEXT)
          .borderRadius(8)
          .border({ width: 1, color: COLOR_PANEL_BORDER })
          .focusable(false)
          .onClick(() => {
            this.clearCustomFont();
          })
      }
      Button('选择文件…')
        .height(30)
        .fontSize(11.5)
        .backgroundColor(COLOR_PANEL_2)
        .fontColor(COLOR_KEY_TEXT)
        .borderRadius(8)
        .border({ width: 1, color: COLOR_PANEL_BORDER })
        .focusable(false)
        .onClick(() => {
          void this.pickCustomFont();
        })
    }
    .width('100%')
    .margin({ top: 14 })
  }

  @Builder
  private buildThemePane() {
    Column({ space: 10 }) {
      TextInput({ text: this.themeFilter, placeholder: '搜索主题…' })
        .height(36)
        .fontSize(12.5)
        .fontColor(COLOR_TEXT_PRIMARY)
        .backgroundColor(COLOR_PANEL_2)
        .borderRadius(8)
        .onChange((value: string) => {
          this.themeFilter = value;
        })

      List({ space: 2 }) {
        ForEach(this.filteredThemes(), (theme: string) => {
          ListItem() {
            this.buildThemeRow(theme)
          }
        }, (theme: string) => theme)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .layoutWeight(1)
    .width('100%')
    .height('100%')
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
  }

  @Builder
  private buildThemeRow(theme: string) {
    Row({ space: 12 }) {
      Stack() {
        Text('Aa')
          .fontSize(12)
          .fontColor(this.themePreviewFg(theme))
      }
      .width(52)
      .height(32)
      .borderRadius(7)
      .backgroundColor(this.themePreviewBg(theme))
      .border({ width: 1, color: '#14FFFFFF' })

      Column({ space: 4 }) {
        Text(theme.split('_').join(' '))
          .fontSize(12.5)
          .fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 3 }) {
          ForEach(this.themePreviewAnsi(theme), (dotColor: string, idx: number) => {
            Circle({ width: 7, height: 7 })
              .fill(dotColor)
          }, (dotColor: string, idx: number) => `${theme}-${idx}`)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Row()
        .width(14)
        .height(2)
        .borderRadius(1)
        .backgroundColor(theme === this.themeName ? COLOR_EMBER : '#00000000')
        .shadow(theme === this.themeName
          ? { radius: 6, color: COLOR_EMBER_GLOW, offsetX: 0, offsetY: 0 }
          : { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 })
        // M06 selected-filament: fade the copper + glow.
        .animation({ duration: DUR_STANDARD, curve: CURVE_DECEL })
    }
    .width('100%')
    .padding({ left: 8, right: 10, top: 6, bottom: 6 })
    .borderRadius(9)
    .backgroundColor(theme === this.themeName ? COLOR_PANEL_2 : '#00000000')
    // M07 selected-face: fast face settle ahead of the filament.
    .animation({ duration: DUR_FAST, curve: CURVE_SHARP })
    .onClick(() => {
      this.applyTheme(theme);
    })
  }

  @Builder
  private buildConnPane() {
    Text(DEFAULT_FUSION_ENGINE_VM_LABEL)
      .fontSize(15)
      .fontWeight(FontWeight.Medium)
      .fontColor(COLOR_TEXT_PRIMARY)
      .margin({ top: 16 })
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })

    Row({ space: 8 }) {
      Row()
        .width(22)
        .height(2)
        .borderRadius(1)
        .backgroundColor(this.activeConnLit() ? COLOR_EMBER : COLOR_ASH)
        .shadow(this.activeConnLit()
          ? { radius: 6, color: COLOR_EMBER_GLOW, offsetX: 0, offsetY: 0 }
          : { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 })
        // M06 selected-filament: fade the copper + glow between states.
        .animation({ duration: DUR_STANDARD, curve: CURVE_DECEL })
        // M09 connecting-breath: after .animation() so only the gated loop drives it.
        .opacity(this.activeConnPending() ? this.connBreatheOpacity : 1)
      Text(this.activeConnStatusText())
        .fontSize(11.5)
        .fontColor(COLOR_TEXT_SECONDARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .padding(10)
    .backgroundColor(COLOR_PANEL_2)
    .borderRadius(8)
    .margin({ top: 16, bottom: 6 })

    Text('主机')
      .fontSize(11.5)
      .fontColor(COLOR_TEXT_SECONDARY)
      .margin({ top: 8, bottom: 4 })
    TextInput({ text: this.draftHost, placeholder: '172.16.100.2' })
      .height(40)
      .fontSize(13)
      .fontColor(COLOR_TEXT_PRIMARY)
      .backgroundColor(COLOR_PANEL_2)
      .borderRadius(8)
      .onChange((value: string) => {
        this.draftHost = value;
      })

    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Text('Agent 端口')
          .fontSize(11.5)
          .fontColor(COLOR_TEXT_SECONDARY)
        TextInput({ text: this.draftPort, placeholder: '端口' })
          .height(40)
          .fontSize(13)
          .fontColor(COLOR_TEXT_PRIMARY)
          .backgroundColor(COLOR_PANEL_2)
          .borderRadius(8)
          .type(InputType.Number)
          .onChange((value: string) => {
            this.draftPort = value;
          })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Column({ space: 4 }) {
        Text('SSH 端口')
          .fontSize(11.5)
          .fontColor(COLOR_TEXT_SECONDARY)
        TextInput({ text: this.draftSshPort, placeholder: '22' })
          .height(40)
          .fontSize(13)
          .fontColor(COLOR_TEXT_PRIMARY)
          .backgroundColor(COLOR_PANEL_2)
          .borderRadius(8)
          .type(InputType.Number)
          .onChange((value: string) => {
            this.draftSshPort = value;
          })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .margin({ top: 10 })

    Text('访问令牌')
      .fontSize(11.5)
      .fontColor(COLOR_TEXT_SECONDARY)
      .margin({ top: 10, bottom: 4 })
    TextInput({ text: this.draftAgentToken, placeholder: '令牌' })
      .height(40)
      .fontSize(13)
      .fontColor(COLOR_TEXT_PRIMARY)
      .backgroundColor(COLOR_PANEL_2)
      .borderRadius(8)
      .type(InputType.Password)
      .onChange((value: string) => {
        this.draftAgentToken = value;
      })

    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Text('SSH 用户')
          .fontSize(11.5)
          .fontColor(COLOR_TEXT_SECONDARY)
        TextInput({ text: this.draftUser, placeholder: '用户名' })
          .height(40)
          .fontSize(13)
          .fontColor(COLOR_TEXT_PRIMARY)
          .backgroundColor(COLOR_PANEL_2)
          .borderRadius(8)
          .onChange((value: string) => {
            this.draftUser = value;
          })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Column({ space: 4 }) {
        Text('SSH 密码(不保存)')
          .fontSize(11.5)
          .fontColor(COLOR_TEXT_SECONDARY)
        TextInput({ text: this.draftPassword, placeholder: '密码' })
          .height(40)
          .fontSize(13)
          .fontColor(COLOR_TEXT_PRIMARY)
          .backgroundColor(COLOR_PANEL_2)
          .borderRadius(8)
          .type(InputType.Password)
          .onChange((value: string) => {
            this.draftPassword = value;
          })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .margin({ top: 10 })

    Row({ space: 8 }) {
      Button('连接 Agent')
        .height(40)
        .layoutWeight(2)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .backgroundColor(COLOR_EMBER)
        .fontColor('#1A0F05')
        .borderRadius(9)
        // M27: the sole ember action button sinks slightly on press,
        // reinforcing "copper = executable". Opacity only, never scale.
        .stateStyles({
          pressed: {
            .opacity(0.82)
          }
        })
        .focusable(false)
        .onClick(() => {
          this.connectFusionAgent();
        })
      Button('SSH 备用')
        .height(40)
        .layoutWeight(1)
        .fontSize(12)
        .backgroundColor(COLOR_PANEL_2)
        .fontColor(COLOR_KEY_TEXT)
        .borderRadius(9)
        .border({ width: 1, color: COLOR_PANEL_BORDER })
        .focusable(false)
        .onClick(() => {
          this.connectFusionVm();
        })
      Button('本地')
        .height(40)
        .layoutWeight(1)
        .fontSize(12)
        .backgroundColor(COLOR_PANEL_2)
        .fontColor(COLOR_KEY_TEXT)
        .borderRadius(9)
        .border({ width: 1, color: COLOR_PANEL_BORDER })
        .focusable(false)
        .onClick(() => {
          this.drawerOpen = false;
          this.startLocalSession();
          this.focusActiveTerminalSoon();
        })
    }
    .width('100%')
    .margin({ top: 18 })
  }

  @Builder
  private buildKbd(label: string) {
    Text(label)
      .fontSize(10.5)
      .fontColor(COLOR_TEXT_PRIMARY)
      .padding({ left: 6, right: 6, top: 3, bottom: 3 })
      .backgroundColor(COLOR_PANEL_2)
      .borderRadius(5)
      .border({ width: 1, color: COLOR_PANEL_BORDER })
  }

  @Builder
  private buildShortcutRow(keys: string, desc: string) {
    Row({ space: 10 }) {
      Row({ space: 4 }) {
        ForEach(keys.split(' '), (keyCap: string) => {
          this.buildKbd(keyCap)
        }, (keyCap: string, idx: number) => `${keys}-${idx}`)
      }
      Text(desc)
        .fontSize(12)
        .fontColor(COLOR_TEXT_SECONDARY)
        .layoutWeight(1)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
  }

  @Builder
  private buildHelpRow(action: string, detail: string) {
    Column({ space: 3 }) {
      Text(action)
        .fontSize(12.5)
        .fontColor(COLOR_TEXT_PRIMARY)
      Text(detail)
        .fontSize(11)
        .fontColor(COLOR_TEXT_SECONDARY)
        .lineHeight(16)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: 7, bottom: 7 })
  }

  @Builder
  private buildHelpPane() {
    this.buildGroupTitle('键盘快捷键')
    this.buildShortcutRow('Ctrl Shift C', '复制选中内容')
    this.buildShortcutRow('Ctrl Insert', '复制选中内容')
    this.buildShortcutRow('Ctrl V', '粘贴')
    this.buildShortcutRow('Shift Insert', '粘贴')
    Text('Ctrl+C 保持终端中断语义,不会被复制占用')
      .fontSize(10.5)
      .fontColor(COLOR_TEXT_FAINT)
      .margin({ top: 4 })

    this.buildGroupTitle('标签页')
    this.buildHelpRow('双击标签', '重命名标签、选择灯丝颜色;「恢复自动命名」可回到自动标题')
    this.buildHelpRow('底部灯丝', '亮 = 已连接;半亮 = 正在连接或重连;灰 = 已断开')
    this.buildHelpRow('关闭标签', '只断开本地连接,不会打断远端 tmux 或正在运行的程序')

    this.buildGroupTitle('触屏手势')
    this.buildHelpRow('单指滑动', '滚动回看,带惯性;轻点呼出键盘或打开链接')
    this.buildHelpRow('长按拖动', '选择文字;选中后右键菜单里复制')
    this.buildHelpRow('鼠标模式(tmux / vim)', '轻点 = 点击;长按后拖 = 拖拽,可以拖动 tmux 分栏;滑动 = 滚轮')
    this.buildHelpRow('辅助键条', '顶栏键盘图标呼出 Esc / Tab / ^C 中断 / 复制 / 粘贴 / 方向键,一键直达')

    this.buildGroupTitle('连接')
    this.buildHelpRow('自动连接', '启动或新建标签时自动连上次保存的 Agent;手动选择传输后该标签不再自动连')
    this.buildHelpRow('断线重连', '连接意外断开后按 1s → 30s 退避自动重连;手动断开不会触发')
    this.buildHelpRow('远程复制', '远端程序可通过 OSC 52(如 tmux set-clipboard)直接写入系统剪贴板')
    this.buildHelpRow('图片粘贴视角', '在会话里手动 ssh 到别的机器后,双击标签把粘贴视角切到「上传」或「共享」,路径才对目标机器有效')

    this.buildGroupTitle('主题与字体')
    this.buildHelpRow('ghostty 键名', '设置项下方的灰色小字是对应的 ghostty 配置键,便于对照 ghostty 文档')
    this.buildHelpRow('自定义字体', '字体页可导入 ttf / otf 文件,导入后自动切换到「自定义」')
  }

  @Builder
  private buildTabEditScrim() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor('#80020305')
      .transition(TransitionEffect.OPACITY.animation({ duration: DUR_STANDARD, curve: CURVE_DECEL }))
      .onClick(() => {
        this.commitTabEditor();
      })
  }

  @Builder
  private buildPasteModeButton(label: string, mode: string) {
    Button(label)
      .height(28)
      .layoutWeight(1)
      .padding(0)
      .fontSize(11.5)
      .backgroundColor(this.editingPasteMode === mode ? '#1A212C' : '#00000000')
      .fontColor(this.editingPasteMode === mode ? COLOR_TEXT_PRIMARY : COLOR_TEXT_SECONDARY)
      .borderRadius(6)
      .focusable(false)
      .onClick(() => {
        this.editingPasteMode = mode;
        if (this.editingSession) {
          this.editingSession.pasteMode = mode;
        }
      })
  }

  // Tab editor (double-tap a tab): rename and pick a filament color.
  @Builder
  private buildTabEditor() {
    Column({ space: 14 }) {
      Text('标签设置')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLOR_TEXT_PRIMARY)
        .width('100%')

      TextInput({ text: this.tabEditDraft, placeholder: '标签名称' })
        .height(40)
        .fontSize(13)
        .fontColor(COLOR_TEXT_PRIMARY)
        .backgroundColor(COLOR_PANEL_2)
        .borderRadius(8)
        .onChange((value: string) => {
          this.tabEditDraft = value;
        })

      Row() {
        ForEach(FILAMENT_PALETTE, (filament: string) => {
          Column()
            .width(22)
            .height(22)
            .borderRadius(11)
            .backgroundColor(filament)
            .border({
              width: 2,
              color: this.filamentSelected(filament) ? '#FFFFFF' : '#00000000'
            })
            // M19: the selection ring eases on/off instead of a hard cut. Only
            // the border color is state-driven here, so the fast micro-feedback
            // animation touches nothing that would relayout.
            .animation({ duration: DUR_FAST, curve: CURVE_SHARP })
            .onClick(() => {
              this.pickFilament(filament);
            })
        }, (filament: string) => filament)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Column({ space: 6 }) {
        Text('图片粘贴视角')
          .fontSize(11.5)
          .fontColor(COLOR_TEXT_SECONDARY)
          .width('100%')
        Row({ space: 2 }) {
          this.buildPasteModeButton('自动', 'auto')
          this.buildPasteModeButton('本地', 'local')
          this.buildPasteModeButton('共享', 'share')
          this.buildPasteModeButton('上传', 'sftp')
        }
        .width('100%')
        .padding(2)
        .backgroundColor(COLOR_PANEL_2)
        .borderRadius(8)
        .border({ width: 1, color: COLOR_PANEL_BORDER })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      Row({ space: 8 }) {
        Button('恢复自动命名')
          .height(34)
          .fontSize(12)
          .backgroundColor(COLOR_PANEL_2)
          .fontColor(COLOR_KEY_TEXT)
          .borderRadius(8)
          .border({ width: 1, color: COLOR_PANEL_BORDER })
          .focusable(false)
          .onClick(() => {
            this.resetTabName();
          })
        Blank()
        Button('完成')
          .height(34)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(COLOR_EMBER)
          .fontColor('#1A0F05')
          .borderRadius(8)
          // M27: same ember-button press feedback as the connect action.
          .stateStyles({
            pressed: {
              .opacity(0.82)
            }
          })
          .focusable(false)
          .onClick(() => {
            this.commitTabEditor();
          })
      }
      .width('100%')
    }
    .width(320)
    .padding(18)
    .backgroundColor(COLOR_PANEL_BG)
    .borderRadius(14)
    .border({ width: 1, color: COLOR_PANEL_BORDER })
    .shadow({ radius: 28, color: '#B3000000', offsetX: 0, offsetY: 12 })
    // M18 asymmetric: entrance keeps the fade + short rise (opacity + translateY
    // 12 -> 0, no scale so the CJK label never rasterizes); exit is a quicker,
    // plainer opacity-only leave that accelerates away.
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.OPACITY
        .combine(TransitionEffect.translate({ y: 12 }))
        .animation({ duration: DUR_STANDARD, curve: CURVE_DECEL }),
      TransitionEffect.OPACITY
        .animation({ duration: DUR_EDITOR_EXIT, curve: CURVE_ACCEL })
    ))
  }


  @Builder
  private buildFieldLabel(label: string) {
    Text(label)
      .fontSize(11)
      .fontColor(COLOR_TEXT_SECONDARY)
      .width('100%')
      .textAlign(TextAlign.Start)
  }


  private markManualConnection(session: TerminalSessionHandle): void {
    session.manualConnectionSelected = true;
    session.autoConnectAttempted = true;
  }

  private tryAutoConnectAllSessions(): void {
    for (const session of this.sessions) {
      this.tryAutoConnectSession(session);
    }
  }

  // Connects a freshly attached tab to the saved Fusion Agent endpoint once
  // per tab, unless the user already picked a transport manually. Returns
  // true when an attempt was started (the caller then skips the demo).
  private tryAutoConnectSession(session: TerminalSessionHandle): boolean {
    if (session.manualConnectionSelected || session.autoConnectAttempted) {
      return false;
    }
    if (!session.attached || !session.controller.isAttached() || !this.connectionSettingsLoaded) {
      return false;
    }
    if (this.draftHost.trim().length === 0) {
      return false;
    }
    session.autoConnectAttempted = true;
    this.connectFusionAgentForSession(session, false);
    return true;
  }

  private connectFusionVm(): void {
    const session = this.activeSession();
    this.markManualConnection(session);
    const sshPort = Number(this.draftSshPort);
    const profile = createFusionVmProfile(
      this.draftHost,
      Number.isFinite(sshPort) ? sshPort : 22,
      this.draftUser,
      this.draftPassword
    );
    this.drawerOpen = false;
    this.focusActiveTerminalSoon();
    this.persistConnection();
    session.agentDriver.disconnect();
    this.ensureDriverAttached(session);
    this.clearTerminalForLiveSession(session);
    session.driver.connectSsh(profile);
  }

  private connectFusionAgent(): void {
    const session = this.activeSession();
    this.drawerOpen = false;
    this.focusActiveTerminalSoon();
    this.markManualConnection(session);
    this.connectFusionAgentForSession(session, true);
  }

  private connectFusionAgentForSession(session: TerminalSessionHandle, persistSettings: boolean): void {
    const port = Number(this.draftPort);
    const size = session.controller.getTerminalSize();
    if (persistSettings) {
      this.persistConnection();
    }
    session.driver.detach();
    session.agentDriver.attach(session.controller);
    this.clearTerminalForLiveSession(session);
    session.agentDriver.connect({
      host: this.draftHost,
      port: Number.isFinite(port) && port > 0 ? port : DEFAULT_FUSION_AGENT_PORT,
      path: DEFAULT_FUSION_AGENT_PATH,
      cols: size.cols,
      rows: size.rows,
      token: this.draftAgentToken
    });
  }

  private startLocalSession(): void {
    const session = this.activeSession();
    this.markManualConnection(session);
    session.agentDriver.disconnect();
    this.ensureDriverAttached(session);
    this.clearTerminalForLiveSession(session);
    session.driver.startLocal();
  }

  private ensureDriverAttached(session: TerminalSessionHandle): void {
    if (this.context) {
      session.driver.attach(session.controller, this.context);
    }
  }

  private formatStatusLabel(label: string, error: string): string {
    const safeError = error || '';
    const safeLabel = label || '';
    return safeError.length > 0 ? safeError : safeLabel;
  }

  private showStartupDemo(session: TerminalSessionHandle): void {
    if (session.demoRendered || !session.controller.isAttached()) {
      return;
    }

    session.controller.feed(buildAnsi256ColorDemo());
    session.demoRendered = true;
  }

  private pasteDirLabel(): string {
    if (this.pasteDirUri.length === 0) {
      return '共享文件夹:未设置';
    }
    const tail = this.linuxShareFolderName();
    return tail.length > 0 ? `共享文件夹:${tail}` : '共享文件夹:已设置';
  }

  // The Linux VM mounts the HarmonyOS share at /mnt/linux_share; the user
  // picks a first-level folder inside it, so its name is the only thing
  // needed to translate a copied file into a VM-visible path.
  private linuxShareFolderName(): string {
    if (this.pasteDirUri.length === 0) {
      return '';
    }
    const segments = this.pasteDirUri.split('/');
    const tail = segments.length > 0 ? segments[segments.length - 1] : '';
    return decodeURIComponent(tail);
  }

  private async pickPasteDirectory(): Promise<void> {
    try {
      const dirPicker = new picker.DocumentViewPicker();
      const options = new picker.DocumentSelectOptions();
      options.selectMode = picker.DocumentSelectMode.FOLDER;
      options.maxSelectNumber = 1;
      const uris = await dirPicker.select(options);
      if (!uris || uris.length === 0) {
        return;
      }
      const policies: Array<fileShare.PolicyInfo> = [{
        uri: uris[0],
        operationMode: fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE
      }];
      try {
        await fileShare.persistPermission(policies);
      } catch (permErr) {
        console.error('Failed to persist paste directory permission: ' + JSON.stringify(permErr));
      }
      this.pasteDirUri = uris[0];
      this.persistAppearance();
    } catch (err) {
      console.error('Failed to pick paste directory: ' + JSON.stringify(err));
    }
  }

  private clearPasteDirectory(): void {
    this.pasteDirUri = '';
    this.persistAppearance();
  }

  // Persisted folder grants must be re-activated once per app launch before
  // the sandbox can reach the public directory again.
  private async activatePasteDirPermission(): Promise<void> {
    if (this.pasteDirUri.length === 0) {
      return;
    }
    try {
      const policies: Array<fileShare.PolicyInfo> = [{
        uri: this.pasteDirUri,
        operationMode: fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE
      }];
      await fileShare.activatePermission(policies);
    } catch (err) {
      console.error('Failed to activate paste directory permission: ' + JSON.stringify(err));
    }
  }

  // Copies a pasted image into the user-chosen public folder and returns the
  // shell-visible path; returns '' when no folder is set or the copy failed,
  // in which case the sandbox path is used as before.
  private exportPastedImage(localPath: string): string {
    if (this.pasteDirUri.length === 0) {
      return '';
    }
    try {
      const segments = localPath.split('/');
      const name = segments.length > 0 ? segments[segments.length - 1] : `paste-${Date.now()}.png`;
      // Creating children directly on a folder uri is not supported; convert
      // the granted uri to its mounted path first and use plain file APIs.
      const dirPath = new fileUri.FileUri(this.pasteDirUri).path;
      const targetPath = `${dirPath}/${name}`;
      const source = fs.openSync(localPath, fs.OpenMode.READ_ONLY);
      const target = fs.openSync(targetPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      const buffer = new ArrayBuffer(65536);
      let bytes = fs.readSync(source.fd, buffer);
      while (bytes > 0) {
        fs.writeSync(target.fd, buffer, { length: bytes });
        bytes = fs.readSync(source.fd, buffer);
      }
      fs.closeSync(source);
      fs.closeSync(target);
      return targetPath;
    } catch (err) {
      console.error('Failed to export pasted image to public folder: ' + JSON.stringify(err));
      return '';
    }
  }

  // A clipboard image was saved into the app sandbox: local sessions paste
  // the sandbox path directly; SSH and agent sessions upload it to the remote
  // /tmp over a dedicated SFTP connection (saved SSH credentials) and paste
  // the remote path instead - handy for feeding screenshots to CLI tools.
  private handleImagePasted(session: TerminalSessionHandle, localPath: string): void {
    const exported = this.exportPastedImage(localPath);
    const mode = session.pasteMode;
    if (mode === 'local') {
      session.controller.paste(exported.length > 0 ? exported : localPath);
      return;
    }
    if (mode === 'share') {
      if (exported.length > 0) {
        this.pasteSharePath(session, exported);
      } else {
        session.controller.paste(localPath);
        session.controller.feed('\r\n[FusionTerm] 未设置共享文件夹,已粘贴本地路径\r\n');
      }
      return;
    }
    if (mode === 'sftp') {
      this.uploadPastedImage(session, localPath);
      return;
    }
    // auto: follow the transport type.
    if (session.statusMode === 'local' || !session.connected) {
      session.controller.paste(exported.length > 0 ? exported : localPath);
      return;
    }
    if (session.statusMode === 'agent' && exported.length > 0) {
      // Agent sessions always talk to the local Linux VM, which sees the
      // shared folder at /mnt/linux_share - no upload needed. SSH sessions
      // may target any remote host, so they upload over SFTP instead.
      this.pasteSharePath(session, exported);
      return;
    }
    this.uploadPastedImage(session, localPath);
  }

  private pasteSharePath(session: TerminalSessionHandle, exported: string): void {
    const parts = exported.split('/');
    const fileName = parts[parts.length - 1];
    session.controller.paste(`/mnt/linux_share/${this.linuxShareFolderName()}/${fileName}`);
  }

  private uploadPastedImage(session: TerminalSessionHandle, localPath: string): void {
    if (this.draftPassword.length === 0) {
      session.controller.paste(localPath);
      session.controller.feed('\r\n[FusionTerm] 已粘贴本地路径;设置共享文件夹或填写 SSH 密码后可直达远端\r\n');
      return;
    }
    const sshPort = Number(this.draftSshPort);
    const remotePath = `/tmp/fusionterm-paste-${Date.now()}.png`;
    FusionTerminalDriver.uploadFile(
      this.draftHost,
      Number.isFinite(sshPort) && sshPort > 0 ? sshPort : 22,
      this.draftUser,
      this.draftPassword,
      localPath,
      remotePath
    ).then((remote: string) => {
      session.controller.paste(remote);
    }).catch((err: Object) => {
      session.controller.feed('\r\n[FusionTerm] 图片上传失败:' + JSON.stringify(err) + '\r\n');
    });
  }

  private clearTerminalForLiveSession(session: TerminalSessionHandle): void {
    if (session.controller.isAttached()) {
      session.controller.feed('\u001b[2J\u001b[H\u001b[0m');
    }
  }

  @Builder
  private buildAccessoryBar() {
    Row({ space: 6 }) {
      Scroll() {
        Row({ space: 6 }) {
          Button('Esc')
            .height(32).fontSize(12).borderRadius(8)
            .backgroundColor(COLOR_KEY_BG).fontColor(COLOR_KEY_TEXT)
            .focusable(false)
            .onClick(() => {
              this.activeSession().controller.write('\u001b');
              this.focusActiveTerminalSoon();
            })
          Button('Tab')
            .height(32).fontSize(12).borderRadius(8)
            .backgroundColor(COLOR_KEY_BG).fontColor(COLOR_KEY_TEXT)
            .focusable(false)
            .onClick(() => {
              this.activeSession().controller.write('\t');
              this.focusActiveTerminalSoon();
            })
          Button('^C')
            .height(32).fontSize(12).borderRadius(8)
            .backgroundColor(COLOR_KEY_BG).fontColor(COLOR_KEY_TEXT)
            .focusable(false)
            .onClick(() => {
              this.activeSession().controller.write('\u0003');
              this.focusActiveTerminalSoon();
            })
          Button('复制')
            .height(32).fontSize(12).borderRadius(8)
            .backgroundColor(COLOR_KEY_BG).fontColor(COLOR_KEY_TEXT)
            .focusable(false)
            .onClick(() => {
              this.activeSession().controller.requestCopy();
              this.focusActiveTerminalSoon();
            })
          Button('粘贴')
            .height(32).fontSize(12).borderRadius(8)
            .backgroundColor(COLOR_KEY_BG).fontColor(COLOR_KEY_TEXT)
            .focusable(false)
            .onClick(() => {
              this.activeSession().controller.requestPaste();
              this.focusActiveTerminalSoon();
            })
          ForEach(['←', '↑', '↓', '→', 'PgUp', 'PgDn'] as string[], (key: string) => {
            Button(key)
              .height(32).fontSize(12).borderRadius(8)
              .backgroundColor(COLOR_KEY_BG).fontColor(COLOR_KEY_TEXT)
              .focusable(false)
              .onClick(() => {
                this.sendAccessoryKey(key);
                this.focusActiveTerminalSoon();
              })
          }, (key: string) => `acc-${key}`)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .align(Alignment.Start)
      .layoutWeight(1)
    }
    .height(44)
    .width('100%')
    .padding({ left: 8, right: 8 })
    .backgroundColor(COLOR_BAR_BG)
    .border({ width: { top: 1 }, color: COLOR_BAR_BORDER })
    // M13: the terminal still reflows exactly once (the `if` mount is kept), but
    // the key bar itself fades up from below instead of hard-inserting. opacity +
    // translateY only — no height animation, which would relayout the terminal.
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: 12 }))
      .animation({ duration: DUR_STANDARD, curve: CURVE_DECEL }))
  }


  private filteredThemes(): string[] {
    const filter = this.themeFilter.trim().toLowerCase();
    if (filter.length === 0) {
      return this.themeList;
    }
    return this.themeList.filter((theme: string) => theme.toLowerCase().includes(filter));
  }

  private prepareThemePane(): void {
    const list = this.activeSession().controller.getThemeList();
    if (list.length > 0) {
      this.themeList = list;
    }
    this.themeFilter = '';
    void this.loadThemePreviews();
  }

  private activeConnLit(): boolean {
    return this.sessions.length > 0 && this.activeSession().connected;
  }

  private activeConnStatusText(): string {
    if (this.sessions.length === 0) {
      return '未连接';
    }
    const session = this.activeSession();
    if (session.connected) {
      return session.statusLabel.length > 0 ? `已连接 · ${session.statusLabel}` : '已连接';
    }
    return session.statusLabel.length > 0 ? session.statusLabel : '未连接';
  }

  private filamentSelected(filament: string): boolean {
    const current = this.editingFilament.length > 0 ? this.editingFilament : COLOR_EMBER;
    return current === filament;
  }

  private themePreviewBg(theme: string): string {
    const preview = this.themePreviews.get(theme);
    return preview ? preview.bg : COLOR_PANEL_2;
  }

  private themePreviewFg(theme: string): string {
    const preview = this.themePreviews.get(theme);
    return preview ? preview.fg : COLOR_TEXT_SECONDARY;
  }

  private themePreviewAnsi(theme: string): string[] {
    const preview = this.themePreviews.get(theme);
    return preview ? preview.ansi : [];
  }

  // Parses every bundled ghostty theme once (background / foreground /
  // palette 0-7) so the list can show real swatches; results are cached for
  // the app lifetime and the list degrades to plain rows on any failure.
  private async loadThemePreviews(): Promise<void> {
    if (this.themePreviewsLoading || this.themePreviews.size > 0 || !this.context) {
      return;
    }
    this.themePreviewsLoading = true;
    const resourceMgr = this.context.resourceManager;
    const next: Map<string, ThemePreview> = new Map();
    for (const theme of this.themeList) {
      try {
        const raw = await resourceMgr.getRawFileContent(`themes/${theme}`);
        const preview = this.parseThemePreview(raw);
        if (preview) {
          next.set(theme, preview);
        }
      } catch (_err) {
        // Theme without a readable file simply renders without a swatch.
      }
    }
    this.themePreviews = next;
    this.themePreviewsLoading = false;
  }

  private parseThemePreview(raw: Uint8Array): ThemePreview | null {
    let text = '';
    for (let i = 0; i < raw.length; i += 1) {
      text += String.fromCharCode(raw[i]);
    }
    const slots: string[] = ['', '', '', '', '', '', '', ''];
    let bg = '';
    let fg = '';
    for (const line of text.split('\n')) {
      const eq = line.indexOf('=');
      if (eq < 0) {
        continue;
      }
      const key = line.slice(0, eq).trim();
      const value = line.slice(eq + 1).trim();
      if (key === 'background') {
        bg = this.normalizeHexColor(value);
      } else if (key === 'foreground') {
        fg = this.normalizeHexColor(value);
      } else if (key === 'palette') {
        const sub = value.indexOf('=');
        if (sub > 0) {
          const idx = Number(value.slice(0, sub).trim());
          if (Number.isInteger(idx) && idx >= 0 && idx < 8) {
            slots[idx] = this.normalizeHexColor(value.slice(sub + 1).trim());
          }
        }
      }
    }
    if (bg.length === 0 || fg.length === 0) {
      return null;
    }
    const dots: string[] = [];
    for (const slot of slots) {
      if (slot.length > 0) {
        dots.push(slot);
      }
    }
    const preview: ThemePreview = { bg: bg, fg: fg, ansi: dots };
    return preview;
  }

  private normalizeHexColor(value: string): string {
    const hex = value.startsWith('#') ? value.slice(1) : value;
    if (hex.length === 6 && /^[0-9a-fA-F]{6}$/.test(hex)) {
      return '#' + hex;
    }
    return '';
  }

  private applyTheme(theme: string): void {
    this.themeName = theme;
    for (const session of this.sessions) {
      session.controller.setTheme(theme);
    }
    this.persistAppearance();
  }

  private applyCursorConfig(): void {
    for (const session of this.sessions) {
      session.controller.updateConfig({ cursorStyle: this.cursorStyle, cursorBlink: this.cursorBlink });
    }
    this.persistAppearance();
  }

  // Shared by the font-size slider and the A-/A+ buttons.
  private applyFontSize(value: number, persist: boolean = false): void {
    const raw = Math.round(value);
    const next = Math.min(MAX_TERMINAL_FONT_SIZE, Math.max(MIN_TERMINAL_FONT_SIZE, raw));
    if (next !== this.fontSize) {
      this.fontSize = next;
      for (const session of this.sessions) {
        session.controller.updateConfig({ fontSize: next });
      }
      // M26: acknowledge the change on the readout only; the terminal grid
      // reflow itself stays an instant cut (no fontSize / reflow tween).
      this.playFontReadoutTick();
    }
    // M26: buzz once when a user press lands on or is pushed past a hard limit,
    // so the min/max wall is felt even though the number stops moving. Gated on
    // `persist` so programmatic loads never fire a phantom haptic.
    if (persist && (raw <= MIN_TERMINAL_FONT_SIZE || raw >= MAX_TERMINAL_FONT_SIZE)) {
      hapticBoundary();
    }
    if (persist) {
      this.persistAppearance();
    }
  }

  // M26: one-shot readout feedback — a small vertical tick up and back plus an
  // ember color flash, over 120ms total. translateY + color only, never scale
  // (CJK-safe), and it is imperative so it never leaves a residual animation.
  private playFontReadoutTick(): void {
    this.getUIContext().keyframeAnimateTo({ iterations: 1 }, [
      {
        duration: DUR_READOUT_TICK_HALF,
        curve: CURVE_SHARP,
        event: () => {
          this.fontReadoutTickY = -3;
          this.fontReadoutColor = COLOR_EMBER;
        }
      },
      {
        duration: DUR_READOUT_TICK_HALF,
        curve: CURVE_DECEL,
        event: () => {
          this.fontReadoutTickY = 0;
          this.fontReadoutColor = COLOR_TEXT_PRIMARY;
        }
      }
    ]);
  }

  @Builder
  private buildFontChoiceButton(label: string, family: string) {
    Column({ space: 4 }) {
      Text('ls -al → 终端 0Oo')
        .fontSize(13.5)
        .fontColor(COLOR_TEXT_PRIMARY)
        // Preview the sample in its own family so the picker is WYSIWYG; the
        // custom slot uses the family name registered by the renderer.
        .fontFamily(family)
        .maxLines(1)
      Text(label)
        .fontSize(11)
        .fontColor(this.fontFamily === family ? COLOR_EMBER : COLOR_TEXT_SECONDARY)
      Row()
        .width('100%')
        .height(2)
        .borderRadius(1)
        .backgroundColor(this.fontFamily === family ? COLOR_EMBER : '#00000000')
        .shadow(this.fontFamily === family
          ? { radius: 6, color: COLOR_EMBER_GLOW, offsetX: 0, offsetY: 0 }
          : { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 })
        // M06 selected-filament: fade the copper + glow.
        .animation({ duration: DUR_STANDARD, curve: CURVE_DECEL })
    }
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 12, right: 12, top: 10, bottom: 6 })
    .borderRadius(10)
    .backgroundColor(COLOR_PANEL_2)
    .border({ width: 1, color: this.fontFamily === family ? COLOR_EMBER : COLOR_PANEL_BORDER })
    // M07 selected-face: fast border-color settle ahead of the filament.
    .animation({ duration: DUR_FAST, curve: CURVE_SHARP })
    .clip(true)
    .layoutWeight(1)
    .onClick(() => {
      this.selectFontFamily(family);
    })
  }

  private selectFontFamily(family: string): void {
    if (this.fontFamily === family) {
      return;
    }
    this.fontFamily = family;
    this.applyFontFamilyConfig();
    this.persistAppearance();
  }

  private applyFontFamilyConfig(): void {
    for (const session of this.sessions) {
      session.controller.updateConfig({ fontFamily: this.fontFamily });
    }
  }

  private normalizeFontFamily(family: string): string {
    const known: string[] = [FONT_FAMILY_MAPLE, FONT_FAMILY_JETBRAINS, FONT_FAMILY_CASCADIA,
      FONT_FAMILY_SARASA, FONT_FAMILY_SYSTEM, FONT_FAMILY_CUSTOM];
    for (const candidate of known) {
      if (candidate === family) {
        return family;
      }
    }
    return DEFAULT_APPEARANCE.fontFamily;
  }

  private persistConnection(): void {
    const snapshot: ConnectionSettings = {
      host: this.draftHost,
      port: this.draftPort,
      token: this.draftAgentToken,
      sshPort: this.draftSshPort,
      user: this.draftUser
    };
    this.connectionStore.save(snapshot).catch((err: Object) => {
      console.error('Failed to persist connection settings: ' + JSON.stringify(err));
    });
  }

  private sendAccessoryKey(key: string): void {
    let value = '';
    switch (key) {
      case '←':
        value = '\u001b[D';
        break;
      case '↑':
        value = '\u001b[A';
        break;
      case '↓':
        value = '\u001b[B';
        break;
      case '→':
        value = '\u001b[C';
        break;
      case 'PgUp':
        value = '\u001b[5~';
        break;
      case 'PgDn':
        value = '\u001b[6~';
        break;
      default:
        break;
    }
    if (value.length > 0) {
      this.activeSession().controller.write(value);
    }
  }

  private surfaceBackdropColor(): string {
    return this.backgroundImagePath.length > 0 ? '#00000000' : COLOR_APP_BG;
  }

  private customFontLabel(): string {
    if (this.customFontPath.length === 0) {
      return 'Maple Mono NF CN(默认)';
    }
    return this.fileDisplayName(this.customFontPath);
  }

  private fileDisplayName(path: string): string {
    const slash = path.lastIndexOf('/');
    return slash >= 0 ? path.substring(slash + 1) : path;
  }

  private openNewWindow(): void {
    if (!this.context) {
      return;
    }
    const want: Want = {
      bundleName: this.context.abilityInfo.bundleName,
      abilityName: this.context.abilityInfo.name
    };
    this.context.startAbility(want).catch((err: Object) => {
      console.error('Failed to open new terminal window: ' + JSON.stringify(err));
    });
  }

  private async loadAppearance(): Promise<void> {
    if (!this.context) {
      return;
    }
    try {
      const settings = await this.appearanceStore.load(this.context);
      this.fontSize = settings.fontSize;
      this.fontFamily = this.normalizeFontFamily(settings.fontFamily);
      this.themeName = settings.themeName;
      this.customFontPath = settings.customFontPath;
      this.backgroundImagePath = settings.backgroundImagePath;
      this.backgroundOpacity = settings.backgroundOpacity;
      this.backgroundBlur = settings.backgroundBlur;
      this.cursorStyle = settings.cursorStyle;
      this.cursorBlink = settings.cursorBlink;
      this.pasteDirUri = settings.pasteDirUri;
      void this.activatePasteDirPermission();
      const conn = await this.connectionStore.load(this.context, {
        host: this.draftHost,
        port: this.draftPort,
        token: this.draftAgentToken,
        sshPort: this.draftSshPort,
        user: this.draftUser
      });
      this.draftHost = conn.host;
      this.draftPort = conn.port;
      this.draftAgentToken = conn.token;
      this.draftSshPort = conn.sshPort;
      this.draftUser = conn.user;
      for (const session of this.sessions) {
        session.controller.setTheme(this.themeName);
        session.controller.updateConfig({
          fontSize: this.fontSize,
          fontFamily: this.fontFamily,
          cursorStyle: this.cursorStyle,
          cursorBlink: this.cursorBlink
        });
      }
      this.applyBackgroundConfig();
      this.applyCustomFont();
    } catch (err) {
      console.error('Failed to load appearance settings: ' + JSON.stringify(err));
    } finally {
      // Auto-connect waits for the persisted endpoint; run it even when the
      // settings load fails so tabs never hang in demo mode forever.
      this.connectionSettingsLoaded = true;
      this.tryAutoConnectAllSessions();
    }
  }

  private persistAppearance(): void {
    const snapshot: AppearanceSettings = {
      fontSize: this.fontSize,
      fontFamily: this.fontFamily,
      themeName: this.themeName,
      customFontPath: this.customFontPath,
      backgroundImagePath: this.backgroundImagePath,
      backgroundOpacity: this.backgroundOpacity,
      backgroundBlur: this.backgroundBlur,
      cursorStyle: this.cursorStyle,
      cursorBlink: this.cursorBlink,
      pasteDirUri: this.pasteDirUri
    };
    this.appearanceStore.save(snapshot).catch((err: Object) => {
      console.error('Failed to persist appearance settings: ' + JSON.stringify(err));
    });
  }

  private applyBackgroundConfig(): void {
    const effectiveOpacity = this.backgroundImagePath.length > 0 ? this.backgroundOpacity : 1;
    for (const session of this.sessions) {
      session.controller.updateConfig({ bgOpacity: effectiveOpacity });
    }
  }

  private applyCustomFont(): void {
    for (const session of this.sessions) {
      this.applyCustomFontTo(session);
    }
  }

  private applyCustomFontTo(session: TerminalSessionHandle): void {
    if (this.customFontPath.length === 0 || !session.controller.isAttached()) {
      return;
    }
    try {
      if (!fs.accessSync(this.customFontPath)) {
        return;
      }
    } catch (_err) {
      return;
    }
    if (!session.controller.registerCustomFont(this.customFontPath)) {
      console.error('Failed to register custom terminal font: ' + this.customFontPath);
    }
  }

  private async pickCustomFont(): Promise<void> {
    if (!this.context) {
      return;
    }
    try {
      const documentPicker = new picker.DocumentViewPicker();
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['.ttf', '.otf'];
      const uris = await documentPicker.select(options);
      if (!uris || uris.length === 0) {
        return;
      }

      const fontDir = `${this.context.filesDir}/fonts`;
      if (!fs.accessSync(fontDir)) {
        fs.mkdirSync(fontDir);
      }
      const suffix = uris[0].toLowerCase().endsWith('.otf') ? '.otf' : '.ttf';
      const destPath = `${fontDir}/CustomTerminalFont-${Date.now()}${suffix}`;
      const srcFile = fs.openSync(uris[0], fs.OpenMode.READ_ONLY);
      fs.copyFileSync(srcFile.fd, destPath);
      fs.closeSync(srcFile);

      const previousPath = this.customFontPath;
      this.customFontPath = destPath;
      this.fontFamily = FONT_FAMILY_CUSTOM;
      this.applyCustomFont();
      this.applyFontFamilyConfig();
      this.persistAppearance();
      this.removeOwnedFile(previousPath);
    } catch (err) {
      console.error('Failed to import custom font: ' + JSON.stringify(err));
    }
  }

  private clearCustomFont(): void {
    const previousPath = this.customFontPath;
    this.customFontPath = '';
    this.persistAppearance();
    this.removeOwnedFile(previousPath);
    console.info('Custom font cleared; default font returns after restart');
  }

  private async pickBackgroundImage(): Promise<void> {
    if (!this.context) {
      return;
    }
    try {
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result = await photoPicker.select(options);
      if (!result || result.photoUris.length === 0) {
        return;
      }

      const destPath = `${this.context.filesDir}/background-${Date.now()}.img`;
      const srcFile = fs.openSync(result.photoUris[0], fs.OpenMode.READ_ONLY);
      fs.copyFileSync(srcFile.fd, destPath);
      fs.closeSync(srcFile);

      const previousPath = this.backgroundImagePath;
      this.backgroundImagePath = destPath;
      this.applyBackgroundConfig();
      this.persistAppearance();
      this.removeOwnedFile(previousPath);
    } catch (err) {
      console.error('Failed to choose background image: ' + JSON.stringify(err));
    }
  }

  private clearBackgroundImage(): void {
    const previousPath = this.backgroundImagePath;
    this.backgroundImagePath = '';
    this.applyBackgroundConfig();
    this.persistAppearance();
    this.removeOwnedFile(previousPath);
  }

  private removeOwnedFile(path: string): void {
    if (!this.context || path.length === 0 || !path.startsWith(this.context.filesDir)) {
      return;
    }
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (err) {
      console.error('Failed to remove replaced file: ' + JSON.stringify(err));
    }
  }
}
