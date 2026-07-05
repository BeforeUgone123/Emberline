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
  // Uploads a local file to the remote host over a dedicated SFTP connection
  // (used for clipboard image paste). Resolves with the remote path.
  static uploadFile(host: string, port: number, user: string, password: string,
    localPath: string, remotePath: string): Promise<string> {
    return nativeDriver.sshUploadFile(host, port, user, password, localPath, remotePath);
  }

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
  // SSH connects run async on the native worker pool; gate re-entry while one
  // is in flight and detect stale completions via an epoch counter.
  private sshConnecting: boolean = false;
  private startEpoch: number = 0;

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
      // Surface was (re)created: if the native PTY/SSH session is already
      // running, re-point the direct output sink at the (possibly new) surface
      // id so native output keeps bypassing the JS bridge after a rebind.
      if (this.started) {
        this.applyDirectOutputTarget();
      }
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

  // Hand-off detach for tab drag-out: drop ONLY the controller listeners so the
  // surface can be rebound into another window. Unlike detach(), this keeps the
  // sessionId, the running native PTY/SSH session and startRequested intact --
  // never destroySession/stop. The native session keeps feeding its direct
  // output target across the move; the JS outputListener is idle until rebind().
  softDetach(): void {
    if (this.controller) {
      this.controller.setInputListener(null);
      this.controller.setAttachmentListener(null);
      this.controller.setSizeListener(null);
    }
  }

  // Re-attach a (possibly new-window) controller to the same live native
  // session: re-hook the three listeners, swap the controller/context, and if
  // the session is already started re-point the direct output sink at the bound
  // surface so PTY/SSH bytes flow into the new XComponent. Mirrors attach() but
  // NEVER calls attach()/detach() (those would destroy the native session).
  rebind(controller: TerminalController, context: common.UIAbilityContext): void {
    if (this.controller && this.controller !== controller) {
      this.controller.setInputListener(null);
      this.controller.setAttachmentListener(null);
      this.controller.setSizeListener(null);
    }
    this.controller = controller;
    this.context = context;
    this.controller.setInputListener(this.inputListener);
    this.controller.setAttachmentListener(this.attachmentListener);
    this.controller.setSizeListener(this.sizeListener);
    if (this.started) {
      this.applyDirectOutputTarget();
    }
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
    if (!this.startRequested || this.started || this.sshConnecting || !this.controller || !this.context) {
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
      const profile = this.pendingProfile;
      const epoch = this.startEpoch;
      this.sshConnecting = true;
      this.lastCols = cols;
      this.lastRows = rows;
      this.emitStatus(false, 'ssh', '正在连接 ' + profile.host + '…', '');
      nativeDriver.connectSshAsync(
        this.sessionId,
        profile.host,
        profile.port,
        profile.user,
        profile.password,
        cols,
        rows
      ).then((ok: boolean) => {
        this.finishSshConnect(epoch, profile, ok);
      }).catch(() => {
        this.finishSshConnect(epoch, profile, false);
      });
      return;
    }

    this.started = nativeDriver.startLocal(this.sessionId, cols, rows);
    this.lastCols = cols;
    this.lastRows = rows;
    if (this.started) {
      this.applyDirectOutputTarget();
    }
    this.emitStatus(this.started, 'local', this.started ? '本地 PTY' : '本地 PTY 启动失败', '');
    if (!this.started) {
      this.scheduleStartRetry();
    }
  }

  private finishSshConnect(epoch: number, profile: ConnectionProfile, ok: boolean): void {
    this.sshConnecting = false;
    if (epoch !== this.startEpoch || !this.startRequested || this.mode !== 'ssh') {
      // The tab was stopped, restarted or switched while we were connecting;
      // this result belongs to a dead attempt. Re-drive any newer request.
      this.startWhenSized();
      return;
    }
    this.started = ok;
    if (ok) {
      this.applyDirectOutputTarget();
    }
    this.emitStatus(ok, 'ssh', ok ? profile.title : 'SSH 连接失败', ok ? '' : '无法连接 Fusion VM');
    if (!ok) {
      this.scheduleStartRetry();
    }
  }

  // Point the native session's direct-output sink at the bound surface so
  // PTY/SSH bytes flow straight into the renderer instead of through the JS
  // outputListener. No-op until both the session and the surface exist; until
  // then EmitOutput keeps using the threadsafe-function path (no output lost).
  private applyDirectOutputTarget(): void {
    if (this.sessionId < 0 || !this.controller) {
      return;
    }
    const surfaceId = this.controller.getSurfaceId();
    if (surfaceId.length > 0) {
      nativeDriver.setDirectOutputTarget(this.sessionId, surfaceId);
    }
  }

  private stopNativeSession(clearRequest: boolean): void {
    this.stopStartRetry();
    if (this.nativeInitialized && this.sessionId >= 0) {
      try {
        nativeDriver.setDirectOutputTarget(this.sessionId, '');
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
    this.startEpoch++;
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
