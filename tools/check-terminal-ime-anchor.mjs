import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const surface = await readFile('libghostty_ohos/src/main/ets/TerminalSurface.ets', 'utf8');
const index = await readFile('entry/src/main/ets/pages/Index.ets', 'utf8');
const ability = await readFile('entry/src/main/ets/entryability/EntryAbility.ets', 'utf8');
const controller = await readFile('libghostty_ohos/src/main/ets/TerminalController.ets', 'utf8');
const nativeBridge = await readFile('libghostty_ohos/src/main/cpp/napi_init.cpp', 'utf8');
const terminalHeader = await readFile('libghostty_ohos/src/main/cpp/terminal/terminal.h', 'utf8');
const terminalSource = await readFile('libghostty_ohos/src/main/cpp/terminal/terminal.cpp', 'utf8');

const requestTerminalFocusBlock =
  surface.match(/private requestTerminalFocus\(\): void \{([\s\S]*?)\n  \}/)?.[1] ?? '';
const foregroundRequestBlock =
  surface.match(/private scheduleForegroundImeRequest\(\): void \{([\s\S]*?)\n  \}/)?.[1] ?? '';
const nativeKeyBlock = nativeBridge.match(/bool DispatchKeyEvent[\s\S]*?\n    void DispatchTouchEvent/)?.[0] ?? '';
const imePrintableGateBlock =
  nativeBridge.match(/bool ShouldLetImeHandlePrintableKey[\s\S]*?\n\}/)?.[0] ?? '';
const nativeTouchBlock = nativeBridge.match(/void DispatchTouchEvent[\s\S]*?\n    void DispatchMouseEvent/)?.[0] ?? '';
const nativeMouseBlock = nativeBridge.match(/void DispatchMouseEvent[\s\S]*?\n    void ScrollViewportByPointerDelta/)?.[0] ?? '';
const nativeSetImeActiveBlock = nativeBridge.match(/void SetImeActive\(bool active\)[\s\S]*?\n    void FeedOutput/)?.[0] ?? '';
const nativeSurfaceShowBlock = nativeBridge.match(/void OnSurfaceShow\(OH_NativeXComponent\* component, void\* window\)[\s\S]*?\n    void OnSurfaceHide/)?.[0] ?? '';
const nativeSurfaceHideBlock = nativeBridge.match(/void OnSurfaceHide\(\)[\s\S]*?\n    void OnSurfaceDestroyed/)?.[0] ?? '';
const nativeFocusBlock = nativeBridge.match(/void OnFocusEvent\(\)[\s\S]*?\n    void OnBlurEvent/)?.[0] ?? '';
const nativeBlurBlock = nativeBridge.match(/void OnBlurEvent\(\)[\s\S]*?\n    bool DispatchKeyEvent/)?.[0] ?? '';
const nativeCanAcceptImeBlock =
  nativeBridge.match(/bool CanAcceptImeCallbacks\(\) const[\s\S]*?\n    }/)?.[0] ?? '';
const nativeGetTextConfigBlock =
  nativeBridge.match(/static void HandleImeGetTextConfig[\s\S]*?\n    static void HandleImeInsertText/)?.[0] ?? '';
const nativeShowImeBlock =
  nativeBridge.match(/void ShowImeLocked\(InputMethod_RequestKeyboardReason reason\)[\s\S]*?\n    void HideImeLocked/)?.[0] ?? '';
const nativeNotifyImeBlock =
  nativeBridge.match(/void NotifyImeStateLocked\(bool force = false\)[\s\S]*?\n    \/\/ Force the next NotifyImeStateLocked/)?.[0] ?? '';
const nativeCaptureImeBlock =
  nativeBridge.match(/void CaptureImeSurroundingText[\s\S]*?\n    void RefreshImeSurroundingText/)?.[0] ?? '';
const nativeRefreshImeBlock =
  nativeBridge.match(/void RefreshImeSurroundingText[\s\S]*?\n    void NotifyImeStateLocked/)?.[0] ?? '';
