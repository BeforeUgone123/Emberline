import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const index = await readFile('entry/src/main/ets/pages/Index.ets', 'utf8');
// TerminalSessionHandle (controller/driver/agentDriver fields + ctor) was
// extracted into the shared model so the SessionRegistry (tab drag-out / merge)
// and the page share one handle definition; the agent-driver ownership
// assertions moved with it.
const sessionModel = await readFile('entry/src/main/ets/model/TerminalSession.ets', 'utf8');

assert.match(sessionModel, /import \{ FusionAgentDriver \} from '\.\.\/drivers\/FusionAgentDriver';/);
assert.match(index, /DEFAULT_FUSION_AGENT_HOST/);
assert.match(index, /DEFAULT_FUSION_AGENT_PATH/);
assert.match(index, /DEFAULT_FUSION_AGENT_PORT/);
assert.match(index, /DEFAULT_FUSION_AGENT_TOKEN/);
assert.match(index, /DEFAULT_FUSION_ENGINE_VM_LABEL/);
assert.match(sessionModel, /readonly agentDriver: FusionAgentDriver;/);
assert.match(sessionModel, /this\.agentDriver = new FusionAgentDriver\(\);/);
assert.match(index, /@State private draftHost: string = DEFAULT_FUSION_AGENT_HOST;/);
assert.match(index, /@State private draftPort: string = String\(DEFAULT_FUSION_AGENT_PORT\);/);
assert.match(index, /@State private draftSshPort: string = '22';/);
assert.match(index, /@State private draftAgentToken: string = DEFAULT_FUSION_AGENT_TOKEN;/);
assert.match(index, /session\.agentDriver\.setStatusListener/);
assert.match(index, /Button\(this\.agentActionLabel\(\)\)/);
assert.match(index, /Button\('SSH 备用'\)/);
assert.match(index, /placeholder: '22'/);
assert.match(index, /placeholder: '密码'/);
assert.match(index, /private connectFusionAgent\(\): void/);
assert.match(index, /const session = this\.activeSession\(\);/);
assert.match(index, /session\.driver\.detach\(\);/);
assert.match(index, /session\.agentDriver\.attach\(session\.controller\);/);
assert.match(index, /path: DEFAULT_FUSION_AGENT_PATH/);
assert.match(index, /token: this\.draftAgentToken/);
assert.match(index, /session\.agentDriver\.connect\(/);
assert.match(index, /session\.agentDriver\.detach\(\);/);
assert.match(index, /const sshPort = Number\(this\.draftSshPort\);/);
