import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import {
  TerminalAttachmentListener,
  CellMetrics,
  cloneTerminalConfig,
  CursorPosition,
  DEFAULT_TERMINAL_CONFIG,
  DEFAULT_THEME_NAME,
  TerminalConfig,
  TerminalConfigPatch,
  TerminalContextMenuListener,
  TerminalCopyRequestListener,
  TerminalInputListener,
  TerminalLinkListener,
  TerminalNotificationListener,
  TerminalPasteRequestListener,
  TerminalScrollbarState,
  TerminalSearchStatus,
  TerminalSize,
  TerminalTitleListener
} from './TerminalTypes';

// These are chrome/control events, not keystroke transport (native input is
// pushed through setInputCallback). A 20 Hz drain keeps gestures and titles
// responsive without pinning the ArkTS thread to six N-API calls every frame.
const UI_EVENT_POLL_INTERVAL_MS: number = 50;

interface TerminalNativeBridge {
  writeInput: (surfaceId: string, data: string) => void;
  pasteText: (surfaceId: string, data: string) => void;
  registerCustomFont: (surfaceId: string, fontPath: string) => boolean;
  feedOutput: (surfaceId: string, data: string) => void;
  requestIme: (surfaceId: string) => void;
  setImeActive: (surfaceId: string, active: boolean) => void;
  setInputBlocked: (surfaceId: string, blocked: boolean) => void;
  drainPendingInput: (surfaceId: string) => string;
  setInputCallback: (surfaceId: string, callback: ((data: string) => void) | null) => void;
  drainPendingLinkActivation: (surfaceId: string) => string;
  drainPendingTitle: (surfaceId: string) => string;
  drainPendingNotification: (surfaceId: string) => string;
  drainPendingContextMenuRequest: (surfaceId: string) => string;
  drainPendingCopyRequest: (surfaceId: string) => string;
  drainPendingPasteRequest: (surfaceId: string) => string;
  resizeTerminal: (surfaceId: string, cols: number, rows: number) => void;
  getScreenContent: (surfaceId: string) => string;
  getCursorPosition: (surfaceId: string) => CursorPosition;
  getTerminalSize: (surfaceId: string) => TerminalSize;
  getCellMetrics: (surfaceId: string) => CellMetrics;
  setFilesDir: (surfaceId: string, filesDir: string) => void;
  setResourceManager: (surfaceId: string, resourceManager: Object) => void;
  setWindowInfo: (surfaceId: string, windowId: number, left: number, top: number) => void;
  setSurfaceOrigin: (surfaceId: string, left: number, top: number) => void;
  setSurfaceFrame: (surfaceId: string, left: number, top: number, width: number, height: number) => void;
  scrollView: (surfaceId: string, delta: number) => void;
  resetScroll: (surfaceId: string) => void;
  getScrollbackSize: (surfaceId: string) => number;
  getScrollbarState: (surfaceId: string) => TerminalScrollbarState;
  scrollToOffset: (surfaceId: string, offset: number) => void;
  startSelection: (surfaceId: string, row: number, col: number) => void;
  updateSelection: (surfaceId: string, row: number, col: number) => void;
  clearSelection: (surfaceId: string) => void;
  getSelectedText: (surfaceId: string) => string;
  startSearch: (surfaceId: string, query: string) => void;
  searchSelection: (surfaceId: string) => void;
  updateSearch: (surfaceId: string, query: string) => void;
  navigateSearch: (surfaceId: string, next: boolean) => void;
  endSearch: (surfaceId: string) => void;
  getSearchStatus: (surfaceId: string) => TerminalSearchStatus;
  setConfig: (surfaceId: string, config: TerminalConfig) => void;
  setDensity: (surfaceId: string, density: number) => void;
  loadTheme: (surfaceId: string, themeName: string) => boolean;
  getThemeList: (surfaceId: string) => string[];
  isRendererReady: (surfaceId: string) => boolean;
  getRendererError: (surfaceId: string) => string;
}

type TerminalConfigListener = (config: TerminalConfig, themeName: string) => void;
type TerminalSizeListener = (size: TerminalSize) => void;

