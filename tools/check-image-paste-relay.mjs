import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

// Image-paste 'relay' mode: a pasted image staged in the shared folder is
// scp-relayed by wand-agent to a configured tailnet host, and the REMOTE path
// is pasted. This check pins the whole client-side chain: protocol message,
// driver round-trip bookkeeping, session config fields, and the Index wiring.

const protocol = await readFile('entry/src/main/ets/drivers/FusionAgentProtocol.ts', 'utf8');
const driver = await readFile('entry/src/main/ets/drivers/FusionAgentDriver.ets', 'utf8');
const session = await readFile('entry/src/main/ets/model/TerminalSession.ets', 'utf8');
const index = await readFile('entry/src/main/ets/pages/Index.ets', 'utf8');

// Protocol: dedicated numeric relayId (the string id belongs to forked) and
// the upload-relay factory carrying src/target/dir.
assert.match(protocol, /relayId\?\s*:\s*number/,
  'FusionAgentMessage must declare the numeric relayId field');
assert.match(protocol, /export function createUploadRelayMessage\(\s*relayId: number,\s*src: string,\s*target: string,\s*dir: string/s,
  'protocol must export createUploadRelayMessage(relayId, src, target, dir)');
assert.match(protocol, /type:\s*'upload-relay'/,
  'createUploadRelayMessage must emit the upload-relay control type');

// Driver: promise-based round trip with timeout and teardown cleanup.
assert.match(driver, /uploadRelay\(src: string, target: string, dir: string\): Promise<string>/,
  'driver must expose uploadRelay returning the remote path');
assert.match(driver, /case 'upload-relay-result':\s*\n\s*this\.settleRelay\(message\);/,
  'driver control switch must settle relay replies');
assert.match(driver, /RELAY_REPLY_TIMEOUT_MS/,
  'relay requests must carry a client-side reply timeout');
assert.match(driver, /this\.rejectAllPendingRelays\('Agent 连接已断开'\);/,
  'closeConnection must reject every in-flight relay so callers never hang');

// Session model: per-tab relay destination config next to pasteMode.
assert.match(session, /relayTarget: string = '';/,
  'session handle must carry relayTarget');
assert.match(session, /relayDir: string = '\/tmp\/emberline-paste';/,
  'session handle must carry relayDir with the documented default');

// Index wiring: the relay branch exists, degrades on missing config, and the
// tab editor exposes the mode plus its two inputs.
assert.match(index, /if \(mode === 'relay'\) \{\s*\n\s*this\.relayPastedImage\(session, exported, localPath\);/,
  'handleImagePasted must route the relay paste mode');
assert.match(index, /agentDriver\.uploadRelay\(vmPath, target, dir\)/,
  'relayPastedImage must relay the VM-visible shared-folder path');
assert.match(index, /未设置中继目标/,
  'relayPastedImage must degrade with a hint when no target is configured');
assert.match(index, /buildPasteModeButton\('中继', 'relay'\)/,
  'tab editor must offer the relay paste mode');
assert.match(index, /this\.editingSession\.relayTarget = value;/,
  'tab editor must persist the relay target onto the session');
assert.match(index, /this\.editingSession\.relayDir = value;/,
  'tab editor must persist the relay dir onto the session');

console.log('check-image-paste-relay: OK');
