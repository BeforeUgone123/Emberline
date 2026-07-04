import { common } from '@kit.AbilityKit';
import {
  TerminalAttachmentListener,
  TerminalController,
  TerminalInputListener,
  TerminalSize
} from 'libghostty-ohos';
import nativeDriver from 'libfusion_terminal_driver.so';
import { ConnectionProfile } from '../models/ConnectionProfile';

export interface DriverStatus {
  connected: boolean;
  mode: string;
  label: string;
  error: string;
}

type DriverStatusListener = (status: DriverStatus) => void;

export class FusionTerminalDriver {
  private sessionId: number = -1;
  private controller: TerminalController | null = null;
  private context: common.UIAbilityContext | null = null;
  private started: boolean = false;
  private startRequested: boolean = false;
  private nativeInitialized: boolean = false;
  private startRetryTimer: number = -1;
  private lastCols: number = 0;
  private lastRows: number = 0;
  private mode: string = 'local';
  private pendingProfile: ConnectionProfile | null = null;
  private statusListener: DriverStatusListener | null = null;

  private readonly inputListener: TerminalInputListener = (data: string): void => {
    if (this.sessionId >= 0) {
      nativeDriver.writeInput(this.sessionId, data);
    }
  };

  private readonly outputListener = (data: string): void => {
    if (data.length > 0 && this.controller) {
      this.controller.feed(data);
    }
  };

  private readonly attachmentListener: TerminalAttachmentListener = (attached: boolean): void => {
    if (attached) {
      this.startWhenSized();
      return;
    }
    this.stopNativeSession(true);
  };

  private readonly sizeListener = (size: TerminalSize): void => {
    const cols = Math.max(1, size.cols || 0);
    const rows = Math.max(1, size.rows || 0);
    if (cols <= 0 || rows <= 0) {
      return;
    }

    if (!this.started) {
      this.startWhenSized();
      return;
    }

    if (cols === this.lastCols && rows === this.lastRows) {
      return;
    }

    this.lastCols = cols;
    this.lastRows = rows;
    if (this.sessionId >= 0) {
      nativeDriver.resize(this.sessionId, cols, rows);
    }
  };

  attach(controller: TerminalController, context: common.UIAbilityContext): void {
    this.detach();
    this.controller = controller;
    this.context = context;
    this.controller.setInputListener(this.inputListener);
    this.controller.setAttachmentListener(this.attachmentListener);
    this.controller.setSizeListener(this.sizeListener);
  }

  detach(): void {
    if (this.controller) {
      this.controller.setInputListener(null);
      this.controller.setAttachmentListener(null);
      this.controller.setSizeListener(null);
    }
    this.stopNativeSession(true);
    if (this.sessionId >= 0) {
      nativeDriver.destroySession(this.sessionId);
      this.sessionId = -1;
    }
    this.controller = null;
    this.context = null;
  }

  setStatusListener(listener: DriverStatusListener | null): void {
    this.statusListener = listener;
    this.emitStatus(false, this.mode, '待机', '');
  }

  startLocal(): void {
    this.mode = 'local';
    this.pendingProfile = null;
    this.startRequested = true;
    this.restart();
  }

  connectSsh(profile: ConnectionProfile): void {
    this.mode = 'ssh';
    this.pendingProfile = profile;
    this.startRequested = true;
    this.restart();
  }

  stop(): void {
    this.stopNativeSession(true);
    this.emitStatus(false, this.mode, '已停止', '');
  }

  private restart(): void {
    this.stopNativeSession(false);
    this.startWhenSized();
  }

  private startWhenSized(): void {
    if (!this.startRequested || this.started || !this.controller || !this.context) {
      return;
    }

    const size = this.controller.getTerminalSize();
    const cols = Math.max(0, size.cols || 0);
    const rows = Math.max(0, size.rows || 0);
    if (cols <= 0 || rows <= 0) {
      this.scheduleStartRetry();
      return;
    }

    if (this.sessionId < 0) {
      this.sessionId = nativeDriver.createSession();
    }
    nativeDriver.initialize(this.sessionId, this.context.filesDir);
    this.nativeInitialized = true;
    nativeDriver.setOutputCallback(this.sessionId, this.outputListener);

    if (this.mode === 'ssh' && this.pendingProfile) {
      this.started = nativeDriver.connectSsh(
        this.sessionId,
        this.pendingProfile.host,
        this.pendingProfile.port,
        this.pendingProfile.user,
        this.pendingProfile.password,
        cols,
        rows
      );
      this.lastCols = cols;
      this.lastRows = rows;
      this.emitStatus(
        this.started,
        'ssh',
        this.started ? this.pendingProfile.title : 'SSH 连接失败',
        this.started ? '' : '无法连接 Fusion VM'
      );
      if (!this.started) {
        this.scheduleStartRetry();
      }
      return;
    }

    this.started = nativeDriver.startLocal(this.sessionId, cols, rows);
    this.lastCols = cols;
    this.lastRows = rows;
    this.emitStatus(this.started, 'local', this.started ? '本地 PTY' : '本地 PTY 启动失败', '');
    if (!this.started) {
      this.scheduleStartRetry();
    }
  }

  private stopNativeSession(clearRequest: boolean): void {
    this.stopStartRetry();
    if (this.nativeInitialized && this.sessionId >= 0) {
      try {
        nativeDriver.setOutputCallback(this.sessionId, null);
        nativeDriver.stop(this.sessionId);
      } catch (err) {
        console.error('Failed to stop native terminal driver: ' + JSON.stringify(err));
      }
      this.nativeInitialized = false;
    }
    this.started = false;
    this.lastCols = 0;
    this.lastRows = 0;
    if (clearRequest) {
      this.startRequested = false;
    }
  }

  private scheduleStartRetry(): void {
    if (this.startRetryTimer >= 0) {
      return;
    }
    this.startRetryTimer = setTimeout(() => {
      this.startRetryTimer = -1;
      this.startWhenSized();
    }, 80) as number;
  }

  private stopStartRetry(): void {
    if (this.startRetryTimer < 0) {
      return;
    }
    clearTimeout(this.startRetryTimer);
    this.startRetryTimer = -1;
  }

  private emitStatus(connected: boolean, mode: string, label: string, error: string): void {
    if (!this.statusListener) {
      return;
    }
    const safeMode = mode || 'local';
    const safeLabel = label || '';
    const safeError = error || '';
    this.statusListener({ connected, mode: safeMode, label: safeLabel, error: safeError });
  }
}
