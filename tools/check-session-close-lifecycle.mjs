import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const index = await readFile('entry/src/main/ets/pages/Index.ets', 'utf8');
const agent = await readFile('entry/src/main/ets/drivers/FusionAgentDriver.ets', 'utf8');
const protocol = await readFile('entry/src/main/ets/drivers/FusionAgentProtocol.ts', 'utf8');
const pty = await readFile('entry/src/main/cpp/pty/pty_handler.cpp', 'utf8');

const closeSessionBody = index.match(/  private closeSession\(id: number\): void \{[\s\S]*?\n  \}/)?.[0] ?? '';
assert.match(closeSessionBody, /session\.agentDriver\.terminate\(\);/,
  'closing a terminal tab should terminate its remote agent task, not only detach UI listeners');
assert.match(closeSessionBody, /session\.driver\.detach\(\);/,
  'closing a terminal tab should still stop and destroy native local\/SSH sessions');

const disappearBody = index.match(/  aboutToDisappear\(\): void \{[\s\S]*?\n  \}/)?.[0] ?? '';
assert.match(disappearBody, /session\.agentDriver\.terminate\(\);/,
  'ability teardown should terminate agent tasks for all tabs');

assert.match(protocol, /export function createTerminateMessage\(\): FusionAgentMessage \{/,
  'Fusion Agent protocol should model an explicit terminate control for hardened agents');
assert.match(protocol, /type: 'terminate'/,
  'terminate control should use a stable JSON message type');

assert.match(agent, /createTerminateMessage/,
  'agent driver should import the terminate control message');
assert.match(agent, /terminate\(\): void \{/,
  'agent driver should expose a termination path separate from passive socket close');
assert.match(agent, /sendRemoteTerminationRequest\(\)/,
  'agent driver should send a remote termination request before closing');
assert.match(agent, /this\.supportsTerminateControl/,
  'agent driver should only send terminate JSON when the server advertises support');
assert.match(agent, /this\.sendSocketPayload\(stringifyFusionAgentMessage\(createTerminateMessage\(\)\)\)/,
  'hardened agents should receive terminate as a JSON control frame');
assert.match(agent, /this\.sendSocketPayload\(this\.encodeUtf8\('\\u0003exit\\r'\)\)/,
  'stock wand-agent fallback should receive terminal-safe Ctrl-C + exit bytes instead of unknown JSON');
assert.match(agent, /private terminateCloseTimer: number = -1;/,
  'agent driver should keep the socket alive briefly so the termination bytes can flush');
assert.match(agent, /clearTimeout\(this\.terminateCloseTimer\)/,
  'agent driver should cancel pending termination timers during reconnect or teardown');

assert.match(pty, /setpgid\(0,\s*0\)/,
  'pipe fallback child should enter its own process group');
assert.match(pty, /kill\(-childPid,\s*SIGHUP\)/,
  'closing a local PTY should hang up the whole process group');
assert.match(pty, /kill\(-childPid,\s*SIGKILL\)/,
  'closing a stubborn local PTY should kill the whole process group');
