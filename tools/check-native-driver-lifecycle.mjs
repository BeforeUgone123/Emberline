import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const source = await readFile('entry/src/main/ets/drivers/FusionTerminalDriver.ets', 'utf8');

assert.match(source, /private sessionId: number = -1;/);
assert.match(source, /private nativeInitialized: boolean = false;/);
assert.match(source, /this\.sessionId = nativeDriver\.createSession\(\);/);
assert.match(source, /nativeDriver\.initialize\(this\.sessionId,\s*this\.context\.filesDir\);\s*this\.nativeInitialized = true;/);
assert.match(source, /nativeDriver\.setOutputCallback\(this\.sessionId,\s*this\.outputListener\);/);
assert.match(source, /if \(this\.nativeInitialized && this\.sessionId >= 0\) \{/);
assert.match(source, /nativeDriver\.setOutputCallback\(this\.sessionId,\s*null\);/);
assert.match(source, /nativeDriver\.destroySession\(this\.sessionId\);/);
assert.match(source, /this\.nativeInitialized = false;/);
assert.doesNotMatch(source, /nativeDriver\.setOutputCallback\(null\);\s*if \(this\.started\)/);
