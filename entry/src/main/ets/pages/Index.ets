import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { notificationManager } from '@kit.NotificationKit';
import { fileIo as fs, fileShare, fileUri, picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { util } from '@kit.ArkTS';
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
import { WindowRegistration, sessionRegistry } from '../model/SessionRegistry';
import { AppearanceSettings, AppearanceStore, DEFAULT_APPEARANCE } from '../settings/AppearanceStore';
import { ConnectionSettings, ConnectionStore } from '../settings/ConnectionStore';
import {
  CURVE_ACCEL,
  CURVE_DECEL,
  CURVE_SHARP,
  CURVE_SINE,
  DUR_AMBIENT,
  DUR_BREATHE_HALF,
  DUR_FAST,
  DUR_STANDARD,
  FRAME_60,
  SPRING_SETTLE
} from '../theme/EmberMotion';
import {
  CHROME_TOKENS_KEY,
  ChromeTokens,
  DEFAULT_CHROME_TOKENS,
  EFFECTIVE_THEME_KEY,
  SYS_DARK_KEY,
  deriveChromeTokens
} from '../theme/ChromeTheme';
import { hapticBoundary } from '../common/EmberHaptics';
import { keepAlive } from '../common/KeepAliveManager';

// Chrome colors are theme-derived ChromeTokens (see theme/ChromeTheme.ets);
// no fixed chrome palette exists any more.
const MIN_TERMINAL_FONT_SIZE: number = 10;
const MAX_TERMINAL_FONT_SIZE: number = 26;
const MIN_BACKGROUND_OPACITY_PCT: number = 0;
const MAX_BACKGROUND_BLUR: number = 60;
const FOREGROUND_FOCUS_EVENT: string = 'fusionTermForeground';
const BACKGROUND_EVENT: string = 'fusionTermBackground';
const CHROME_MODE_EVENT: string = 'fusionTermChromeMode';
// The tab strip doubles as the custom window chrome: EntryAbility hides the
// system decor bar and reserves its height, so the strip must match it and
// keep the top-right corner free for the floating system window buttons.
const WINDOW_CHROME_HEIGHT: number = 48;
const WINDOW_DECOR_BUTTON_RESERVE: number = 148;
const INSPECTOR_COMPACT_WIDTH: number = 352;
const INSPECTOR_DEFAULT_WIDTH: number = 400;
const INSPECTOR_BREAKPOINT: number = 900;
const THEME_PREVIEW_BATCH_SIZE: number = 24;
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
const TAB_STRIP_END_OFFSET_VP: number = 100000;// Bundled terminal font aliases shared by the native renderer and ArkUI picker;
// the custom slot is filled by a user-imported ttf/otf.
const FONT_FAMILY_MAPLE: string = 'FusionTerm Maple Mono';
const FONT_FAMILY_JETBRAINS: string = 'FusionTerm JetBrains Mono';
const FONT_FAMILY_CASCADIA: string = 'FusionTerm Cascadia Mono';
const FONT_FAMILY_SARASA: string = 'FusionTerm Sarasa Fixed SC';
const FONT_FAMILY_SYSTEM: string = 'PingFang SC';
const FONT_FAMILY_CUSTOM: string = 'FusionTerm Custom';
// Chrome-style responsive tab geometry. Tabs share the visible strip equally,
// grow only to the desktop-friendly cap, then stop shrinking at the touch-safe
// minimum and let the existing horizontal Scroll handle overflow.
const TAB_STRIP_GAP_VP: number = 4;
const TAB_CHIP_MIN_WIDTH_VP: number = 64;
const TAB_CHIP_MAX_WIDTH_VP: number = 210;
const TAB_NEW_BUTTON_WIDTH_VP: number = 40;
// "Move to window" adoption defers a couple frames so the source strip
// finishes unmounting the surface before the target mounts the SAME
// surfaceId -- same-vsync mount/unmount native ordering is undefined
// (docs/tab-tearoff-plan.md risk; the direct same-thread deliver hit it).
const TAB_MOVE_ADOPT_DELAY_MS: number = 32;

interface ThemePreview {
  bg: string;
  fg: string;
  red: string;
  ansi: string[];
}

// Theme selection and preview data are observed per row. Keeping these values
// out of page-level @State prevents a theme click or one preview read from
// invalidating the entire catalogue.
@Observed
class ThemeOptionState {
  readonly name: string;
  selected: boolean;
  preview: ThemePreview | null = null;

  constructor(name: string, selected: boolean) {
    this.name = name;
    this.selected = selected;
  }
}

@Component
struct ThemeOptionRow {
  @StorageProp(CHROME_TOKENS_KEY) chrome: ChromeTokens = DEFAULT_CHROME_TOKENS;
  @ObjectLink option: ThemeOptionState;
  @Prop canFocus: boolean;
  onSelect: (theme: string) => void = () => {};

  private previewBackground(): string {
    const preview: ThemePreview | null = this.option.preview;
    return preview ? preview.bg : this.chrome.panelBg2;
  }

  private previewForeground(): string {
    const preview: ThemePreview | null = this.option.preview;
    return preview ? preview.fg : this.chrome.textSecondary;
  }

  private previewAnsi(): string[] {
    const preview: ThemePreview | null = this.option.preview;
    return preview ? preview.ansi : [];
  }

  build() {
    Row({ space: 12 }) {
      Stack() {
        Text('Aa')
          .fontSize(12)
          .fontColor(this.previewForeground())
      }
      .width(52)
      .height(32)
      .borderRadius(7)
      .backgroundColor(this.previewBackground())
      .border({ width: 1, color: this.chrome.panelBorder })

      Column({ space: 4 }) {
        Text(this.option.name.split('_').join(' '))
          .fontSize(12.5)
          .fontColor(this.chrome.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 3 }) {
          ForEach(this.previewAnsi(),
            (dotColor: string, idx: number) => {
              Circle({ width: 7, height: 7 })
                .fill(dotColor)
            }, (dotColor: string, idx: number) => `${this.option.name}-${idx}`)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Row()
        .width(14)
        .height(2)
        .borderRadius(1)
        .backgroundColor(this.option.selected ? this.chrome.textPrimary : '#00000000')
        // Neutral selected underline fade (accent system retired).
        .animation({ duration: DUR_STANDARD, curve: CURVE_DECEL })
    }
    .width('100%')
    .padding({ left: 8, right: 10, top: 6, bottom: 6 })
    .borderRadius(8)
    .backgroundColor(this.option.selected ? this.chrome.panelBg2 : '#00000000')
    // M07 selected-face: fast face settle ahead of the underline.
    .animation({ duration: DUR_FAST, curve: CURVE_SHARP })
    .focusable(this.canFocus)
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => {
      this.onSelect(this.option.name);
    })
  }
}

// A ghostty-macOS style tab: an equal-share slot in the strip whose active
// face is a floating pill capsule over the theme-derived bar material.
// Connection state is a small neutral dot (solid = connected, breathing =
// connecting, hollow = disconnected, theme ANSI red = failed) -- the filament
// accent system is retired, no fixed accent color anywhere.
@Component
struct TerminalTabChip {
  @StorageProp(CHROME_TOKENS_KEY) chrome: ChromeTokens = DEFAULT_CHROME_TOKENS;
  // Deep-observed so any session field change re-renders the chip; the @Watch
  // only gates the connecting-dot breathing loop now.
  @ObjectLink @Watch('onSessionSignal') session: TerminalSessionHandle;
  @Prop active: boolean;
  @Prop @Watch('onAppBackgroundedChanged') appBackgrounded: boolean;
  // The page computes one shared equal-split width from the live strip viewport
  // and session count. Width changes are deliberately instantaneous relayouts.
  @Prop chipWidth: number;
  // In-track reorder offset (vp). The page owns the drag state and hands each chip
  // its current horizontal offset as a plain value @Prop so a parent @State change
  // always re-syncs it (a nested @Observed field would NOT re-sync a @Prop).
  @Prop translateX: number;
  // True only for the chip currently under the finger: lift it above neighbours.
  @Prop lifted: boolean;
  // Live-window registry stamp of the owning window, for the move-to-window
  // submenu (excludes this window from its own list).
  @Prop windowStamp: number = 0;
  onSelect: () => void = () => {};
  onClose: () => void = () => {};
  onEdit: () => void = () => {};
  onSplitWindow: () => void = () => {};
  onMoveToWindow: (stamp: number) => void = () => {};
  onReorderStart: () => void = () => {};
  onReorderUpdate: (offsetX: number) => void = () => {};
  onReorderEnd: () => void = () => {};
  onReorderCancel: () => void = () => {};

  // Connecting-state breathing: drives the dot opacity inside a calm band.
  // Bound after the dot's .animation() scope so only the explicit animateTo
  // loop moves it.
  @State private dotOpacity: number = 1;
  private breathing: boolean = false;
  @State private hovered: boolean = false;
  private lastPending: boolean = false;

  // "Connecting" (first connect or reconnect in flight) is visually distinct
  // from "dead": the dot breathes instead of hollowing out.
  private isPending(): boolean {
    return !this.session.connected &&
      (this.session.statusLabel.includes('重连') || this.session.statusLabel.includes('正在连接'));
  }

  // A connection that dropped with an error and is not retrying shows the
  // theme's ANSI red -- the only non-fg color in the chrome.
  private isFailed(): boolean {
    return !this.session.connected && this.session.hadError && !this.isPending();
  }

  private dotColor(): string {
    if (this.isFailed()) {
      return this.chrome.dotFailed;
    }
    if (this.session.connected || this.isPending()) {
      return this.chrome.dotOn;
    }
    return this.chrome.dotOff;
  }

  // Plain disconnect (no error, not retrying) renders as a hollow ring.
  private isHollow(): boolean {
    return !this.session.connected && !this.isPending() && !this.isFailed();
  }

  // Unread lifts an inactive tab's title to the primary text color so a
  // finished background task reads at a glance.
  private titleColor(): string {
    if (this.active || this.session.unread) {
      return this.chrome.textPrimary;
    }
    return this.chrome.textSecondary;
  }

  // Single reactive entry point: gate the breathing loop on the pending edge.
  private onSessionSignal(): void {
    if (this.appBackgrounded) {
      this.stopBreathing();
      this.lastPending = this.isPending();
      return;
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

  private onAppBackgroundedChanged(): void {
    if (this.appBackgrounded) {
      this.stopBreathing();
      return;
    }
    this.lastPending = false;
    this.onSessionSignal();
  }

  // Status-gated loop (the only permitted looping animation family): runs while
  // connecting, stops on the connected/dead edge, never while backgrounded.
  private startBreathing(): void {
    if (this.breathing || this.appBackgrounded) {
      return;
    }
    this.breathing = true;
    this.dotOpacity = 0.9;
    this.getUIContext().animateTo(
      {
        duration: DUR_BREATHE_HALF,
        curve: CURVE_SINE,
        iterations: -1,
        playMode: PlayMode.Alternate,
        expectedFrameRateRange: FRAME_60
      },
      () => {
        this.dotOpacity = 0.25;
      });
  }

  private stopBreathing(): void {
    if (!this.breathing) {
      return;
    }
    this.breathing = false;
    this.getUIContext().animateTo(
      { duration: DUR_STANDARD, curve: CURVE_DECEL },
      () => {
        this.dotOpacity = 1;
      });
  }

  aboutToDisappear(): void {
    this.breathing = false;
  }

  build() {
    Row({ space: 7 }) {
      Row()
        .width(6)
        .height(6)
        .borderRadius(3)
        .backgroundColor(this.isHollow() ? '#00000000' : this.dotColor())
        .border({ width: 1, color: this.isHollow() ? this.dotColor() : '#00000000' })
        .flexShrink(0)
        .opacity(this.dotOpacity)
      Text(this.session.title)
        .fontSize(12.5)
        .fontColor(this.titleColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .flexShrink(1)
      Image($r('app.media.ic_close_faint'))
        .width(12)
        .height(12)
        .accessibilityText('关闭标签')
        .flexShrink(0)
        // Keep the 12vp glyph but expand the touch target without changing
        // the pill layout; hidden (but space-stable) unless usable.
        .responseRegion({ x: -10, y: -10, width: 32, height: 32 })
        .visibility(this.hovered || this.active ? Visibility.Visible : Visibility.Hidden)
        .onClick(() => {
          this.onClose();
        })
    }
    .justifyContent(FlexAlign.Center)
    .height(34)
    .borderRadius(999)
    .padding({ left: 14, right: 10 })
    .backgroundColor(this.active
      ? this.chrome.capBg
      : (this.hovered ? this.chrome.hoverBg : '#00000000'))
    .border({
      width: 1,
      color: this.active ? this.chrome.capBorder : '#00000000'
    })
    .accessibilityText(`${this.active ? '当前标签, ' : ''}${this.session.title}, ${this.session.statusLabel}${this.session.unread ? ', 后台任务完成' : ''}`)
    // The active capsule floats on a soft neutral shadow; while dragged the
    // lift deepens. Never scale -- CJK titles must not rasterize.
    .shadow(this.lifted
      ? { radius: 12, color: '#66000000', offsetX: 0, offsetY: 3 }
      : (this.active
        ? { radius: 5, color: this.chrome.capShadowColor, offsetX: 0, offsetY: 1 }
        : { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 }))
    .onHover((isHover: boolean) => {
      this.hovered = isHover;
    })
    // Capsule face/border fade rather than a hard cut on tab switch.
    .animation({ duration: DUR_FAST, curve: CURVE_SHARP })
    // Keep the equal-split width OUTSIDE the implicit animation above:
    // opening/closing tabs and free-window resize reflow once, not per frame.
    .width(this.chipWidth)
    // In-track reorder offset. Placed AFTER .animation() so the implicit tween
    // never captures it (finger-follow must be zero-delay).
    .translate({ x: this.translateX })
    .zIndex(this.lifted ? 3 : 0)
    .focusable(false)
    .onClick(() => {
      this.onSelect();
    })
    // In-track reorder: 1-finger horizontal pan (grab on 8vp move) forwarded to
    // the page, which owns the session list + offsets.
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 8 })
        .onActionStart((_event: GestureEvent): void => {
          this.onReorderStart();
        })
        .onActionUpdate((event: GestureEvent): void => {
          this.onReorderUpdate(Number(event.offsetX ?? 0));
        })
        .onActionEnd((_event: GestureEvent): void => {
          this.onReorderEnd();
        })
        .onActionCancel((_event: GestureEvent): void => {
          this.onReorderCancel();
        })
    )
    // Touch pick-up: a long press lifts the chip into the same in-track drag
    // the pan drives (press-and-hold to move, macOS style); the parallel pan
    // takes over finger-follow once the finger travels. Releasing without
    // moving settles the chip back in place. Both end paths are idempotent.
    .parallelGesture(
      LongPressGesture({ fingers: 1, repeat: false })
        .onAction((_event: GestureEvent): void => {
          this.onReorderStart();
        })
        .onActionEnd((_event: GestureEvent): void => {
          this.onReorderEnd();
        })
        .onActionCancel((_event: GestureEvent): void => {
          this.onReorderCancel();
        })
    )
    // Touch rename: double-tap opens the tab editor (long-press now means
    // "pick up", so the editor moved off it; right-click stays the 2-in-1
    // primary path). The first tap's onClick activating the tab first is fine.
    .parallelGesture(
      TapGesture({ count: 2 })
        .onAction((_event: GestureEvent): void => {
          this.onEdit();
        })
    )
    .bindContextMenu(this.buildTabContextMenu(), ResponseType.RightClick)
    // Asymmetric add/remove: a new pill fades + slides in from the right;
    // closing is quicker and plainer so remaining tabs settle without fuss.
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.OPACITY
        .combine(TransitionEffect.translate({ x: 12 }))
        .animation({ duration: DUR_STANDARD, curve: CURVE_DECEL }),
      TransitionEffect.OPACITY
        .animation({ duration: DUR_FAST, curve: CURVE_ACCEL })
    ))
  }

  // Right-click / long-press tab menu: rename and close, desktop-terminal
  // restraint (no icons, no accent).
  @Builder
  private buildTabContextMenu() {
    Menu() {
      MenuItem({ content: '标签设置' })
        .onClick(() => {
          this.onEdit();
        })
      MenuItem({ content: '拆分为新窗口' })
        .onClick(() => {
          this.onSplitWindow();
        })
      if (sessionRegistry.listWindows(this.windowStamp).length > 0) {
        MenuItem({ content: '移动到窗口…', builder: (): void => { this.buildMoveToWindowMenu() } })
      }
      MenuItem({ content: '关闭标签' })
        .onClick(() => {
          this.onClose();
        })
    }
  }

  // Live window list evaluated when the menu opens (multiton shared heap).
  @Builder
  private buildMoveToWindowMenu() {
    Menu() {
      ForEach(sessionRegistry.listWindows(this.windowStamp), (reg: WindowRegistration) => {
        MenuItem({ content: `${reg.label} · ${reg.tabCount()} 标签` })
          .onClick(() => {
            this.onMoveToWindow(reg.stamp);
          })
      }, (reg: WindowRegistration) => String(reg.stamp))
    }
  }

}

