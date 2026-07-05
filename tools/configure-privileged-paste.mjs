#!/usr/bin/env node
import { readFile, writeFile } from 'node:fs/promises';

const mode = process.argv[2] || 'status';
const buildProfilePath = 'build-profile.json5';
const modulePath = 'entry/src/main/module.json5';
const stringPath = 'entry/src/main/resources/base/element/string.json';
const surfacePath = 'libghostty_ohos/src/main/ets/TerminalSurface.ets';
const privilegedProfilePath = './docs/粘贴板Debug.p7b';

const permissionName = 'ohos.permission.READ_PASTEBOARD';
const reasonName = 'pasteboard_permission_reason';

const permissionBlock = `      {
        "name": "${permissionName}",
        "reason": "$string:${reasonName}",
        "usedScene": {
          "abilities": [
            "EntryAbility"
          ],
          "when": "inuse"
        }
      }`;

const reasonBlock = `    {
      "name": "${reasonName}",
      "value": "用于在 PC/2in1 终端中通过物理键盘直接粘贴系统剪贴板文字"
    }`;

function hasPrivilegedPermission(content) {
  return content.includes(permissionName);
}

function hasReasonString(content) {
  return content.includes(`"name": "${reasonName}"`);
}

function setPrivilegedConstant(content, enabled) {
  return content.replace(
    /const PRIVILEGED_PASTE_ENABLED: boolean = (true|false);/,
    `const PRIVILEGED_PASTE_ENABLED: boolean = ${enabled ? 'true' : 'false'};`
  );
}

function setPrivilegedProfile(content) {
  return content.replace(
    /"profile":\s*"[^"]+\.p7b"/,
    `"profile": "${privilegedProfilePath}"`
  );
}

function enableModule(content) {
  if (hasPrivilegedPermission(content)) {
    return content;
  }

  const internetPermissionPattern = /(\s+\{\n\s+"name": "ohos\.permission\.INTERNET"\n\s+\})/;
  if (!internetPermissionPattern.test(content)) {
    throw new Error(`Could not find INTERNET permission in ${modulePath}`);
  }

  return content.replace(internetPermissionPattern, `$1,\n${permissionBlock}`);
}

function disableModule(content) {
  if (!hasPrivilegedPermission(content)) {
    return content;
  }

  return content.replace(
    /,\n\s+\{\n\s+"name": "ohos\.permission\.READ_PASTEBOARD",\n\s+"reason": "\$string:pasteboard_permission_reason",\n\s+"usedScene": \{\n\s+"abilities": \[\n\s+"EntryAbility"\n\s+\],\n\s+"when": "inuse"\n\s+\}\n\s+\}/,
    ''
  );
}

function enableReasonString(content) {
  if (hasReasonString(content)) {
    return content;
  }

  const labelPattern = /(\s+\{\n\s+"name": "EntryAbility_label",\n\s+"value": "Emberline"\n\s+\})(\n\s+\]\n\}\n*)$/;
  if (!labelPattern.test(content)) {
    throw new Error(`Could not find EntryAbility_label string in ${stringPath}`);
  }

  return content.replace(labelPattern, `$1,\n${reasonBlock}$2`);
}

function disableReasonString(content) {
  if (!hasReasonString(content)) {
    return content;
  }

  return content.replace(
    /,\n\s+\{\n\s+"name": "pasteboard_permission_reason",\n\s+"value": "用于在 PC\/2in1 终端中通过物理键盘直接粘贴系统剪贴板文字"\n\s+\}/,
    ''
  );
}

async function readProjectFiles() {
  const [buildProfile, moduleJson, stringJson, surface] = await Promise.all([
    readFile(buildProfilePath, 'utf8'),
    readFile(modulePath, 'utf8'),
    readFile(stringPath, 'utf8'),
    readFile(surfacePath, 'utf8')
  ]);
  return { buildProfile, moduleJson, stringJson, surface };
}

async function writeProjectFiles(files) {
  await Promise.all([
    writeFile(buildProfilePath, files.buildProfile),
    writeFile(modulePath, files.moduleJson),
    writeFile(stringPath, files.stringJson),
    writeFile(surfacePath, files.surface)
  ]);
}

async function main() {
  if (!['enable', 'disable', 'status'].includes(mode)) {
    throw new Error('Usage: node tools/configure-privileged-paste.mjs <enable|disable|status>');
  }

  const files = await readProjectFiles();
  const enabled = hasPrivilegedPermission(files.moduleJson) &&
    /const PRIVILEGED_PASTE_ENABLED: boolean = true;/.test(files.surface);

  if (mode === 'status') {
    console.log(enabled ? 'privileged paste: enabled' : 'privileged paste: disabled');
    return;
  }

  if (mode === 'enable') {
    files.buildProfile = setPrivilegedProfile(files.buildProfile);
    files.moduleJson = enableModule(files.moduleJson);
    files.stringJson = enableReasonString(files.stringJson);
    files.surface = setPrivilegedConstant(files.surface, true);
    await writeProjectFiles(files);
    console.log('privileged paste: enabled');
    console.log('Regenerate the DevEco Studio signing profile with READ_PASTEBOARD before installing.');
    return;
  }

  files.moduleJson = disableModule(files.moduleJson);
  files.stringJson = disableReasonString(files.stringJson);
  files.surface = setPrivilegedConstant(files.surface, false);
  await writeProjectFiles(files);
  console.log('privileged paste: disabled');
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : String(err));
  process.exit(1);
});
