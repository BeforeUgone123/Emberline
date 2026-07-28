import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const index = await readFile('entry/src/main/ets/pages/Index.ets', 'utf8');
const agent = await readFile('entry/src/main/ets/drivers/FusionAgentDriver.ets', 'utf8');
const protocol = await readFile('entry/src/main/ets/drivers/FusionAgentProtocol.ts', 'utf8');
const pty = await readFile('entry/src/main/cpp/pty/pty_handler.cpp', 'utf8');

const closeSessionBody = index.match(/  private closeSession\(id: number\): void \{[\s\S]*?\n  \}/)?.[0] ?? '';
assert.match(closeSessionBody, /session\.agentDriver\.detach\(\);/,
  'closing a terminal tab should passively detach from the remote agent instead of interrupting tmux/codex');
assert.doesNotMatch(closeSessionBody, /session\.agentDriver\.terminate\(\);/,
  'closing a terminal tab must not send remote termination controls or Ctrl-C bytes');
assert.match(closeSessionBody, /session\.driver\.detach\(\);/,
  'closing a terminal tab should still stop and destroy native local\/SSH sessions');

// Anchor on the ability-teardown body specifically: the chip also defines an
// aboutToDisappear (dot breathing cleanup), so target the one that starts by
// unregistering the window registry entry then the event hub — the page's.
const disappearBody = index.match(/  aboutToDisappear\(\): void \{\s*sessionRegistry\.unregisterWindow\(this\.windowStamp\);\s*this\.context\?\.eventHub\.off\([\s\S]*?\n  \}/)?.[0] ?? '';
assert.match(disappearBody, /session\.agentDriver\.detach\(\);/,
  'ability teardown should passively detach agent sockets without injecting terminal input');
assert.doesNotMatch(disappearBody, /session\.agentDriver\.terminate\(\);/,
  'ability teardown must not interrupt remote foreground tasks');

assert.match(protocol, /export function createTerminateMessage\(\): FusionAgentMessage \{/,
  'Fusion Agent protocol should model an explicit terminate control for hardened agents');
assert.match(protocol, /type: 'terminate'/,
  'terminate control should use a stable JSON message type');

assert.match(agent, /createTerminateMessage/,
  'agent driver should import the terminate control message');
assert.match(agent, /terminate\(\): void \{/,
  'agent driver should expose a termination path separate from passive socket close');
assert.match(agent, /sendRemoteTerminationRequest\(\)/,
  'explicit termination should still use a separate remote termination path');
assert.match(agent, /this\.supportsTerminateControl/,
  'agent driver should only send terminate JSON when the server advertises support');
assert.match(agent, /this\.sendSocketPayload\(stringifyFusionAgentMessage\(createTerminateMessage\(\)\)\)/,
  'hardened agents should receive terminate as a JSON control frame');
assert.doesNotMatch(agent, /encodeUtf8\('\\u0003exit\\r'\)/,
  'stock wand-agent fallback must not receive Ctrl-C + exit bytes because that can kill tmux foreground tasks');
assert.doesNotMatch(agent, /encodeUtf8\('\\u0003/,
  'remote lifecycle cleanup must not be implemented by injecting Ctrl-C into the PTY');
assert.match(agent, /detach\(\): void \{[\s\S]*?this\.closeConnection\(false, 0\);[\s\S]*?this\.controller = null;/,
  'detach should passively close the socket and release controller listeners');
assert.match(agent, /disconnect\(\): void \{\s*this\.closeConnection\(false, 0\);\s*\}/,
  'manual disconnect should be passive and must not interrupt the remote PTY');
assert.match(agent, /connect\(endpoint: FusionAgentEndpoint\): void \{\s*this\.closeConnection\(false, 0\);/,
  'reconnecting should passively close the old socket before opening a new one');
assert.match(agent, /private terminateCloseTimer: number = -1;/,
  'agent driver should keep the socket alive briefly so an advertised terminate control can flush');
assert.match(agent, /clearTimeout\(this\.terminateCloseTimer\)/,
  'agent driver should cancel pending termination timers during reconnect or teardown');

assert.match(pty, /setpgid\(0,\s*0\)/,
  'pipe fallback child should enter its own process group');
assert.match(pty, /kill\(-childPid,\s*SIGHUP\)/,
  'closing a local PTY should hang up the whole process group');
assert.match(pty, /kill\(-childPid,\s*SIGKILL\)/,
  'closing a stubborn local PTY should kill the whole process group');