export class TerminalController {
  private native: TerminalNativeBridge | null = null;
  private nativeSurfaceId: string = '';
  private config: TerminalConfig = cloneTerminalConfig(DEFAULT_TERMINAL_CONFIG);
  private themeName: string = DEFAULT_THEME_NAME;
  // Tracks only successful native applications. A failed load remains
  // retryable, while repeated startup/config notifications cannot re-read and
  // reparse the same raw theme for an already configured surface.
  private appliedThemeName: string = '';
  private configListener: TerminalConfigListener | null = null;
  private inputListener: TerminalInputListener | null = null;
  private linkListener: TerminalLinkListener | null = null;
  private contextMenuListener: TerminalContextMenuListener | null = null;
  private titleListener: TerminalTitleListener | null = null;
  private notificationListener: TerminalNotificationListener | null = null;
  private copyRequestListener: TerminalCopyRequestListener | null = null;
  private pasteRequestListener: TerminalPasteRequestListener | null = null;
  private attachmentListener: TerminalAttachmentListener | null = null;
  private sizeListener: TerminalSizeListener | null = null;
  private inputPollTimer: number = -1;
  // Hidden tabs suspend the full input drain. Their title-only cadence is
  // supplied by the surface so inactive tabs can stay responsive in the
  // foreground without keeping the same cadence after the app is backgrounded.
  private pollingSuspended: boolean = false;
  private titlePollTimer: number = -1;
  private titlePollIntervalMs: number = 500;
  private trackedWindow: window.Window | null = null;
  private windowRectListener: ((options: window.RectChangeOptions) => void) | null = null;
  private lastReportedSize: TerminalSize = { cols: 0, rows: 0 };

  bindNative(native: Object, context: common.UIAbilityContext, density: number, surfaceId: string): void {
    this.native = native as TerminalNativeBridge;
    this.nativeSurfaceId = surfaceId;
    this.native.setDensity(this.nativeSurfaceId, density);
    this.native.setFilesDir(this.nativeSurfaceId, context.filesDir);
    this.native.setResourceManager(this.nativeSurfaceId, context.resourceManager);
    this.native.setInputCallback(this.nativeSurfaceId, this.inputListener);
    this.appliedThemeName = '';
    this.applyTheme();
    if (this.titleListener) {
      this.startInputPolling();
    }
    this.applyConfig();
    this.startInputPolling();
    if (this.pollingSuspended) {
      this.startBackgroundTitlePolling();
    }
    this.bindWindowMetadata(context);
    this.notifyAttachmentChanged(true);
  }

  unbindNative(): void {
    if (this.native) {
      this.native.setInputCallback(this.nativeSurfaceId, null);
    }
    this.unbindWindowMetadata();
    this.stopInputPolling();
    this.stopBackgroundTitlePolling();
    this.native = null;
    this.nativeSurfaceId = '';
    this.appliedThemeName = '';
    this.notifyAttachmentChanged(false);
  }

  isAttached(): boolean {
    return this.native !== null;
  }

  // Native surface id this controller is bound to (empty when unbound). Lets a
  // driver point the native direct-output sink at the right renderer surface.
  getSurfaceId(): string {
    return this.native ? this.nativeSurfaceId : '';
  }

  setConfig(config: TerminalConfig): void {
    this.config = cloneTerminalConfig(config);
    this.applyConfig();
    this.notifyConfigChanged();
  }

  updateConfig(patch: TerminalConfigPatch): void {
    const nextConfig = cloneTerminalConfig(this.config);
    if (patch.fontSize !== undefined) {
      nextConfig.fontSize = patch.fontSize;
    }
    if (patch.fontFamily !== undefined) {
      nextConfig.fontFamily = patch.fontFamily;
    }
    if (patch.scrollbackLines !== undefined) {
      nextConfig.scrollbackLines = patch.scrollbackLines;
    }
    if (patch.bgColor !== undefined) {
      nextConfig.bgColor = patch.bgColor;
    }
    if (patch.fgColor !== undefined) {
      nextConfig.fgColor = patch.fgColor;
    }
    if (patch.cursorStyle !== undefined) {
      nextConfig.cursorStyle = patch.cursorStyle;
    }
    if (patch.cursorBlink !== undefined) {
      nextConfig.cursorBlink = patch.cursorBlink;
    }
    if (patch.bgOpacity !== undefined) {
      nextConfig.bgOpacity = patch.bgOpacity;
    }

    this.setConfig(nextConfig);
  }

