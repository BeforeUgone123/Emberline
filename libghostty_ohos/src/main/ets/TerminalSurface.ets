import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { curves, display } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { vibrator } from '@kit.SensorServiceKit';
import { TerminalController } from './TerminalController';
import {
  DEFAULT_TERMINAL_CONFIG,
  TerminalConfig,
  TerminalLinkListener,
  TerminalScrollbarState
} from './TerminalTypes';

const SCROLLBAR_POLL_INTERVAL_MS: number = 100;
const SCROLLBAR_TRACK_WIDTH: number = 12;
const SCROLLBAR_TOUCH_WIDTH: number = 18;
const SCROLLBAR_THUMB_WIDTH: number = 4;
const SCROLLBAR_MIN_THUMB_HEIGHT: number = 28;
const PRIVILEGED_PASTE_ENABLED: boolean = true;
// This HAR cannot import the app-module EmberMotion tokens (entry depends on
// libghostty-ohos, not the reverse), so the few motion values these surface
// overlays need are mirrored locally — kept in sync with EmberMotion.ets by value.
const EMBER_BOUNDARY_COLOR: string = '#D08F53';                         // 余烬铜: the accent reserved for the "hit the edge" moment
const CURVE_DECEL_LOCAL: ICurve = curves.cubicBezierCurve(0.2, 0, 0, 1); // = CURVE_DECEL
const CURVE_ACCEL_LOCAL: ICurve = curves.cubicBezierCurve(0.4, 0, 1, 1); // = CURVE_ACCEL
const DUR_FLOAT_OVERLAY: number = 180;  // M17 secure-paste float slide + fade
const DUR_OVERLAY_FADE: number = 150;   // M24 scrollbar overlay auto-hide fade
const DUR_THUMB_TWEEN: number = 100;    // M24 scrollbar thumb catch-up while not dragging
const DUR_BOUNDARY_IN: number = 120;    // M21 edge glow fade-in
const DUR_BOUNDARY_OUT: number = 200;   // M21 edge glow fade-out

@Component
export struct TerminalSurface {
  controller: TerminalController = new TerminalController();
  surfaceId: string = 'terminalSurface';
  @Prop surfaceColor: string = '#0B0D10';
  @Prop @Watch('onActiveChanged') active: boolean = true;
  // Tab visibility, independent of the drawer / tab-edit overlays. A
  // half-transparent drawer still leaves the active terminal on screen, so
  // polling and the scrollbar loop follow tab visibility rather than `active`
  // (which additionally drops while an overlay owns the keyboard).
  @Prop @Watch('onVisibleChanged') visible: boolean = true;
  @Prop @Watch('onForegroundFocusEpochChanged') foregroundFocusEpoch: number = 0;
  onLinkActivated: TerminalLinkListener | null = null;
  // Clipboard images are packed to PNG in the app sandbox and handed to the
  // host app, which decides where the file should land (local paste or a
  // remote upload) before pasting the resulting path.
  onImagePasted: ((localPath: string) => void) | null = null;

  private context: common.UIAbilityContext | null = null;
  private fallbackTimer: number = -1;
  private scrollbarTimer: number = -1;
  private foregroundFocusTimer: number = -1;
  private scrollbarDragStartOffset: number = 0;
  private pastePermissionGranted: boolean = false;
  private directPasteUnavailable: boolean = false;
  private contextMenuSelectedText: string = '';
  private contextMenuScreenContent: string = '';
  private contextMenuCanPaste: boolean = false;

