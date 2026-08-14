export const DEFAULT_FUSION_ENGINE_VM_LABEL: string = 'Fusion Development Engine VM';
export const DEFAULT_FUSION_AGENT_HOST: string = '172.16.100.2';
export const DEFAULT_FUSION_AGENT_PORT: number = 8765;
export const DEFAULT_FUSION_AGENT_PATH: string = '/ws';
export const DEFAULT_FUSION_AGENT_TOKEN: string = 'harmonyterm';
export const DEFAULT_AGENT_COLS: number = 80;
export const DEFAULT_AGENT_ROWS: number = 24;

export interface FusionAgentEndpoint {
  host: string;
  port: number;
  path: string;
  cols: number;
  rows: number;
  cwd?: string;
  shell?: string;
  token?: string;
  secure?: boolean;
}

export interface FusionAgentMessage {
  type: string;
  protocol?: number;
  client?: string;
  clientVersion?: string;
  sessionId?: string;
  id?: string;
  cols?: number;
  rows?: number;
  cwd?: string;
  dir?: string;
  shell?: string;
  term?: string;
  colorTerm?: string;
  capabilities?: Array<string>;
  list?: Array<string>;
  ts?: number;
  status?: number;
  signal?: string;
  code?: string;
  error?: string;
  message?: string;
  // upload-relay: push a shared-folder file to a remote host via the agent.
  // relayId is numeric and deliberately distinct from the string-typed id
  // that the forked reply uses.
  relayId?: number;
  src?: string;
  target?: string;
  ok?: boolean;
  path?: string;
}

function normalizePositiveInteger(value: number, fallback: number): number {
  return Number.isFinite(value) && value > 0 ? Math.floor(value) : fallback;
}

function normalizePath(path: string): string {
  if (path.trim().length === 0) {
    return DEFAULT_FUSION_AGENT_PATH;
  }
  return path.startsWith('/') ? path : `/${path}`;
}

function encodeQueryValue(value: string): string {
  return encodeURIComponent(value).replace(/%20/g, '+');
}

function appendQueryParam(parts: Array<string>, key: string, value: string | number): void {
  const text = String(value);
  if (text.length === 0) {
    return;
  }
  parts.push(`${encodeQueryValue(key)}=${encodeQueryValue(text)}`);
}

export function buildFusionAgentUrl(endpoint: FusionAgentEndpoint): string {
  const scheme = endpoint.secure ? 'wss' : 'ws';
  const host = endpoint.host.trim().length > 0 ? endpoint.host.trim() : DEFAULT_FUSION_AGENT_HOST;
  const port = normalizePositiveInteger(endpoint.port, DEFAULT_FUSION_AGENT_PORT);
  const path = normalizePath(endpoint.path);
  const cols = normalizePositiveInteger(endpoint.cols, DEFAULT_AGENT_COLS);
  const rows = normalizePositiveInteger(endpoint.rows, DEFAULT_AGENT_ROWS);
  const query: Array<string> = [];

  if (endpoint.token && endpoint.token.length > 0) {
    appendQueryParam(query, 'token', endpoint.token);
  }
  appendQueryParam(query, 'cols', cols);
  appendQueryParam(query, 'rows', rows);
  if (endpoint.cwd && endpoint.cwd.length > 0) {
    appendQueryParam(query, 'cwd', endpoint.cwd);
  }
  if (endpoint.shell && endpoint.shell.length > 0) {
    appendQueryParam(query, 'shell', endpoint.shell);
  }

  return `${scheme}://${host}:${port}${path}?${query.join('&')}`;
}

export function createCwdQueryMessage(): FusionAgentMessage {
  return {
    type: 'cwd'
  };
}

export function createForkMessage(cwd: string): FusionAgentMessage {
  return {
    type: 'fork',
    cwd
  };
}

export function createPingMessage(ts: number): FusionAgentMessage {
  return {
    type: 'ping',
    ts
  };
}

export function createResizeMessage(cols: number, rows: number): FusionAgentMessage {
  return {
    type: 'resize',
    cols: normalizePositiveInteger(cols, DEFAULT_AGENT_COLS),
    rows: normalizePositiveInteger(rows, DEFAULT_AGENT_ROWS)
  };
}

export function createTerminateMessage(): FusionAgentMessage {
  return {
    type: 'terminate'
  };
}

export function createUploadRelayMessage(
  relayId: number,
  src: string,
  target: string,
  dir: string
): FusionAgentMessage {
  return {
    type: 'upload-relay',
    relayId,
    src,
    target,
    dir
  };
}

export function stringifyFusionAgentMessage(message: FusionAgentMessage): string {
  return JSON.stringify(message);
}

export function parseFusionAgentMessage(data: string): FusionAgentMessage {
  try {
    const parsed = JSON.parse(data) as FusionAgentMessage;
    if (!parsed || typeof parsed.type !== 'string' || parsed.type.length === 0) {
      return {
        type: 'error',
        code: 'invalid-message',
        message: 'Fusion Agent sent a control message without a type'
      };
    }
    return parsed;
  } catch (_err) {
    return {
      type: 'error',
      code: 'invalid-message',
      message: 'Fusion Agent sent invalid JSON'
    };
  }
}
