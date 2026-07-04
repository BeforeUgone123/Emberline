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
  TerminalInputListener,
  TerminalLinkListener,
  TerminalSearchStatus,
  TerminalSize,
  TerminalTitleListener
} from './TerminalTypes';

interface TerminalNativeBridge {
  writeInput: (surfaceId: string, data: string) => void;
  pasteText: (surfaceId: string, data: string) => void;
  registerCustomFont: (surfaceId: string, fontPath: string) => boolean;
  feedOutput: (surfaceId: string, data: string) => void;
  requestIme: (surfaceId: string) => void;
  setImeActive: (surfaceId: string, active: boolean) => void;
  drainPendingInput: (surfaceId: string) => string;
  setInputCallback: (surfaceId: string, callback: ((data: string) => void) | null) => void;
  drainPendingLinkActivation: (surfaceId: string) => string;
  drainPendingTitle: (surfaceId: string) => string;
  drainPendingContextMenuRequest: (surfaceId: string) => string;
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
  private configListener: TerminalConfigListener | null = null;
  private inputListener: TerminalInputListener | null = null;
  private linkListener: TerminalLinkListener | null = null;
  private contextMenuListener: TerminalContextMenuListener | null = null;
  private titleListener: TerminalTitleListener | null = null;
  private attachmentListener: TerminalAttachmentListener | null = null;
  private sizeListener: TerminalSizeListener | null = null;
  private inputPollTimer: number = -1;
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
    this.applyTheme();
    if (this.titleListener) {
      this.startInputPolling();
    }
    this.applyConfig();
    this.startInputPolling();
    this.bindWindowMetadata(context);
    this.notifyAttachmentChanged(true);
  }

  unbindNative(): void {
    if (this.native) {
      this.native.setInputCallback(this.nativeSurfaceId, null);
    }
    this.unbindWindowMetadata();
    this.stopInputPolling();
    this.native = null;
    this.nativeSurfaceId = '';
    this.notifyAttachmentChanged(false);
  }

  isAttached(): boolean {
    return this.native !== null;
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
    this.themeName = themeName;
    const loaded = this.applyTheme();
    this.notifyConfigChanged();
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
    if (this.linkListener || this.contextMenuListener) {
      this.startInputPolling();
    } else {
      this.stopInputPolling();
    }
  }

  setLinkListener(listener: TerminalLinkListener | null): void {
    this.linkListener = listener;
    if (this.inputListener || this.linkListener || this.contextMenuListener) {
      this.startInputPolling();
    } else {
      this.stopInputPolling();
    }
  }

  setContextMenuListener(listener: TerminalContextMenuListener | null): void {
    this.contextMenuListener = listener;
    if (this.inputListener || this.linkListener || this.contextMenuListener) {
      this.startInputPolling();
    } else {
      this.stopInputPolling();
    }
  }

  setTitleListener(listener: TerminalTitleListener | null): void {
    this.titleListener = listener;
    if (this.linkListener || this.contextMenuListener || this.titleListener) {
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
    return this.native.loadTheme(this.nativeSurfaceId, this.themeName);
  }

  private notifyConfigChanged(): void {
    if (!this.configListener) {
      return;
    }
    this.configListener(this.getConfig(), this.themeName);
  }

  private startInputPolling(): void {
    if (!this.native ||
      (!this.linkListener && !this.contextMenuListener && !this.titleListener) ||
      this.inputPollTimer >= 0) {
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
    }, 16) as number;
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
