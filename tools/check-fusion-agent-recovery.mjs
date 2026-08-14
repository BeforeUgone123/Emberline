import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const driver = await readFile('entry/src/main/ets/drivers/FusionAgentDriver.ets', 'utf8');

assert.match(driver, /const AGENT_HEARTBEAT_INTERVAL_MS = 25000;/,
  'the client must send traffic before a typical 30s agent read deadline');
assert.match(driver, /private heartbeatTimer: number = -1;/);
assert.match(driver, /private startHeartbeat\(ownSocket: webSocket\.WebSocket\): void/);
assert.match(driver, /stringifyFusionAgentMessage\(createPingMessage\(Date\.now\(\)\)\)/);
assert.match(driver, /private stopHeartbeat\(\): void/);

const openHandler = driver.match(/ownSocket\.on\('open',[\s\S]*?\n    \}\);/)?.[0] ?? '';
assert.match(openHandler, /this\.startHeartbeat\(ownSocket\);/,
  'heartbeat must start only after the socket opens');

const connectBlock = driver.match(/private openSocket\(endpoint:[\s\S]*?\n  disconnect\(\): void/)?.[0] ?? '';
assert.match(connectBlock, /\.connect\([\s\S]*?\.catch\(\(err: Error\) => \{/,
  'asynchronous handshake rejection must enter the reconnect path');
assert.match(connectBlock, /\.then\(\(connected: boolean\) => \{\s*if \(!connected\)/,
  'a resolved false handshake must enter the reconnect path too');
assert.match(connectBlock, /this\.handleUnexpectedSocketFailure\(ownSocket, 'Agent 连接失败'/);

const closeConnection = driver.match(/private closeConnection[\s\S]*?\n  private closeSocket/)?.[0] ?? '';
assert.match(closeConnection, /this\.stopHeartbeat\(\);/,
  'deliberate teardown must cancel the heartbeat timer');

const handlers = driver.match(/private registerSocketHandlers[\s\S]*?\n  private handleSocketMessage/)?.[0] ?? '';
assert.match(handlers, /on\('close'[\s\S]*?handleUnexpectedSocketFailure\(ownSocket, 'Agent 已断开'/);
assert.match(handlers, /on\('error'[\s\S]*?handleUnexpectedSocketFailure\(ownSocket, 'Agent 错误'/);

const send = driver.match(/private sendSocketPayload[\s\S]*?\n  private sendRemoteTerminationRequest/)?.[0] ?? '';
assert.match(send, /\.send\(payload\)[\s\S]*?\.catch\(\(err: Error\) => \{/,
  'asynchronous send rejection must not leave a half-open session');
assert.match(send, /\.then\(\(sent: boolean\) => \{\s*if \(!sent\)/,
  'a resolved false send must not leave a half-open session');
assert.match(send, /handleUnexpectedSocketFailure\(ownSocket, 'Agent 发送失败'/);

console.log('Fusion Agent recovery checks passed.');
