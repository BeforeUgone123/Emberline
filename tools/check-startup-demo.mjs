import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

import { buildAnsi256ColorDemo } from '../entry/src/main/ets/demo/Ansi256ColorDemo.ts';

const demo = buildAnsi256ColorDemo();
const backgroundCodes = [...demo.matchAll(/\x1b\[48;5;(\d+)m/g)].map((match) => Number(match[1]));
const uniqueCodes = new Set(backgroundCodes);

assert.equal(demo.startsWith('\x1b[2J\x1b[H'), true, 'demo should clear the terminal before drawing');
assert.equal(uniqueCodes.size, 256, 'demo should render every ANSI 256-color index');

for (let color = 0; color < 256; color += 1) {
  assert.equal(uniqueCodes.has(color), true, `demo is missing color ${color}`);
}

assert.match(demo, /TERM=xterm-256color/, 'demo should label the terminal mode being mocked');
assert.match(demo, /FusionTerm 256-color renderer mock/, 'demo should include a clear mock title');

const indexSource = await readFile('entry/src/main/ets/pages/Index.ets', 'utf8');
const aboutStart = indexSource.indexOf('  aboutToAppear(): void {');
const aboutEnd = indexSource.indexOf('  aboutToDisappear(): void {');
const aboutToAppearBody = indexSource.slice(aboutStart, aboutEnd);

assert.match(indexSource, /buildAnsi256ColorDemo/, 'startup page should use the 256-color demo builder');
assert.notEqual(aboutStart, -1, 'Index.ets should define aboutToAppear');
assert.notEqual(aboutEnd, -1, 'Index.ets should define aboutToDisappear after aboutToAppear');
assert.doesNotMatch(aboutToAppearBody, /this\.driver\.startLocal\(\);/, 'aboutToAppear should not auto-start the local PTY before the mock demo');
