import assert from 'node:assert/strict';

import {
  buildFusionAgentUrl,
  createCwdQueryMessage,
  createPingMessage,
  createResizeMessage,
  DEFAULT_FUSION_AGENT_HOST,
  DEFAULT_FUSION_AGENT_PATH,
  DEFAULT_FUSION_AGENT_TOKEN,
  parseFusionAgentMessage
} from '../entry/src/main/ets/drivers/FusionAgentProtocol.ts';

assert.equal(DEFAULT_FUSION_AGENT_HOST, '172.16.100.2');
assert.equal(DEFAULT_FUSION_AGENT_PATH, '/ws');
assert.equal(DEFAULT_FUSION_AGENT_TOKEN, 'harmonyterm');

// CR-003: the hardened fork gets the token in the Authorization header only;
// a token without the legacy fallback flag must never appear in the URL.
const defaultUrl = buildFusionAgentUrl({
  host: '172.16.100.2',
  port: 8765,
  path: '/ws',
  cols: 120,
  rows: 34,
  token: 'harmony term',
  cwd: '/home/user/work space'
});

assert.equal(
  defaultUrl,
  'ws://172.16.100.2:8765/ws?cols=120&rows=34&cwd=%2Fhome%2Fuser%2Fwork+space'
);

// Stock wand-agent compatibility: the query token survives only behind the
// explicit legacyQueryToken endpoint flag.
const legacyUrl = buildFusionAgentUrl({
  host: '172.16.100.2',
  port: 8765,
  path: '/ws',
  cols: 120,
  rows: 34,
  token: 'harmony term',
  cwd: '/home/user/work space',
  legacyQueryToken: true
});

assert.equal(
  legacyUrl,
  'ws://172.16.100.2:8765/ws?token=harmony+term&cols=120&rows=34&cwd=%2Fhome%2Fuser%2Fwork+space'
);

const fallbackUrl = buildFusionAgentUrl({
  host: '',
  port: 0,
  path: '',
  cols: 0,
  rows: 0
});

assert.equal(fallbackUrl, 'ws://172.16.100.2:8765/ws?cols=80&rows=24');

const tokenUrl = buildFusionAgentUrl({
  host: '172.16.100.2',
  port: 8765,
  path: '/ws',
  cols: 80,
  rows: 24,
  token: 'harmonyterm'
});

assert.equal(
  tokenUrl,
  'ws://172.16.100.2:8765/ws?cols=80&rows=24'
);

const legacyTokenUrl = buildFusionAgentUrl({
  host: '172.16.100.2',
  port: 8765,
  path: '/ws',
  cols: 80,
  rows: 24,
  token: 'harmonyterm',
  legacyQueryToken: true
});

assert.equal(
  legacyTokenUrl,
  'ws://172.16.100.2:8765/ws?token=harmonyterm&cols=80&rows=24'
);

// Durable-session reattach travels as a query pair on reconnect.
const attachUrl = buildFusionAgentUrl({
  host: '172.16.100.2',
  port: 8765,
  path: '/ws',
  cols: 80,
  rows: 24,
  token: 'harmonyterm'
}, { sessionId: 'abc123' });

assert.equal(
  attachUrl,
  'ws://172.16.100.2:8765/ws?cols=80&rows=24&attach=1&sessionId=abc123'
);

assert.deepEqual(createCwdQueryMessage(), { type: 'cwd' });
assert.deepEqual(createPingMessage(123), { type: 'ping', ts: 123 });

assert.deepEqual(createResizeMessage(140, 42), {
  type: 'resize',
  cols: 140,
  rows: 42
});

assert.deepEqual(parseFusionAgentMessage('{"type":"cwd","dir":"/tmp"}'), {
  type: 'cwd',
  dir: '/tmp'
});

assert.deepEqual(parseFusionAgentMessage('{"type":"error","error":"pty start failed"}'), {
  type: 'error',
  error: 'pty start failed'
});

assert.deepEqual(parseFusionAgentMessage('not-json'), {
  type: 'error',
  code: 'invalid-message',
  message: 'Fusion Agent sent invalid JSON'
});