// Solo-tab title: the strip's single-tab mode. This MUST be its own component
// with an @ObjectLink. The old page-level builder read this.sessions[0].title
// directly, which gives ArkUI no deep observation of the @Observed handle --
// title/status edges froze until an unrelated page @State happened to
// re-render (device evidence 2026-07-28: driver logged connected=true while
// the title stayed on 正在连接). Same family as the moved-tab stale title.
@Component
struct SoloTabTitle {
  @StorageProp(CHROME_TOKENS_KEY) chrome: ChromeTokens = DEFAULT_CHROME_TOKENS;
  @ObjectLink @Watch('onSessionSignal') session: TerminalSessionHandle;
  @Prop @Watch('onAppBackgroundedChanged') appBackgrounded: boolean;
  @Prop windowStamp: number = 0;
  @Prop soloWidth: number;
  onEdit: () => void = () => {};
  onClose: () => void = () => {};
  onMoveToWindow: (stamp: number) => void = () => {};

  @State private dotOpacity: number = 1;
  private breathing: boolean = false;
  private lastPending: boolean = false;

  private isPending(): boolean {
    return !this.session.connected &&
      (this.session.statusLabel.includes('重连') || this.session.statusLabel.includes('正在连接'));
  }

  private isFailed(): boolean {
    return !this.session.connected && this.session.hadError && !this.isPending();
  }

  private dotColor(): string {
    if (this.isFailed()) {
      return this.chrome.dotFailed;
    }
    if (this.session.connected || this.isPending()) {
      return this.chrome.dotOn;
    }
    return this.chrome.dotOff;
  }

  private isHollow(): boolean {
    return !this.session.connected && !this.isPending() && !this.isFailed();
  }

