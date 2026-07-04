import assert from 'node:assert/strict';
import { readFile, stat } from 'node:fs/promises';

const appScope = JSON.parse(await readFile('AppScope/app.json5', 'utf8'));
const moduleConfig = JSON.parse(await readFile('entry/src/main/module.json5', 'utf8'));

const ability = moduleConfig.module?.abilities?.find((item) => item.name === 'EntryAbility');
assert.ok(ability, 'entry module should declare EntryAbility');

assert.equal(
  appScope.app?.icon,
  '$media:fusionterm_icon',
  'installed application icon should use the generated FusionTerm icon asset'
);
assert.equal(
  ability.icon,
  '$media:fusionterm_icon',
  'launcher ability icon should use the generated FusionTerm icon asset'
);
assert.equal(
  ability.startWindowIcon,
  '$media:fusionterm_start_icon',
  'startup window should use the generated FusionTerm start icon asset'
);

for (const path of [
  'entry/src/main/resources/base/media/fusionterm_icon.png',
  'entry/src/main/resources/base/media/fusionterm_start_icon.png',
]) {
  const asset = await stat(path);
  assert.ok(asset.size > 0, `${path} should exist and be non-empty`);
}