  getConfig(): TerminalConfig {
    return cloneTerminalConfig(this.config);
  }

  setTheme(themeName: string): boolean {
    const changed: boolean = this.themeName !== themeName;
    this.themeName = themeName;
    const loaded = this.applyTheme();
    if (changed) {
      this.notifyConfigChanged();
    }
    return loaded;
  }

  getThemeName(): string {
    return this.themeName;
  }

  getThemeList(): string[] {
    if (!this.native) {
      return [];
    }
    return this.native.getThemeList(this.nativeSurfaceId);
  }

  setConfigListener(listener: TerminalConfigListener | null): void {
    this.configListener = listener;
    this.notifyConfigChanged();
  }

  setInputListener(listener: TerminalInputListener | null): void {
    this.inputListener = listener;
    if (this.native) {
      this.native.setInputCallback(this.nativeSurfaceId, this.inputListener);
    }
    this.refreshInputPolling();
  }

  setLinkListener(listener: TerminalLinkListener | null): void {
    this.linkListener = listener;
    this.refreshInputPolling();
  }

  setContextMenuListener(listener: TerminalContextMenuListener | null): void {
    this.contextMenuListener = listener;
    this.refreshInputPolling();
  }

  setTitleListener(listener: TerminalTitleListener | null): void {
    this.titleListener = listener;
    this.refreshInputPolling();
  }

  setNotificationListener(listener: TerminalNotificationListener | null): void {
    this.notificationListener = listener;
    this.refreshInputPolling();
  }

  setCopyRequestListener(listener: TerminalCopyRequestListener | null): void {
    this.copyRequestListener = listener;
    this.refreshInputPolling();
  }

  setPasteRequestListener(listener: TerminalPasteRequestListener | null): void {
    this.pasteRequestListener = listener;
    this.refreshInputPolling();
  }

  // One-tap accessory-bar entry points: reuse the same surface listeners the
  // native shortcut path drains, so behaviour matches Ctrl+Shift+C / Ctrl+V.
  requestCopy(): void {
    if (this.copyRequestListener) {
      this.copyRequestListener('');
    }
  }

  requestPaste(): void {
    if (this.pasteRequestListener) {
      this.pasteRequestListener();
    }
  }

  setPollingSuspended(suspended: boolean, titlePollIntervalMs: number = 500): void {
    const intervalChanged: boolean = this.titlePollIntervalMs !== titlePollIntervalMs;
    if (this.pollingSuspended === suspended && !intervalChanged) {
      return;
    }
    this.pollingSuspended = suspended;
    this.titlePollIntervalMs = titlePollIntervalMs;
    if (suspended) {
      this.stopInputPolling();
      if (intervalChanged) {
        this.stopBackgroundTitlePolling();
      }
      this.drainPendingTitleOnce();
      this.drainPendingNotificationOnce();
      this.startBackgroundTitlePolling();
    } else {
      this.stopBackgroundTitlePolling();
      this.refreshInputPolling();
    }
  }

  private drainPendingNotificationOnce(): void {
    if (!this.native || !this.notificationListener || !this.native.drainPendingNotification) {
      return;
    }
    const pending = this.native.drainPendingNotification(this.nativeSurfaceId);
    if (pending.length > 0) {
      this.notificationListener(pending.startsWith('T') ? pending.slice(1) : '');
    }
  }

  private drainPendingTitleOnce(): void {
    if (!this.native || !this.titleListener || !this.native.drainPendingTitle) {
      return;
    }
    const pendingTitle = this.native.drainPendingTitle(this.nativeSurfaceId);
    if (pendingTitle.length > 0) {
      this.titleListener(pendingTitle);
    }
  }

  private startBackgroundTitlePolling(): void {
    if (this.titlePollTimer >= 0 || !this.native) {
      return;
    }
    this.titlePollTimer = setInterval(() => {
      this.drainPendingTitleOnce();
      this.drainPendingNotificationOnce();
    }, this.titlePollIntervalMs) as number;
  }

