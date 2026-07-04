import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

import {
  buildFusionAgentUrl,
  DEFAULT_FUSION_AGENT_HOST,
  DEFAULT_FUSION_AGENT_PATH,
  DEFAULT_FUSION_AGENT_PORT,
  DEFAULT_FUSION_AGENT_TOKEN,
  DEFAULT_FUSION_ENGINE_VM_LABEL
} from '../entry/src/main/ets/drivers/FusionAgentProtocol.ts';

const index = await readFile('entry/src/main/ets/pages/Index.ets', 'utf8');
const agentDriver = await readFile('entry/src/main/ets/drivers/FusionAgentDriver.ets', 'utf8');
const connectionProfile = await readFile('entry/src/main/ets/models/ConnectionProfile.ets', 'utf8');

assert.equal(DEFAULT_FUSION_ENGINE_VM_LABEL, 'Fusion Development Engine VM');
assert.equal(DEFAULT_FUSION_AGENT_HOST, '172.16.100.2');
assert.equal(DEFAULT_FUSION_AGENT_PATH, '/ws');
assert.equal(DEFAULT_FUSION_AGENT_PORT, 8765);
assert.equal(DEFAULT_FUSION_AGENT_TOKEN, 'harmonyterm');

assert.equal(
  buildFusionAgentUrl({
    host: '',
    port: 0,
    path: '',
    cols: 0,
    rows: 0,
    token: DEFAULT_FUSION_AGENT_TOKEN
  }),
  'ws://172.16.100.2:8765/ws?token=harmonyterm&cols=80&rows=24'
);

assert.match(index, /DEFAULT_FUSION_AGENT_HOST/);
assert.match(index, /DEFAULT_FUSION_AGENT_PORT/);
assert.match(index, /DEFAULT_FUSION_ENGINE_VM_LABEL/);
assert.match(index, /@State private draftHost: string = DEFAULT_FUSION_AGENT_HOST;/);
assert.match(index, /@State private draftPort: string = String\(DEFAULT_FUSION_AGENT_PORT\);/);
assert.match(index, /@State private draftAgentToken: string = DEFAULT_FUSION_AGENT_TOKEN;/);
assert.match(index, /Text\(DEFAULT_FUSION_ENGINE_VM_LABEL\)/);

assert.doesNotMatch(index, /bruce/);
assert.doesNotMatch(agentDriver, /bruce/);
assert.match(agentDriver, /DEFAULT_FUSION_ENGINE_VM_LABEL/);
assert.match(agentDriver, /const endpointLabel = endpointHost\.length === 0 \|\| endpointHost === DEFAULT_FUSION_AGENT_HOST/);
assert.doesNotMatch(agentDriver, /Connecting \$\{endpoint\.host/);
assert.doesNotMatch(connectionProfile, /bruce/);