  private onSessionSignal(): void {
    if (this.appBackgrounded) {
      this.stopBreathing();
      this.lastPending = this.isPending();
      return;
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

  private onAppBackgroundedChanged(): void {
    if (this.appBackgrounded) {
      this.stopBreathing();
      return;
    }
    this.lastPending = false;
    this.onSessionSignal();
  }

  private startBreathing(): void {
    if (this.breathing || this.appBackgrounded) {
      return;
    }
    this.breathing = true;
    this.dotOpacity = 0.9;
    this.getUIContext().animateTo(
      {
        duration: DUR_BREATHE_HALF,
        curve: CURVE_SINE,
        iterations: -1,
        playMode: PlayMode.Alternate,
        expectedFrameRateRange: FRAME_60
      },
      () => {
        this.dotOpacity = 0.25;
      });
  }

  private stopBreathing(): void {
    if (!this.breathing) {
      return;
    }
    this.breathing = false;
    this.getUIContext().animateTo(
      { duration: DUR_STANDARD, curve: CURVE_DECEL },
      () => {
        this.dotOpacity = 1;
      });
  }

  aboutToDisappear(): void {
    this.breathing = false;
  }

  build() {
    Row({ space: 7 }) {
      Row()
        .width(6)
        .height(6)
        .borderRadius(3)
        .backgroundColor(this.isHollow() ? '#00000000' : this.dotColor())
        .border({ width: 1, color: this.isHollow() ? this.dotColor() : '#00000000' })
        .flexShrink(0)
        .opacity(this.dotOpacity)
      Text(this.session.title)
        .fontSize(12.5)
        .fontColor(this.chrome.textSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .flexShrink(1)
    }
    .justifyContent(FlexAlign.Center)
    .height(34)
    .width(this.soloWidth)
    .focusable(false)
    .bindContextMenu(this.buildSoloTabContextMenu(), ResponseType.RightClick)
    .parallelGesture(
      LongPressGesture({ fingers: 1, repeat: false })
        .onAction((_event: GestureEvent): void => {
          this.onEdit();
        })
    )
  }

  @Builder
  private buildSoloTabContextMenu() {
    Menu() {
      MenuItem({ content: '标签设置' })
        .onClick(() => {
          this.onEdit();
        })
      if (sessionRegistry.listWindows(this.windowStamp).length > 0) {
        MenuItem({ content: '移动到窗口…', builder: (): void => { this.buildSoloMoveMenu() } })
      }
      MenuItem({ content: '关闭标签' })
        .onClick(() => {
          this.onClose();
        })
    }
  }

  @Builder
  private buildSoloMoveMenu() {
    Menu() {
      ForEach(sessionRegistry.listWindows(this.windowStamp), (reg: WindowRegistration) => {
        MenuItem({ content: `${reg.label} · ${reg.tabCount()} 标签` })
          .onClick(() => {
            this.onMoveToWindow(reg.stamp);
          })
      }, (reg: WindowRegistration) => String(reg.stamp))
    }
  }

}

// wand-agent deploy walkthrough used by the explicit Help & Diagnostics panel.
// Keep the systemd unit in one constant so the copyable command never drifts.
const AGENT_GUIDE_SERVICE_UNIT: string =
  '[Unit]\n' +
  'Description=wand-agent WebSocket PTY for Emberline\n' +
  'After=network-online.target\n' +
  '\n' +
  '[Service]\n' +
  'ExecStart=/usr/local/bin/wand-agent --host 172.16.100.2 --token 你的token\n' +
  'Restart=always\n' +
  'RestartSec=2\n' +
  '\n' +
  '[Install]\n' +
  'WantedBy=multi-user.target';

const CODEX_TASK_NOTIFICATION_CONFIG: string =
  '[tui]\n' +
  'notifications = ["agent-turn-complete"]\n' +
  'notification_method = "osc9"\n' +
  'notification_condition = "always"';
const CODEX_TMUX_NOTIFICATION_SETUP_COMMAND: string =
  "grep -qxF 'set -g allow-passthrough on' ~/.tmux.conf 2>/dev/null || " +
  "printf '\\nset -g allow-passthrough on\\n' >> ~/.tmux.conf\n" +
  'tmux source-file ~/.tmux.conf';
const CODEX_TASK_NOTIFICATION_TEST_COMMAND: string =
  "(sleep 5; if [ -n \"$TMUX\" ]; then " +
  "printf '\\033Ptmux;\\033\\033]9;Emberline Codex notification test\\007\\033\\\\'; else " +
  "printf '\\033]9;Emberline Codex notification test\\007'; fi) &";
const TASK_NOTIFICATION_TEST_ID: number = 1000000;

@Entry
@Component
struct Index {
  // Theme-derived chrome tokens: replaced wholesale whenever the effective
  // terminal theme changes so every chrome surface re-colors in one pass.
  @StorageLink(CHROME_TOKENS_KEY) chrome: ChromeTokens = DEFAULT_CHROME_TOKENS;
  // System light/dark from EntryAbility.onConfigurationUpdate; picks which
  // of the two configured themes is in effect (ghostty light:/dark: model).
  @StorageProp(SYS_DARK_KEY) @Watch('onSystemColorModeChanged') sysDark: boolean = true;
  // The effective theme of whichever window last changed it. A sibling window
  // re-colours its own terminals from here so the tab bar and the grid never
  // disagree (the chrome tokens themselves are already shared via StorageLink).
  @StorageProp(EFFECTIVE_THEME_KEY) @Watch('onSharedThemeChanged') sharedTheme: string = '';
  @State private sessions: TerminalSessionHandle[] = [];
  @State private activeSessionId: number = 0;
  private nextSessionId: number = 1;
  // Drives the horizontal tab strip so a newly added tab can be scrolled into
  // view past the right edge.
  private tabScroller: Scroller = new Scroller();
  private context: common.UIAbilityContext | null = null;
  // In-track tab reorder state (application-level drag, no system drag pipeline).
  // draggingSessionId is the chip under the finger (-1 = idle); dragFromIndex its
  // original slot; dragTargetIndex the current hover slot (insertion index among the
  // OTHER chips, 0..n-1); dragDx is the raw finger-follow translation in vp.
  @State private draggingSessionId: number = -1;
  // This window's live registration stamp in the process-global registry.
  private windowStamp: number = 0;
  @State private dragTargetIndex: number = -1;
  @State private dragDx: number = 0;
  private dragFromIndex: number = -1;
  // True from finger-up until the settle animation's onFinish has committed the
  // reorder. The pan and the long-press BOTH end on finger-up, so endTabDrag /
  // cancelTabDrag can be entered twice for one gesture; draggingSessionId only
  // clears inside that onFinish and therefore cannot guard the gap on its own.
  private dragSettling: boolean = false;
  @State private tabStripViewportWidth: number =
    TAB_CHIP_MAX_WIDTH_VP + TAB_NEW_BUTTON_WIDTH_VP + TAB_STRIP_GAP_VP;
  @State private drawerOpen: boolean = false;
  @State private drawerShown: boolean = false;
  @State private drawerPane: string = 'terminal';
  @State private workspaceWidth: number = 960;
  @State private workbenchFocusZone: number = 0;
  @State private connectionTipVisible: boolean = false;
  @State private settingsTipVisible: boolean = false;
  @State private moreTipVisible: boolean = false;
  @State private newTabTipVisible: boolean = false;
  @State private hoveredChromeAction: string = '';
  @State private focusedChromeAction: string = '';
  @State private tabEditOpen: boolean = false;
  @State private agentGuideOpen: boolean = false;
  @State private connectionAdvancedOpen: boolean = false;
  @State private connectionErrorDetailsOpen: boolean = false;
  @State private tabEditDraft: string = '';
  @State private editingPasteMode: string = 'auto';
  @State private editingRelayTarget: string = '';
  @State private editingRelayDir: string = '';
  private editingSession: TerminalSessionHandle | null = null;
  private themePreviewsLoading: boolean = false;
  private themePreviewQueue: string[] = [];
  private themePreviewGeneration: number = 0;
  private themeOptionByName: Map<string, ThemeOptionState> = new Map();
  private themePreviewDecoder: util.TextDecoder = util.TextDecoder.create('utf-8', {
    fatal: false,
    ignoreBOM: true
  });
  private fontPreviewsRegistered: boolean = false;
  @State private draftHost: string = DEFAULT_FUSION_AGENT_HOST;
  @State private draftPort: string = String(DEFAULT_FUSION_AGENT_PORT);
  @State private draftAgentToken: string = DEFAULT_FUSION_AGENT_TOKEN;
  @State private draftSshPort: string = '22';
  @State private draftUser: string = 'user';
  @State private draftPassword: string = '';
  @State private fontSize: number = 13;
  @State private fontFamily: string = DEFAULT_APPEARANCE.fontFamily;
  // Ghostty light/dark pairing: one theme per system color mode. The
  // effective theme follows the live system mode (sysDark).
  private darkThemeName: string = 'Catppuccin_Mocha';
  private lightThemeName: string = 'Catppuccin_Latte';
  // App-level appearance override: 'system' follows the OS color mode,
  // 'dark' / 'light' pin the app to one slot regardless of the OS.
  @State private colorModeOverride: string = 'system';
  // Which slot the theme pane is editing ('dark' | 'light').
  @State private themeEditSlot: string = 'dark';
  @State private themeFilter: string = '';
  @State private themeOptions: ThemeOptionState[] = [];
  @State private themeRenderLimit: number = THEME_PREVIEW_BATCH_SIZE;
  @State private cursorStyle: number = DEFAULT_APPEARANCE.cursorStyle;
  @State private cursorBlink: boolean = DEFAULT_APPEARANCE.cursorBlink;
  @State private customFontPath: string = '';
  @State private backgroundImagePath: string = '';
  @State private backgroundOpacity: number = DEFAULT_APPEARANCE.backgroundOpacity;
  @State private backgroundBlur: number = DEFAULT_APPEARANCE.backgroundBlur;
  @State private pasteDirUri: string = DEFAULT_APPEARANCE.pasteDirUri;
  @State private foregroundFocusEpoch: number = 0;
  // Connection-pane 22x2 status-bar breathing (M09): reuses the half-lit
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
  @State private fontReadoutColor: string = DEFAULT_CHROME_TOKENS.textPrimary;
  private connectionSettingsLoaded: boolean = false;
  private appearanceStore: AppearanceStore = new AppearanceStore();
  private connectionStore: ConnectionStore = new ConnectionStore();
  private drawerTransitionEpoch: number = 0;
  private demoRendered: boolean = false;
  @State private taskNotificationEnabled: boolean = false;
  @State private taskNotificationBusy: boolean = false;
  @State private taskNotificationStatus: string = '正在检查系统通知';
  @State private appInBackground: boolean = false;
  private foregroundFocusListener: () => void = (): void => {
    this.appInBackground = false;
    this.foregroundFocusEpoch += 1;
    this.syncConnPaneBreathing();
  };
  private backgroundListener: () => void = (): void => {
    this.appInBackground = true;
    this.syncConnPaneBreathing();
  };

  aboutToAppear(): void {
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.context.eventHub.on(FOREGROUND_FOCUS_EVENT, this.foregroundFocusListener);
    this.context.eventHub.on(BACKGROUND_EVENT, this.backgroundListener);
    void this.refreshTaskNotificationState();
    // Register this window for "move to window" delivery and the live window
    // list shown in tab context menus (same-process multiton shared heap).
    // Adoption is deferred so the source window finishes unmounting the
    // surface first (see TAB_MOVE_ADOPT_DELAY_MS).
    this.windowStamp = sessionRegistry.registerWindow('', (handle: TerminalSessionHandle): void => {
      setTimeout((): void => {
        this.adoptSession(handle);
      }, TAB_MOVE_ADOPT_DELAY_MS);
    }, (): number => this.sessions.length);
    // A tab dragged out of another window arrives via a hand-off token parked in
    // the process-global SessionRegistry; adopt that live session instead of
    // spawning a blank tab. Fall back to a fresh tab on an ordinary launch.
    if (!this.tryAdoptHandoffSession()) {
      this.addSession();
    }
    void this.loadAppearance();
  }

  aboutToDisappear(): void {
    sessionRegistry.unregisterWindow(this.windowStamp);
    this.context?.eventHub.off(FOREGROUND_FOCUS_EVENT, this.foregroundFocusListener);
    this.context?.eventHub.off(BACKGROUND_EVENT, this.backgroundListener);
    this.drawerTransitionEpoch += 1;
    this.cancelThemePreviewWork();
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
      bgOpacity: this.terminalBackgroundOpacity()
    });
    session.controller.setTheme(this.effectiveThemeName());
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
    // The releasing window dropped this session's keep-alive unit, and the
    // status replay that wireSessionListeners just triggered carries NO
    // false->true edge (the session never stopped being connected), so
    // syncSessionKeepAlive cannot re-request it. Claim one directly for a
    // session that arrives already live, or the process-global ref count
    // silently loses a unit until the next reconnect -- and a moved tab that
    // is the only live session would lose background protection entirely
    // (frozen socket + swallowed task-finished notification).
    if (handle.connected && !handle.keepAliveHeld && this.context) {
      handle.keepAliveHeld = true;
      keepAlive.noteSessionActive(this.context);
    }
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
  //
  // Callers: splitSessionToNewWindow and moveSessionToWindow (the two
  // context-menu cross-window paths that survived the system-drag retirement).
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

  // Move a tab already in THIS window to a new position. Remove then insert; a
  // target to the right of the old slot shifts left by one once the tab is pulled
  // out. No transport churn -- the same controller stays live. Called by the
  // in-track drag on drop (endTabDrag), inside the settle animation's finish frame.
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

  // ── In-track tab reorder (Chrome / ghostty style: the chip follows the finger
  // inside the strip, neighbours make room, a spring lands it in the target slot).
  // No system drag, no floating snapshot -- the chip never leaves the strip. ─────

  // Chrome-style width: every tab gets an equal share of the visible strip after
  // reserving the new-tab button and the Row gaps. Tabs grow to 210vp, shrink with
  // added sessions/window resize, then hold at 64vp while the strip scrolls.
  private tabChipWidth(): number {
    const count: number = this.sessions.length;
    if (count <= 0) {
      return TAB_CHIP_MAX_WIDTH_VP;
    }
    const reservedWidth: number = TAB_NEW_BUTTON_WIDTH_VP + count * TAB_STRIP_GAP_VP;
    const sharedWidth: number = Math.max(0, this.tabStripViewportWidth - reservedWidth) / count;
    // ghostty/Safari equal split: tabs always share the whole strip; only a
    // floor guards pathological tab counts.
    return Math.max(TAB_CHIP_MIN_WIDTH_VP, sharedWidth);
  }

  private tabAdvance(): number {
    return this.tabChipWidth() + TAB_STRIP_GAP_VP;
  }

  // The horizontal offset for the chip at array index `i` during a drag. The dragged
  // chip follows the finger (dragDx, written directly -> zero delay); a chip the
  // dragged one has crossed shifts by one advance to open / close the gap; everyone
  // else sits still. Returns 0 when no drag is in flight. Passed to each chip as the
  // translateX @Prop, so a parent @State change always re-syncs it.
  private tabShiftFor(i: number): number {
    if (this.draggingSessionId < 0 || i < 0 || i >= this.sessions.length) {
      return 0;
    }
    if (this.sessions[i].id === this.draggingSessionId) {
      return this.dragDx;
    }
    const from: number = this.dragFromIndex;
    const insertAt: number = this.dragTargetIndex;
    const adv: number = this.tabAdvance();
    // Others-space index of chip i (the array with the dragged chip removed).
    const j: number = i > from ? i - 1 : i;
    // Originally right of the dragged chip, now left of it -> slide left to fill.
    if (i > from && j < insertAt) {
      return -adv;
    }
    // Originally left of the dragged chip, now right of it -> slide right to open.
    if (i < from && j >= insertAt) {
      return adv;
    }
    return 0;
  }

  // Which slot the dragged chip currently hovers, as an insertion index among the
  // OTHER chips (0..n-1). Count how many peers' centres sit left of the dragged
  // chip's live centre; all peers use the same responsive advance.
  private computeDragTargetIndex(): number {
    const from: number = this.dragFromIndex;
    const n: number = this.sessions.length;
    if (from < 0 || from >= n) {
      return Math.max(0, from);
    }
    const advance: number = this.tabAdvance();
    let left: number = 0;
    let draggedLeft: number = 0;
    const lefts: number[] = [];
    for (let k = 0; k < n; k++) {
      lefts.push(left);
      if (k === from) {
        draggedLeft = left;
      }
      left += advance;
    }
    const draggedCentre: number = draggedLeft + this.dragDx + advance / 2;
    let target: number = 0;
    for (let k = 0; k < n; k++) {
      if (k === from) {
        continue;
      }
      const centreK: number = lefts[k] + advance / 2;
      if (centreK < draggedCentre) {
        target += 1;
      }
    }
    return target;
  }

  // Where the dragged chip must spring to on drop, as a translate from its resting
  // slot: the final left edge (sum of the advances of the chips that end up left of
  // it) minus its original left edge. Applied via dragDx inside the settle animateTo
  // so the chip glides into the slot before the splice zeroes every offset.
  private dragFinalTranslate(): number {
    const from: number = this.dragFromIndex;
    const insertAt: number = this.dragTargetIndex;
    const n: number = this.sessions.length;
    const advance: number = this.tabAdvance();
    let originalLeft: number = 0;
    for (let k = 0; k < from && k < n; k++) {
      originalLeft += advance;
    }
    let finalLeft: number = 0;
    let count: number = 0;
    for (let k = 0; k < n && count < insertAt; k++) {
      if (k === from) {
        continue;
      }
      finalLeft += advance;
      count += 1;
    }
    return finalLeft - originalLeft;
  }

  private resetTabDragState(): void {
    this.draggingSessionId = -1;
    this.dragFromIndex = -1;
    this.dragTargetIndex = -1;
    this.dragDx = 0;
    this.dragSettling = false;
  }

  // Drag begin: pick up the chip. Initial target == its own slot so nothing shifts.
  private beginTabDrag(sessionId: number): void {
    const from: number = this.sessions.findIndex((s: TerminalSessionHandle) => s.id === sessionId);
    if (from < 0) {
      return;
    }
    this.dragFromIndex = from;
    this.draggingSessionId = sessionId;
    this.dragDx = 0;
    this.dragTargetIndex = from;
    this.dragSettling = false;
  }

  // Drag move: the cumulative offset is written straight to dragDx (finger follow,
  // zero delay). When the hover slot changes, animate the neighbours' let-position
  // with a spring and give one light tick so the reorder is felt as well as seen.
  private updateTabDrag(offsetX: number): void {
    if (this.draggingSessionId < 0) {
      return;
    }
    this.dragDx = offsetX;
    const nextTarget: number = this.computeDragTargetIndex();
    if (nextTarget !== this.dragTargetIndex) {
      hapticBoundary();
      this.getUIContext().animateTo(
        { duration: DUR_STANDARD, curve: SPRING_SETTLE },
        () => {
          this.dragTargetIndex = nextTarget;
        });
    }
  }

  // Drag end: spring the dragged chip into the target slot, then in the SAME finish
  // frame splice the array into its new order and zero every offset. The ForEach key
  // `tab-${id}` is stable, so the splice moves the existing chip components instead
  // of rebuilding them; because the reorder and the offset reset happen together the
  // chips are already at their final pixels when the translates drop to 0 -- no
  // flash. The reset runs OUTSIDE animateTo so it applies instantly, not as a tween.
  private endTabDrag(): void {
    // Already settling: the other gesture of the parallel pair got here first
    // and its onFinish owns the reorder. Return WITHOUT resetting -- a reset
    // here would clear the very guard that keeps the reorder single.
    if (this.dragSettling) {
      return;
    }
    if (this.draggingSessionId < 0) {
      this.resetTabDragState();
      return;
    }
    const sessionId: number = this.draggingSessionId;
    const from: number = this.sessions.findIndex((s: TerminalSessionHandle) => s.id === sessionId);
    if (from < 0) {
      this.resetTabDragState();
      return;
    }
    this.dragFromIndex = from;
    const insertAt: number = this.dragTargetIndex;
    const finalTranslate: number = this.dragFinalTranslate();
    this.dragSettling = true;
    this.getUIContext().animateTo(
      {
        duration: DUR_STANDARD,
        curve: SPRING_SETTLE,
        onFinish: () => {
          // Others-space insertAt -> full-array insert index for reorderSession.
          const fullInsert: number = insertAt <= from ? insertAt : insertAt + 1;
          this.reorderSession(from, fullInsert);
          this.resetTabDragState();
        }
      },
      () => {
        this.dragDx = finalTranslate;
      });
    this.activateSession(sessionId);
  }

  // Drag cancel (gesture interrupted): spring back to the original slot and clear.
  private cancelTabDrag(): void {
    if (this.dragSettling) {
      return;
    }
    if (this.draggingSessionId < 0) {
      this.resetTabDragState();
      return;
    }
    this.dragSettling = true;
    const from: number = this.dragFromIndex;
    this.getUIContext().animateTo(
      {
        duration: DUR_STANDARD,
        curve: SPRING_SETTLE,
        onFinish: () => {
          this.resetTabDragState();
        }
      },
      () => {
        this.dragDx = 0;
        this.dragTargetIndex = from;
      });
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

  private activeConnFailed(): boolean {
    if (this.sessions.length === 0) {
      return false;
    }
    const session: TerminalSessionHandle = this.activeSession();
    return !session.connected && !this.isSessionPending(session) && session.hadError;
  }

  private agentActionLabel(): string {
    if (this.activeConnPending()) {
      return '连接中…';
    }
    if (this.activeConnFailed()) {
      return '重试 Agent';
    }
    return this.activeConnLit() ? '重新连接 Agent' : '连接 Agent';
  }

  // M09: start/stop the conn-pane status breathing. Gated on the pane being
  // visible AND the active session connecting; stopped on connect / fail /
  // disconnect / drawer close / pane switch so no loop survives off screen.
  private syncConnPaneBreathing(): void {
    const shouldBreathe: boolean =
      this.drawerShown && this.drawerPane === 'conn' && !this.appInBackground && this.activeConnPending();
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
    return this.sessions.length > 0 &&
      !this.drawerOpen &&
      !this.tabEditOpen &&
      !this.agentGuideOpen &&
      !this.appInBackground;
  }

  private inspectorWidth(): number {
    if (this.workspaceWidth < INSPECTOR_COMPACT_WIDTH) {
      return this.workspaceWidth;
    }
    return this.workspaceWidth < INSPECTOR_BREAKPOINT
      ? INSPECTOR_COMPACT_WIDTH
      : INSPECTOR_DEFAULT_WIDTH;
  }

  private dialogWidth(preferredWidth: number): number {
    return Math.min(preferredWidth, Math.max(0, this.workspaceWidth - 32));
  }

  private openDrawer(pane: string): void {
    this.drawerTransitionEpoch += 1;
    this.drawerPane = pane;
    this.drawerOpen = true;
    this.drawerShown = true;
    // Opening the drawer reveals the target pane at full opacity: the drawer
    // slide itself carries the entrance, so reset the crossfade scalar in case a
    // prior in-drawer pane switch was interrupted mid-animation.
    this.paneT = 1;
    if (pane === 'appearance') {
      this.prepareThemePane();
    } else if (pane === 'terminal') {
      this.registerBundledFontPreviews();
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
    if (this.drawerPane === 'appearance') {
      this.cancelThemePreviewWork();
    }
    const epoch: number = this.drawerTransitionEpoch + 1;
    this.drawerTransitionEpoch = epoch;
    this.getUIContext().animateTo(
      {
        duration: DUR_PANE_OUT,
        curve: CURVE_ACCEL,
        onFinish: () => {
          if (this.drawerTransitionEpoch !== epoch || !this.drawerShown) {
            this.paneT = 1;
            return;
          }
          this.drawerPane = pane;
          if (pane === 'appearance') {
            this.prepareThemePane();
          } else if (pane === 'terminal') {
            this.registerBundledFontPreviews();
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
    if (!this.drawerOpen || !this.drawerShown) {
      return;
    }
    this.cancelThemePreviewWork();
    this.drawerShown = false;
    this.syncConnPaneBreathing();
    const epoch: number = this.drawerTransitionEpoch + 1;
    this.drawerTransitionEpoch = epoch;
    setTimeout(() => {
      if (this.drawerTransitionEpoch !== epoch || this.drawerShown) {
        return;
      }
      this.drawerOpen = false;
      // The inspector shell stays mounted for its slide transition, but its
      // heaviest pane must not survive invisibly beside the live terminal.
      this.drawerPane = 'terminal';
      this.paneT = 1;
      this.focusActiveTerminalSoon();
    }, DUR_STANDARD);
  }

  private openTabEditor(session: TerminalSessionHandle): void {
    this.editingSession = session;
    this.tabEditDraft = session.customName.length > 0 ? session.customName : session.title;
    this.editingPasteMode = session.pasteMode;
    this.editingRelayTarget = session.relayTarget;
    this.editingRelayDir = session.relayDir;
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

  // BEL / OSC 9 from a background tab means "task finished, look at me".
  // Codex emits OSC 9 after the documented TUI notification config is enabled;
  // foreground work gets an in-app toast, while background work also re-kindles
  // its tab. Every accepted event still reaches the system-notification path so
  // paired-device forwarding is not defeated merely because the app has focus.
  private handleTerminalNotification(session: TerminalSessionHandle, text: string): void {
    const now = Date.now();
    if (now - session.lastNotifyMs < 5000) {
      return;
    }
    session.lastNotifyMs = now;
    const terminalVisible = session.id === this.activeSessionId && !this.appInBackground;
    if (terminalVisible) {
      const summary = text.trim().length > 0 ? text.trim().slice(0, 80) : '终端任务完成';
      this.getUIContext().getPromptAction().showToast({
        message: `任务完成 · ${summary}`,
        duration: 1800
      });
    } else {
      // A background answer lives on the tab itself: mark it unread so the
      // title lifts to the primary text color until activated.
      session.unread = true;
    }
    void this.publishTerminalNotification(session, text);
  }

  private taskNotificationActionLabel(): string {
    if (this.taskNotificationBusy) {
      return '处理中…';
    }
    return this.taskNotificationEnabled ? '发送测试提醒' : '启用并测试';
  }

  private async refreshTaskNotificationState(): Promise<void> {
    try {
      const enabled = await notificationManager.isNotificationEnabled();
      this.taskNotificationEnabled = enabled;
      this.taskNotificationStatus = enabled ? '系统通知已启用' : '系统通知未启用';
    } catch (err) {
      this.taskNotificationEnabled = false;
      this.taskNotificationStatus = '无法读取系统通知状态';
      console.error('Failed to read terminal notification state: ' + JSON.stringify(err));
    }
  }

  private taskNotificationErrorStatus(prefix: string, error: BusinessError): string {
    if (error.code === 1600004) {
      return '系统通知授权已被拒绝,请在系统设置中重新开启';
    }
    if (error.code === 1600005) {
      return '任务提醒通知渠道已关闭,请在系统设置中重新开启';
    }
    if (error.code === 1600009) {
      return '通知发送过于频繁,请稍后重试';
    }
    return `${prefix} (${error.code}: ${error.message})`;
  }

  private async enableAndTestTaskNotification(): Promise<void> {
    if (this.taskNotificationBusy) {
      return;
    }
    this.taskNotificationBusy = true;
    try {
      let enabled = await notificationManager.isNotificationEnabled();
      if (!enabled) {
        const context = this.context;
        if (!context) {
          this.taskNotificationStatus = '当前窗口无法申请系统通知';
          this.getUIContext().getPromptAction().showToast({
            message: this.taskNotificationStatus,
            duration: 2400
          });
          return;
        }
        await notificationManager.requestEnableNotification(context);
        enabled = await notificationManager.isNotificationEnabled();
      }
      this.taskNotificationEnabled = enabled;
      if (!enabled) {
        this.taskNotificationStatus = '系统通知未启用';
        this.getUIContext().getPromptAction().showToast({
          message: this.taskNotificationStatus,
          duration: 2400
        });
        return;
      }
      await this.publishTaskNotification(
        TASK_NOTIFICATION_TEST_ID,
        'Emberline · Codex',
        '任务完成提醒已就绪'
      );
      const activeCount = await notificationManager.getActiveNotificationCount();
      this.taskNotificationStatus = `系统已接收测试通知 · 通知栏 ${activeCount} 条`;
      this.getUIContext().getPromptAction().showToast({
        message: '测试通知已提交到系统',
        duration: 1800
      });
    } catch (err) {
      const error = err as BusinessError;
      this.taskNotificationStatus = this.taskNotificationErrorStatus(
        '启用或测试系统通知失败',
        error
      );
      this.getUIContext().getPromptAction().showToast({
        message: this.taskNotificationStatus,
        duration: 2400
      });
      console.error(
        `Failed to enable or test terminal notifications: ${error.code}: ${error.message}`
      );
    } finally {
      this.taskNotificationBusy = false;
    }
  }

  private async publishTerminalNotification(session: TerminalSessionHandle, text: string): Promise<void> {
    try {
      const enabled = await notificationManager.isNotificationEnabled();
      this.taskNotificationEnabled = enabled;
      if (!enabled) {
        this.taskNotificationStatus = '系统通知未启用';
        return;
      }
      this.taskNotificationStatus = '系统通知已启用';
      await this.publishTaskNotification(
        session.surfaceSeq,
        session.title.length > 0 ? session.title : 'Emberline',
        text.length > 0 ? text : '任务完成,终端在等你'
      );
    } catch (err) {
      const error = err as BusinessError;
      this.taskNotificationStatus = this.taskNotificationErrorStatus('系统通知发布失败', error);
      console.error(`Failed to publish terminal notification: ${error.code}: ${error.message}`);
    }
  }

  private async publishTaskNotification(id: number, title: string, text: string): Promise<void> {
    await notificationManager.addSlot(notificationManager.SlotType.SERVICE_INFORMATION);
    const request: notificationManager.NotificationRequest = {
      id,
      notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title,
          text
        }
      }
    };
    await notificationManager.publish(request);
  }

  private focusActiveTerminalSoon(): void {
    this.workbenchFocusZone = 0;
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

  private requestWorkbenchFocusSoon(componentId: string): void {
    setTimeout(() => {
      try {
        focusControl.requestFocus(componentId);
      } catch (err) {
        console.error('Failed to move workbench focus: ' + JSON.stringify(err));
      }
    }, 40);
  }

  // Window-level ArkUI shortcuts run before the native XComponent key event.
  // Keep F6 for desktop keyboards and Ctrl+Alt+. for compact keyboards without
  // a function row; neither steals Tab/Shift+Tab from terminal programs.
  private cycleWorkbenchFocus(): void {
    if (this.tabEditOpen || this.agentGuideOpen) {
      return;
    }
    if (this.workbenchFocusZone === 0) {
      this.workbenchFocusZone = 1;
      this.requestWorkbenchFocusSoon('workbenchConnectionAction');
      return;
    }
    if (this.workbenchFocusZone === 1) {
      if (!this.drawerOpen) {
        this.openDrawer('terminal');
      }
      this.workbenchFocusZone = 2;
      this.requestWorkbenchFocusSoon(`workbenchInspector-${this.drawerPane}`);
      return;
    }
    this.closeDrawer();
  }

  private workbenchOverlayOpen(): boolean {
    return this.drawerOpen || this.tabEditOpen || this.agentGuideOpen;
  }

  private closeTopmostOverlay(): void {
    if (this.agentGuideOpen) {
      this.dismissAgentGuide();
    } else if (this.tabEditOpen) {
      this.commitTabEditor();
    } else if (this.drawerOpen) {
      this.closeDrawer();
    }
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

      if (this.agentGuideOpen) {
        this.buildAgentGuideScrim();
        this.buildAgentGuidePanel();
      }

      Button('')
        .width(1)
        .height(1)
        .visibility(Visibility.Hidden)
        .enabled(this.workbenchOverlayOpen())
        .focusable(false)
        .hitTestBehavior(HitTestMode.None)
        .keyboardShortcut(FunctionKey.ESC, [], () => {
          this.closeTopmostOverlay();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.chrome.appBg)
    .onAreaChange((_oldValue: Area, newValue: Area): void => {
      const width: number = Number(newValue.width ?? 0);
      if (Number.isFinite(width) && width > 0) {
        this.workspaceWidth = width;
      }
    })
    .keyboardShortcut(FunctionKey.F6, [], () => {
      this.cycleWorkbenchFocus();
    })
    .keyboardShortcut('.', [ModifierKey.CTRL, ModifierKey.ALT], () => {
      this.cycleWorkbenchFocus();
    })
  }

  @Builder
  private buildTerminalLayer() {
    Stack() {
      ForEach(this.sessions, (session: TerminalSessionHandle) => {
        Stack() {
          TerminalSurface({
            controller: session.controller,
            surfaceId: `fusionTermSurface-g${session.surfaceSeq}`,
            surfaceColor: this.surfaceBackdropColor(),
            active: session.id === this.activeSessionId &&
              !this.drawerOpen &&
              !this.tabEditOpen &&
              !this.agentGuideOpen &&
              !this.appInBackground,
            // Polling / scrollbar follow raw tab visibility: a translucent
            // drawer must not throttle the terminal still showing behind it.
            visible: session.id === this.activeSessionId && !this.appInBackground,
            appBackgrounded: this.appInBackground,
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
  }

  @Builder
  private buildTabBar() {
    Row({ space: 8 }) {
      Scroll(this.tabScroller) {
        Row({ space: TAB_STRIP_GAP_VP }) {
          if (this.sessions.length === 1) {
            SoloTabTitle({
              session: this.sessions[0],
              appBackgrounded: this.appInBackground,
              windowStamp: this.windowStamp,
              soloWidth: this.tabChipWidth(),
              onEdit: (): void => {
                this.openTabEditor(this.sessions[0]);
              },
              onClose: (): void => {
                this.closeSession(this.sessions[0].id);
              },
              onMoveToWindow: (stamp: number): void => {
                this.moveSessionToWindow(this.sessions[0].id, stamp);
              }
            })
          } else {
          ForEach(this.sessions, (session: TerminalSessionHandle, index: number) => {
            TerminalTabChip({
              session: session,
              active: session.id === this.activeSessionId,
              appBackgrounded: this.appInBackground,
              chipWidth: this.tabChipWidth(),
              // In-track drag: current horizontal offset for this chip (finger follow
              // for the dragged chip, let-position for a displaced one) and whether it
              // is the lifted chip. tabShiftFor re-reads the page drag @State, so both
              // re-sync as plain-value @Props on every parent re-render.
              translateX: this.tabShiftFor(index),
              lifted: this.draggingSessionId === session.id,
              windowStamp: this.windowStamp,
              onSelect: (): void => {
                this.activateSession(session.id, true);
              },
              onClose: (): void => {
                this.closeSession(session.id);
              },
              onEdit: (): void => {
                this.openTabEditor(session);
              },
              onSplitWindow: (): void => {
                this.splitSessionToNewWindow(session.id);
              },
              onMoveToWindow: (stamp: number): void => {
                this.moveSessionToWindow(session.id, stamp);
              },
              onReorderStart: (): void => {
                this.beginTabDrag(session.id);
              },
              onReorderUpdate: (offsetX: number): void => {
                this.updateTabDrag(offsetX);
              },
              onReorderEnd: (): void => {
                this.endTabDrag();
              },
              onReorderCancel: (): void => {
                this.cancelTabDrag();
              }
            })
          }, (session: TerminalSessionHandle) => `tab-${session.id}`)
          }

          Button() {
            Image($r('app.media.ic_plus'))
              .width(16)
              .height(16)
          }
          .height(40)
          .width(TAB_NEW_BUTTON_WIDTH_VP)
          .padding(0)
          .backgroundColor('#00000000')
          .borderRadius(8)
          .accessibilityText('新建标签页')
          .focusable(false)
          .hoverEffect(HoverEffect.Highlight)
          .onHover((isHover: boolean) => {
            this.newTabTipVisible = isHover;
          })
          .bindPopup(this.newTabTipVisible, {
            message: '新建标签页',
            placement: Placement.Bottom,
            enableArrow: false,
            mask: false,
            targetSpace: 4,
            popupColor: this.chrome.panelBg2,
            radius: 6
          })
          .onClick(() => {
            this.newTabTipVisible = false;
            this.addSession(true);
          })
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .align(Alignment.Start)
      .onAreaChange((_oldValue: Area, newValue: Area): void => {
        const width: number = Number(newValue.width ?? 0);
        if (Number.isFinite(width) && width > 0) {
          this.tabStripViewportWidth = width;
        }
      })
      .layoutWeight(1)

      Button() {
        Image($r('app.media.ic_link'))
          .width(17)
          .height(17)
      }
      .height(40)
      .width(40)
      .padding(0)
      .backgroundColor((this.drawerShown && this.drawerPane === 'conn') ||
        this.hoveredChromeAction === 'conn' || this.focusedChromeAction === 'conn'
        ? this.chrome.panelBg2 : '#00000000')
      .borderRadius(8)
      .id('workbenchConnectionAction')
      .accessibilityText('连接')
      .focusable(this.workbenchFocusZone > 0)
      .hoverEffect(HoverEffect.None)
      .onFocus(() => {
        this.workbenchFocusZone = 1;
        this.focusedChromeAction = 'conn';
      })
      .onBlur(() => {
        if (this.focusedChromeAction === 'conn') {
          this.focusedChromeAction = '';
        }
      })
      .onHover((isHover: boolean) => {
        this.hoveredChromeAction = isHover ? 'conn' : '';
        this.connectionTipVisible = isHover;
      })
      .bindPopup(this.connectionTipVisible, {
        message: '连接',
        placement: Placement.Bottom,
        enableArrow: false,
        mask: false,
        targetSpace: 4,
        popupColor: this.chrome.panelBg2,
        radius: 6
      })
      .onClick(() => {
        this.connectionTipVisible = false;
        this.workbenchFocusZone = 1;
        if (this.drawerShown && this.drawerPane === 'conn') {
          this.closeDrawer();
        } else {
          this.openDrawer('conn');
        }
      })

      Button() {
        Image($r('app.media.ic_gear'))
          .width(17)
          .height(17)
      }
      .height(40)
      .width(40)
      .padding(0)
      .backgroundColor((this.drawerShown && this.drawerPane !== 'conn') ||
        this.hoveredChromeAction === 'settings' || this.focusedChromeAction === 'settings'
        ? this.chrome.panelBg2 : '#00000000')
      .borderRadius(8)
      .id('workbenchSettingsAction')
      .accessibilityText('设置')
      .focusable(this.workbenchFocusZone > 0)
      .hoverEffect(HoverEffect.None)
      .onFocus(() => {
        this.workbenchFocusZone = 1;
        this.focusedChromeAction = 'settings';
      })
      .onBlur(() => {
        if (this.focusedChromeAction === 'settings') {
          this.focusedChromeAction = '';
        }
      })
      .onHover((isHover: boolean) => {
        this.hoveredChromeAction = isHover ? 'settings' : '';
        this.settingsTipVisible = isHover;
      })
      .bindPopup(this.settingsTipVisible, {
        message: '设置',
        placement: Placement.Bottom,
        enableArrow: false,
        mask: false,
        targetSpace: 4,
        popupColor: this.chrome.panelBg2,
        radius: 6
      })
      .onClick(() => {
        this.settingsTipVisible = false;
        this.workbenchFocusZone = 1;
        if (this.drawerShown && this.drawerPane !== 'conn') {
          this.closeDrawer();
        } else {
          this.openDrawer('terminal');
        }
      })

      Button() {
        Image($r('app.media.ic_more'))
          .width(17)
          .height(17)
      }
      .height(40)
      .width(40)
      .padding(0)
      .backgroundColor(this.hoveredChromeAction === 'more' || this.focusedChromeAction === 'more'
        ? this.chrome.panelBg2 : '#00000000')
      .borderRadius(8)
      .id('workbenchMoreAction')
      .accessibilityText('更多')
      .focusable(this.workbenchFocusZone > 0)
      .hoverEffect(HoverEffect.None)
      .onFocus(() => {
        this.workbenchFocusZone = 1;
        this.focusedChromeAction = 'more';
      })
      .onBlur(() => {
        if (this.focusedChromeAction === 'more') {
          this.focusedChromeAction = '';
        }
      })
      .onHover((isHover: boolean) => {
        this.hoveredChromeAction = isHover ? 'more' : '';
        this.moreTipVisible = isHover;
      })
      .bindPopup(this.moreTipVisible, {
        message: '更多',
        placement: Placement.Bottom,
        enableArrow: false,
        mask: false,
        targetSpace: 4,
        popupColor: this.chrome.panelBg2,
        radius: 6
      })
      .onClick(() => {
        this.moreTipVisible = false;
      })
      .bindMenu(this.buildWorkspaceMenu())
    }
    .height(WINDOW_CHROME_HEIGHT)
    .width('100%')
    .padding({ left: 8, right: WINDOW_DECOR_BUTTON_RESERVE })
    .backgroundColor(this.chrome.barBg)
  }

  @Builder
  private buildWorkspaceMenu() {
    Menu() {
      MenuItem({ content: '新建窗口' })
        .onClick(() => {
          this.openNewWindow();
        })
      MenuItem({ content: '帮助与诊断' })
        .onClick(() => {
          this.workbenchFocusZone = 0;
          this.agentGuideOpen = true;
          void this.refreshTaskNotificationState();
          this.requestWorkbenchFocusSoon('workbenchHelpCloseAction');
        })
      MenuItem({ content: '关于 Emberline' })
        .onClick(() => {
          this.workbenchFocusZone = 0;
          this.agentGuideOpen = true;
          void this.refreshTaskNotificationState();
          this.requestWorkbenchFocusSoon('workbenchHelpCloseAction');
        })
    }
  }

  // Kept mounted as a transparent outside-click target. The terminal remains
  // visually undimmed; input is blocked explicitly while the inspector is open.
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
        .backgroundColor('#00000000')
        .hitTestBehavior(this.drawerOpen ? HitTestMode.Default : HitTestMode.None)
        .onClick(() => {
          this.closeDrawer();
        })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }

  // Right-hand inspector. It overlays rather than resizes the terminal, and
  // exposes only the three workbench destinations: terminal, appearance and
  // connection. The width changes only at the 900vp responsive breakpoint.
  @Builder
  private buildDrawer() {
    Column() {
      Row()
        .width('100%')
        .height(WINDOW_CHROME_HEIGHT)
        .hitTestBehavior(HitTestMode.None)
      Row() {
        Column() {
          Column() {
            Row({ space: 4 }) {
              this.buildDrawerNavItem('终端', 'terminal')
              this.buildDrawerNavItem('外观', 'appearance')
              this.buildDrawerNavItem('连接', 'conn')
            }
            .width('100%')
            .height(48)
            .padding({ left: 10, right: 10, top: 6, bottom: 4 })
            .border({ width: { bottom: 1 }, color: this.chrome.panelBorder })

            // Only the content changes; the terminal behind it never reflows.
            Column() {
              if (this.drawerPane === 'appearance') {
                this.buildThemePane()
              } else {
                Scroll() {
                  Column() {
                    if (this.drawerPane === 'terminal') {
                      this.buildTerminalPane()
                    } else {
                      this.buildConnPane()
                    }
                  }
                  .width('100%')
                  .padding({ left: 18, right: 18, top: 4, bottom: 24 })
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
            .width('100%')
            .opacity(this.paneT)
            .translate({ x: (1 - this.paneT) * 10 })
          }
          .height('100%')
          .enabled(this.drawerShown)
          .width('100%')
          .backgroundColor(this.chrome.panelBg)
          .border({ width: { left: 1 }, color: this.chrome.panelBorder })
          .opacity(this.drawerShown ? 1 : 0)
          .translate({ x: this.drawerShown ? 0 : this.inspectorWidth() })
          .animation({ duration: DUR_STANDARD, curve: CURVE_DECEL })
          .onClick(() => {})
        }
        .height('100%')
        .width(this.inspectorWidth())
        .hitTestBehavior(this.drawerOpen ? HitTestMode.Default : HitTestMode.None)
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.End)
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
    Column({ space: 5 }) {
      Text(label)
        .fontSize(12.5)
        .fontColor(this.drawerPane === pane ? this.chrome.textPrimary : this.chrome.textSecondary)
      Row()
        .width(24)
        .height(2)
        .borderRadius(1)
        .backgroundColor(this.drawerPane === pane ? this.chrome.textPrimary : '#00000000')
        // Neutral selected underline fade (accent system retired).
        .animation({ duration: DUR_STANDARD, curve: CURVE_DECEL })
    }
    .height(40)
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .borderRadius(6)
    .backgroundColor(this.drawerPane === pane ? this.chrome.panelBg2 : '#00000000')
    // M07 selected-face: settles fast (120) so the face lands a beat before
    // the selected underline fades in.
    .animation({ duration: DUR_FAST, curve: CURVE_SHARP })
    .clip(true)
    .id(`workbenchInspector-${pane}`)
    .focusable(this.workbenchFocusZone === 2)
    .onFocus(() => {
      this.workbenchFocusZone = 2;
    })
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => {
      this.workbenchFocusZone = 2;
      this.switchDrawerPane(pane);
    })
  }

  @Builder
  private buildGroupTitle(title: string) {
    Row() {
      Text(title)
        .fontSize(11)
        .fontColor(this.chrome.textSecondary)
    }
    .width('100%')
    .padding({ bottom: 8 })
    .margin({ top: 16 })
    .border({ width: { bottom: 1 }, color: this.chrome.panelBorder })
  }

  // Setting-row label: plain name on top, the matching ghostty config key
  // below in faint type. The key is structure, not decoration - it documents
  // the ghostty vocabulary and paves the way for config import/export.
  @Builder
  private buildRowLabel(name: string, key: string) {
    Column({ space: 2 }) {
      Text(name)
        .fontSize(13)
        .fontColor(this.chrome.textPrimary)
      Text('= ' + key)
        .fontSize(10.5)
        .fontColor(this.chrome.textFaint)
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  @Builder
  private buildTerminalPane() {
    this.buildGroupTitle('光标')
    Row() {
      this.buildRowLabel('光标样式', 'cursor-style')
      Row({ space: 2 }) {
        ForEach([2, 0, 1] as number[], (style: number) => {
          Button(style === 2 ? '竖线' : style === 0 ? '方块' : '下划线')
            .height(36)
            .fontSize(11.5)
            .backgroundColor(this.cursorStyle === style ? '#1A212C' : '#00000000')
            .fontColor(this.cursorStyle === style ? this.chrome.textPrimary : this.chrome.textSecondary)
            .borderRadius(6)
            .focusable(this.drawerShown)
            .onClick(() => {
              this.cursorStyle = style;
              this.applyCursorConfig();
            })
        }, (style: number) => `cursor-${style}`)
      }
      .padding(2)
      .backgroundColor(this.chrome.panelBg2)
      .borderRadius(8)
      .border({ width: 1, color: this.chrome.panelBorder })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })

    Row() {
      this.buildRowLabel('光标闪烁', 'cursor-style-blink')
      Toggle({ type: ToggleType.Switch, isOn: this.cursorBlink })
        .selectedColor(this.chrome.textPrimary)
        .onChange((isOn: boolean) => {
          this.cursorBlink = isOn;
          this.applyCursorConfig();
        })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })

    this.buildFontPane()
  }

  @Builder
  private buildAppearancePane() {
    this.buildGroupTitle('背景')
    Row({ space: 10 }) {
      this.buildRowLabel('背景图片', 'background-image')
      if (this.backgroundImagePath.length > 0) {
        Button('清除')
          .height(36)
          .fontSize(11.5)
          .backgroundColor(this.chrome.panelBg2)
          .fontColor(this.chrome.textPrimary)
          .borderRadius(8)
          .border({ width: 1, color: this.chrome.panelBorder })
          .focusable(this.drawerShown)
          .onClick(() => {
            this.clearBackgroundImage();
          })
      }
      Button('选择…')
        .height(36)
        .fontSize(11.5)
        .backgroundColor(this.chrome.panelBg2)
        .fontColor(this.chrome.textPrimary)
        .borderRadius(8)
        .border({ width: 1, color: this.chrome.panelBorder })
        .focusable(this.drawerShown)
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
          .selectedColor(this.chrome.textPrimary)
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

    }

    if (this.backgroundImagePath.length > 0) {
      Row() {
        this.buildRowLabel(`亚克力模糊 ${Math.round(this.backgroundBlur)}`, 'background-blur')
        Slider({
          value: this.backgroundBlur,
          min: 0,
          max: MAX_BACKGROUND_BLUR,
          step: 2
        })
          .width(150)
          .selectedColor(this.chrome.textPrimary)
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

  }

  @Builder
  private buildImagePasteSettings() {
    this.buildGroupTitle('图片粘贴')
    Row() {
      this.buildRowLabel(this.pasteDirLabel(), 'linux-share-folder')
    }
    .width('100%')
    .padding({ top: 8 })
    Row({ space: 8 }) {
      if (this.pasteDirUri.length > 0) {
        Button('恢复默认')
          .height(36)
          .layoutWeight(1)
          .fontSize(11.5)
          .backgroundColor(this.chrome.panelBg2)
          .fontColor(this.chrome.textPrimary)
          .borderRadius(8)
          .border({ width: 1, color: this.chrome.panelBorder })
          .focusable(this.drawerShown)
          .onClick(() => {
            this.clearPasteDirectory();
          })
      }
      Button('选择共享文件夹…')
        .height(36)
        .layoutWeight(2)
        .fontSize(11.5)
        .backgroundColor(this.chrome.panelBg2)
        .fontColor(this.chrome.textPrimary)
        .borderRadius(8)
        .border({ width: 1, color: this.chrome.panelBorder })
        .focusable(this.drawerShown)
        .onClick(() => {
          void this.pickPasteDirectory();
        })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    Text('选择与 Linux 模拟机共享的目录(share 下的一级文件夹)。粘贴的截图会存入该文件夹,远端会话直接粘贴 /mnt/linux_share/<文件夹> 路径,无需上传')
      .fontSize(10.5)
      .fontColor(this.chrome.textFaint)
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
          .width(36)
          .height(36)
          .padding(0)
          .fontSize(14)
          .backgroundColor('#00000000')
          .fontColor(this.chrome.textSecondary)
          .borderRadius(6)
          .focusable(this.drawerShown)
          .onClick(() => {
            this.applyFontSize(this.fontSize - 1, true);
          })
        Text(`${this.fontSize}`)
          .fontSize(12.5)
          // M26: fontColor + translateY are driven by the one-shot readout tick
          // (keyframeAnimateTo), so they flash ember and nudge up-and-back on a
          // size change. No .animation() here — the imperative tick owns them.
          .fontColor(this.fontReadoutColor)
          .width(36)
          .textAlign(TextAlign.Center)
          .translate({ y: this.fontReadoutTickY })
        Button('+')
          .width(36)
          .height(36)
          .padding(0)
          .fontSize(14)
          .backgroundColor('#00000000')
          .fontColor(this.chrome.textSecondary)
          .borderRadius(6)
          .focusable(this.drawerShown)
          .onClick(() => {
            this.applyFontSize(this.fontSize + 1, true);
          })
      }
      .padding(2)
      .backgroundColor(this.chrome.panelBg2)
      .borderRadius(8)
      .border({ width: 1, color: this.chrome.panelBorder })
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
          .height(36)
          .fontSize(11.5)
          .backgroundColor(this.chrome.panelBg2)
          .fontColor(this.chrome.textPrimary)
          .borderRadius(8)
          .border({ width: 1, color: this.chrome.panelBorder })
          .focusable(this.drawerShown)
          .onClick(() => {
            this.clearCustomFont();
          })
      }
      Button('选择文件…')
        .height(36)
        .fontSize(11.5)
        .backgroundColor(this.chrome.panelBg2)
        .fontColor(this.chrome.textPrimary)
        .borderRadius(8)
        .border({ width: 1, color: this.chrome.panelBorder })
        .focusable(this.drawerShown)
        .onClick(() => {
          void this.pickCustomFont();
        })
    }
    .width('100%')
    .margin({ top: 14 })
  }

  // App appearance mode: follow the OS, or pin dark/light manually.
  @Builder
  private buildColorModeButton(label: string, mode: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.colorModeOverride === mode ? this.chrome.textPrimary : this.chrome.textSecondary)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .padding({ top: 6, bottom: 6 })
      .borderRadius(6)
      .backgroundColor(this.colorModeOverride === mode ? this.chrome.panelBg2 : '#00000000')
      .border({
        width: 1,
        color: this.colorModeOverride === mode ? this.chrome.panelBorder : '#00000000'
      })
      .onClick(() => {
        this.applyColorModeOverride(mode);
      })
  }

  // Ghostty theme = light:...,dark:... — the pane edits one slot at a time and
  // shows that slot's theme as selected in the catalogue below.
  @Builder
  private buildThemeSlotButton(label: string, slot: string) {
    Column({ space: 3 }) {
      Text(label)
        .fontSize(12)
        .fontColor(this.themeEditSlot === slot ? this.chrome.textPrimary : this.chrome.textSecondary)
      Text(slot === 'dark' ? this.darkThemeName : this.lightThemeName)
        .fontSize(9.5)
        .fontColor(this.chrome.textFaint)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .alignItems(HorizontalAlign.Center)
    .layoutWeight(1)
    .padding({ top: 6, bottom: 6 })
    .borderRadius(6)
    .backgroundColor(this.themeEditSlot === slot ? this.chrome.panelBg2 : '#00000000')
    .border({
      width: 1,
      color: this.themeEditSlot === slot ? this.chrome.panelBorder : '#00000000'
    })
    .onClick(() => {
      if (this.themeEditSlot !== slot) {
        this.themeEditSlot = slot;
        this.syncThemeOptionSelection();
      }
    })
  }

  @Builder
  private buildThemePane() {
    List({ space: 2 }) {
      ListItem() {
        Column() {
          this.buildAppearancePane()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 14, right: 14 })
      }

      ListItem() {
        Column() {
          this.buildGroupTitle('主题')
          Row({ space: 2 }) {
            this.buildColorModeButton('跟随系统', 'system')
            this.buildColorModeButton('深色', 'dark')
            this.buildColorModeButton('浅色', 'light')
          }
          .width('100%')
          .margin({ bottom: 6 })
          Row({ space: 2 }) {
            this.buildThemeSlotButton('深色模式', 'dark')
            this.buildThemeSlotButton('浅色模式', 'light')
          }
          .width('100%')
          .margin({ bottom: 8 })
          TextInput({ text: this.themeFilter, placeholder: '搜索主题…' })
            .height(36)
            .fontSize(12.5)
            .fontColor(this.chrome.textPrimary)
            .backgroundColor(this.chrome.panelBg2)
            .borderRadius(8)
            .onChange((value: string) => {
              this.themeFilter = value;
              this.themeRenderLimit = THEME_PREVIEW_BATCH_SIZE;
              void this.loadThemePreviews(
                this.renderedThemeOptions().map((option: ThemeOptionState) => option.name));
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 14, right: 14, bottom: 8 })
      }

      ForEach(this.renderedThemeOptions(), (option: ThemeOptionState) => {
        ListItem() {
          ThemeOptionRow({
            option: option,
            canFocus: this.drawerShown,
            onSelect: (theme: string) => {
              this.applyTheme(theme);
            }
          })
        }
        .padding({ left: 14, right: 14 })
      }, (option: ThemeOptionState) => option.name)
    }
    .layoutWeight(1)
    .width('100%')
    .height('100%')
    .padding({ top: 4, bottom: 14 })
    .scrollBar(BarState.Auto)
    .onScrollIndex((_start: number, end: number, _center: number) => {
      const options: ThemeOptionState[] = this.filteredThemeOptions();
      const renderedCount: number = Math.min(options.length, this.themeRenderLimit);
      const nextThemeIndex: number = Math.max(0, end - 1);
      void this.loadThemePreviews(
        options.slice(nextThemeIndex, nextThemeIndex + THEME_PREVIEW_BATCH_SIZE)
          .map((option: ThemeOptionState) => option.name));
      if (nextThemeIndex + 8 >= renderedCount && renderedCount < options.length) {
        const nextLimit: number = Math.min(
          options.length,
          renderedCount + THEME_PREVIEW_BATCH_SIZE
        );
        this.themeRenderLimit = nextLimit;
        void this.loadThemePreviews(
          options.slice(renderedCount, nextLimit)
            .map((option: ThemeOptionState) => option.name));
      }
    })
  }

  @Builder
  private buildConnPane() {
    Text(DEFAULT_FUSION_ENGINE_VM_LABEL)
      .fontSize(15)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.chrome.textPrimary)
      .margin({ top: 16 })
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })

    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Row()
          .width(22)
          .height(2)
          .borderRadius(1)
          .backgroundColor(this.activeConnLit() ? this.chrome.dotOn : this.chrome.dotOff)
          // Neutral status bar fade between states.
          .animation({ duration: DUR_STANDARD, curve: CURVE_DECEL })
          // M09 connecting-breath: after .animation() so only the gated loop drives it.
          .opacity(this.activeConnPending() ? this.connBreatheOpacity : 1)
        Text(this.activeConnStatusText())
          .fontSize(11.5)
          .fontColor(this.chrome.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      Text(`ws://${this.draftHost}:${this.draftPort}${DEFAULT_FUSION_AGENT_PATH}`)
        .fontSize(10.5)
        .fontColor(this.chrome.textFaint)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .padding(10)
    .backgroundColor(this.chrome.panelBg2)
    .borderRadius(8)
    .margin({ top: 16, bottom: 6 })

    if (this.activeConnFailed()) {
      Button(this.connectionErrorDetailsOpen ? '收起详细信息' : '详细信息')
        .height(36)
        .width('100%')
        .fontSize(12)
        .backgroundColor('#00000000')
        .fontColor(this.chrome.textSecondary)
        .borderRadius(6)
        .focusable(this.drawerShown)
        .onClick(() => {
          this.connectionErrorDetailsOpen = !this.connectionErrorDetailsOpen;
        })
      if (this.connectionErrorDetailsOpen) {
        Text(this.activeSession().statusLabel)
          .fontSize(10.5)
          .fontColor(this.chrome.textFaint)
          .lineHeight(15)
          .width('100%')
          .padding({ top: 4, bottom: 4 })
      }
    }

    this.buildGroupTitle('Fusion Agent')
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Text('主机')
          .fontSize(11.5)
          .fontColor(this.chrome.textSecondary)
        TextInput({ text: this.draftHost, placeholder: '172.16.100.2' })
          .height(40)
          .fontSize(13)
          .fontColor(this.chrome.textPrimary)
          .backgroundColor(this.chrome.panelBg2)
          .borderRadius(8)
          .onChange((value: string) => {
            this.draftHost = value;
          })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(2)
      Column({ space: 4 }) {
        Text('端口')
          .fontSize(11.5)
          .fontColor(this.chrome.textSecondary)
        TextInput({ text: this.draftPort, placeholder: '8765' })
          .height(40)
          .fontSize(13)
          .fontColor(this.chrome.textPrimary)
          .backgroundColor(this.chrome.panelBg2)
          .borderRadius(8)
          .type(InputType.Number)
          .onChange((value: string) => {
            this.draftPort = value;
          })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .margin({ top: 10 })

    Text('访问令牌')
      .fontSize(11.5)
      .fontColor(this.chrome.textSecondary)
      .margin({ top: 10, bottom: 4 })
    TextInput({ text: this.draftAgentToken, placeholder: '令牌' })
      .height(40)
      .fontSize(13)
      .fontColor(this.chrome.textPrimary)
      .backgroundColor(this.chrome.panelBg2)
      .borderRadius(8)
      .type(InputType.Password)
      .onChange((value: string) => {
        this.draftAgentToken = value;
      })

    Button(this.agentActionLabel())
      .height(40)
      .width('100%')
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .backgroundColor(this.chrome.primaryBtnBg)
      .fontColor(this.chrome.primaryBtnText)
      .borderRadius(8)
      .enabled(!this.activeConnPending())
      .stateStyles({
        pressed: {
          .opacity(0.82)
        }
      })
      .focusable(this.drawerShown)
      .onClick(() => {
        this.connectionErrorDetailsOpen = false;
        this.connectFusionAgent();
      })
      .margin({ top: 16 })

    Button(this.connectionAdvancedOpen ? '收起高级选项' : '高级选项')
      .height(36)
      .width('100%')
      .fontSize(12)
      .backgroundColor('#00000000')
      .fontColor(this.chrome.textSecondary)
      .borderRadius(6)
      .focusable(this.drawerShown)
      .onClick(() => {
        this.connectionAdvancedOpen = !this.connectionAdvancedOpen;
      })
      .margin({ top: 8 })

    if (this.connectionAdvancedOpen) {
      this.buildGroupTitle('SSH 与本地')
      Row({ space: 10 }) {
        Column({ space: 4 }) {
          Text('SSH 端口')
            .fontSize(11.5)
            .fontColor(this.chrome.textSecondary)
          TextInput({ text: this.draftSshPort, placeholder: '22' })
            .height(40)
            .fontSize(13)
            .fontColor(this.chrome.textPrimary)
            .backgroundColor(this.chrome.panelBg2)
            .borderRadius(8)
            .type(InputType.Number)
            .onChange((value: string) => {
              this.draftSshPort = value;
            })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Column({ space: 4 }) {
          Text('SSH 用户')
            .fontSize(11.5)
            .fontColor(this.chrome.textSecondary)
          TextInput({ text: this.draftUser, placeholder: '用户名' })
            .height(40)
            .fontSize(13)
            .fontColor(this.chrome.textPrimary)
            .backgroundColor(this.chrome.panelBg2)
            .borderRadius(8)
            .onChange((value: string) => {
              this.draftUser = value;
            })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')

      Text('SSH 密码(不保存)')
        .fontSize(11.5)
        .fontColor(this.chrome.textSecondary)
        .margin({ top: 10, bottom: 4 })
      TextInput({ text: this.draftPassword, placeholder: '密码' })
        .height(40)
        .fontSize(13)
        .fontColor(this.chrome.textPrimary)
        .backgroundColor(this.chrome.panelBg2)
        .borderRadius(8)
        .type(InputType.Password)
        .onChange((value: string) => {
          this.draftPassword = value;
        })

      Row({ space: 8 }) {
        Button('SSH 备用')
          .height(40)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor(this.chrome.panelBg2)
          .fontColor(this.chrome.textPrimary)
          .borderRadius(8)
          .border({ width: 1, color: this.chrome.panelBorder })
          .focusable(this.drawerShown)
          .onClick(() => {
            this.connectFusionVm();
          })
        Button('本地 shell')
          .height(40)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor(this.chrome.panelBg2)
          .fontColor(this.chrome.textPrimary)
          .borderRadius(8)
          .border({ width: 1, color: this.chrome.panelBorder })
          .focusable(this.drawerShown)
          .onClick(() => {
            this.closeDrawer();
            this.startLocalSession();
          })
      }
      .width('100%')
      .margin({ top: 12 })

      this.buildImagePasteSettings()
    }
  }

  @Builder
  private buildKbd(label: string) {
    Text(label)
      .fontSize(10.5)
      .fontColor(this.chrome.textPrimary)
      .padding({ left: 6, right: 6, top: 3, bottom: 3 })
      .backgroundColor(this.chrome.panelBg2)
      .borderRadius(5)
      .border({ width: 1, color: this.chrome.panelBorder })
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
        .fontColor(this.chrome.textSecondary)
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
        .fontColor(this.chrome.textPrimary)
      Text(detail)
        .fontSize(11)
        .fontColor(this.chrome.textSecondary)
        .lineHeight(16)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: 7, bottom: 7 })
  }

  @Builder
  private buildHelpPane() {
    this.buildGroupTitle('Emberline')
    this.buildHelpRow('HarmonyOS 开发终端', 'Fusion Agent 是首选连接;SSH 与本地 shell 保留为高级备用路径')

    this.buildGroupTitle('键盘快捷键')
    this.buildShortcutRow('Ctrl Shift C', '复制选中内容')
    this.buildShortcutRow('Ctrl Insert', '复制选中内容')
    this.buildShortcutRow('Ctrl V', '粘贴')
    this.buildShortcutRow('Shift Insert', '粘贴')
    Text('Ctrl+C 保持终端中断语义,不会被复制占用')
      .fontSize(10.5)
      .fontColor(this.chrome.textFaint)
      .margin({ top: 4 })

    this.buildGroupTitle('标签页')
    this.buildHelpRow('右键标签', '标签设置:重命名、图片粘贴视角;触屏双击同效')
    this.buildHelpRow('拖动排序', '横向拖动标签即可排序;触屏长按拿起同效')
    this.buildHelpRow('多窗口', '右键标签「拆分为新窗口/移动到窗口…」跨窗口搬移会话;唯一标签移走后原窗口自动关闭')
    this.buildHelpRow('状态圆点', '实心 = 已连接;呼吸 = 正在连接或重连;空心 = 已断开;红 = 连接失败')
    this.buildHelpRow('关闭标签', '只断开本地连接,不会打断远端 tmux 或正在运行的程序')

    this.buildGroupTitle('触屏手势')
    this.buildHelpRow('单指滑动', '滚动回看,带惯性;轻点呼出键盘或打开链接')
    this.buildHelpRow('长按拖动', '选择文字;选中后右键菜单里复制')
    this.buildHelpRow('鼠标模式(tmux / vim)', '轻点 = 点击;长按后拖 = 拖拽,可以拖动 tmux 分栏;滑动 = 滚轮')

    this.buildGroupTitle('连接')
    this.buildHelpRow('自动连接', '启动或新建标签时自动连上次保存的 Agent;手动选择传输后该标签不再自动连')
    this.buildHelpRow('断线重连', '连接意外断开后按 1s → 30s 退避自动重连;手动断开不会触发')
    this.buildHelpRow('远程复制', '远端程序可通过 OSC 52(如 tmux set-clipboard)直接写入系统剪贴板')
    this.buildHelpRow('图片粘贴视角', '在会话里手动 ssh 到别的机器后,右键标签把粘贴视角切到「上传」或「中继」,路径才对目标机器有效')

    this.buildGroupTitle('Codex 任务提醒')
    this.buildHelpRow('系统通知', this.taskNotificationStatus)
    Button(this.taskNotificationActionLabel())
      .width(120)
      .height(40)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .backgroundColor(this.taskNotificationEnabled ? this.chrome.panelBg2 : this.chrome.primaryBtnBg)
      .fontColor(this.taskNotificationEnabled ? this.chrome.textPrimary : this.chrome.primaryBtnText)
      .borderRadius(8)
      .border({
        width: this.taskNotificationEnabled ? 1 : 0,
        color: this.taskNotificationEnabled ? this.chrome.panelBorder : '#00000000'
      })
      .stateStyles({
        pressed: {
          .opacity(0.82)
        }
      })
      .enabled(!this.taskNotificationBusy)
      .focusable(this.agentGuideOpen)
      .onClick(() => {
        void this.enableAndTestTaskNotification();
      })
    this.buildHelpRow('Codex CLI', '在虚拟机的 ~/.codex/config.toml 中启用完成事件的 OSC 9 通道。若已有 [tui] 段,只合并下面三项,不要重复表头。保存配置后先退出当前 Codex,再从 shell 恢复会话,让新进程读取通知设置。')
    this.buildGuideCommand('mkdir -p ~/.codex && ${EDITOR:-vi} ~/.codex/config.toml')
    this.buildGuideCommand(CODEX_TASK_NOTIFICATION_CONFIG)
    this.buildGuideCommand('codex resume --last')
    this.buildHelpRow('tmux', '在 tmux 内运行 Codex 时必须允许 passthrough,否则 tmux 会吞掉完成事件。下面的命令会幂等写入 ~/.tmux.conf 并立即重新加载。')
    this.buildGuideCommand(CODEX_TMUX_NOTIFICATION_SETUP_COMMAND)
    this.buildHelpRow('链路自检', '运行下面的延迟命令,并在 5 秒内切到其他标签或把应用退到后台;它会验证终端输出到 Emberline 系统通知的整条 OSC 9 链路')
    this.buildGuideCommand(CODEX_TASK_NOTIFICATION_TEST_COMMAND)
    this.buildHelpRow('手表同步', 'Emberline 发布的是 HarmonyOS 系统通知;已配对手表能否收到由系统跨设备通知设置和设备支持决定')

    this.buildGroupTitle('诊断')
    this.buildHelpRow('当前会话', this.activeConnStatusText())
    this.buildHelpRow('Agent 端点', `ws://${this.draftHost}:${this.draftPort}${DEFAULT_FUSION_AGENT_PATH}`)

    this.buildGroupTitle('部署 wand-agent(Agent 会话)')
    this.buildAgentGuideContent()

    this.buildGroupTitle('主题与字体')
    this.buildHelpRow('ghostty 键名', '设置项下方的灰色小字是对应的 ghostty 配置键,便于对照 ghostty 文档')
    this.buildHelpRow('自定义字体', '检查器「终端」可导入 ttf / otf 文件,导入后自动切换到「自定义」')
  }

  // Explicit help/diagnostics content opened from the top-bar overflow. It is
  // never auto-mounted on launch, so the terminal remains the first viewport.
  @Builder
  private buildAgentGuideContent() {
    Text('Agent 会话面向融合开发引擎的 Linux 虚拟机:虚拟机里常驻一个 wand-agent,应用经 WebSocket 直连它的伪终端。SSH 与本地 shell 无需以下步骤。长按命令可复制。')
      .fontSize(11)
      .fontColor(this.chrome.textSecondary)
      .lineHeight(16)
      .width('100%')
      .padding({ top: 4, bottom: 4 })

    this.buildHelpRow('第 1 步 · 进入虚拟机', '打开融合开发引擎的 Linux 虚拟机终端(或任何能进入虚拟机 shell 的方式),以下命令都在虚拟机里执行')

    this.buildHelpRow('第 2 步 · 安装 wand-agent', '方式一,源码构建(需要 Go 1.21 及以上):')
    this.buildGuideCommand('git clone https://github.com/beforeugone520/wand-agent.git\ncd wand-agent\ngo build -o wand-agent .\ninstall -m 755 wand-agent /usr/local/bin/')
    Text('方式二,预构建二进制:把 wand-agent 经共享目录拷进虚拟机,再执行:')
      .fontSize(11)
      .fontColor(this.chrome.textSecondary)
      .lineHeight(16)
      .padding({ top: 2 })
    this.buildGuideCommand('install -m 755 wand-agent /usr/local/bin/')

    this.buildHelpRow('第 3 步 · 试运行', '--host 填虚拟机桥接网卡地址(融合引擎通常是 172.16.100.2),--token 是鉴权令牌,应用侧需填一致:')
    this.buildGuideCommand('wand-agent --host 172.16.100.2 --token 你的token')
    Text('默认监听 8765 端口、路径 /ws。前台跑通即可先做第 5 步连一次。')
      .fontSize(10.5)
      .fontColor(this.chrome.textFaint)
      .lineHeight(15)

    this.buildHelpRow('第 4 步 · 开机常驻(推荐)', '把 agent 改为 systemd 服务,先写入 /etc/systemd/system/wand-agent.service:')
    this.buildGuideCommand(AGENT_GUIDE_SERVICE_UNIT)
    Text('然后启用:')
      .fontSize(11)
      .fontColor(this.chrome.textSecondary)
      .padding({ top: 2 })
    this.buildGuideCommand('systemctl daemon-reload && systemctl enable --now wand-agent')

    this.buildHelpRow('第 5 步 · 回到应用连接', '检查器「连接」页填入地址与 token(默认 ws://172.16.100.2:8765/ws),点「连接 Agent」;应用会记住端点,之后启动与新建标签都会自动连接')

    Text('安全提示:token 鉴权面向可信的虚拟机桥接网络;若把 agent 暴露到桥接网络之外,请更换强随机 token 并用防火墙限制来源。')
      .fontSize(10.5)
      .fontColor(this.chrome.textFaint)
      .lineHeight(15)
      .width('100%')
      .padding({ top: 4 })
  }

  @Builder
  private buildGuideCommand(cmd: string) {
    Text(cmd)
      .fontSize(10.5)
      .fontColor(this.chrome.textPrimary)
      .lineHeight(16)
      .copyOption(CopyOptions.LocalDevice)
      .width('100%')
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .backgroundColor(this.chrome.panelBg2)
      .borderRadius(8)
      .border({ width: 1, color: this.chrome.panelBorder })
      .margin({ top: 2, bottom: 4 })
  }

  @Builder
  private buildAgentGuideScrim() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor('#00000000')
      .onClick(() => {
        this.dismissAgentGuide();
      })
  }

  @Builder
  private buildAgentGuidePanel() {
    Column({ space: 12 }) {
      Text('帮助与诊断')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.chrome.textPrimary)
        .width('100%')

      Scroll() {
        Column() {
          this.buildHelpPane()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .layoutWeight(1)
      .width('100%')

      Row({ space: 8 }) {
        Text('顶栏更多菜单可随时重新打开')
          .fontSize(10.5)
          .fontColor(this.chrome.textFaint)
        Blank()
        Button('关闭')
          .height(40)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(this.chrome.primaryBtnBg)
          .fontColor(this.chrome.primaryBtnText)
          .borderRadius(8)
          .stateStyles({
            pressed: {
              .opacity(0.82)
            }
          })
          .id('workbenchHelpCloseAction')
          .focusable(this.agentGuideOpen)
          .onClick(() => {
            this.dismissAgentGuide();
          })
      }
      .width('100%')
    }
    .width(this.dialogWidth(480))
    .height('78%')
    .padding(18)
    .backgroundColor(this.chrome.panelBg)
    .borderRadius(8)
    .border({ width: 1, color: this.chrome.panelBorder })
    .shadow({ radius: 28, color: '#B3000000', offsetX: 0, offsetY: 12 })
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.OPACITY
        .combine(TransitionEffect.translate({ y: 12 }))
        .animation({ duration: DUR_STANDARD, curve: CURVE_DECEL }),
      TransitionEffect.OPACITY
        .animation({ duration: DUR_EDITOR_EXIT, curve: CURVE_ACCEL })
    ))
  }

  private dismissAgentGuide(): void {
    this.agentGuideOpen = false;
    this.focusActiveTerminalSoon();
  }

  @Builder
  private buildTabEditScrim() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor('#00000000')
      .onClick(() => {
        this.commitTabEditor();
      })
  }

  @Builder
  private buildPasteModeButton(label: string, mode: string) {
    Button(label)
      .height(36)
      .layoutWeight(1)
      .padding(0)
      .fontSize(11.5)
      .backgroundColor(this.editingPasteMode === mode ? '#1A212C' : '#00000000')
      .fontColor(this.editingPasteMode === mode ? this.chrome.textPrimary : this.chrome.textSecondary)
      .borderRadius(6)
      .focusable(this.tabEditOpen)
      .onClick(() => {
        this.editingPasteMode = mode;
        if (this.editingSession) {
          this.editingSession.pasteMode = mode;
        }
      })
  }

  // Tab editor (right-click a tab -> 标签设置): rename and paste mode.
  @Builder
  private buildTabEditor() {
    Column({ space: 14 }) {
      Text('标签设置')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.chrome.textPrimary)
        .width('100%')

      TextInput({ text: this.tabEditDraft, placeholder: '标签名称' })
        .height(40)
        .fontSize(13)
        .fontColor(this.chrome.textPrimary)
        .backgroundColor(this.chrome.panelBg2)
        .borderRadius(8)
        .onChange((value: string) => {
          this.tabEditDraft = value;
        })

      Column({ space: 6 }) {
        Text('图片粘贴视角')
          .fontSize(11.5)
          .fontColor(this.chrome.textSecondary)
          .width('100%')
        Row({ space: 2 }) {
          this.buildPasteModeButton('自动', 'auto')
          this.buildPasteModeButton('本地', 'local')
          this.buildPasteModeButton('共享', 'share')
          this.buildPasteModeButton('上传', 'sftp')
          this.buildPasteModeButton('中继', 'relay')
        }
        .width('100%')
        .padding(2)
        .backgroundColor(this.chrome.panelBg2)
        .borderRadius(8)
        .border({ width: 1, color: this.chrome.panelBorder })

        // Relay settings only exist while the relay perspective is selected:
        // the wand-agent scp-pushes the staged image to this tailnet host, so
        // a shell ssh'd into that machine can read the pasted path directly.
        if (this.editingPasteMode === 'relay') {
          TextInput({ text: this.editingRelayTarget, placeholder: '目标机(host 或 user@host)' })
            .height(36)
            .fontSize(12)
            .fontColor(this.chrome.textPrimary)
            .backgroundColor(this.chrome.panelBg2)
            .borderRadius(8)
            .onChange((value: string) => {
              this.editingRelayTarget = value;
              if (this.editingSession) {
                this.editingSession.relayTarget = value;
              }
            })
          TextInput({ text: this.editingRelayDir, placeholder: '远端目录(默认 /tmp/emberline-paste)' })
            .height(36)
            .fontSize(12)
            .fontColor(this.chrome.textPrimary)
            .backgroundColor(this.chrome.panelBg2)
            .borderRadius(8)
            .onChange((value: string) => {
              this.editingRelayDir = value;
              if (this.editingSession) {
                this.editingSession.relayDir = value;
              }
            })
          Text('经 Agent 所在虚拟机 scp 转发;需要虚拟机可免交互 ssh 到目标机(Tailscale ACL 或已装密钥)')
            .fontSize(10.5)
            .fontColor(this.chrome.textSecondary)
            .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      Row({ space: 8 }) {
        Button('恢复自动命名')
          .height(40)
          .fontSize(12)
          .backgroundColor(this.chrome.panelBg2)
          .fontColor(this.chrome.textPrimary)
          .borderRadius(8)
          .border({ width: 1, color: this.chrome.panelBorder })
          .focusable(this.tabEditOpen)
          .onClick(() => {
            this.resetTabName();
          })
        Blank()
        Button('完成')
          .height(40)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(this.chrome.primaryBtnBg)
          .fontColor(this.chrome.primaryBtnText)
          .borderRadius(8)
          // M27: same ember-button press feedback as the connect action.
          .stateStyles({
            pressed: {
              .opacity(0.82)
            }
          })
          .focusable(this.tabEditOpen)
          .onClick(() => {
            this.commitTabEditor();
          })
      }
      .width('100%')
    }
    .width(this.dialogWidth(320))
    .padding(18)
    .backgroundColor(this.chrome.panelBg)
    .borderRadius(8)
    .border({ width: 1, color: this.chrome.panelBorder })
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
      .fontColor(this.chrome.textSecondary)
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
    this.closeDrawer();
    this.persistConnection();
    session.agentDriver.disconnect();
    this.ensureDriverAttached(session);
    this.clearTerminalForLiveSession(session);
    session.driver.connectSsh(profile);
  }

  private connectFusionAgent(): void {
    const session = this.activeSession();
    this.closeDrawer();
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
    if (mode === 'relay') {
      this.relayPastedImage(session, exported, localPath);
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

  // 'relay' paste mode: the image is staged in the shared folder (VM-visible),
  // then wand-agent scp-relays it to the configured tailnet host and the
  // REMOTE path is pasted - for shells that ssh'd from the agent session into
  // another machine. Needs the agent channel alive; every failure degrades to
  // pasting a path that at least exists somewhere, plus an explanatory line.
  private relayPastedImage(session: TerminalSessionHandle, exported: string, localPath: string): void {
    if (exported.length === 0) {
      session.controller.paste(localPath);
      session.controller.feed('\r\n[FusionTerm] 未设置共享文件夹,无法中继;已粘贴本地路径\r\n');
      return;
    }
    const target = session.relayTarget.trim();
    if (target.length === 0) {
      this.pasteSharePath(session, exported);
      session.controller.feed('\r\n[FusionTerm] 未设置中继目标(标签设置 → 图片粘贴视角 → 中继),已粘贴共享路径\r\n');
      return;
    }
    const parts = exported.split('/');
    const fileName = parts[parts.length - 1];
    const vmPath = `/mnt/linux_share/${this.linuxShareFolderName()}/${fileName}`;
    const dir = session.relayDir.trim().length > 0 ? session.relayDir.trim() : '/tmp/emberline-paste';
    session.agentDriver.uploadRelay(vmPath, target, dir)
      .then((remotePath: string) => {
        session.controller.paste(remotePath);
      })
      .catch((err: Error) => {
        this.pasteSharePath(session, exported);
        session.controller.feed(`\r\n[FusionTerm] 图片中继失败(${err.message}),已粘贴共享路径\r\n`);
      });
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

  private filteredThemeOptions(): ThemeOptionState[] {
    const filter = this.themeFilter.trim().toLowerCase();
    if (filter.length === 0) {
      return this.themeOptions;
    }
    return this.themeOptions.filter((option: ThemeOptionState) =>
      option.name.toLowerCase().includes(filter));
  }

  private renderedThemeOptions(): ThemeOptionState[] {
    return this.filteredThemeOptions().slice(0, this.themeRenderLimit);
  }

  private prepareThemePane(): void {
    if (this.themeOptions.length === 0) {
      const names: string[] = this.activeSession().controller.getThemeList();
      if (names.length > 0) {
        const options: ThemeOptionState[] = names.map((name: string) =>
          new ThemeOptionState(name, name === this.editedThemeName()));
        this.themeOptionByName.clear();
        for (const option of options) {
          this.themeOptionByName.set(option.name, option);
        }
        this.themeOptions = options;
      }
    } else {
      this.syncThemeOptionSelection();
    }
    this.themeFilter = '';
    this.themeRenderLimit = THEME_PREVIEW_BATCH_SIZE;
    void this.loadThemePreviews(
      this.renderedThemeOptions().map((option: ThemeOptionState) => option.name));
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

  private cancelThemePreviewWork(): void {
    this.themePreviewGeneration += 1;
    this.themePreviewQueue = [];
  }

  // Load only the visible/search-leading preview batch. New requests are queued
  // behind the active batch so rapid search input never starts parallel raw-file
  // reads or forces the whole bundled theme catalogue into memory at once. The
  // generation check drops an in-flight batch as soon as the pane closes.
  private async loadThemePreviews(themes: string[]): Promise<void> {
    if (!this.context) {
      return;
    }
    for (const theme of themes) {
      const option = this.themeOptionByName.get(theme);
      if (option && !option.preview && !this.themePreviewQueue.includes(theme)) {
        this.themePreviewQueue.push(theme);
      }
    }
    if (this.themePreviewsLoading) {
      return;
    }
    this.themePreviewsLoading = true;
    const generation: number = this.themePreviewGeneration;
    const resourceMgr = this.context.resourceManager;
    while (this.themePreviewQueue.length > 0 && generation === this.themePreviewGeneration) {
      const batch: string[] = this.themePreviewQueue.splice(0, THEME_PREVIEW_BATCH_SIZE);
      const loaded: Map<string, ThemePreview> = new Map<string, ThemePreview>();
      for (const theme of batch) {
        if (generation !== this.themePreviewGeneration) {
          break;
        }
        try {
          const raw = await resourceMgr.getRawFileContent(`themes/${theme}`);
          if (generation !== this.themePreviewGeneration) {
            break;
          }
          const preview = this.parseThemePreview(raw);
          if (preview) {
            loaded.set(theme, preview);
          }
        } catch (_err) {
          // Theme without a readable file simply renders without a swatch.
        }
      }
      if (generation !== this.themePreviewGeneration) {
        break;
      }
      loaded.forEach((preview: ThemePreview, theme: string) => {
        const option = this.themeOptionByName.get(theme);
        if (option) {
          option.preview = preview;
        }
      });
    }
    this.themePreviewsLoading = false;
    // A close/reopen can enqueue the new pane's first batch while the cancelled
    // worker is still unwinding. Hand that queue to a worker with the new epoch.
    if (this.themePreviewQueue.length > 0 &&
      this.drawerShown && this.drawerPane === 'appearance') {
      void this.loadThemePreviews([]);
    }
  }

  private parseThemePreview(raw: Uint8Array): ThemePreview | null {
    const text: string = this.themePreviewDecoder.decodeToString(raw);
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
    const preview: ThemePreview = { bg: bg, fg: fg, red: slots[1], ansi: dots };
    return preview;
  }

  private normalizeHexColor(value: string): string {
    const hex = value.startsWith('#') ? value.slice(1) : value;
    if (hex.length === 6 && /^[0-9a-fA-F]{6}$/.test(hex)) {
      return '#' + hex;
    }
    return '';
  }

  private syncThemeOptionSelection(): void {
    for (const option of this.themeOptions) {
      const selected: boolean = option.name === this.editedThemeName();
      if (option.selected !== selected) {
        option.selected = selected;
      }
    }
  }

  private resolvedDark(): boolean {
    if (this.colorModeOverride === 'dark') {
      return true;
    }
    if (this.colorModeOverride === 'light') {
      return false;
    }
    return this.sysDark;
  }

  private effectiveThemeName(): string {
    return this.resolvedDark() ? this.darkThemeName : this.lightThemeName;
  }

  private editedThemeName(): string {
    return this.themeEditSlot === 'light' ? this.lightThemeName : this.darkThemeName;
  }

  // System light/dark flipped (EntryAbility.onConfigurationUpdate): swap to the
  // paired theme and re-derive every chrome token in one pass.
  private onSystemColorModeChanged(): void {
    // A manual override pins the appearance; OS flips are ignored until the
    // user returns to 跟随系统.
    if (this.colorModeOverride !== 'system') {
      return;
    }
    this.themeEditSlot = this.sysDark ? 'dark' : 'light';
    this.applyEffectiveTheme();
    this.syncThemeOptionSelection();
  }

  private applyColorModeOverride(mode: string): void {
    if (this.colorModeOverride === mode) {
      return;
    }
    this.colorModeOverride = mode;
    this.themeEditSlot = this.resolvedDark() ? 'dark' : 'light';
    this.applyEffectiveTheme();
    this.syncThemeOptionSelection();
    this.persistAppearance();
  }

  private applyEffectiveTheme(): void {
    const theme: string = this.effectiveThemeName();
    for (const session of this.sessions) {
      session.controller.setTheme(theme);
    }
    // Publish for sibling windows (see onSharedThemeChanged). Writing the same
    // value again is a no-op for @StorageProp observers, so this cannot loop.
    AppStorage.setOrCreate(EFFECTIVE_THEME_KEY, theme);
    void this.recomputeChromeTokens();
  }

  // Another window changed the theme. Its chrome tokens already reached us
  // through AppStorage, but our terminal grids are ours to re-colour -- without
  // this the tab bar would re-tint while the grid kept the old palette.
  // Deliberately does NOT touch this window's slot fields or persist anything:
  // the window that made the change owns that side.
  private onSharedThemeChanged(): void {
    if (this.sharedTheme.length === 0) {
      return;
    }
    for (const session of this.sessions) {
      session.controller.setTheme(this.sharedTheme);
    }
  }

  // Re-derive the adaptive chrome from the effective theme's bg/fg/red. The
  // token object is replaced wholesale so every @StorageProp consumer
  // re-colors; the system decor buttons restyle through the ability event.
  private async recomputeChromeTokens(): Promise<void> {
    if (!this.context) {
      return;
    }
    let next = DEFAULT_CHROME_TOKENS;
    try {
      const raw = await this.context.resourceManager.getRawFileContent(
        `themes/${this.effectiveThemeName()}`);
      const preview = this.parseThemePreview(raw);
      if (preview) {
        next = deriveChromeTokens(preview.bg, preview.fg, preview.red);
      }
    } catch (err) {
      console.error('Failed to derive chrome tokens: ' + JSON.stringify(err));
    }
    this.chrome = next;
    this.context.eventHub.emit(CHROME_MODE_EVENT, next.isLight);
  }

  private applyTheme(theme: string): void {
    if (theme === this.editedThemeName()) {
      return;
    }
    if (this.themeEditSlot === 'light') {
      this.lightThemeName = theme;
    } else {
      this.darkThemeName = theme;
    }
    this.syncThemeOptionSelection();
    const editingLight: boolean = this.themeEditSlot === 'light';
    if (editingLight !== this.resolvedDark()) {
      // The edited slot is the one currently on screen: apply it live.
      this.applyEffectiveTheme();
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

  // M26: one-shot readout feedback — a small vertical tick up and back over
  // 120ms total. translateY only, never scale
  // (CJK-safe), and it is imperative so it never leaves a residual animation.
  private playFontReadoutTick(): void {
    this.getUIContext().keyframeAnimateTo({ iterations: 1 }, [
      {
        duration: DUR_READOUT_TICK_HALF,
        curve: CURVE_SHARP,
        event: () => {
          this.fontReadoutTickY = -3;
        }
      },
      {
        duration: DUR_READOUT_TICK_HALF,
        curve: CURVE_DECEL,
        event: () => {
          this.fontReadoutTickY = 0;
        }
      }
    ]);
  }

  private registerBundledFontPreviews(): void {
    if (this.fontPreviewsRegistered) {
      return;
    }
    try {
      const fontManager = this.getUIContext().getFont();
      fontManager.registerFont({
        familyName: FONT_FAMILY_MAPLE,
        familySrc: $rawfile('fonts/MapleMonoNormal-NF-CN-Regular.ttf')
      });
      fontManager.registerFont({
        familyName: FONT_FAMILY_JETBRAINS,
        familySrc: $rawfile('fonts/JetBrainsMono-Regular.ttf')
      });
      fontManager.registerFont({
        familyName: FONT_FAMILY_CASCADIA,
        familySrc: $rawfile('fonts/CascadiaMono.ttf')
      });
      fontManager.registerFont({
        familyName: FONT_FAMILY_SARASA,
        familySrc: $rawfile('fonts/SarasaFixedSC-Regular.ttf')
      });
      this.fontPreviewsRegistered = true;
    } catch (err) {
      console.error('Failed to register bundled ArkUI font previews: ' + JSON.stringify(err));
    }
  }

  private registerCustomFontPreview(): void {
    if (this.customFontPath.length === 0) {
      return;
    }
    try {
      if (!fs.accessSync(this.customFontPath)) {
        return;
      }
      this.getUIContext().getFont().registerFont({
        familyName: FONT_FAMILY_CUSTOM,
        familySrc: this.customFontPath
      });
    } catch (err) {
      console.error('Failed to register custom ArkUI font preview: ' + JSON.stringify(err));
    }
  }

  @Builder
  private buildFontChoiceButton(label: string, family: string) {
    Column({ space: 4 }) {
      Text('ls -al → 终端 0Oo')
        .fontSize(13.5)
        .fontColor(this.chrome.textPrimary)
        // Preview the sample in the ArkUI alias registered for this font; the
        // custom slot receives the same treatment after import.
        .fontFamily(family)
        .maxLines(1)
      Text(label)
        .fontSize(11)
        .fontColor(this.fontFamily === family ? this.chrome.textPrimary : this.chrome.textSecondary)
      Row()
        .width('100%')
        .height(2)
        .borderRadius(1)
        .backgroundColor(this.fontFamily === family ? this.chrome.textPrimary : '#00000000')
        // Neutral selected underline fade (accent system retired).
        .animation({ duration: DUR_STANDARD, curve: CURVE_DECEL })
    }
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 12, right: 12, top: 10, bottom: 6 })
    .borderRadius(8)
    .backgroundColor(this.chrome.panelBg2)
    .border({
      width: 1,
      color: this.fontFamily === family ? this.chrome.textPrimary : this.chrome.panelBorder
    })
    // M07 selected-face: fast border-color settle ahead of the underline.
    .animation({ duration: DUR_FAST, curve: CURVE_SHARP })
    .clip(true)
    .layoutWeight(1)
    .focusable(this.drawerShown)
    .hoverEffect(HoverEffect.Highlight)
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

  private terminalBackgroundOpacity(): number {
    return this.backgroundImagePath.length > 0 ? this.backgroundOpacity : 1;
  }

  private surfaceBackdropColor(): string {
    return this.backgroundImagePath.length > 0 ? '#00000000' : this.chrome.appBg;
  }

  // ── Cross-window tab management (menu split / move only) ─────────────────
  // Decision 2026-07-28: the system-drag pipeline (vertical lift, programmatic
  // drag session, strip drops, tear-off at the release point) is retired --
  // device testing never got the drag to start reliably; menus cover the need.
  // The context menu is the only cross-window路径:「拆分为新窗口」parks the
  // live session and launches a sibling window that claims it;「移动到窗口…」
  // hands the handle to a live window on the shared heap. Cancel/expiry paths
  // below re-adopt so a session can never be stranded.
  private recoverParkedSession(token: string, originIndex: number): void {
    const handle = sessionRegistry.claim(token);
    if (!handle) {
      return;
    }
    // Lifting the only tab auto-backfilled a blank placeholder (the window must
    // never be empty mid-drag). If the drag comes back, that placeholder is
    // redundant -- close it instead of leaving a stray empty tab behind.
    const placeholder: TerminalSessionHandle | null = this.sessions.length === 1 &&
      this.sessions[0].statusMode === 'demo' &&
      !this.sessions[0].connected &&
      !this.sessions[0].attached &&
      this.sessions[0].customName.length === 0
      ? this.sessions[0] : null;
    this.adoptSession(handle, Math.min(originIndex, this.sessions.length));
    if (placeholder) {
      this.closeSession(placeholder.id);
    }
  }

  // Launch a sibling window that claims the parked session through the Want
  // hand-off token (EntryAbility -> AppStorage -> tryAdoptHandoffSession).
  private tearOffParkedSession(token: string): void {
    if (!this.context) {
      this.recoverParkedSession(token, this.sessions.length);
      return;
    }
    const want: Want = {
      bundleName: this.context.abilityInfo.bundleName,
      abilityName: this.context.abilityInfo.name,
      parameters: { 'emberHandoffToken': token }
    };
    console.info('[EmberHandoff] split launching sibling window');
    this.context.startAbility(want).catch((err: Object): void => {
      console.error('[EmberHandoff] split startAbility failed: ' + JSON.stringify(err));
      this.recoverParkedSession(token, this.sessions.length);
    });
  }

  // Context-menu path: split this tab into a new window (no drop geometry).
  private splitSessionToNewWindow(sessionId: number): void {
    const originIndex: number = this.sessions.findIndex((s: TerminalSessionHandle) => s.id === sessionId);
    if (originIndex < 0) {
      return;
    }
    const handle = this.releaseSessionForHandoff(sessionId);
    if (!handle) {
      return;
    }
    const token: string = sessionRegistry.generateToken();
    sessionRegistry.park(token, handle, (expired: TerminalSessionHandle): void => {
      this.adoptSession(expired, Math.min(originIndex, this.sessions.length));
    });
    console.info(`[EmberHandoff] split id=${sessionId} to new window`);
    this.tearOffParkedSession(token);
  }

  // Context-menu path: same-thread direct delivery to a live sibling window
  // (its registered receive defers adoption by TAB_MOVE_ADOPT_DELAY_MS).
  // Moving the ONLY tab out closes this window: the release auto-backfills a
  // blank placeholder to keep the strip alive mid-flight, but an empty
  // disconnected shell window has no reason to stay open.
  private moveSessionToWindow(sessionId: number, stamp: number): void {
    const wasOnlyTab: boolean = this.sessions.length === 1 &&
      this.sessions[0].id === sessionId;
    const handle = this.releaseSessionForHandoff(sessionId);
    if (!handle) {
      return;
    }
    console.info(`[EmberHandoff] move id=${sessionId} -> window ${stamp}`);
    if (!sessionRegistry.deliverTo(stamp, handle)) {
      // The target window closed between menu open and click: take it back.
      this.adoptSession(handle);
      return;
    }
    if (wasOnlyTab && this.context) {
      this.context.terminateSelf().catch((err: Object): void => {
        console.error('[EmberHandoff] terminateSelf failed: ' + JSON.stringify(err));
      });
    }
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
      this.darkThemeName = settings.darkThemeName;
      this.lightThemeName = settings.lightThemeName;
      this.colorModeOverride = settings.colorModeOverride;
      this.themeEditSlot = this.resolvedDark() ? 'dark' : 'light';
      this.syncThemeOptionSelection();
      this.customFontPath = settings.customFontPath;
      this.registerCustomFontPreview();
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
        session.controller.setTheme(this.effectiveThemeName());
        session.controller.updateConfig({
          fontSize: this.fontSize,
          fontFamily: this.fontFamily,
          cursorStyle: this.cursorStyle,
          cursorBlink: this.cursorBlink
        });
      }
      this.applyBackgroundConfig();
      this.applyCustomFont();
      void this.recomputeChromeTokens();
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
      darkThemeName: this.darkThemeName,
      lightThemeName: this.lightThemeName,
      colorModeOverride: this.colorModeOverride,
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
    const effectiveOpacity = this.terminalBackgroundOpacity();
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
      this.registerCustomFontPreview();
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
