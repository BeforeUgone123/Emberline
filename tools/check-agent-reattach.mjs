import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

// Lock-screen session survival contract:
//  1. the 25s keepalive ping carries a ~35-40s pong deadline, and a missed
//     deadline enters the same guarded failure path as a socket error;
//  2. foreground/network resume probes immediately or short-circuits a pending
//     backoff retry via reconnectNowIfWaiting;
//  3. reconnects prefer reattaching the remembered session id, and a
//     successful reattach never clears the renderer grid;
//  4. CR-003: the hardened fork gets the token in the Authorization header
//     only; the query token survives solely behind legacyQueryToken.

const driver = await readFile('entry/src/main/ets/drivers/FusionAgentDriver.ets', 'utf8');
const protocol = await readFile('entry/src/main/ets/drivers/FusionAgentProtocol.ts', 'utf8');
const ability = await readFile('entry/src/main/ets/entryability/EntryAbility.ets', 'utf8');
const resumeEvents = await readFile('entry/src/main/ets/common/AppResumeEvents.ets', 'utf8');
const doc = await readFile('docs/fusion-agent-protocol.md', 'utf8');

// --- 1. pong deadline ---------------------------------------------------------

const deadlineMatch = driver.match(/const AGENT_PONG_DEADLINE_MS = (\d+);/);
assert.ok(deadlineMatch, 'the driver must define a pong deadline constant');
const deadlineMs = Number(deadlineMatch[1]);
assert.ok(deadlineMs >= 35000 && deadlineMs <= 40000,
  `pong deadline must stay within 35-40s, got ${deadlineMs}`);
assert.match(driver, /private pongDeadlineTimer: number = -1;/,
  'the pong deadline needs its own timer field');
assert.match(driver, /private armPongDeadline\(ownSocket: webSocket\.WebSocket, timeoutMs: number\): void/,
  'pong deadline must be tied to its own socket generation');

const heartbeatBlock = driver.match(/private startHeartbeat[\s\S]*?\n  private stopHeartbeat/)?.[0] ?? '';
assert.match(heartbeatBlock, /createPingMessage\(Date\.now\(\)\)/,
  'the 25s keepalive ping must stay');
assert.match(heartbeatBlock, /this\.armPongDeadline\(ownSocket, AGENT_PONG_DEADLINE_MS\);/,
  'every keepalive ping must arm the pong deadline');