  @State private appliedFontSize: number = DEFAULT_TERMINAL_CONFIG.fontSize;
  @State private useTextFallback: boolean = false;
  @State private fallbackContent: string = '';
  @State private fallbackError: string = '';
  @State private scrollbarTotal: number = 0;
  @State private scrollbarOffset: number = 0;
  @State private scrollbarVisible: number = 0;
  @State private scrollbarTrackHeight: number = 0;
  @State private scrollbarDragging: boolean = false;
  @State private securePasteVisible: boolean = false;
  // Right-click context menu, driven by the native controlled path rather than
  // ArkUI's unconditional ResponseType.RightClick: the menu only opens when the
  // native mouse handler decided the right-click was NOT forwarded to a
  // mouse-tracking shell (see TerminalController.setContextMenuListener), so the
  // app menu and the shell's own mouse handling are mutually exclusive.
  @State private contextMenuVisible: boolean = false;
  @State private contextMenuAnchorX: number = 0;
  @State private contextMenuAnchorY: number = 0;
  // M21 boundary glow: opacity of the top / bottom ember edge lines, flashed on
  // the rising edge of reaching the scrollback top / bottom. Primed `true` so the
  // initial at-top position on attach never counts as an arrival.
  @State private topBoundaryGlow: number = 0;
  @State private bottomBoundaryGlow: number = 0;
  private prevAtTop: boolean = true;
  private prevAtBottom: boolean = true;

  aboutToAppear(): void {
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.controller.setPollingSuspended(!this.visible);
    this.controller.setConfigListener((config: TerminalConfig) => {
      this.appliedFontSize = config.fontSize;
    });
    this.controller.setLinkListener((url: string) => {
      this.handleLinkActivated(url);
    });
    this.controller.setCopyRequestListener((text: string): void => {
      this.copyTerminalTextToClipboard(text);
    });
    this.controller.setPasteRequestListener((): void => {
      void this.pasteFromClipboardOrShowSecureButton();
    });
    this.controller.setContextMenuListener((x: number, y: number): void => {
      this.showContextMenuAtPixel(x, y);
    });
    this.appliedFontSize = this.controller.getConfig().fontSize;
  }

