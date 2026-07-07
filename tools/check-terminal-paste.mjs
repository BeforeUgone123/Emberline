import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const moduleJson = await readFile('entry/src/main/module.json5', 'utf8');
const buildProfile = await readFile('build-profile.json5', 'utf8');
const privilegedProfile = await readFile('docs/粘贴板Debug.p7b');
const surface = await readFile('libghostty_ohos/src/main/ets/TerminalSurface.ets', 'utf8');
const controller = await readFile('libghostty_ohos/src/main/ets/TerminalController.ets', 'utf8');
const types = await readFile('libghostty_ohos/src/main/ets/TerminalTypes.ets', 'utf8');
const nativeBridge = await readFile('libghostty_ohos/src/main/cpp/napi_init.cpp', 'utf8');
const privilegedPasteTool = await readFile('tools/configure-privileged-paste.mjs', 'utf8');

const privilegedPasteEnabled = /const PRIVILEGED_PASTE_ENABLED: boolean = true;/.test(surface);
const usesBundledPrivilegedProfile = /"profile":\s*"\.\/docs\/粘贴板Debug\.p7b"/.test(buildProfile);

assert.match(
  moduleJson,
  /"name":\s*"ohos\.permission\.INTERNET"/,
  'terminal app should still declare internet permission for the Fusion Agent connection'
);
if (privilegedPasteEnabled) {
  assert.match(
    moduleJson,
    /ohos\.permission\.READ_PASTEBOARD/,
    'privileged paste builds must declare READ_PASTEBOARD so the signed profile can grant it'
  );
  assert.match(
    buildProfile,
    /"profile":\s*"[^"]+\.p7b"/,
    'privileged paste builds should use a Harmony signing profile so READ_PASTEBOARD can be granted'
  );
  if (usesBundledPrivilegedProfile) {
    assert.match(
      privilegedProfile.toString('utf8'),
      /allowed-acls[\s\S]*ohos\.permission\.READ_PASTEBOARD/,
      'privileged paste profile should contain the READ_PASTEBOARD ACL'
    );
  }
} else {
  assert.doesNotMatch(
    moduleJson,
    /ohos\.permission\.READ_PASTEBOARD/,
    'default builds must not declare READ_PASTEBOARD because it breaks debug install without an ACL/profile'
  );
}

assert.match(types, /export type TerminalPasteRequestListener = \(\) => void;/);
assert.match(controller, /drainPendingPasteRequest: \(surfaceId: string\) => string;/);
assert.match(controller, /private pasteRequestListener: TerminalPasteRequestListener \| null = null;/);
assert.match(controller, /setPasteRequestListener\(listener: TerminalPasteRequestListener \| null\): void/);
assert.match(
  controller,
  /const pendingPaste = this\.pasteRequestListener \?[\s\S]*?this\.native\.drainPendingPasteRequest\(this\.nativeSurfaceId\) : '';[\s\S]*?if \(this\.pasteRequestListener && pendingPaste\.length > 0\) \{\s*this\.pasteRequestListener\(\);\s*\}/s,
  'controller polling should turn native paste shortcut requests into an ArkTS paste callback'
);

assert.match(surface, /const PRIVILEGED_PASTE_ENABLED: boolean = (true|false);/);
assert.match(surface, /private pastePermissionGranted: boolean = false;/);
assert.match(surface, /private directPasteUnavailable: boolean = false;/);
assert.match(surface, /this\.controller\.setPasteRequestListener\(\(\): void => \{\s*void this\.pasteFromClipboardOrShowSecureButton\(\);\s*\}\);/s);
assert.match(surface, /this\.controller\.setPasteRequestListener\(null\);/);
assert.match(surface, /abilityAccessCtrl/);
assert.match(surface, /requestPermissionsFromUser\(this\.context, \['ohos\.permission\.READ_PASTEBOARD'\]\)/);
assert.match(surface, /@State private securePasteVisible: boolean = false;/);
assert.match(surface, /private showSecurePasteButton\(\): void/);
assert.match(surface, /private async pasteFromClipboardOrShowSecureButton\(\): Promise<void>/);
assert.match(surface, /if \(!PRIVILEGED_PASTE_ENABLED \|\| this\.directPasteUnavailable \|\| !await this\.ensurePrivilegedPastePermission\(\)\) \{/);
assert.match(surface, /private async ensurePrivilegedPastePermission\(\): Promise<boolean>/);
assert.match(surface, /private async pasteFromClipboardDirect\(\): Promise<boolean>/);
assert.match(surface, /private async readClipboardText\(\): Promise<string>/);
assert.match(surface, /PasteButton\(/);
assert.match(surface, /PasteButtonOnClickResult\.SUCCESS === result/);
assert.match(surface, /this\.pasteFromClipboardAfterSecureGrant\(\);/);
assert.match(surface, /const data = await clipboard\.getData\(\);/);
assert.match(surface, /this\.controller\.paste\(text\);/);
// The right-click menu moved off ArkUI's unconditional ResponseType.RightClick
// onto the isShown-controlled overload so it can be mutually exclusive with the
// shell's own mouse tracking (see check-terminal-context-menu-mutex.mjs).
assert.doesNotMatch(
  surface,
  /\.bindContextMenu\([^;]*ResponseType\.RightClick\)/,
  'right-click must not unconditionally open the app menu; it is now driven by the native controlled path'
);
assert.match(
  surface,
  /\.bindContextMenu\(this\.contextMenuVisible, this\.buildTerminalContextMenu\(\),/,
  'terminal context menu must use the isShown-controlled overload bound to contextMenuVisible'
);
assert.doesNotMatch(
  surface,
  /if \(this\.hasClipboardContents\(\)\) \{\s*MenuItem\(\{ content: '粘贴' \}\)/s,
  'paste menu must stay visible before clipboard read permission has been granted'
);

assert.match(privilegedPasteTool, /enable|disable|status/);
assert.match(privilegedPasteTool, /ohos\.permission\.READ_PASTEBOARD/);
assert.match(privilegedPasteTool, /PRIVILEGED_PASTE_ENABLED: boolean = true/);
assert.match(privilegedPasteTool, /DevEco Studio/);

assert.match(nativeBridge, /bool IsPasteShortcut\(OH_NativeXComponent_KeyCode code, uint64_t modifiers\)/);
assert.match(nativeBridge, /const bool isCtrlPaste = ctrl && !alt && \(code == LINUX_KEY_V \|\| code == KEY_V\);/);
assert.match(nativeBridge, /const bool isShiftInsertPaste = shift && !ctrl && !alt && \(code == LINUX_KEY_INSERT \|\| code == KEY_INSERT\);/);
assert.match(
  nativeBridge,
  /if \(IsPasteShortcut\(code, modifiers\)\) \{\s*QueuePasteRequest\(\);\s*return true;\s*\}/s,
  'native key path must not send Ctrl-V as a terminal control byte when the user asked to paste'
);
assert.match(nativeBridge, /void QueuePasteRequest\(\) \{[\s\S]*?m_pendingPasteRequest = "paste";[\s\S]*?\}/);
assert.match(nativeBridge, /std::string DrainPendingPasteRequest\(\) \{[\s\S]*?drained\.swap\(m_pendingPasteRequest\);[\s\S]*?\}/);
assert.match(nativeBridge, /static napi_value DrainPendingPasteRequest\(napi_env env, napi_callback_info info\)/);
assert.match(nativeBridge, /\{"drainPendingPasteRequest", nullptr, DrainPendingPasteRequest,/);