  private stopBackgroundTitlePolling(): void {
    if (this.titlePollTimer < 0) {
      return;
    }
    clearInterval(this.titlePollTimer);
    this.titlePollTimer = -1;
  }

  private needsInputPolling(): boolean {
    return !!(this.inputListener || this.linkListener || this.contextMenuListener ||
      this.titleListener || this.notificationListener ||
      this.copyRequestListener || this.pasteRequestListener);
  }

  private refreshInputPolling(): void {
    if (this.needsInputPolling()) {
      this.startInputPolling();
    } else {
      this.stopInputPolling();
    }
  }

  setAttachmentListener(listener: TerminalAttachmentListener | null): void {
    this.attachmentListener = listener;
    this.notifyAttachmentChanged(this.isAttached());
  }

  setSizeListener(listener: TerminalSizeListener | null): void {
    this.sizeListener = listener;
    if (listener) {
      this.notifySizeChanged();
    }
  }

  write(data: string): void {
    if (!this.native || data.length === 0) {
      return;
    }
    this.native.writeInput(this.nativeSurfaceId, data);
  }

  paste(data: string): void {
    if (!this.native || data.length === 0) {
      return;
    }
    if (this.native.pasteText) {
      this.native.pasteText(this.nativeSurfaceId, data);
    } else {
      this.native.writeInput(this.nativeSurfaceId, data);
    }
  }

  registerCustomFont(fontPath: string): boolean {
    if (!this.native || fontPath.length === 0 || !this.native.registerCustomFont) {
      return false;
    }
    return this.native.registerCustomFont(this.nativeSurfaceId, fontPath);
  }

  requestIme(): void {
    this.native?.requestIme(this.nativeSurfaceId);
  }

  setImeActive(active: boolean): void {
    this.native?.setImeActive(this.nativeSurfaceId, active);
  }

  setInputBlocked(blocked: boolean): void {
    this.native?.setInputBlocked(this.nativeSurfaceId, blocked);
  }

  feed(data: string): void {
    if (!this.native || data.length === 0) {
      return;
    }
    this.native.feedOutput(this.nativeSurfaceId, data);
  }

  resize(cols: number, rows: number): void {
    if (!this.native) {
      return;
    }
    this.native.resizeTerminal(this.nativeSurfaceId, cols, rows);
  }

  setSurfaceOrigin(left: number, top: number): void {
    if (!this.native) {
      return;
    }
    this.native.setSurfaceOrigin(this.nativeSurfaceId, left, top);
  }

  setSurfaceFrame(left: number, top: number, width: number, height: number): void {
    if (!this.native) {
      return;
    }
    this.native.setSurfaceFrame(this.nativeSurfaceId, left, top, width, height);
    this.notifySizeChanged();
  }

  scrollView(delta: number): void {
    if (!this.native) {
      return;
    }
    this.native.scrollView(this.nativeSurfaceId, delta);
  }

  resetScroll(): void {
    if (!this.native) {
      return;
    }
    this.native.resetScroll(this.nativeSurfaceId);
  }

  getScrollbackSize(): number {
    if (!this.native) {
      return 0;
    }
    return this.native.getScrollbackSize(this.nativeSurfaceId);
  }

  getScrollbarState(): TerminalScrollbarState {
    if (!this.native) {
      return { total: 0, offset: 0, visible: 0 };
    }
    return this.native.getScrollbarState(this.nativeSurfaceId);
  }

  scrollToOffset(offset: number): void {
    if (!this.native) {
      return;
    }
    this.native.scrollToOffset(this.nativeSurfaceId, offset);
  }

  getScreenContent(): string {
    if (!this.native) {
      return '';
    }
    return this.native.getScreenContent(this.nativeSurfaceId);
  }

  getCursorPosition(): CursorPosition {
    if (!this.native) {
      return { row: 0, col: 0 };
    }
    return this.native.getCursorPosition(this.nativeSurfaceId);
  }

