import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const profile = JSON.parse(await readFile('build-profile.json5', 'utf8'));
const appScope = JSON.parse(await readFile('AppScope/app.json5', 'utf8'));
const moduleProfile = JSON.parse(await readFile('entry/src/main/module.json5', 'utf8'));
const resources = JSON.parse(
  await readFile('entry/src/main/resources/base/element/string.json', 'utf8')
);

const product = profile.app.products.find((item) => item.name === 'default');
assert.ok(product, 'the default development product must exist');
assert.equal(product.bundleName, 'com.preview.fusionterm.debug');
assert.equal(product.label, '$string:app_name_dev');
assert.equal(product.compatibleSdkVersion, '6.1.0(23)');
assert.equal(product.targetSdkVersion, '6.1.0(23)');
assert.equal(product.signingConfig, 'debug');

assert.equal(profile.app.signingConfigs.length, 1);
assert.equal(profile.app.signingConfigs[0].name, 'debug');
assert.equal(profile.app.signingConfigs[0].material.keyAlias, 'debugKey');

assert.equal(appScope.app.bundleName, 'com.preview.fusionterm.debug');
assert.equal(appScope.app.label, '$string:app_name_dev');
assert.equal(Object.hasOwn(appScope.app, 'debug'), false);

const devLabel = resources.string.find((item) => item.name === 'app_name_dev');
assert.equal(devLabel?.value, 'Emberline Dev');

const entryAbility = moduleProfile.module.abilities.find((item) => item.name === 'EntryAbility');
assert.ok(entryAbility, 'EntryAbility must exist');
assert.equal(
  Object.hasOwn(entryAbility, 'label'),
  false,
  'EntryAbility must inherit the channel-specific application label'
);

console.log('Development worktree identity check passed.');
