import { webSocket } from '@kit.NetworkKit';
import { TerminalController, TerminalInputListener, TerminalSize } from 'libghostty-ohos';
import {
  buildFusionAgentUrl,
  createCwdQueryMessage,
  createForkMessage,
  createPingMessage,
  createResizeMessage,
  createTerminateMessage,
  createUploadRelayMessage,
  DEFAULT_AGENT_COLS,
  DEFAULT_AGENT_ROWS,
  DEFAULT_FUSION_AGENT_HOST,
  DEFAULT_FUSION_ENGINE_VM_LABEL,
  FusionAgentEndpoint,
  FusionAgentMessage,
  parseFusionAgentMessage,
  stringifyFusionAgentMessage
} from './FusionAgentProtocol';

export interface FusionAgentStatus {
  connected: boolean;
  mode: string;
  label: string;
  error: string;
  cwd: string;
}

type FusionAgentStatusListener = (status: FusionAgentStatus) => void;

// One in-flight upload-relay request awaiting its result frame.
interface PendingRelay {
  resolve: (path: string) => void;
  reject: (err: Error) => void;
  timer: number;
}

// Client-side deadline slightly above the agent's own 30s scp timeout so the
// agent's error message wins the race when the transfer itself is slow.
const RELAY_REPLY_TIMEOUT_MS = 35000;
// Stock wand-agent accepts JSON `ping` control messages. Keep a small margin
// below hardened-agent 30s read deadlines so an idle terminal stays attached.
const AGENT_HEARTBEAT_INTERVAL_MS = 25000;

export class FusionAgentDriver {
  private controller: TerminalController | null = null;
  private socket: webSocket.WebSocket | null = null;
  private statusListener: FusionAgentStatusListener | null = null;
  private lastCols: number = DEFAULT_AGENT_COLS;
  private lastRows: number = DEFAULT_AGENT_ROWS;
  private currentCwd: string = '';
  private currentEndpointLabel: string = DEFAULT_FUSION_ENGINE_VM_LABEL;
  private connected: boolean = false;
  private ready: boolean = false;
  private supportsTerminateControl: boolean = false;
  private terminateCloseTimer: number = -1;
  // Auto-reconnect after an unexpected drop: armed by connect(), disarmed by
  // every deliberate teardown (closeConnection), so manual disconnect, tab
  // close, and a clean shell exit never trigger retries.
  private autoReconnect: boolean = false;
  // Last state pushed through emitStatus, replayed verbatim when a new
  // listener attaches (tab moved across windows must not repaint a live
  // connection as idle -- that fake edge made adopting windows treat a live
  // socket as dead).
  private lastEmittedConnected: boolean = false;
  private lastEmittedLabel: string = 'Agent 待机';
  private lastEmittedError: string = '';
  private lastEndpoint: FusionAgentEndpoint | null = null;
  private reconnectAttempt: number = 0;
  private reconnectTimer: number = -1;
  private heartbeatTimer: number = -1;
  // PTY output arrives in arbitrary WebSocket frame chunks, so a multi-byte
  // UTF-8 sequence can be split across frames; the incomplete tail is kept
  // here until the next frame arrives.
  private pendingUtf8Tail: Array<number> = [];
  // upload-relay requests keyed by relayId, settled by the matching
  // upload-relay-result frame, a timeout, or connection teardown.
  private pendingRelays: Map<number, PendingRelay> = new Map();
  private nextRelayId: number = 1;

  private readonly inputListener: TerminalInputListener = (input: string): void => {
    if (!this.socket || !this.connected || input.length === 0) {
      // Typing into a dropped session should not be silently swallowed:
      // treat any keystroke as "reconnect now" and skip the backoff wait.
      if (input.length > 0) {
        this.reconnectNowIfWaiting();
      }
      return;
    }

    const data = this.encodeUtf8(input);
    this.sendSocketPayload(data);
  };

  private reconnectNowIfWaiting(): void {
    if (!this.autoReconnect || !this.lastEndpoint || this.reconnectTimer < 0) {
      return;
    }
    clearTimeout(this.reconnectTimer);
    this.reconnectTimer = -1;
    this.openSocket(this.lastEndpoint);
  }

