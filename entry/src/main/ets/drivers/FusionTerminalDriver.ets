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
  private controller: TerminalController | null = null;
  private context: common.UIAbilityContext | null = null;
  private started: boolean = false;
  private startRetryTimer: number = -1;
  private lastCols: number = 0;
  private lastRows: number = 0;
  private mode: string = 'local';
  private pendingProfile: ConnectionProfile | null = null;
  private statusListener: DriverStatusListener | null = null;

  private readonly inputListener: TerminalInputListener = (data: string): void => {
    nativeDriver.writeInput(data);
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
    this.stopNativeSession();
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
    nativeDriver.resize(cols, rows);
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
    this.stopNativeSession();
    this.controller = null;
    this.context = null;
  }

  setStatusListener(listener: DriverStatusListener | null): void {
    this.statusListener = listener;
    this.emitStatus(false, this.mode, 'Idle', '');
  }

  startLocal(): void {
    this.mode = 'local';
    this.pendingProfile = null;
    this.restart();
  }

  connectSsh(profile: ConnectionProfile): void {
    this.mode = 'ssh';
    this.pendingProfile = profile;
    this.restart();
  }

  stop(): void {
    this.stopNativeSession();
    this.emitStatus(false, this.mode, 'Stopped', '');
  }

  private restart(): void {
    this.stopNativeSession();
    this.startWhenSized();
  }

  private startWhenSized(): void {
    if (this.started || !this.controller || !this.context) {
      return;
    }

    const size = this.controller.getTerminalSize();
    const cols = Math.max(0, size.cols || 0);
    const rows = Math.max(0, size.rows || 0);
    if (cols <= 0 || rows <= 0) {
      this.scheduleStartRetry();
      return;
    }

    nativeDriver.initialize(this.context.filesDir);
    nativeDriver.setOutputCallback(this.outputListener);

    if (this.mode === 'ssh' && this.pendingProfile) {
      this.started = nativeDriver.connectSsh(
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
        this.started ? this.pendingProfile.title : 'SSH failed',
        this.started ? '' : 'Unable to connect to Fusion VM'
      );
      if (!this.started) {
        this.scheduleStartRetry();
      }
      return;
    }

    this.started = nativeDriver.startLocal(cols, rows);
    this.lastCols = cols;
    this.lastRows = rows;
    this.emitStatus(this.started, 'local', this.started ? 'Local PTY' : 'Local PTY failed', '');
    if (!this.started) {
      this.scheduleStartRetry();
    }
  }

  private stopNativeSession(): void {
    this.stopStartRetry();
    nativeDriver.setOutputCallback(null);
    if (this.started) {
      nativeDriver.stop();
    } else {
      nativeDriver.stop();
    }
    this.started = false;
    this.lastCols = 0;
    this.lastRows = 0;
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
    this.statusListener({ connected, mode, label, error });
  }
}