  getTerminalSize(): TerminalSize {
    if (!this.native) {
      const emptySize: TerminalSize = { cols: 0, rows: 0 };
      return emptySize;
    }
    return this.native.getTerminalSize(this.nativeSurfaceId);
  }

  getCellMetrics(): CellMetrics {
    if (!this.native) {
      return {
        width: Math.max(1, this.config.fontSize * 0.6),
        height: Math.max(1, this.config.fontSize * 1.2)
      };
    }
    return this.native.getCellMetrics(this.nativeSurfaceId);
  }

  startSelection(row: number, col: number): void {
    if (!this.native) {
      return;
    }
    this.native.startSelection(this.nativeSurfaceId, row, col);
  }

  updateSelection(row: number, col: number): void {
    if (!this.native) {
      return;
    }
    this.native.updateSelection(this.nativeSurfaceId, row, col);
  }

  clearSelection(): void {
    if (!this.native) {
      return;
    }
    this.native.clearSelection(this.nativeSurfaceId);
  }

  getSelectedText(): string {
    if (!this.native) {
      return '';
    }
    return this.native.getSelectedText(this.nativeSurfaceId);
  }

  startSearch(query: string = ''): void {
    if (!this.native) {
      return;
    }
    this.native.startSearch(this.nativeSurfaceId, query);
  }

  searchSelection(): void {
    if (!this.native) {
      return;
    }
    this.native.searchSelection(this.nativeSurfaceId);
  }

  updateSearch(query: string): void {
    if (!this.native) {
      return;
    }
    this.native.updateSearch(this.nativeSurfaceId, query);
  }

  navigateSearch(next: boolean): void {
    if (!this.native) {
      return;
    }
    this.native.navigateSearch(this.nativeSurfaceId, next);
  }

  endSearch(): void {
    if (!this.native) {
      return;
    }
    this.native.endSearch(this.nativeSurfaceId);
  }

  getSearchStatus(): TerminalSearchStatus {
    if (!this.native) {
      return {
        active: false,
        total: 0,
        selected: -1,
        query: ''
      };
    }
    return this.native.getSearchStatus(this.nativeSurfaceId);
  }

  isRendererReady(): boolean {
    if (!this.native) {
      return false;
    }
    return this.native.isRendererReady(this.nativeSurfaceId);
  }

  getRendererError(): string {
    if (!this.native) {
      return '';
    }
    return this.native.getRendererError(this.nativeSurfaceId);
  }

  private applyConfig(): void {
    if (!this.native) {
      return;
    }
    this.native.setConfig(this.nativeSurfaceId, this.config);
  }

  private applyTheme(): boolean {
    if (!this.native) {
      return false;
    }
    if (this.appliedThemeName === this.themeName) {
      return true;
    }
    const loaded: boolean = this.native.loadTheme(this.nativeSurfaceId, this.themeName);
    if (loaded) {
      this.appliedThemeName = this.themeName;
    }
    return loaded;
  }

  private notifyConfigChanged(): void {
    if (!this.configListener) {
      return;
    }
    this.configListener(this.getConfig(), this.themeName);
  }

  // Native copy requests arrive as "copy" (copy the current selection) or as
  // "T<text>" (copy explicit text, e.g. an OSC 52 payload); an empty callback
  // argument tells the surface to read the selection itself.
  private dispatchCopyRequest(pendingCopy: string): void {
    if (!this.copyRequestListener) {
      return;
    }
    if (pendingCopy.startsWith('T')) {
      this.copyRequestListener(pendingCopy.slice(1));
      return;
    }
    this.copyRequestListener('');
  }

