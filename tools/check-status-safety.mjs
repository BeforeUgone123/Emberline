import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const index = await readFile('entry/src/main/ets/pages/Index.ets', 'utf8');
const agentDriver = await readFile('entry/src/main/ets/drivers/FusionAgentDriver.ets', 'utf8');
const nativeDriver = await readFile('entry/src/main/ets/drivers/FusionTerminalDriver.ets', 'utf8');

assert.doesNotMatch(index, /status\.error\.length/);
assert.match(index, /private formatStatusLabel\(label: string, error: string\): string \{/);
assert.match(index, /const safeError = error \|\| '';/);
assert.match(index, /const safeLabel = label \|\| '';/);

assert.match(agentDriver, /const safeLabel = label \|\| '';/);
assert.match(agentDriver, /const safeError = error \|\| '';/);
assert.match(agentDriver, /error: safeError/);
assert.doesNotMatch(agentDriver, /'Agent error', err\.message\)/);
assert.match(agentDriver, /const errorText = err && err\.message \? err\.message : '连接失败';/);
assert.match(agentDriver, /this\.handleUnexpectedSocketFailure\(ownSocket, 'Agent 错误', errorText\);/);

assert.match(nativeDriver, /const safeMode = mode \|\| 'local';/);
assert.match(nativeDriver, /const safeLabel = label \|\| '';/);
assert.match(nativeDriver, /const safeError = error \|\| '';/);