  private readonly sizeListener = (size: TerminalSize): void => {
    const cols = Math.max(1, size.cols || DEFAULT_AGENT_COLS);
    const rows = Math.max(1, size.rows || DEFAULT_AGENT_ROWS);
    if (cols === this.lastCols && rows === this.lastRows) {
      return;
    }

    this.lastCols = cols;
    this.lastRows = rows;
    if (this.socket && this.connected) {
      this.sendSocketPayload(stringifyFusionAgentMessage(createResizeMessage(cols, rows)));
    }
  };

  attach(controller: TerminalController): void {
    this.detach();
    this.controller = controller;
    this.controller.setInputListener(this.inputListener);
    this.controller.setSizeListener(this.sizeListener);
  }

  // Passive teardown: closing a tab or replacing the driver must not disturb
  // whatever runs inside the remote PTY (tmux, codex, long builds).
  detach(): void {
    if (this.controller) {
      this.controller.setInputListener(null);
      this.controller.setSizeListener(null);
    }
    this.closeConnection(false, 0);
    this.controller = null;
  }

  // Hand-off detach for tab drag-out: drop the controller input/size listeners
  // but keep the live WebSocket, autoReconnect state and the controller
  // reference untouched. Remote PTY output keeps feeding the SAME controller
  // grid across the move (no direct-output sink on the agent path), so tmux /
  // codex output is never dropped and rebind() re-hooks input with zero
  // reconnect. Never call closeConnection here.
  softDetach(): void {
    if (this.controller) {
      this.controller.setInputListener(null);
      this.controller.setSizeListener(null);
    }
  }

  // Re-attach a (possibly new-window) controller to the same live socket:
  // re-hook input/size and swap the controller. The WebSocket is left exactly
  // as-is -- no disconnect, no reconnect, no capability re-handshake.
  rebind(controller: TerminalController): void {
    if (this.controller && this.controller !== controller) {
      this.controller.setInputListener(null);
      this.controller.setSizeListener(null);
    }
    this.controller = controller;
    this.controller.setInputListener(this.inputListener);
    this.controller.setSizeListener(this.sizeListener);
  }

  // Explicit termination: only used when the user asks to end the remote
  // session itself, and only advertised-capability agents receive it.
  terminate(): void {
    if (this.controller) {
      this.controller.setInputListener(null);
      this.controller.setSizeListener(null);
    }
    this.closeConnection(true, 80);
    this.controller = null;
  }

  setStatusListener(listener: FusionAgentStatusListener | null): void {
    this.statusListener = listener;
    // Replay the CURRENT truth to the new listener instead of hardcoded idle.
    this.emitStatus(this.lastEmittedConnected, this.lastEmittedLabel,
      this.lastEmittedError);
  }

  connect(endpoint: FusionAgentEndpoint): void {
    this.closeConnection(false, 0);
    this.lastEndpoint = endpoint;
    this.autoReconnect = true;
    this.reconnectAttempt = 0;
    this.openSocket(endpoint);
  }