  private startInputPolling(): void {
    if (!this.native || !this.needsInputPolling() || this.pollingSuspended || this.inputPollTimer >= 0) {
      return;
    }

    this.inputPollTimer = setInterval(() => {
      if (!this.native) {
        return;
      }

      const activatedLink = this.linkListener ? this.native.drainPendingLinkActivation(this.nativeSurfaceId) : '';
      if (this.linkListener && activatedLink.length > 0) {
        this.linkListener(activatedLink);
      }

      const pendingTitle = this.titleListener && this.native.drainPendingTitle ?
        this.native.drainPendingTitle(this.nativeSurfaceId) : '';
      if (this.titleListener && pendingTitle.length > 0) {
        this.titleListener(pendingTitle);
      }

      this.drainPendingNotificationOnce();

      const pendingContextMenu = this.contextMenuListener ?
        this.native.drainPendingContextMenuRequest(this.nativeSurfaceId) : '';
      if (this.contextMenuListener && pendingContextMenu.length > 0) {
        const parts = pendingContextMenu.split(',');
        const x = parts.length > 0 ? Number(parts[0]) : 0;
        const y = parts.length > 1 ? Number(parts[1]) : 0;
        this.contextMenuListener(
          Number.isFinite(x) ? x : 0,
          Number.isFinite(y) ? y : 0
        );
      }

      const pendingCopy = this.copyRequestListener && this.native.drainPendingCopyRequest ?
        this.native.drainPendingCopyRequest(this.nativeSurfaceId) : '';
      if (this.copyRequestListener && pendingCopy.length > 0) {
        this.dispatchCopyRequest(pendingCopy);
      }

      const pendingPaste = this.pasteRequestListener ?
        this.native.drainPendingPasteRequest(this.nativeSurfaceId) : '';
      if (this.pasteRequestListener && pendingPaste.length > 0) {
        this.pasteRequestListener();
      }
    }, UI_EVENT_POLL_INTERVAL_MS) as number;
  }

  private stopInputPolling(): void {
    if (this.inputPollTimer < 0) {
      return;
    }
    clearInterval(this.inputPollTimer);
    this.inputPollTimer = -1;
  }

  private bindWindowMetadata(context: common.UIAbilityContext): void {
    this.unbindWindowMetadata();
    const boundNative = this.native;
    if (!boundNative) {
      return;
    }

    void window.getLastWindow(context).then((appWindow: window.Window) => {
      if (this.native !== boundNative) {
        return;
      }

      this.trackedWindow = appWindow;
      this.syncWindowMetadata(appWindow);

      this.windowRectListener = (_options: window.RectChangeOptions) => {
        this.syncWindowMetadata(appWindow);
      };

      try {
        appWindow.on('windowRectChange', this.windowRectListener);
      } catch (err) {
        console.error('Failed to subscribe to windowRectChange: ' + JSON.stringify(err));
      }
    }).catch((err: Object) => {
      console.error('Failed to bind window metadata: ' + JSON.stringify(err));
    });
  }

  private unbindWindowMetadata(): void {
    if (!this.trackedWindow) {
      this.windowRectListener = null;
      return;
    }

    if (this.windowRectListener) {
      try {
        this.trackedWindow.off('windowRectChange', this.windowRectListener);
      } catch (err) {
        console.error('Failed to unsubscribe from windowRectChange: ' + JSON.stringify(err));
      }
    }

    this.trackedWindow = null;
    this.windowRectListener = null;
  }

  private syncWindowMetadata(appWindow: window.Window): void {
    if (!this.native) {
      return;
    }

    try {
      const props = appWindow.getWindowProperties();
      try {
        const globalRect = appWindow.getGlobalRect();
        this.native.setWindowInfo(this.nativeSurfaceId, props.id, globalRect.left, globalRect.top);
      } catch (_err) {
        this.native.setWindowInfo(this.nativeSurfaceId, props.id, props.windowRect.left, props.windowRect.top);
      }
    } catch (err) {
      console.error('Failed to sync window metadata: ' + JSON.stringify(err));
    }
  }

  private notifyAttachmentChanged(attached: boolean): void {
    if (!this.attachmentListener) {
      return;
    }
    this.attachmentListener(attached);
  }

  private notifySizeChanged(): void {
    if (!this.native || !this.sizeListener) {
      return;
    }
    const size = this.native.getTerminalSize(this.nativeSurfaceId);
    if (size.cols <= 0 || size.rows <= 0) {
      return;
    }
    if (size.cols === this.lastReportedSize.cols && size.rows === this.lastReportedSize.rows) {
      return;
    }
    this.lastReportedSize = { cols: size.cols, rows: size.rows };
    this.sizeListener(this.lastReportedSize);
  }
}
