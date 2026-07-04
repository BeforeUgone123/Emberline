import { webSocket } from '@kit.NetworkKit';
import { TerminalController, TerminalInputListener, TerminalSize } from 'libghostty-ohos';
import {
  buildFusionAgentUrl,
  createCwdQueryMessage,
  createForkMessage,
  createPingMessage,
  createResizeMessage,
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
  // PTY output arrives in arbitrary WebSocket frame chunks, so a multi-byte
  // UTF-8 sequence can be split across frames; the incomplete tail is kept
  // here until the next frame arrives.
  private pendingUtf8Tail: Array<number> = [];

  private readonly inputListener: TerminalInputListener = (input: string): void => {
    if (!this.socket || !this.connected || input.length === 0) {
      return;
    }

    const data = this.encodeUtf8(input);
    this.sendSocketPayload(data);
  };

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

  detach(): void {
    if (this.controller) {
      this.controller.setInputListener(null);
      this.controller.setSizeListener(null);
    }
    this.disconnect();
    this.controller = null;
  }

  setStatusListener(listener: FusionAgentStatusListener | null): void {
    this.statusListener = listener;
    this.emitStatus(false, 'Agent 待机', '');
  }

  connect(endpoint: FusionAgentEndpoint): void {
    this.disconnect();
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
      this.socket = webSocket.createWebSocket();
      this.registerSocketHandlers();
      this.emitStatus(false, `正在连接 ${endpointLabel}`, '');
      // The hardened wand-agent fork prefers Authorization: Bearer; the token
      // stays in the URL query as well for stock wand-agent compatibility.
      if (endpoint.token && endpoint.token.length > 0) {
        const options: webSocket.WebSocketRequestOptions = {
          header: { 'Authorization': `Bearer ${endpoint.token}` }
        };
        this.socket.connect(url, options);
      } else {
        this.socket.connect(url);
      }
    } catch (err) {
      this.connected = false;
      this.ready = false;
      this.socket = null;
      this.emitStatus(false, 'Agent 连接失败', JSON.stringify(err));
    }
  }

  disconnect(): void {
    this.ready = false;
    this.connected = false;
    this.pendingUtf8Tail = [];
    if (this.socket) {
      try {
        this.socket.close();
      } catch (_err) {
      }
    }
    this.socket = null;
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
      if (this.socket !== ownSocket) {
        return;
      }
      const wasConnected = this.connected;
      this.connected = false;
      this.ready = false;
      this.pendingUtf8Tail = [];
      if (wasConnected) {
        this.emitStatus(false, 'Agent 已断开', '');
      }
    });

    ownSocket.on('error', (err: Error) => {
      if (this.socket !== ownSocket) {
        return;
      }
      this.connected = false;
      this.ready = false;
      this.pendingUtf8Tail = [];
      const errorText = err && err.message ? err.message : '连接失败';
      this.emitStatus(false, 'Agent 错误', errorText);
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
        this.emitStatus(true, message.sessionId ? `Agent ${message.sessionId}` : 'Agent 就绪', '');
        break;
      case 'cwd':
        this.currentCwd = message.dir || message.cwd || this.currentCwd;
        this.emitStatus(this.connected, this.currentCwd.length > 0 ? this.currentCwd : 'Agent 就绪', '');
        break;
      case 'exit': {
        // The remote shell is gone: tear the socket down so stale input can
        // no longer be sent, then report the exit label (disconnect() nulls
        // the socket first, so the late 'close' event cannot overwrite it).
        const exitLabel = message.message || 'Shell 已退出';
        this.disconnect();
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
    if (!this.socket) {
      return;
    }

    try {
      this.socket.send(payload);
    } catch (err) {
      this.connected = false;
      this.ready = false;
      this.emitStatus(false, 'Agent 发送失败', JSON.stringify(err));
    }
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