  private openSocket(endpoint: FusionAgentEndpoint): void {
    this.stopHeartbeat();
    if (this.socket) {
      this.closeSocket(this.socket);
      this.socket = null;
    }
    const endpointHost = endpoint.host.trim();
    const endpointLabel = endpointHost.length === 0 || endpointHost === DEFAULT_FUSION_AGENT_HOST ?
      DEFAULT_FUSION_ENGINE_VM_LABEL : endpointHost;
    this.currentEndpointLabel = endpointLabel;
    const fallbackSize: TerminalSize = {
      cols: DEFAULT_AGENT_COLS,
      rows: DEFAULT_AGENT_ROWS
    };
    const size: TerminalSize = this.controller ? this.controller.getTerminalSize() : fallbackSize;
    this.lastCols = Math.max(1, size.cols || endpoint.cols || DEFAULT_AGENT_COLS);
    this.lastRows = Math.max(1, size.rows || endpoint.rows || DEFAULT_AGENT_ROWS);
    const url = buildFusionAgentUrl({
      host: endpoint.host,
      port: endpoint.port,
      path: endpoint.path,
      cols: this.lastCols,
      rows: this.lastRows,
      cwd: endpoint.cwd,
      shell: endpoint.shell,
      token: endpoint.token,
      secure: endpoint.secure
    });

    try {
      const ownSocket = webSocket.createWebSocket();
      this.socket = ownSocket;
      this.registerSocketHandlers();
      this.emitStatus(false, `正在连接 ${endpointLabel}`, '');
      // The hardened wand-agent fork prefers Authorization: Bearer; the token
      // stays in the URL query as well for stock wand-agent compatibility.
      if (endpoint.token && endpoint.token.length > 0) {
        const options: webSocket.WebSocketRequestOptions = {
          header: { 'Authorization': `Bearer ${endpoint.token}` }
        };
        ownSocket.connect(url, options)
          .then((connected: boolean) => {
            if (!connected) {
              this.handleUnexpectedSocketFailure(ownSocket, 'Agent 连接失败', '连接请求未成功');
            }
          })
          .catch((err: Error) => {
            this.handleUnexpectedSocketFailure(ownSocket, 'Agent 连接失败',
              err && err.message ? err.message : '连接失败');
          });
      } else {
        ownSocket.connect(url)
          .then((connected: boolean) => {
            if (!connected) {
              this.handleUnexpectedSocketFailure(ownSocket, 'Agent 连接失败', '连接请求未成功');
            }
          })
          .catch((err: Error) => {
            this.handleUnexpectedSocketFailure(ownSocket, 'Agent 连接失败',
              err && err.message ? err.message : '连接失败');
          });
      }
    } catch (err) {
      const failedSocket = this.socket;
      if (failedSocket) {
        this.handleUnexpectedSocketFailure(failedSocket, 'Agent 连接失败', JSON.stringify(err));
        return;
      }
      this.connected = false;
      this.ready = false;
      this.supportsTerminateControl = false;
      this.socket = null;
      this.emitStatus(false, 'Agent 连接失败', JSON.stringify(err));
      this.maybeScheduleReconnect();
    }
  }

  disconnect(): void {
    this.closeConnection(false, 0);
  }

  private closeConnection(terminateRemote: boolean, closeDelayMs: number): void {
    this.autoReconnect = false;
    this.cancelReconnectTimer();
    this.stopTerminateCloseTimer();
    this.stopHeartbeat();
    const socketToClose = this.socket;
    if (terminateRemote) {
      this.sendRemoteTerminationRequest();
    }

    this.ready = false;
    this.connected = false;
    this.supportsTerminateControl = false;
    this.pendingUtf8Tail = [];
    this.rejectAllPendingRelays('Agent 连接已断开');
    if (!socketToClose) {
      this.socket = null;
      return;
    }

    if (closeDelayMs > 0) {
      this.terminateCloseTimer = setTimeout(() => {
        this.terminateCloseTimer = -1;
        if (this.socket !== socketToClose) {
          return;
        }
        this.closeSocket(socketToClose);
        this.socket = null;
      }, closeDelayMs) as number;
      return;
    }

    this.closeSocket(socketToClose);
    if (this.socket === socketToClose) {
      this.socket = null;
    }
  }

  private closeSocket(socketToClose: webSocket.WebSocket): void {
    try {
      socketToClose.close();
    } catch (_err) {
    }
  }

  private stopTerminateCloseTimer(): void {
    if (this.terminateCloseTimer < 0) {
      return;
    }
    clearTimeout(this.terminateCloseTimer);
    this.terminateCloseTimer = -1;
  }

  private cancelReconnectTimer(): void {
    if (this.reconnectTimer < 0) {
      return;
    }
    clearTimeout(this.reconnectTimer);
    this.reconnectTimer = -1;
  }

  private startHeartbeat(ownSocket: webSocket.WebSocket): void {
    this.stopHeartbeat();
    this.heartbeatTimer = setInterval(() => {
      if (this.socket !== ownSocket || !this.connected) {
        this.stopHeartbeat();
        return;
      }
      this.sendSocketPayload(stringifyFusionAgentMessage(createPingMessage(Date.now())));
    }, AGENT_HEARTBEAT_INTERVAL_MS) as number;
  }

  private stopHeartbeat(): void {
    if (this.heartbeatTimer < 0) {
      return;
    }
    clearInterval(this.heartbeatTimer);
    this.heartbeatTimer = -1;
  }