  aboutToDisappear(): void {
    this.stopFallbackPolling();
    this.stopScrollbarPolling();
    this.stopForegroundImeRequest();
    this.controller.setImeActive(false);
    this.controller.setConfigListener(null);
    this.controller.setLinkListener(null);
    this.controller.setCopyRequestListener(null);
    this.controller.setPasteRequestListener(null);
    this.controller.setContextMenuListener(null);
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      this.buildTerminalXComponent();
      this.buildContextMenuAnchor();
      if (this.useTextFallback) {
        this.buildTextFallback();
      }
      if (this.shouldShowScrollbar()) {
        this.buildScrollbarOverlay();
        this.buildBoundaryGlow();
      }
      if (this.securePasteVisible) {
        this.buildSecurePasteOverlay();
      }
    }
    .width('100%')
    .height('100%')
    .padding(0)
    .backgroundColor(this.surfaceColor)
  }

  @Builder
  private buildTerminalXComponent() {
    XComponent({
      id: this.surfaceId,
      type: XComponentType.SURFACE,
      libraryname: 'libghostty_ohos'
    })
      .onLoad((nativeContext?: Object) => {
        if (!nativeContext || !this.context) {
          return;
        }

        this.controller.bindNative(nativeContext, this.context, this.getDisplayDensity(), this.surfaceId);
        this.controller.setImeActive(this.active);
        this.controller.setInputBlocked(!this.active);
        this.useTextFallback = !this.controller.isRendererReady();
        this.fallbackError = this.controller.getRendererError();
        this.appliedFontSize = this.controller.getConfig().fontSize;
        this.syncScrollbarState();
        if (this.visible) {
          this.startScrollbarPolling();
        }
        if (this.useTextFallback) {
          this.syncFallbackScreen();
          this.startFallbackPolling();
        } else {
          this.stopFallbackPolling();
        }
      })
      .onDestroy(() => {
        this.stopFallbackPolling();
        this.stopScrollbarPolling();
        this.controller.setImeActive(false);
        this.controller.unbindNative();
      })
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        const density = this.getDisplayDensity();
        const globalX = Number(newValue.globalPosition?.x ?? 0);
        const globalY = Number(newValue.globalPosition?.y ?? 0);
        const width = Number(newValue.width ?? 0);
        const height = Number(newValue.height ?? 0);
        if (Number.isFinite(globalX) && Number.isFinite(globalY) &&
          Number.isFinite(width) && Number.isFinite(height)) {
          this.controller.setSurfaceFrame(
            globalX * density,
            globalY * density,
            width * density,
            height * density
          );
        }
      })
      .onTouch((_event?: TouchEvent) => {
        this.requestTerminalFocus();
      })
      // The component id must match the surface id: focusControl.requestFocus
      // looks components up by this id, and without it every programmatic
      // focus restore (tab switch, drawer close) silently no-opped.
      .id(this.surfaceId)
      .focusable(true)
      .focusOnTouch(true)
      .defaultFocus(true)
      .width('100%')
      .height('100%')
      .backgroundColor(this.surfaceColor)
  }

  // Invisible 1x1 anchor that tracks the last right-click point. The controlled
  // context menu (isShown overload, API 11+; visibility is owned by
  // contextMenuVisible, which only the native controlled path flips true, so a
  // right-click that was forwarded to a mouse-tracking shell never also pops
  // the app menu) must bind HERE and not on the XComponent itself: placement is
  // resolved against the bound component, and against the full-screen surface
  // every side overflows, so ArkUI falls back to centering the menu on screen
  // regardless of offset. With a 1x1 anchor at the pointer, BottomLeft means
  // "open at the pointer, desktop style", and ArkUI still auto-flips near
  // screen edges.
  @Builder
  private buildContextMenuAnchor() {
    Column()
      .width(1)
      .height(1)
      .hitTestBehavior(HitTestMode.None)
      .position({ x: this.contextMenuAnchorX, y: this.contextMenuAnchorY })
      .bindContextMenu(this.contextMenuVisible, this.buildTerminalContextMenu(), {
        placement: Placement.BottomLeft,
        onDisappear: () => {
          // Must clear the flag or the menu can never reopen.
          this.contextMenuVisible = false;
        }
      })
  }

  // Native reports the right-click point in physical px relative to the surface
  // (matching the renderer's cell metrics). Convert to vp with the same display
  // density the surface uses for setSurfaceFrame, move the anchor there, then
  // open the controlled menu.
  private showContextMenuAtPixel(pxX: number, pxY: number): void {
    const density = Math.max(1, this.getDisplayDensity());
    const vpX = Number.isFinite(pxX) ? pxX / density : 0;
    const vpY = Number.isFinite(pxY) ? pxY / density : 0;
    this.contextMenuAnchorX = vpX;
    this.contextMenuAnchorY = vpY;
    this.contextMenuVisible = true;
  }

  @Builder
  private buildScrollbarOverlay() {
    Column() {
      Stack() {
        Column()
          .width(SCROLLBAR_TRACK_WIDTH)
          .height('100%')
          .backgroundColor('#00000000')

        Column()
          .width(SCROLLBAR_THUMB_WIDTH)
          .height(this.getScrollbarThumbHeight())
          .borderRadius(SCROLLBAR_THUMB_WIDTH / 2)
          .backgroundColor(this.scrollbarDragging ? '#FFD8DEE9' : '#AA7F8BA0')
          // M24: freeze height / color changes (no relayout tween) before opening
          // a position-only animation, so the every-100ms polled thumb top glides
          // continuously instead of jumping a notch at a time.
          .animation({ duration: 0 })
          .position({
            x: (SCROLLBAR_TRACK_WIDTH - SCROLLBAR_THUMB_WIDTH) / 2,
            y: this.getScrollbarThumbTop()
          })
          .animation({ duration: this.scrollbarDragging ? 0 : DUR_THUMB_TWEEN, curve: Curve.Linear })
      }
      .width(SCROLLBAR_TRACK_WIDTH)
      .height('100%')
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        const height = Number(newValue.height ?? 0);
        if (Number.isFinite(height) && height >= 0) {
          this.scrollbarTrackHeight = height;
        }
      })
      .gesture(
        PanGesture({ direction: PanDirection.Vertical })
          .onActionStart((_event: GestureEvent) => {
            this.syncScrollbarState();
            this.scrollbarDragging = true;
            this.scrollbarDragStartOffset = this.scrollbarOffset;
          })
          .onActionUpdate((event: GestureEvent) => {
            this.handleScrollbarDrag(Number(event.offsetY ?? 0));
          })
          .onActionEnd((_event: GestureEvent) => {
            this.finishScrollbarDrag();
          })
          .onActionCancel((_event: GestureEvent) => {
            this.finishScrollbarDrag();
          })
      )
    }
    .width(SCROLLBAR_TOUCH_WIDTH)
    .height('100%')
    .padding({ top: 8, bottom: 8 })
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    // M24: the overlay auto-hides with the scrollbar's presence, so it fades in /
    // out instead of hard mounting / unmounting.
    .transition(TransitionEffect.OPACITY.animation({ duration: DUR_OVERLAY_FADE, curve: CURVE_DECEL_LOCAL }))
  }

  // M21: two thin ember edge lines that flash on the rising edge of reaching the
  // scrollback top / bottom. Full-size but draws only the 2px caps; hit-test None
  // so it never intercepts touches, and the content itself never moves.
  @Builder
  private buildBoundaryGlow() {
    Column() {
      Row()
        .width('100%')
        .height(2)
        .backgroundColor(EMBER_BOUNDARY_COLOR)
        .opacity(this.topBoundaryGlow)
      Row()
        .width('100%')
        .height(2)
        .backgroundColor(EMBER_BOUNDARY_COLOR)
        .opacity(this.bottomBoundaryGlow)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildTextFallback() {
    Scroll() {
      Text(this.fallbackContent.length > 0 ? this.fallbackContent : this.fallbackError)
        .width('100%')
        .textAlign(TextAlign.Start)
        .fontSize(this.appliedFontSize)
        .fontFamily('monospace')
        .fontColor('#D8DEE9')
        .lineHeight(this.appliedFontSize * 1.35)
        .padding(12)
    }
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.None)
    .width('100%')
    .height('100%')
    .backgroundColor(this.surfaceColor)
  }

  @Builder
  private buildSecurePasteOverlay() {
    Column() {
      Row({ space: 8 }) {
        PasteButton({ icon: PasteIconStyle.LINES, text: PasteDescription.PASTE })
          .width(112)
          .height(38)
          .fontSize(14)
          .fontColor('#FF0B0D10')
          .backgroundColor('#FFF4F7FB')
          .borderRadius(8)
          .onClick((_event: ClickEvent, result: PasteButtonOnClickResult) => {
            if (PasteButtonOnClickResult.SUCCESS === result) {
              void this.pasteFromClipboardAfterSecureGrant();
              this.securePasteVisible = false;
            }
            this.requestTerminalFocus();
          })

        Button('取消')
          .width(56)
          .height(38)
          .fontSize(13)
          .fontColor('#FFE8EEF8')
          .backgroundColor('#FF2A303A')
          .borderRadius(8)
          .onClick(() => {
            this.securePasteVisible = false;
            this.requestTerminalFocus();
          })
      }
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .backgroundColor('#EE11161D')
      .borderRadius(12)
    }
    // Size-to-content on purpose: a transparent full-screen layer would let
    // touches fall through to the XComponent underneath.
    .margin({ top: 12, right: 12 })
    // M17: top-edge slide + fade on show / hide.
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: -8 }))
      .animation({ duration: DUR_FLOAT_OVERLAY, curve: CURVE_DECEL_LOCAL }))
  }

  private getDisplayDensity(): number {
    try {
      return display.getDefaultDisplaySync().densityPixels;
    } catch (err) {
      console.error('Failed to get display density: ' + JSON.stringify(err));
      return 1;
    }
  }

  private requestTerminalFocus(): void {
    if (!this.active) {
      return;
    }
    this.controller.setImeActive(true);
    focusControl.requestFocus(this.surfaceId);
  }

  private onForegroundFocusEpochChanged(): void {
    this.scheduleForegroundImeRequest();
  }

  // `active` gates only IME ownership and focus: an open drawer / tab editor
  // flips it false so the keyboard hides, while the (still on-screen)
  // terminal keeps polling via `visible`.
  private onActiveChanged(): void {
    if (this.active) {
      this.controller.setInputBlocked(false);
      this.controller.setImeActive(true);
      this.scheduleForegroundImeRequest();
      return;
    }

    // Overlay open (drawer / tab editor): key and trackpad-axis events bypass
    // the ArkUI hit-test shield, so the native side must go deaf explicitly.
    this.controller.setInputBlocked(true);
    this.controller.setImeActive(false);
    this.stopForegroundImeRequest();
  }

  // Tab visibility owns the controller polling budget and the scrollbar
  // refresh loop, so a background tab throttles to the 500ms cadence and stops
  // scrollbar polling, but a foreground tab under a translucent drawer keeps
  // running its task output and title at full speed.
  private onVisibleChanged(): void {
    this.controller.setPollingSuspended(!this.visible);
    if (this.visible) {
      this.syncScrollbarState();
      this.startScrollbarPolling();
    } else {
      this.stopScrollbarPolling();
    }
  }

  private scheduleForegroundImeRequest(): void {
    this.stopForegroundImeRequest();
    this.foregroundFocusTimer = setTimeout(() => {
      this.foregroundFocusTimer = -1;
      if (!this.active) {
        return;
      }
      this.requestTerminalFocus();
    }, 120) as number;
  }

  private stopForegroundImeRequest(): void {
    if (this.foregroundFocusTimer < 0) {
      return;
    }
    clearTimeout(this.foregroundFocusTimer);
    this.foregroundFocusTimer = -1;
  }

  private startFallbackPolling(): void {
    if (this.fallbackTimer >= 0) {
      return;
    }

    this.fallbackTimer = setInterval(() => {
      this.syncFallbackScreen();
    }, 100) as number;
  }

  private stopFallbackPolling(): void {
    if (this.fallbackTimer < 0) {
      return;
    }

    clearInterval(this.fallbackTimer);
    this.fallbackTimer = -1;
  }

  private startScrollbarPolling(): void {
    if (this.scrollbarTimer >= 0) {
      return;
    }

    this.scrollbarTimer = setInterval(() => {
      this.syncScrollbarState();
    }, SCROLLBAR_POLL_INTERVAL_MS) as number;
  }

  private stopScrollbarPolling(): void {
    if (this.scrollbarTimer < 0) {
      return;
    }

    clearInterval(this.scrollbarTimer);
    this.scrollbarTimer = -1;
  }

  private syncScrollbarState(): void {
    if (!this.controller.isAttached()) {
      this.scrollbarTotal = 0;
      this.scrollbarOffset = 0;
      this.scrollbarVisible = 0;
      this.resetBoundaryEdges();
      return;
    }

    try {
      const state: TerminalScrollbarState = this.controller.getScrollbarState();
      const total = this.normalizeScrollbarValue(state.total);
      const visible = Math.min(total, this.normalizeScrollbarValue(state.visible));
      const maxOffset = Math.max(0, total - visible);
      const clampedOffset = Math.min(maxOffset, this.normalizeScrollbarValue(state.offset));
      this.scrollbarTotal = total;
      this.scrollbarVisible = visible;
      this.scrollbarOffset = clampedOffset;
      this.detectBoundaryEdges(clampedOffset, maxOffset);
    } catch (err) {
      this.scrollbarTotal = 0;
      this.scrollbarOffset = 0;
      this.scrollbarVisible = 0;
      this.resetBoundaryEdges();
      console.error('Failed to sync terminal scrollbar state: ' + JSON.stringify(err));
    }
  }

  // M21: flash the ember edge line on the RISING edge of reaching the scrollback
  // top / bottom. Polling gives position, not intent, so this fires once on
  // arrival — it cannot see an over-scroll attempt made while already parked at
  // the edge. No-op until there is real scrollback to hit.
  private detectBoundaryEdges(offset: number, maxOffset: number): void {
    if (maxOffset <= 0) {
      this.prevAtTop = true;
      this.prevAtBottom = true;
      return;
    }
    const atTop = offset <= 0;
    const atBottom = offset >= maxOffset;
    if (atTop && !this.prevAtTop) {
      this.flashBoundary(true);
    }
    if (atBottom && !this.prevAtBottom) {
      this.flashBoundary(false);
    }
    this.prevAtTop = atTop;
    this.prevAtBottom = atBottom;
  }

  private resetBoundaryEdges(): void {
    this.prevAtTop = true;
    this.prevAtBottom = true;
    this.topBoundaryGlow = 0;
    this.bottomBoundaryGlow = 0;
  }

  // opacity 0 -> 0.5 over 120ms, then a longer 200ms accelerate-away fade. Only
  // the 2px edge line's opacity moves; the terminal content never shifts.
  private flashBoundary(top: boolean): void {
    this.getUIContext().keyframeAnimateTo({ iterations: 1 }, [
      {
        duration: DUR_BOUNDARY_IN,
        curve: CURVE_DECEL_LOCAL,
        event: () => {
          if (top) {
            this.topBoundaryGlow = 0.5;
          } else {
            this.bottomBoundaryGlow = 0.5;
          }
        }
      },
      {
        duration: DUR_BOUNDARY_OUT,
        curve: CURVE_ACCEL_LOCAL,
        event: () => {
          if (top) {
            this.topBoundaryGlow = 0;
          } else {
            this.bottomBoundaryGlow = 0;
          }
        }
      }
    ]);
  }

  private shouldShowScrollbar(): boolean {
    return this.scrollbarVisible > 0 && this.scrollbarTotal > this.scrollbarVisible;
  }

  private getScrollbarMaxOffset(): number {
    return Math.max(0, this.scrollbarTotal - this.scrollbarVisible);
  }

  private getScrollbarThumbHeight(): number {
    const trackHeight = Math.max(1, this.scrollbarTrackHeight);
    if (!this.shouldShowScrollbar() || this.scrollbarTotal <= 0) {
      return trackHeight;
    }

    const proportionalHeight = trackHeight * (this.scrollbarVisible / this.scrollbarTotal);
    return Math.min(trackHeight, Math.max(SCROLLBAR_MIN_THUMB_HEIGHT, proportionalHeight));
  }

  private getScrollbarThumbTop(): number {
    const trackHeight = Math.max(1, this.scrollbarTrackHeight);
    const thumbHeight = this.getScrollbarThumbHeight();
    const maxTravel = Math.max(0, trackHeight - thumbHeight);
    const maxOffset = this.getScrollbarMaxOffset();
    if (maxTravel <= 0 || maxOffset <= 0) {
      return 0;
    }

    return this.clampNumber((this.scrollbarOffset / maxOffset) * maxTravel, 0, maxTravel);
  }

  private handleScrollbarDrag(deltaY: number): void {
    const maxOffset = this.getScrollbarMaxOffset();
    const maxTravel = Math.max(1, this.scrollbarTrackHeight - this.getScrollbarThumbHeight());
    if (maxOffset <= 0) {
      return;
    }

    const desiredOffset = Math.round(this.clampNumber(
      this.scrollbarDragStartOffset + (deltaY / maxTravel) * maxOffset,
      0,
      maxOffset
    ));
    this.controller.scrollToOffset(desiredOffset);
    this.syncScrollbarState();
  }

  private finishScrollbarDrag(): void {
    this.scrollbarDragging = false;
    this.syncScrollbarState();
    this.requestTerminalFocus();
  }

  private normalizeScrollbarValue(value: number): number {
    if (!Number.isFinite(value)) {
      return 0;
    }
    return Math.max(0, Math.floor(value));
  }

  private clampNumber(value: number, min: number, max: number): number {
    return Math.min(max, Math.max(min, value));
  }

  private syncFallbackScreen(): void {
    if (!this.controller.isAttached()) {
      return;
    }

    try {
      const content = this.controller.getScreenContent();
      if (content.length > 0) {
        this.fallbackContent = content;
      } else if (this.fallbackError.length > 0) {
        this.fallbackContent = this.fallbackError + '\n\n等待终端输出…';
      }
    } catch (err) {
      this.fallbackContent = '读取终端缓冲区失败';
      console.error('Failed to sync fallback screen: ' + JSON.stringify(err));
    }
  }

  private handleLinkActivated(url: string): void {
    if (url.length === 0) {
      return;
    }

    if (this.onLinkActivated) {
      this.onLinkActivated(url);
      return;
    }

    if (!this.context) {
      return;
    }

    this.context.openLink(url).catch((err: Object) => {
      console.error('Failed to open terminal link: ' + JSON.stringify(err));
    });
  }

  @Builder
  private buildTerminalContextMenu() {
    Menu() {
      if (this.hasTerminalSelection()) {
        MenuItem({ content: '复制' })
          .onClick(() => {
            this.copySelectionToClipboard();
          })
      }
      MenuItem({ content: '粘贴' })
        .onClick(() => {
          void this.pasteFromClipboardOrShowSecureButton();
        })
      if (this.hasTerminalSelection()) {
        MenuItem({ content: '取消选择' })
          .onClick(() => {
            this.controller.clearSelection();
            this.requestTerminalFocus();
          })
      }
      if (this.hasTerminalScreenContent()) {
        MenuItem({ content: '复制整屏' })
          .onClick(() => {
            this.copyToClipboard(this.controller.getScreenContent());
          })
      }
    }
  }

  private hasTerminalSelection(): boolean {
    return this.controller.getSelectedText().length > 0;
  }

  private hasTerminalScreenContent(): boolean {
    return this.controller.getScreenContent().trim().length > 0;
  }

  private copyToClipboard(text: string): void {
    if (text.length === 0) {
      return;
    }
    const clipboard = pasteboard.getSystemPasteboard();
    try {
      clipboard.setDataSync(pasteboard.createPlainTextData(text));
      this.showCopyFeedback();
    } catch (err) {
      console.error('Failed to copy terminal text: ' + JSON.stringify(err));
    }
    this.requestTerminalFocus();
  }

  // Copy is otherwise silent, so a brief toast plus a light haptic confirm the
  // pasteboard write without stealing focus from the terminal. Both are
  // best-effort: the haptic is dropped on devices without the preset effect.
  private showCopyFeedback(): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: '已复制', duration: 1200 });
    } catch (err) {
      console.error('Failed to show copy toast: ' + JSON.stringify(err));
    }
    try {
      vibrator.startVibration(
        { type: 'preset', effectId: 'haptic.clock.timer' },
        { usage: 'physicalFeedback' }
      ).catch((_err: Object) => {
        // Best-effort haptic; ignore devices lacking the preset or permission.
      });
    } catch (_err) {
      // Some devices have no vibrator; the copy still succeeds silently.
    }
  }

  private copySelectionToClipboard(): void {
    const selectedText = this.controller.getSelectedText();
    this.copyToClipboard(selectedText);
  }

  private copyTerminalTextToClipboard(text: string): void {
    if (text.length > 0) {
      this.copyToClipboard(text);
      return;
    }
    this.copySelectionToClipboard();
  }

  private showSecurePasteButton(): void {
    this.securePasteVisible = true;
  }

  private async pasteFromClipboardAfterSecureGrant(): Promise<void> {
    try {
      if (await this.tryPasteClipboardImage()) {
        this.requestTerminalFocus();
        return;
      }
      const text = await this.readClipboardText();
      if (text.length > 0) {
        this.controller.paste(text);
      }
    } catch (err) {
      console.error('Failed to paste into terminal: ' + JSON.stringify(err));
    }
    this.requestTerminalFocus();
  }

  private async pasteFromClipboardOrShowSecureButton(): Promise<void> {
    if (!PRIVILEGED_PASTE_ENABLED || this.directPasteUnavailable || !await this.ensurePrivilegedPastePermission()) {
      this.showSecurePasteButton();
      return;
    }

    if (!await this.pasteFromClipboardDirect()) {
      this.showSecurePasteButton();
    }
  }

  private async ensurePrivilegedPastePermission(): Promise<boolean> {
    if (this.pastePermissionGranted) {
      return true;
    }
    if (!this.context) {
      return false;
    }

    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const result = await atManager.requestPermissionsFromUser(this.context, ['ohos.permission.READ_PASTEBOARD']);
      const authResults = result.authResults || [];
      const granted = authResults.length === 0 || authResults[0] === 0;
      this.pastePermissionGranted = granted;
      if (!granted) {
        this.directPasteUnavailable = true;
      }
      return granted;
    } catch (err) {
      this.directPasteUnavailable = true;
      console.error('Failed to request privileged terminal paste permission: ' + JSON.stringify(err));
      return false;
    }
  }

  private async pasteFromClipboardDirect(): Promise<boolean> {
    try {
      if (await this.tryPasteClipboardImage()) {
        this.requestTerminalFocus();
        return true;
      }
      const text = await this.readClipboardText();
      if (text.length > 0) {
        this.controller.paste(text);
      }
      this.requestTerminalFocus();
      return true;
    } catch (err) {
      this.directPasteUnavailable = true;
      console.error('Failed to paste into terminal through privileged permission: ' + JSON.stringify(err));
      this.requestTerminalFocus();
      return false;
    }
  }

  // Detects an image on the clipboard (screenshot pixel map), packs it as a
  // PNG into the sandbox, and lets the host app decide how to paste it.
  // Returns false when the clipboard holds no image so text paste proceeds.
  private async tryPasteClipboardImage(): Promise<boolean> {
    if (!this.onImagePasted || !this.context) {
      return false;
    }
    try {
      const clipboard = pasteboard.getSystemPasteboard();
      if (!clipboard.hasDataSync()) {
        return false;
      }
      const data = await clipboard.getData();
      if (data.getRecordCount() === 0) {
        return false;
      }
      const record = data.getRecord(0);
      if (record.mimeType !== pasteboard.MIMETYPE_PIXELMAP || !record.pixelMap) {
        return false;
      }
      const packer = image.createImagePacker();
      const packed = await packer.packing(record.pixelMap, { format: 'image/png', quality: 100 });
      const dir = `${this.context.filesDir}/pastes`;
      try {
        if (!fs.accessSync(dir)) {
          fs.mkdirSync(dir);
        }
      } catch (_dirErr) {
        fs.mkdirSync(dir);
      }
      const path = `${dir}/paste-${Date.now()}.png`;
      const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      fs.writeSync(file.fd, packed);
      fs.closeSync(file);
      this.onImagePasted(path);
      return true;
    } catch (err) {
      console.error('Failed to paste clipboard image: ' + JSON.stringify(err));
      return false;
    }
  }

  private async readClipboardText(): Promise<string> {
    const clipboard = pasteboard.getSystemPasteboard();
    if (!clipboard.hasDataSync()) {
      return '';
    }

    const data = await clipboard.getData();
    let text = data.getPrimaryText();
    if (text.length === 0 && data.getRecordCount() > 0) {
      const primaryRecord = data.getRecord(0);
      text = primaryRecord.toPlainText();
    }
    return text;
  }
}