const armBlock = driver.match(/private armPongDeadline[\s\S]*?\n  private stopPongDeadline/)?.[0] ?? '';
assert.match(armBlock, /handleUnexpectedSocketFailure\(ownSocket, 'Agent 心跳超时'/,
  'a missed pong deadline must enter the guarded failure transition');

const pongCase = driver.match(/case 'pong':[\s\S]*?break;/)?.[0] ?? '';
assert.match(pongCase, /this\.stopPongDeadline\(\);/,
  'any incoming pong must disarm the deadline');

const failureBlock = driver.match(/private handleUnexpectedSocketFailure[\s\S]*?\n  private maybeScheduleReconnect/)?.[0] ?? '';
assert.match(failureBlock, /this\.stopPongDeadline\(\);/,
  'the failure transition must cancel the pong deadline');

const closeBlock = driver.match(/private closeConnection[\s\S]*?\n  private closeSocket/)?.[0] ?? '';
assert.match(closeBlock, /this\.stopPongDeadline\(\);/,
  'deliberate teardown must cancel the pong deadline');

// --- 2. resume probing --------------------------------------------------------

assert.match(driver, /const RESUME_PROBE_PONG_TIMEOUT_MS = 10000;/,
  'resume probing needs a short pong deadline');
assert.match(driver, /private readonly resumeListener = \(\): void => \{/,
  'the driver must subscribe a resume listener');
const resumeBlock = driver.match(/private readonly resumeListener[\s\S]*?\n  \};/)?.[0] ?? '';
assert.match(resumeBlock, /this\.reconnectNowIfWaiting\(\);/,
  'resume must short-circuit a pending backoff retry');
assert.match(resumeBlock, /createPingMessage\(Date\.now\(\)\)/,
  'resume must probe a still-connected socket with an immediate ping');
assert.match(resumeBlock, /this\.armPongDeadline\(this\.socket, RESUME_PROBE_PONG_TIMEOUT_MS\);/,
  'the resume probe must use the short pong deadline');

const connectBlock = driver.match(/connect\(endpoint: FusionAgentEndpoint\): void \{[\s\S]*?this\.openSocket\(endpoint\);/)?.[0] ?? '';
assert.match(connectBlock, /appResumeEvents\.subscribe\(this\.resumeListener\);/,
  'arming auto-reconnect must also subscribe the resume listener');
assert.match(closeBlock, /appResumeEvents\.unsubscribe\(this\.resumeListener\);/,
  'deliberate teardown must unsubscribe the resume listener');

assert.match(ability, /appResumeEvents\.publishForeground\(\);/,
  'EntryAbility must publish the background-to-foreground edge to transports');
assert.match(resumeEvents, /netAvailable/,
  'network recovery must also reach transports');
assert.match(resumeEvents, /connection\.createNetConnection\(\)/,
  'the network watch must use the NetworkKit connection monitor');

// --- 3. attach protocol + reattach does not clear the renderer ----------------

assert.match(protocol, /export interface FusionAgentAttachRequest \{/,
  'the protocol must model the attach request');
assert.match(protocol, /appendQueryParam\(query, 'attach', '1'\);/,
  'the attach handshake travels as attach=1');
assert.match(protocol, /appendQueryParam\(query, 'sessionId', attach\.sessionId\);/,
  'the attach handshake carries the remembered session id');

assert.match(driver, /private agentSessionId: string = '';/,
  'the driver must remember the agent session id');
assert.match(driver, /private supportsSessionAttach: boolean = false;/,
  'attach must be gated on the advertised capability');
assert.match(connectBlock, /this\.agentSessionId = '';/,
  'a deliberate connect() must drop attach state so it spawns a fresh session');

const readyCase = driver.match(/case 'ready':[\s\S]*?break;/)?.[0] ?? '';
assert.match(readyCase, /this\.agentSessionId = message\.sessionId \|\| '';/,
  'the ready frame must update the remembered session id');
assert.match(readyCase, /this\.supportsSessionAttach = this\.hasAttachCapability\(message\.capabilities\);/,
  'the ready frame must update the attach capability');

const openBlock = driver.match(/private openSocket\(endpoint:[\s\S]*?\n  disconnect\(\): void/)?.[0] ?? '';
assert.match(openBlock, /\{ sessionId: attachSessionId \}/,
  'reconnects must carry the remembered session id as an attach request');

const attachedCase = driver.match(/case 'attached':[\s\S]*?break;/)?.[0] ?? '';
assert.ok(attachedCase.length > 0, "the driver must handle the 'attached' frame");
assert.match(attachedCase, /must NOT be[\s\S]*?cleared/,
  'the attached handler must document the no-clear invariant');
assert.doesNotMatch(attachedCase, /feed\('\\u001b\[2J|\[2J/,
  'reattach must never clear the renderer grid');
assert.match(attachedCase, /createResizeMessage\(this\.lastCols, this\.lastRows\)/,
  'reattach must re-send the current grid size');

assert.doesNotMatch(driver, /\\u001b\[2J|\\u001b\[H/,
  'the agent driver must never clear or home the renderer on any reconnect path');

const exitCase = driver.match(/case 'exit': \{[\s\S]*?break;\s*\}/)?.[0] ?? '';
assert.match(exitCase, /this\.agentSessionId = '';/,
  'a dead shell must drop the attach state (nothing left to reattach to)');

// --- 4. CR-003: header-only token with a legacy query fallback -----------------

assert.match(protocol, /legacyQueryToken\?: boolean;/,
  'the endpoint must expose the stock-agent legacy fallback flag');
assert.match(protocol, /if \(endpoint\.legacyQueryToken && endpoint\.token && endpoint\.token\.length > 0\) \{/,
  'the query token must be gated behind legacyQueryToken');
assert.match(driver, /legacyQueryToken: endpoint\.legacyQueryToken/,
  'the driver must pass the legacy flag through to the URL builder');
assert.match(driver, /'Authorization': `Bearer \$\{endpoint\.token\}`/,
  'the Authorization: Bearer header must stay the default auth channel');

// --- 5. protocol documentation -------------------------------------------------

assert.match(doc, /attach=1&sessionId=<id>/, 'the protocol doc must document the attach pair');
assert.match(doc, /legacyQueryToken/, 'the protocol doc must document the legacy query fallback');
assert.match(doc, /40-second pong deadline/, 'the protocol doc must document the pong deadline');
assert.match(doc, /--session-grace-seconds/, 'the protocol doc must document the server grace period');
assert.match(doc, /must NOT clear the renderer on reattach/,
  'the protocol doc must document the reattach no-clear rule');

console.log('Fusion Agent reattach / heartbeat-deadline / CR-003 checks passed.');