const terminalImeSnapshotBlock =
  terminalSource.match(/void Terminal::getImeSnapshot[\s\S]*?\n}\n\nstd::string Terminal::getLinkAt/)?.[0] ?? '';
const indexTabBarBlock = index.match(/private buildTabBar\(\)[\s\S]*?\n  @Builder\n  private buildDrawerScrim/)?.[0] ?? '';

assert.match(surface, /XComponent\(\{\s*id: this\.surfaceId,\s*type: XComponentType\.SURFACE,\s*libraryname: 'libghostty_ohos'/s);
assert.match(surface, /\.focusable\(true\)/);
assert.match(surface, /\.focusOnTouch\(true\)/);
assert.match(surface, /\.defaultFocus\(true\)/);
assert.match(surface, /\.onTouch\(\(_event\?: TouchEvent\) => \{\s*this\.requestTerminalFocus\(\);\s*\}\)/s);

assert.doesNotMatch(
  surface,
  /buildImeInputAnchor|imeInputController|imeAnchorSentinel|imeText|TextInput\(\{ text: this\.imeText/,
  'terminal input must not use a hidden ArkUI TextInput; XComponent/native IME is the single software IME owner'
);
assert.doesNotMatch(
  surface,
  /focusControl\.requestFocus\(this\.imeInputId\)/,
  'terminal focus recovery must not move focus away from the XComponent'
);
assert.match(requestTerminalFocusBlock, /focusControl\.requestFocus\(this\.surfaceId\);/);
assert.doesNotMatch(
  requestTerminalFocusBlock,
  /this\.controller\.requestIme\(\);/,
  'ArkUI foreground/touch focus must not synchronously call the native IME bridge; native XComponent focus/touch owns IME restore'
);
assert.match(surface, /@Prop @Watch\('onForegroundFocusEpochChanged'\) foregroundFocusEpoch: number = 0;/);
assert.match(surface, /@Prop @Watch\('onActiveChanged'\) active: boolean = true;/);
assert.match(surface, /private foregroundFocusTimer: number = -1;/);
assert.match(surface, /this\.controller\.setImeActive\(this\.active\);/);
assert.match(surface, /private onActiveChanged\(\): void \{/);
// active now owns IME/focus and the native input gate: an open drawer/tab-editor
// hides the keyboard and deafens native input (key/axis bypass hit-test
// occlusion), but the still-visible terminal keeps polling via `visible`.
assert.match(surface, /if \(this\.active\) \{\s*this\.controller\.setInputBlocked\(false\);\s*this\.controller\.setImeActive\(true\);\s*this\.scheduleForegroundImeRequest\(\);\s*return;\s*\}/s);
assert.match(
  surface,
  /@Prop @Watch\('onVisibleChanged'\) visible: boolean = true;/,
  'tab visibility must be a prop distinct from active so a translucent drawer does not throttle the visible terminal'
);
assert.match(surface, /const INACTIVE_TAB_TITLE_POLL_INTERVAL_MS: number = 120;/);
assert.match(surface, /const APP_BACKGROUND_TITLE_POLL_INTERVAL_MS: number = 500;/);
assert.match(surface, /@Prop @Watch\('onAppBackgroundedChanged'\) appBackgrounded: boolean = false;/);
assert.match(
  surface,
  /private onVisibleChanged\(\): void \{\s*this\.syncPollingBudget\(\);/s,
  'tab visibility (not active) must gate the controller input polling for background tabs'
);
assert.match(
  surface,
  /private onAppBackgroundedChanged\(\): void \{\s*this\.syncPollingBudget\(\);\s*\}/s,
  'the app lifecycle must switch hidden-title polling back to the low-power cadence'
);
assert.match(
  surface,
  /private syncPollingBudget\(\): void \{[\s\S]*?this\.appBackgrounded\s*\? APP_BACKGROUND_TITLE_POLL_INTERVAL_MS\s*: INACTIVE_TAB_TITLE_POLL_INTERVAL_MS;[\s\S]*?this\.controller\.setPollingSuspended\(!this\.visible, titlePollIntervalMs\);/s,
  'inactive tabs stay responsive while the app is foregrounded but throttle when the whole app is backgrounded'
);
assert.match(
  surface,
  /private onVisibleChanged\(\): void \{[\s\S]*?if \(this\.visible\) \{\s*this\.syncScrollbarState\(\);\s*this\.startScrollbarPolling\(\);\s*\} else \{\s*this\.stopScrollbarPolling\(\);\s*\}/s,
  'the visibility watch owns the scrollbar refresh loop for background/foreground tabs'
);
const onActiveChangedBlock =
  surface.match(/private onActiveChanged\(\): void \{[\s\S]*?\n  \}/)?.[0] ?? '';
assert.doesNotMatch(
  onActiveChangedBlock,
  /setPollingSuspended|startScrollbarPolling|stopScrollbarPolling|syncScrollbarState/,
  'active watch must only touch IME/focus; polling and scrollbar belong to the visibility watch'
);
assert.match(surface, /this\.controller\.setImeActive\(false\);/);
assert.match(surface, /private onForegroundFocusEpochChanged\(\): void \{/);
assert.match(surface, /private scheduleForegroundImeRequest\(\): void \{/);
assert.match(foregroundRequestBlock, /if \(!this\.active\) \{/);
assert.match(foregroundRequestBlock, /this\.requestTerminalFocus\(\);/);

assert.match(
  index,
  /const FOREGROUND_FOCUS_EVENT: string = 'fusionTermForeground';/,
  'foreground IME recovery must use the UIAbility foreground event rather than initial page display'
);
assert.match(index, /@State private foregroundFocusEpoch: number = 0;/);
assert.match(index, /private foregroundFocusListener: \(\) => void = \(\): void => \{/);
assert.match(index, /this\.foregroundFocusEpoch \+= 1;/);
assert.match(index, /this\.context\.eventHub\.on\(FOREGROUND_FOCUS_EVENT, this\.foregroundFocusListener\);/);
assert.match(index, /this\.context\?\.eventHub\.off\(FOREGROUND_FOCUS_EVENT, this\.foregroundFocusListener\);/);
assert.doesNotMatch(
  index,
  /onPageShow\(\): void \{\s*this\.foregroundFocusEpoch \+= 1;\s*\}/s,
  'startup page display must not request IME or the app can hang before the terminal is interactive'
);
assert.match(
  index,
  /active: session\.id === this\.activeSessionId &&\s*!this\.drawerOpen &&\s*!this\.tabEditOpen/s
);
assert.match(
  index,
  /visible: session\.id === this\.activeSessionId/,
  'polling/scrollbar gating must follow raw tab visibility, independent of drawer/tab-edit overlays'
);
assert.match(index, /appBackgrounded: this\.appInBackground/);
assert.match(index, /foregroundFocusEpoch: this\.foregroundFocusEpoch/);
assert.match(index, /private focusActiveTerminalSoon\(\): void \{/);
assert.match(
  index,
  /focusControl\.requestFocus\(`fusionTermSurface-g\$\{session\.surfaceSeq\}`\);/,
  'programmatic focus must target the process-global surface id (multiton-safe)'
);
assert.match(index, /session\.controller\.setImeActive\(true\);/);
assert.doesNotMatch(
  index.match(/private focusActiveTerminalSoon\(\): void \{[\s\S]*?\n  \}/)?.[0] ?? '',
  /session\.controller\.requestIme\(\);/,
  'tab/chrome focus recovery must not stack a second synchronous IME request on top of XComponent focus callbacks'
);
assert.match(
  indexTabBarBlock,
  /ic_plus[\s\S]*?\.focusable\(false\)[\s\S]*?this\.addSession\(true\);/s,
  'new-tab button must not keep keyboard focus from the terminal'
);
for (const label of ['ic_link', 'ic_gear', 'ic_more']) {
  assert.match(
    indexTabBarBlock,
    new RegExp(`${label}[\\s\\S]*?\\.focusable\\(this\\.workbenchFocusZone > 0\\)`),
    `${label} chrome button must join focus traversal only after the explicit focus shortcut leaves the terminal`
  );
}
assert.doesNotMatch(indexTabBarBlock, /ic_keyboard|ic_help/, 'quick-key and standalone help actions must stay out of persistent chrome');
assert.match(index, /\.keyboardShortcut\(FunctionKey\.F6, \[\], \(\) => \{\s*this\.cycleWorkbenchFocus\(\);/s);
assert.match(
  index,
  /\.keyboardShortcut\('\.', \[ModifierKey\.CTRL, ModifierKey\.ALT\], \(\) => \{\s*this\.cycleWorkbenchFocus\(\);/s,
  'compact keyboards without a function row must retain the explicit workbench focus route'
);
assert.match(index, /private cycleWorkbenchFocus\(\): void \{/);
assert.match(index, /focusControl\.requestFocus\(componentId\);/);
assert.match(index, /\.id\(`workbenchInspector-\$\{pane\}`\)[\s\S]*?\.focusable\(this\.workbenchFocusZone === 2\)/s);
assert.match(index, /\.keyboardShortcut\(FunctionKey\.ESC, \[\], \(\) => \{/);
assert.doesNotMatch(index, /accessoryVisible|buildAccessoryBar|sendAccessoryKey/);
assert.match(
  index,
  /\.backgroundColor\(this\.active\s*\? this\.chrome\.capBg[\s\S]*?\.focusable\(false\)\s*\.onClick/s,
  'tab chips must be mouse/touch clickable without stealing arrow-key focus'
);

assert.match(ability, /const FOREGROUND_FOCUS_EVENT: string = 'fusionTermForeground';/);
assert.match(ability, /private wasBackgrounded: boolean = false;/);
assert.match(
  ability,
  /onBackground\(\): void \{[\s\S]*?this\.wasBackgrounded = true;[\s\S]*?eventHub\.emit\(BACKGROUND_EVENT\);\s*\}/s,
  'onBackground must record the flag AND broadcast so the page can notify for the active tab'
);
assert.match(
  ability,
  /onForeground\(\): void \{[\s\S]*?if \(!this\.wasBackgrounded\) \{\s*return;\s*\}\s*this\.wasBackgrounded = false;\s*this\.context\.eventHub\.emit\(FOREGROUND_FOCUS_EVENT\);\s*\}/s,
  'initial launch foreground must be ignored; only a real background->foreground transition should refocus IME'
);

assert.match(controller, /requestIme: \(surfaceId: string\) => void;/);
assert.match(controller, /setImeActive: \(surfaceId: string, active: boolean\) => void;/);
assert.match(controller, /requestIme\(\): void \{/);
assert.match(controller, /private titlePollIntervalMs: number = 500;/);
assert.match(
  controller,
  /setPollingSuspended\(suspended: boolean, titlePollIntervalMs: number = 500\): void/
);
assert.match(controller, /\}, this\.titlePollIntervalMs\) as number;/);
assert.match(
  controller,
  /private nativeSurfaceId: string = '';/,
  'each TerminalController must remember its own XComponent id; native module exports can be shared across XComponent instances'
);
assert.match(
  controller,
  /bindNative\(native: Object, context: common\.UIAbilityContext, density: number, surfaceId: string\): void/,
  'TerminalSurface must pass the XComponent id into the native bridge binding'
);
assert.match(controller, /this\.nativeSurfaceId = surfaceId;/);
assert.match(controller, /this\.native\?\.requestIme\(this\.nativeSurfaceId\);/);
assert.match(controller, /setImeActive\(active: boolean\): void \{/);
assert.match(controller, /this\.native\?\.setImeActive\(this\.nativeSurfaceId, active\);/);
assert.match(
  surface,
  /this\.controller\.bindNative\(nativeContext, this\.context, this\.getDisplayDensity\(\), this\.surfaceId\);/,
  'TerminalSurface must bind native calls to its stable surface id'
);
assert.match(
  requestTerminalFocusBlock,
  /if \(!this\.active\) \{\s*return;\s*\}\s*this\.controller\.setImeActive\(true\);\s*focusControl\.requestFocus\(this\.surfaceId\);/s,
  'foreground/touch recovery must re-activate the native IME owner before returning focus to the XComponent'
);

assert.match(
  nativeBridge,
  /OH_NativeXComponent_SetNeedSoftKeyboard\(nativeXComponent, true\);/,
  'XComponent must opt in to soft keyboard support or focus transfer to it closes the IME'
);
assert.match(nativeBridge, /OH_NativeXComponent_RegisterFocusEventCallback\(nativeXComponent, OnFocusEventCB\);/);
assert.match(nativeBridge, /OH_NativeXComponent_RegisterBlurEventCallback\(nativeXComponent, OnBlurEventCB\);/);
assert.match(nativeBridge, /std::unordered_map<std::string, std::unique_ptr<TerminalHost>> g_hostsById;/);
assert.match(nativeBridge, /std::unordered_map<OH_NativeXComponent\*, TerminalHost\*> g_hostsByComponent;/);
assert.match(nativeBridge, /TerminalHost\* FindHostById\(const std::string& id\)/);
assert.match(
  nativeBridge,
  /OH_NativeXComponent_GetXComponentId\(component, idStr, &idSize\)/,
  'native init must read the XComponent id so shared module exports can route calls to the intended terminal'
);
assert.match(
  nativeBridge,
  /if \(rawArgc > 0 && TryReadStringArg\(env, rawArgs\[0\], id\)\) \{\s*if \(TerminalHost\* idHost = FindHostById\(id\)\) \{/s,
  'NAPI callbacks must prefer the explicit surface id passed from ArkTS over stale descriptor data'
);
assert.match(nativeBridge, /static napi_value RequestIme/);
assert.match(nativeBridge, /static napi_value SetImeActive/);
assert.match(nativeBridge, /\{"requestIme"/);
assert.match(nativeBridge, /\{"setImeActive"/);
assert.match(nativeBridge, /std::atomic<bool> m_imeActive \{ true \};/);
assert.match(nativeBridge, /std::atomic<bool> m_xComponentFocused \{ false \};/);
assert.match(nativeBridge, /constexpr auto IME_RENDER_REPORT_INTERVAL = std::chrono::milliseconds\(50\);/);
assert.doesNotMatch(
  nativeBridge,
  /NATIVE_IME_API_ENABLED|Focused-stutter A\/B/,
  'the temporary no-IME diagnostic switch must not ship after the InputMethod API is restored'
);
assert.match(nativeBridge, /static TerminalHost\* FindActiveImeHost\(InputMethod_TextEditorProxy\* proxy\)/);
assert.ok(
  (nativeBridge.match(/FindActiveImeHost\(proxy\)/g) ?? []).length >= 13,
  'IME input and query callbacks must be dropped while their terminal surface is inactive or unfocused'
);
assert.match(nativeBridge, /static TerminalHost\* FindConfigurableImeHost\(InputMethod_TextEditorProxy\* proxy\)/);
assert.match(nativeGetTextConfigBlock, /FindConfigurableImeHost\(proxy\)/);
assert.doesNotMatch(
  nativeGetTextConfigBlock,
  /FindActiveImeHost\(proxy\)/,
  'attach-time text configuration must remain available before the restored XComponent receives focus'
);
assert.match(
  nativeSurfaceShowBlock,
  /shouldRestoreIme = m_wantsIme && m_imeActive\.load\(std::memory_order_relaxed\);/s,
  'foreground surface restore must still ignore hidden sessions when deciding whether to reclaim IME'
);
assert.match(
  nativeSurfaceHideBlock,
  /m_xComponentFocused\.store\(false, std::memory_order_relaxed\);/,
  'a hidden XComponent must stop render-driven IME reporting even when its proxy stays attached'
);
assert.match(
  nativeSetImeActiveBlock,
  /m_imeActive\.store\(active, std::memory_order_relaxed\);\s*if \(!m_imeActive\.load\(std::memory_order_relaxed\)\) \{\s*m_wantsIme = false;\s*m_imeVisible = false;\s*m_imePreviewActive = false;\s*return;\s*\}/s,
  'inactive terminal sessions must stop owning IME without synchronously detaching input method services'
);
assert.doesNotMatch(
  nativeSetImeActiveBlock,
  /DetachImeLocked|HideImeLocked|ShowImeLocked|OH_InputMethod/,
  'opening connection/settings panels must not block the UI thread on IME framework calls'
);
assert.match(
  nativeBridge,
  /if \(!m_imeActive\.load\(std::memory_order_relaxed\)\) \{\s*m_wantsIme = false;\s*return;\s*\}\s*m_wantsIme = true;/s,
  'hidden sessions must not leave physical letters delegated to an unavailable IME'
);
assert.match(nativeBridge, /std::recursive_mutex m_surfaceMutex;/);
assert.match(nativeBridge, /void RequestIme\(\)\s*\{\s*std::lock_guard<std::recursive_mutex> surfaceLock\(m_surfaceMutex\);\s*ShowImeLocked\(IME_REQUEST_REASON_OTHER\);\s*NotifyImeStateLocked\(true\);/s);
assert.match(nativeBridge, /ResetImeSessionLocked\(\);/);
assert.match(nativeBridge, /OH_InputMethodController_Detach\(m_imeInputMethodProxy\);/);
assert.doesNotMatch(
  nativeBridge,
  /OH_TextEditorProxy_Destroy/,
  'text editor proxies must NEVER be destroyed: the IME service delivers ' +
  'OnInputStop -> SendKeyboardStatusV2 asynchronously over binder and a ' +
  'destroyed proxy is the exact UAF behind the OS_IPC SIGSEGV cppcrash ' +
  '(2026-07-04/05). Retire via g_retiredImeProxies instead.'
);
assert.doesNotMatch(nativeBridge, /m_imeSessionNeedsReset/);
assert.match(
  nativeBridge,
  /bool AttachImeLocked\(bool showKeyboard, InputMethod_RequestKeyboardReason reason\)/,
  'native IME attach must mirror the official custom-editor lifecycle: bind on focus with optional keyboard display'
);
assert.match(
  nativeBridge,
  /OH_AttachOptions_CreateWithRequestKeyboardReason\(showKeyboard, reason\)/,
  'attach must pass showKeyboard through OH_InputMethodController_Attach rather than relying only on ShowTextInput'
);
assert.match(
  nativeBridge,
  /if \(m_imeInputMethodProxy == nullptr\) \{\s*if \(!AttachImeLocked\(true, reason\)\) \{/s,
  'a missing IME proxy must be attached when foreground focus requests input'
);
assert.match(
  nativeBridge,
  /if \(rc == IME_ERR_DETACHED\) \{\s*ResetImeSessionLocked\(\);\s*if \(!AttachImeLocked\(true, reason\)\) \{/s,
  'foreground restore must recover from OpenHarmony C API detached state by attaching again'
);
assert.match(
  nativeSurfaceShowBlock,
  /bool shouldRestoreIme = false;[\s\S]*?shouldRestoreIme = m_wantsIme && m_imeActive\.load\(std::memory_order_relaxed\);[\s\S]*?if \(shouldRestoreIme\) \{\s*RequestIme\(\);\s*\}/s,
  'surface foreground restore must schedule IME restore after releasing the surface lifecycle lock'
);
assert.doesNotMatch(
  nativeSurfaceShowBlock.match(/\{\s*std::lock_guard<std::recursive_mutex> surfaceLock\(m_surfaceMutex\);[\s\S]*?\n        \}/)?.[0] ?? '',
  /ShowImeLocked|HideImeLocked|ResetImeSessionLocked|NotifyImeStateLocked|OH_InputMethod/,
  'surface show must not call IME services while HarmonyOS is holding XComponent lifecycle focus'
);
assert.doesNotMatch(
  nativeSurfaceHideBlock,
  /HideImeLocked|DetachImeLocked|OH_InputMethod/,
  'surface hide/background must not synchronously call IME services; HarmonyOS may be tearing down the input channel'
);
assert.doesNotMatch(
  nativeBlurBlock,
  /HideImeLocked|DetachImeLocked|OH_InputMethod/,
  'blur must mark local IME visibility only; synchronous hide can deadlock during foreground/background transitions'
);
assert.match(
  nativeFocusBlock,
  /m_xComponentFocused\.store\(true, std::memory_order_relaxed\);\s*ShowImeLocked\(IME_REQUEST_REASON_OTHER\);\s*NotifyImeStateLocked\(true\);/s,
  'native focus remains the single keyboard restore path after ArkUI focusControl.requestFocus'
);
assert.match(
  nativeBlurBlock,
  /m_xComponentFocused\.store\(false, std::memory_order_relaxed\);/,
  'native blur must stop render-driven IME reporting before the next terminal frame'
);
assert.match(
  nativeTouchBlock,
  /ShowImeLocked\(IME_REQUEST_REASON_TOUCH\);\s*NotifyImeStateLocked\(true\);/s,
  'native touch is the reliable event path for libraryname XComponent taps'
);
assert.match(
  nativeMouseBlock,
  /ShowImeLocked\(IME_REQUEST_REASON_MOUSE\);\s*NotifyImeStateLocked\(true\);/s,
  'mouse clicks must restore native IME for trackpad and pointer users'
);
assert.match(
  nativeNotifyImeBlock,
  /if \(!m_imeActive\.load\(std::memory_order_relaxed\) \|\|\s*!m_xComponentFocused\.load\(std::memory_order_relaxed\) \|\|\s*!m_wantsIme \|\|\s*m_terminal == nullptr \|\| !m_surfaceReady\) \{\s*return;\s*\}/s,
  'render-driven IME snapshots must stop before touching terminal state when the surface is inactive, unfocused, hidden, or failed'
);
assert.match(
  nativeNotifyImeBlock,
  /if \(!force && m_lastImeReportAt\.time_since_epoch\(\)\.count\(\) != 0 &&\s*now - m_lastImeReportAt < IME_RENDER_REPORT_INTERVAL\) \{\s*return;\s*\}/s,
  'render-driven IME reports must be rate-limited before capturing terminal text'
);
assert.match(
  nativeCanAcceptImeBlock,
  /CanConfigureIme\(\) &&\s*m_xComponentFocused\.load\(std::memory_order_relaxed\)/s,
  'IME callbacks must be rejected after either ArkTS deactivation or real XComponent blur'
);
assert.match(
  nativeBridge,
  /bool CanConfigureIme\(\) const\s*\{\s*return m_imeActive\.load\(std::memory_order_relaxed\);\s*\}/s,
  'attach-time configuration may run before focus but must still reject inactive terminal surfaces'
);
assert.match(
  nativeBridge,
  /m_terminal->drawFrame\(\);\s*NotifyImeStateLocked\(\);/s,
  'the render loop must use the rate-limited IME report path rather than forcing Binder work every frame'
);
assert.match(
  nativeBridge,
  /void InvalidateImeReportCacheLocked\(\)\s*\{\s*m_lastImeReportAt = \{\};/s,
  'focus/show/session hand-off must make the next IME report immediately eligible'
);
assert.match(nativeNotifyImeBlock, /RefreshImeSurroundingText\(surrounding, cursorIndex\);/);
assert.match(
  nativeCaptureImeBlock,
  /std::lock_guard<std::mutex> lock\(m_imeSnapshotMutex\);[\s\S]*?text = m_cachedImeSurrounding;[\s\S]*?cursorIndex = m_cachedImeCursor;/s,
  'IME Binder queries must copy the last renderer-owned snapshot under their own short lock'
);
assert.doesNotMatch(
  nativeCaptureImeBlock,
  /m_terminal|getImeSnapshot|ghostty_render_state_update|getScreenContent|getCursorPosition|std::vector<std::string>/,
  'IME Binder queries must never enter terminal state or update Ghostty render state'
);
assert.match(nativeRefreshImeBlock, /m_terminal->getImeSnapshot\(line, cursorColumn\);/);
assert.match(
  nativeRefreshImeBlock,
  /std::lock_guard<std::mutex> lock\(m_imeSnapshotMutex\);[\s\S]*?m_cachedImeSurrounding = text;[\s\S]*?m_cachedImeCursor = cursorIndex;/s,
  'the render/report path must publish each cursor-row snapshot atomically for IME callbacks'
);
assert.doesNotMatch(
  nativeRefreshImeBlock,
  /OH_InputMethodProxy_NotifySelectionChange|OH_InputMethodProxy_NotifyCursorUpdate/,
  'the snapshot lock must be released before outgoing Binder notifications can re-enter callbacks'
);
assert.match(nativeBridge, /mutable std::mutex m_imeSnapshotMutex;/);
assert.match(nativeBridge, /std::u16string m_cachedImeSurrounding;/);
assert.match(nativeBridge, /int32_t m_cachedImeCursor = 0;/);
assert.match(terminalHeader, /void getImeSnapshot\(std::string& line, int& cursorCol\) const;/);
assert.match(terminalImeSnapshotBlock, /ghostty_render_state_update\(m_renderState, m_vt\)/);
assert.match(terminalImeSnapshotBlock, /row != cursorRow/);
assert.doesNotMatch(
  terminalImeSnapshotBlock,
  /std::vector<std::string>|getScreenContent|getCursorPosition/,
  'the terminal IME snapshot must capture only the cursor row under one state lock'
);
assert.match(nativeBridge, /bool ShouldLetImeHandlePrintableKey\(/);
assert.match(nativeBridge, /bool IsTerminalLetterKey\(/);
assert.match(imePrintableGateBlock, /bool imePreviewActive/);
assert.match(imePrintableGateBlock, /if \(imePreviewActive\) \{\s*return true;\s*\}/s);
assert.match(
  imePrintableGateBlock,
  /return IsTerminalLetterKey\(code\);/,
  'without an active IME preview, digits and punctuation must stay on the terminal native key path'
);
assert.match(nativeBridge, /bool m_imePreviewActive = false;/);
assert.match(nativeBridge, /m_imePreviewActive = length > 0;/);
assert.match(nativeBridge, /m_imePreviewActive = false;/);
assert.match(
  nativeKeyBlock,
  /if \(m_wantsIme && ShouldLetImeHandlePrintableKey\(code, modifiers, m_imePreviewActive\)\) \{\s*return false;\s*\}/s,
  'letters start IME composition, while digits/punctuation stay available to terminal unless IME preview is active'
);

// Search UI is parked (2026-07-06): buggy overlay removed, native search API
// retained in TerminalController for a future reintroduction. Keep the surface
// free of the overlay so a half-revert cannot sneak back without the fixes.
assert.doesNotMatch(
  surface,
  /buildSearchOverlay|searchVisible|searchInputController|openSearch\(/,
  'search overlay stays removed from TerminalSurface until the feature is reworked'
);