  private handleUnexpectedSocketFailure(ownSocket: webSocket.WebSocket, label: string, error: string): void {
    if (this.socket !== ownSocket) {
      return;
    }

    // Null first so close/error events raised by closeSocket cannot run the
    // failure transition twice or mutate a newer connection generation.
    this.socket = null;
    this.stopHeartbeat();
    this.connected = false;
    this.ready = false;
    this.supportsTerminateControl = false;
    this.pendingUtf8Tail = [];
    this.rejectAllPendingRelays('Agent 连接已断开');
    this.closeSocket(ownSocket);
    this.emitStatus(false, label, error);
    // Initial handshakes must retry too; the old wasConnected gate stranded a
    // session forever when the first connection failed during screen resume.
    this.maybeScheduleReconnect();
  }

  private maybeScheduleReconnect(): void {
    if (!this.autoReconnect || !this.lastEndpoint || this.reconnectTimer >= 0) {
      return;
    }
    this.reconnectAttempt += 1;
    const delayMs = Math.min(30000, 1000 * Math.pow(2, this.reconnectAttempt - 1));
    this.emitStatus(false, `连接断开,${Math.round(delayMs / 1000)} 秒后重连(第 ${this.reconnectAttempt} 次)`, '');
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = -1;
      if (!this.autoReconnect || !this.lastEndpoint) {
        return;
      }
      this.openSocket(this.lastEndpoint);
    }, delayMs) as number;
  }

  requestCurrentDirectory(): void {
    if (!this.socket || !this.connected) {
      return;
    }
    this.sendSocketPayload(stringifyFusionAgentMessage(createCwdQueryMessage()));
  }

  forkSession(cwd: string): void {
    if (!this.socket || !this.connected) {
      return;
    }
    this.sendSocketPayload(stringifyFusionAgentMessage(createForkMessage(cwd || this.currentCwd)));
  }

  // Ask the agent to scp a shared-folder file to a remote host. Resolves with
  // the remote path on success; rejects on validation/scp failure, reply
  // timeout, or connection teardown while the request is in flight.
  uploadRelay(src: string, target: string, dir: string): Promise<string> {
    return new Promise<string>((resolve: (path: string) => void, reject: (err: Error) => void) => {
      if (!this.socket || !this.connected) {
        reject(new Error('Agent 未连接'));
        return;
      }
      const relayId = this.nextRelayId;
      this.nextRelayId += 1;
      const timer = setTimeout(() => {
        const pending = this.pendingRelays.get(relayId);
        if (!pending) {
          return;
        }
        this.pendingRelays.delete(relayId);
        pending.reject(new Error('上传中继超时'));
      }, RELAY_REPLY_TIMEOUT_MS) as number;
      this.pendingRelays.set(relayId, { resolve, reject, timer });
      this.sendSocketPayload(stringifyFusionAgentMessage(createUploadRelayMessage(relayId, src, target, dir)));
    });
  }

  private settleRelay(message: FusionAgentMessage): void {
    const relayId = message.relayId;
    if (relayId === undefined) {
      return;
    }
    const pending = this.pendingRelays.get(relayId);
    if (!pending) {
      return;
    }
    this.pendingRelays.delete(relayId);
    clearTimeout(pending.timer);
    if (message.ok && message.path && message.path.length > 0) {
      pending.resolve(message.path);
    } else {
      pending.reject(new Error(message.error && message.error.length > 0 ? message.error : '上传中继失败'));
    }
  }

  private rejectAllPendingRelays(reason: string): void {
    if (this.pendingRelays.size === 0) {
      return;
    }
    const pendings: Array<PendingRelay> = [];
    this.pendingRelays.forEach((pending: PendingRelay) => {
      pendings.push(pending);
    });
    this.pendingRelays.clear();
    for (const pending of pendings) {
      clearTimeout(pending.timer);
      pending.reject(new Error(reason));
    }
  }

  private registerSocketHandlers(): void {
    // Guard every handler against its own socket instance so late events from
    // a replaced/disconnected socket cannot pollute the next session's state.
    const ownSocket = this.socket;
    if (!ownSocket) {
      return;
    }

    ownSocket.on('open', () => {
      if (this.socket !== ownSocket) {
        return;
      }
      this.connected = true;
      this.ready = true;
      this.reconnectAttempt = 0;
      this.startHeartbeat(ownSocket);
      this.emitStatus(true, this.currentEndpointLabel, '');
      this.requestCurrentDirectory();
    });

    ownSocket.on('message', (_err: Error, data: string | ArrayBuffer) => {
      if (this.socket !== ownSocket) {
        return;
      }
      this.handleSocketMessage(data);
    });

    ownSocket.on('close', () => {
      this.handleUnexpectedSocketFailure(ownSocket, 'Agent 已断开', '');
    });

    ownSocket.on('error', (err: Error) => {
      const errorText = err && err.message ? err.message : '连接失败';
      this.handleUnexpectedSocketFailure(ownSocket, 'Agent 错误', errorText);
    });
  }

  private handleSocketMessage(data: string | ArrayBuffer): void {
    if (typeof data === 'string') {
      this.handleControlMessage(parseFusionAgentMessage(data));
      return;
    }

    if (this.controller) {
      this.controller.feed(this.decodeUtf8(data));
    }
  }

  private handleControlMessage(message: FusionAgentMessage): void {
    switch (message.type) {
      case 'ready':
        this.ready = true;
        this.currentCwd = message.cwd || message.dir || this.currentCwd;
        this.supportsTerminateControl = this.hasTerminateCapability(message.capabilities);
        this.emitStatus(true, message.sessionId ? `Agent ${message.sessionId}` : 'Agent 就绪', '');
        break;
      case 'cwd':
        this.currentCwd = message.dir || message.cwd || this.currentCwd;
        this.emitStatus(this.connected, this.currentCwd.length > 0 ? this.currentCwd : 'Agent 就绪', '');
        break;
      case 'exit': {
        // The remote shell is gone: tear the socket down so stale input can
        // no longer be sent, then report the exit label (closeConnection nulls
        // the socket first, so the late 'close' event cannot overwrite it).
        const exitLabel = message.message || 'Shell 已退出';
        this.closeConnection(false, 0);
        this.emitStatus(false, exitLabel, '');
        break;
      }
      case 'error':
        this.emitStatus(false, 'Agent 错误', message.error || message.message || message.code || '未知的 wand-agent 错误');
        break;
      case 'forked':
        this.emitStatus(this.connected, message.id ? `Forked ${message.id}` : 'Forked session', '');
        break;
      case 'shells':
        break;
      case 'upload-relay-result':
        this.settleRelay(message);
        break;
      case 'ping':
        this.sendSocketPayload(stringifyFusionAgentMessage(createPingMessage(message.ts || Date.now())));
        break;
      case 'pong':
        break;
      default:
        break;
    }
  }

  private emitStatus(connected: boolean, label: string, error: string): void {
    this.lastEmittedConnected = connected;
    this.lastEmittedLabel = label || '';
    this.lastEmittedError = error || '';
    if (!this.statusListener) {
      return;
    }

    const safeLabel = label || '';
    const safeError = error || '';
    const safeCwd = this.currentCwd || '';
    this.statusListener({
      connected,
      mode: 'agent',
      label: safeLabel,
      error: safeError,
      cwd: safeCwd
    });
  }

  private sendSocketPayload(payload: string | ArrayBuffer): void {
    const ownSocket = this.socket;
    if (!ownSocket) {
      return;
    }

    try {
      ownSocket.send(payload)
        .then((sent: boolean) => {
          if (!sent) {
            this.handleUnexpectedSocketFailure(ownSocket, 'Agent 发送失败', '发送请求未成功');
          }
        })
        .catch((err: Error) => {
          this.handleUnexpectedSocketFailure(ownSocket, 'Agent 发送失败',
            err && err.message ? err.message : '发送失败');
        });
    } catch (err) {
      this.handleUnexpectedSocketFailure(ownSocket, 'Agent 发送失败', JSON.stringify(err));
    }
  }

  private sendRemoteTerminationRequest(): void {
    if (!this.socket || !this.connected) {
      return;
    }

    if (this.supportsTerminateControl) {
      this.sendSocketPayload(stringifyFusionAgentMessage(createTerminateMessage()));
    }
    // Stock wand-agent has no safe termination control. Never fall back to
    // injecting Ctrl-C/exit bytes into the PTY: that would interrupt tmux or
    // codex foreground tasks the user intends to keep running.
  }

  private hasTerminateCapability(capabilities?: Array<string>): boolean {
    if (!capabilities) {
      return false;
    }

    for (const capability of capabilities) {
      if (capability === 'terminate' ||
        capability === 'session.terminate' ||
        capability === 'control.terminate') {
        return true;
      }
    }
    return false;
  }

  private encodeUtf8(input: string): ArrayBuffer {
    const bytes: Array<number> = [];
    for (let index = 0; index < input.length; index += 1) {
      let code = input.charCodeAt(index);
      if (code >= 0xD800 && code <= 0xDBFF && index + 1 < input.length) {
        const next = input.charCodeAt(index + 1);
        if (next >= 0xDC00 && next <= 0xDFFF) {
          code = 0x10000 + ((code - 0xD800) << 10) + (next - 0xDC00);
          index += 1;
        }
      }
      if (code <= 0x7F) {
        bytes.push(code);
      } else if (code <= 0x7FF) {
        bytes.push(0xC0 | (code >> 6), 0x80 | (code & 0x3F));
      } else if (code <= 0xFFFF) {
        bytes.push(0xE0 | (code >> 12), 0x80 | ((code >> 6) & 0x3F), 0x80 | (code & 0x3F));
      } else {
        bytes.push(
          0xF0 | (code >> 18),
          0x80 | ((code >> 12) & 0x3F),
          0x80 | ((code >> 6) & 0x3F),
          0x80 | (code & 0x3F)
        );
      }
    }

    const buffer = new ArrayBuffer(bytes.length);
    const view = new Uint8Array(buffer);
    for (let index = 0; index < bytes.length; index += 1) {
      view[index] = bytes[index];
    }
    return buffer;
  }

  private static utf8SequenceLength(first: number): number {
    if (first < 0x80) {
      return 1;
    }
    if ((first & 0xE0) === 0xC0) {
      return 2;
    }
    if ((first & 0xF0) === 0xE0) {
      return 3;
    }
    if ((first & 0xF8) === 0xF0) {
      return 4;
    }
    return 0;
  }

  private decodeUtf8(buffer: ArrayBuffer): string {
    const chunk = new Uint8Array(buffer);
    let bytes: Uint8Array;
    if (this.pendingUtf8Tail.length > 0) {
      bytes = new Uint8Array(this.pendingUtf8Tail.length + chunk.length);
      bytes.set(this.pendingUtf8Tail, 0);
      bytes.set(chunk, this.pendingUtf8Tail.length);
      this.pendingUtf8Tail = [];
    } else {
      bytes = chunk;
    }

    let output = '';
    for (let index = 0; index < bytes.length;) {
      const first = bytes[index];
      const needed = FusionAgentDriver.utf8SequenceLength(first);
      if (needed === 0) {
        output += String.fromCharCode(0xFFFD);
        index += 1;
        continue;
      }
      if (index + needed > bytes.length) {
        // Incomplete sequence at the end of this frame: keep the tail bytes
        // until the continuation arrives in the next frame.
        for (let tail = index; tail < bytes.length; tail += 1) {
          this.pendingUtf8Tail.push(bytes[tail]);
        }
        break;
      }

      let valid = true;
      for (let cont = 1; cont < needed; cont += 1) {
        if ((bytes[index + cont] & 0xC0) !== 0x80) {
          valid = false;
          break;
        }
      }
      if (!valid) {
        output += String.fromCharCode(0xFFFD);
        index += 1;
        continue;
      }

      if (needed === 1) {
        output += String.fromCharCode(first);
      } else if (needed === 2) {
        output += String.fromCharCode(((first & 0x1F) << 6) | (bytes[index + 1] & 0x3F));
      } else if (needed === 3) {
        output += String.fromCharCode(
          ((first & 0x0F) << 12) | ((bytes[index + 1] & 0x3F) << 6) | (bytes[index + 2] & 0x3F));
      } else {
        const code = ((first & 0x07) << 18) |
          ((bytes[index + 1] & 0x3F) << 12) |
          ((bytes[index + 2] & 0x3F) << 6) |
          (bytes[index + 3] & 0x3F);
        const adjusted = code - 0x10000;
        output += String.fromCharCode(0xD800 + (adjusted >> 10), 0xDC00 + (adjusted & 0x3FF));
      }
      index += needed;
    }
    return output;
  }
}
