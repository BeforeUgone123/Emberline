# Harmony Advanced Terminal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the current FusionTerm scaffold into a buildable HarmonyOS terminal app that renders through `libghostty-ohos`, opens local PTY sessions when available, and connects to the Fusion Development Engine Linux VM through SSH remote PTY.

**Architecture:** Keep `libghostty-ohos` as the renderer HAR and keep app-specific session orchestration in the `entry` module. ArkTS owns UI, settings, profiles, and state; `libfusion_terminal_driver.so` owns byte-stream transports, PTY, SSH, resize, and native lifecycle.

**Tech Stack:** HarmonyOS Stage model, ArkTS, ArkUI, `libghostty-ohos` `TerminalSurface`, XComponent, N-API C++, POSIX PTY, libssh2, mbedTLS, Preferences, DevEco/hvigor/ohpm.

---

## Official Source Anchors

- HAR dependency and exported ArkUI component usage: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/har-package
- XComponent rendering surface contract: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-xcomponent
- ArkUI `@State` update model: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-state
- User preferences storage: https://developer.huawei.com/consumer/cn/doc/harmonyos-references-v5/js-apis-data-preferences-V5
- Network permission reference examples for modules requiring `ohos.permission.INTERNET`: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-request
- OpenHarmony N-API module registration and native bridge model: https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/napi/use-napi-process.md
- OpenHarmony thread-safe native-to-ArkTS callback guidance: https://gitee.com/openharmony/docs/blob/2ed58e733b0b6605277ba1fe49648011abcfc02c/zh-cn/application-dev/napi/use-napi-thread-safety.md

## File Structure Map

- `entry/src/main/ets/pages/Index.ets`: thin page that wires application state into the terminal workspace.
- `entry/src/main/ets/components/*.ets`: ArkUI components for toolbar, quick keys, connection sheet, settings sheet, and status banner.
- `entry/src/main/ets/models/*.ets`: serializable data models for profiles, sessions, quick keys, settings, and driver events.
- `entry/src/main/ets/services/*.ets`: Preferences-backed stores for profiles, trusted hosts, and app settings.
- `entry/src/main/ets/drivers/FusionTerminalDriver.ets`: typed ArkTS wrapper around `libfusion_terminal_driver.so`.
- `entry/src/main/cpp/terminal_driver.cpp`: N-API exports and native driver lifecycle.
- `entry/src/main/cpp/ssh/ssh_session.*`: SSH handshake, host key fingerprint, authentication, remote PTY, read loop, resize.
- `entry/src/main/cpp/pty/pty_handler.*`: local PTY start, resize, close.
- `tools/*.sh`: reproducible local checks, third-party fetch, and DevEco handoff helpers.
- `docs/build/*.md`: build, signing, device, and manual QA notes.

## Task 1: DevEco Build Handoff And Environment Checks

**Files:**
- Create: `tools/dev-env-check.sh`
- Create: `docs/build/dev-env.md`
- Modify: `README.md`

- [ ] **Step 1: Create a local environment checker**

Create `tools/dev-env-check.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

missing=0
for cmd in ohpm hvigor hdc git cmake ninja; do
  if command -v "$cmd" >/dev/null 2>&1; then
    printf '%s=%s\n' "$cmd" "$(command -v "$cmd")"
  else
    printf '%s=missing\n' "$cmd"
    missing=1
  fi
done

if [[ ! -d /home/user/libghostty-ohos/libghostty_ohos ]]; then
  echo 'renderer=missing /home/user/libghostty-ohos/libghostty_ohos'
  missing=1
else
  echo 'renderer=ok /home/user/libghostty-ohos/libghostty_ohos'
fi

if [[ ! -d third_party/libssh2 || ! -d third_party/mbedtls ]]; then
  echo 'third_party=missing, run: bash tools/fetch-third-party.sh'
  missing=1
else
  echo 'third_party=ok'
fi

exit "$missing"
```

- [ ] **Step 2: Document the build handoff**

Create `docs/build/dev-env.md`:

````markdown
# DevEco Build Environment

FusionTerm is developed as a HarmonyOS Stage application.

## Required Commands

- `ohpm`
- `hvigor` or project `hvigorw`
- `hdc`
- `git`
- `cmake`
- `ninja`

## First Build On A DevEco Machine

```sh
bash tools/fetch-third-party.sh
ohpm install --all
hvigorw --mode module -p product=default -p module=entry@default assembleHap --no-daemon
```

## Device Run Checklist

1. Add local signing material to root `build-profile.json5`.
2. Connect device or emulator and confirm `hdc list targets`.
3. Install the generated HAP.
4. Launch `com.preview.fusionterm/EntryAbility`.
5. Open the `VM` panel and connect to `bruce` or the Fusion VM address.

## Current Local Limitation

The Codex workspace intentionally has no local Harmony runtime tools installed.
Local checks cover file structure, shell syntax, JSON syntax, and source scans.
Full HAP compilation runs on a DevEco/Harmony SDK machine.
````

- [ ] **Step 3: Update README build section**

Replace the README build section with:

````markdown
## Build In DevEco Studio

Run the environment checker first:

```sh
bash tools/dev-env-check.sh
```

Then build on a DevEco/Harmony SDK machine:

```sh
bash tools/fetch-third-party.sh
ohpm install --all
hvigorw --mode module -p product=default -p module=entry@default assembleHap --no-daemon
```

Add signing material in root `build-profile.json5` before installing on a device.
````

- [ ] **Step 4: Verify and commit**

Run:

```sh
bash -n tools/dev-env-check.sh
bash tools/dev-env-check.sh || true
git diff -- README.md docs/build/dev-env.md tools/dev-env-check.sh
```

Expected: shell syntax succeeds; the checker reports missing Harmony tools in this machine; diff only touches the files listed above.

Commit:

```sh
git add README.md docs/build/dev-env.md tools/dev-env-check.sh
git commit -m "docs: add FusionTerm DevEco build handoff"
```

## Task 2: Typed Models For Profiles, Sessions, Settings, And Driver Events

**Files:**
- Modify: `entry/src/main/ets/models/ConnectionProfile.ets`
- Create: `entry/src/main/ets/models/TerminalSettings.ets`
- Create: `entry/src/main/ets/models/TerminalSession.ets`
- Create: `entry/src/main/ets/models/QuickKey.ets`
- Create: `entry/src/main/ets/models/DriverEvent.ets`

- [ ] **Step 1: Replace `ConnectionProfile.ets` with explicit profile and auth types**

```ts
export type AuthMode = 'password' | 'none';

export interface ConnectionProfile {
  id: string;
  title: string;
  host: string;
  port: number;
  user: string;
  authMode: AuthMode;
  trustedHostKeySha256: string;
}

export interface ConnectionSecret {
  profileId: string;
  password: string;
}

export interface ConnectRequest {
  profile: ConnectionProfile;
  secret: ConnectionSecret;
}

export function createProfileId(user: string, host: string, port: number): string {
  return `${user.trim()}@${host.trim()}:${port}`;
}

export function createFusionVmProfile(host: string, port: number, user: string): ConnectionProfile {
  const normalizedHost = host.trim().length > 0 ? host.trim() : 'bruce';
  const normalizedUser = user.trim().length > 0 ? user.trim() : 'user';
  const normalizedPort = port > 0 ? port : 22;
  return {
    id: createProfileId(normalizedUser, normalizedHost, normalizedPort),
    title: `${normalizedUser}@${normalizedHost}`,
    host: normalizedHost,
    port: normalizedPort,
    user: normalizedUser,
    authMode: 'password',
    trustedHostKeySha256: ''
  };
}
```

- [ ] **Step 2: Add terminal settings model**

Create `entry/src/main/ets/models/TerminalSettings.ets`:

```ts
export interface TerminalSettings {
  fontSize: number;
  themeName: string;
  scrollbackLines: number;
  cursorBlink: boolean;
}

export const DEFAULT_TERMINAL_SETTINGS: TerminalSettings = {
  fontSize: 15,
  themeName: 'Catppuccin_Mocha',
  scrollbackLines: 50000,
  cursorBlink: true
};

export function normalizeTerminalSettings(value: Partial<TerminalSettings>): TerminalSettings {
  return {
    fontSize: clampNumber(value.fontSize, 10, 28, DEFAULT_TERMINAL_SETTINGS.fontSize),
    themeName: value.themeName && value.themeName.length > 0 ? value.themeName : DEFAULT_TERMINAL_SETTINGS.themeName,
    scrollbackLines: clampNumber(value.scrollbackLines, 1000, 200000, DEFAULT_TERMINAL_SETTINGS.scrollbackLines),
    cursorBlink: value.cursorBlink ?? DEFAULT_TERMINAL_SETTINGS.cursorBlink
  };
}

function clampNumber(value: number | undefined, min: number, max: number, fallback: number): number {
  if (value === undefined || !Number.isFinite(value)) {
    return fallback;
  }
  return Math.max(min, Math.min(max, Math.floor(value)));
}
```

- [ ] **Step 3: Add terminal session model**

Create `entry/src/main/ets/models/TerminalSession.ets`:

```ts
import { ConnectionProfile } from './ConnectionProfile';

export type SessionKind = 'local' | 'ssh';
export type SessionStatus = 'idle' | 'connecting' | 'connected' | 'failed' | 'stopped';

export interface TerminalSession {
  id: string;
  title: string;
  kind: SessionKind;
  status: SessionStatus;
  profile?: ConnectionProfile;
  message: string;
}

export function createLocalSession(): TerminalSession {
  return {
    id: `local-${Date.now()}`,
    title: 'Local PTY',
    kind: 'local',
    status: 'idle',
    message: ''
  };
}

export function createSshSession(profile: ConnectionProfile): TerminalSession {
  return {
    id: `ssh-${profile.id}-${Date.now()}`,
    title: profile.title,
    kind: 'ssh',
    status: 'idle',
    profile,
    message: ''
  };
}
```

- [ ] **Step 4: Add quick-key model**

Create `entry/src/main/ets/models/QuickKey.ets`:

```ts
export interface QuickKey {
  label: string;
  sequence: string;
}

export const DEFAULT_QUICK_KEYS: QuickKey[] = [
  { label: 'Esc', sequence: '\u001b' },
  { label: 'Tab', sequence: '\t' },
  { label: 'Ctrl-C', sequence: '\u0003' },
  { label: 'Ctrl-D', sequence: '\u0004' },
  { label: 'Up', sequence: '\u001b[A' },
  { label: 'Down', sequence: '\u001b[B' },
  { label: 'PgUp', sequence: '\u001b[5~' },
  { label: 'PgDn', sequence: '\u001b[6~' }
];
```

- [ ] **Step 5: Add native driver event model**

Create `entry/src/main/ets/models/DriverEvent.ets`:

```ts
export type DriverEventType =
  'local-started' |
  'ssh-host-key' |
  'ssh-connected' |
  'session-ended' |
  'error';

export interface DriverEvent {
  type: DriverEventType;
  message: string;
  hostKeySha256: string;
}

export function parseDriverEvent(payload: string): DriverEvent {
  try {
    const parsed = JSON.parse(payload) as Partial<DriverEvent>;
    return {
      type: normalizeType(parsed.type),
      message: parsed.message ?? '',
      hostKeySha256: parsed.hostKeySha256 ?? ''
    };
  } catch (_err) {
    return {
      type: 'error',
      message: payload,
      hostKeySha256: ''
    };
  }
}

function normalizeType(value: string | undefined): DriverEventType {
  switch (value) {
    case 'local-started':
    case 'ssh-host-key':
    case 'ssh-connected':
    case 'session-ended':
    case 'error':
      return value;
    default:
      return 'error';
  }
}
```

- [ ] **Step 6: Verify and commit**

Run:

```sh
rg -n "draftPassword|password:" entry/src/main/ets
rg -n "ConnectionProfile|TerminalSettings|TerminalSession|QuickKey|DriverEvent" entry/src/main/ets
```

Expected: password remains only in transient `ConnectionSecret` or connection UI state; model imports resolve by exact file names.

Commit:

```sh
git add entry/src/main/ets/models
git commit -m "feat: add typed terminal app models"
```

## Task 3: Preferences Stores For Profiles, Trusted Hosts, And Settings

**Files:**
- Create: `entry/src/main/ets/services/ProfileStore.ets`
- Create: `entry/src/main/ets/services/SettingsStore.ets`
- Create: `entry/src/main/ets/services/TrustedHostStore.ets`

- [ ] **Step 1: Create profile store without password persistence**

Create `entry/src/main/ets/services/ProfileStore.ets`:

```ts
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ConnectionProfile } from '../models/ConnectionProfile';

const STORE_NAME = 'fusionterm_profiles';
const PROFILES_KEY = 'profiles_json';

export class ProfileStore {
  async list(context: common.UIAbilityContext): Promise<ConnectionProfile[]> {
    const store = await preferences.getPreferences(context, STORE_NAME);
    const raw = await store.get(PROFILES_KEY, '[]') as string;
    return parseProfiles(raw);
  }

  async save(context: common.UIAbilityContext, profile: ConnectionProfile): Promise<void> {
    const profiles = await this.list(context);
    const filtered = profiles.filter((item) => item.id !== profile.id);
    filtered.push(profile);
    const store = await preferences.getPreferences(context, STORE_NAME);
    await store.put(PROFILES_KEY, JSON.stringify(filtered));
    await store.flush();
  }

  async remove(context: common.UIAbilityContext, profileId: string): Promise<void> {
    const profiles = await this.list(context);
    const store = await preferences.getPreferences(context, STORE_NAME);
    await store.put(PROFILES_KEY, JSON.stringify(profiles.filter((item) => item.id !== profileId)));
    await store.flush();
  }
}

function parseProfiles(raw: string): ConnectionProfile[] {
  try {
    const parsed = JSON.parse(raw) as ConnectionProfile[];
    if (!Array.isArray(parsed)) {
      return [];
    }
    return parsed.filter((item) => typeof item.id === 'string' && typeof item.host === 'string');
  } catch (_err) {
    return [];
  }
}
```

- [ ] **Step 2: Create settings store**

Create `entry/src/main/ets/services/SettingsStore.ets`:

```ts
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import {
  DEFAULT_TERMINAL_SETTINGS,
  normalizeTerminalSettings,
  TerminalSettings
} from '../models/TerminalSettings';

const STORE_NAME = 'fusionterm_settings';
const SETTINGS_KEY = 'terminal_settings_json';

export class SettingsStore {
  async load(context: common.UIAbilityContext): Promise<TerminalSettings> {
    const store = await preferences.getPreferences(context, STORE_NAME);
    const raw = await store.get(SETTINGS_KEY, JSON.stringify(DEFAULT_TERMINAL_SETTINGS)) as string;
    try {
      return normalizeTerminalSettings(JSON.parse(raw) as Partial<TerminalSettings>);
    } catch (_err) {
      return DEFAULT_TERMINAL_SETTINGS;
    }
  }

  async save(context: common.UIAbilityContext, settings: TerminalSettings): Promise<void> {
    const normalized = normalizeTerminalSettings(settings);
    const store = await preferences.getPreferences(context, STORE_NAME);
    await store.put(SETTINGS_KEY, JSON.stringify(normalized));
    await store.flush();
  }
}
```

- [ ] **Step 3: Create trusted host store**

Create `entry/src/main/ets/services/TrustedHostStore.ets`:

```ts
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const STORE_NAME = 'fusionterm_trusted_hosts';
const TRUSTED_KEY = 'trusted_hosts_json';

export interface TrustedHostRecord {
  profileId: string;
  host: string;
  port: number;
  fingerprintSha256: string;
  acceptedAt: number;
}

export class TrustedHostStore {
  async get(context: common.UIAbilityContext, profileId: string): Promise<TrustedHostRecord | null> {
    const records = await this.list(context);
    return records.find((item) => item.profileId === profileId) ?? null;
  }

  async list(context: common.UIAbilityContext): Promise<TrustedHostRecord[]> {
    const store = await preferences.getPreferences(context, STORE_NAME);
    const raw = await store.get(TRUSTED_KEY, '[]') as string;
    try {
      const parsed = JSON.parse(raw) as TrustedHostRecord[];
      return Array.isArray(parsed) ? parsed.filter((item) => item.profileId.length > 0) : [];
    } catch (_err) {
      return [];
    }
  }

  async trust(context: common.UIAbilityContext, record: TrustedHostRecord): Promise<void> {
    const records = (await this.list(context)).filter((item) => item.profileId !== record.profileId);
    records.push(record);
    const store = await preferences.getPreferences(context, STORE_NAME);
    await store.put(TRUSTED_KEY, JSON.stringify(records));
    await store.flush();
  }
}
```

- [ ] **Step 4: Verify and commit**

Run:

```sh
rg -n "preferences.getPreferences|password|trusted_hosts|terminal_settings" entry/src/main/ets/services entry/src/main/ets/models
```

Expected: no store persists a password; settings and trusted host records serialize as JSON strings.

Commit:

```sh
git add entry/src/main/ets/services entry/src/main/ets/models
git commit -m "feat: persist terminal profiles and settings"
```

## Task 4: Native SSH Host-Key Fingerprint And Driver Events

**Files:**
- Modify: `entry/src/main/cpp/ssh/ssh_session.h`
- Modify: `entry/src/main/cpp/ssh/ssh_session.cpp`
- Modify: `entry/src/main/cpp/terminal_driver.cpp`
- Modify: `entry/src/main/ets/native-modules.d.ts`
- Modify: `entry/src/main/ets/drivers/FusionTerminalDriver.ets`

- [ ] **Step 1: Extend SSH session with fingerprint reporting**

Add to `SSHSession` public API in `ssh_session.h`:

```cpp
const std::string& hostKeySha256() const { return m_hostKeySha256; }
```

Add to private members:

```cpp
std::string m_hostKeySha256;
```

Add helper declarations in `ssh_session.cpp`:

```cpp
#include <mbedtls/sha256.h>

std::string HexEncode(const unsigned char* data, size_t length)
{
    static constexpr char kHex[] = "0123456789abcdef";
    std::string result;
    result.reserve(length * 2);
    for (size_t i = 0; i < length; ++i) {
        result.push_back(kHex[(data[i] >> 4) & 0x0f]);
        result.push_back(kHex[data[i] & 0x0f]);
    }
    return result;
}
```

After `libssh2_session_handshake` succeeds and before password auth, add:

```cpp
size_t hostKeyLength = 0;
int hostKeyType = 0;
const char* hostKey = libssh2_session_hostkey(m_session, &hostKeyLength, &hostKeyType);
if (hostKey != nullptr && hostKeyLength > 0) {
    unsigned char digest[32] = {0};
    mbedtls_sha256(reinterpret_cast<const unsigned char*>(hostKey), hostKeyLength, digest, 0);
    m_hostKeySha256 = HexEncode(digest, sizeof(digest));
}
```

- [ ] **Step 2: Add native event callback to the N-API driver**

Add event callback fields to `FusionTerminalDriver` in `terminal_driver.cpp`:

```cpp
std::mutex m_eventMutex;
std::string m_eventBuffer;
napi_threadsafe_function m_eventTsfn = nullptr;
```

Add event emitter:

```cpp
void EmitEvent(const std::string& type, const std::string& message, const std::string& hostKeySha256)
{
    const std::string payload =
        "{\"type\":\"" + type + "\",\"message\":\"" + message +
        "\",\"hostKeySha256\":\"" + hostKeySha256 + "\"}";
    napi_threadsafe_function tsfn = nullptr;
    {
        std::lock_guard<std::mutex> lock(m_eventMutex);
        if (m_eventTsfn == nullptr) {
            m_eventBuffer += payload;
            m_eventBuffer += "\n";
            return;
        }
        tsfn = m_eventTsfn;
    }
    auto* output = new std::string(payload);
    const napi_status status = napi_call_threadsafe_function(tsfn, output, napi_tsfn_nonblocking);
    if (status != napi_ok) {
        delete output;
    }
}
```

Call it after successful local start:

```cpp
EmitEvent("local-started", "Local PTY ready", "");
```

Call it after successful SSH connect:

```cpp
EmitEvent("ssh-connected", "SSH connected", m_sshSession->hostKeySha256());
```

Call it for failures:

```cpp
EmitEvent("error", error, "");
```

- [ ] **Step 3: Export event callback to ArkTS**

In `native-modules.d.ts`, add:

```ts
setEventCallback(callback: ((data: string) => void) | null): void;
```

In `terminal_driver.cpp`, add a `SetEventCallback` function following the same shape as `SetOutputCallback`, but using `m_eventTsfn`, `m_eventMutex`, and `m_eventBuffer`. Register it:

```cpp
SetNamedFunction(env, exports, "setEventCallback", SetEventCallback);
```

- [ ] **Step 4: Consume driver events in ArkTS**

In `FusionTerminalDriver.ets`, import and parse events:

```ts
import { parseDriverEvent } from '../models/DriverEvent';
```

Add event listener field:

```ts
private readonly eventListener = (payload: string): void => {
  const event = parseDriverEvent(payload);
  if (event.type === 'error') {
    this.emitStatus(false, this.mode, 'Error', event.message);
    return;
  }
  if (event.type === 'ssh-connected') {
    this.emitStatus(true, 'ssh', this.pendingProfile?.title ?? 'SSH', '');
    return;
  }
  if (event.type === 'local-started') {
    this.emitStatus(true, 'local', 'Local PTY', '');
  }
};
```

Set and clear the callback:

```ts
nativeDriver.setEventCallback(this.eventListener);
```

```ts
nativeDriver.setEventCallback(null);
```

- [ ] **Step 5: Verify and commit**

Run on a DevEco/Harmony SDK machine:

```sh
ohpm install --all
hvigorw --mode module -p product=default -p module=entry@default assembleHap --no-daemon
```

Expected: N-API module compiles; import `libfusion_terminal_driver.so` resolves; no missing `setEventCallback` symbol.

Commit:

```sh
git add entry/src/main/cpp entry/src/main/ets
git commit -m "feat: emit native terminal driver events"
```

## Task 5: Host-Key Trust Flow For Fusion VM SSH

**Files:**
- Modify: `entry/src/main/ets/drivers/FusionTerminalDriver.ets`
- Modify: `entry/src/main/ets/pages/Index.ets`
- Create: `entry/src/main/ets/components/HostKeyDialog.ets`
- Modify: `entry/src/main/ets/services/TrustedHostStore.ets`

- [ ] **Step 1: Add host-key dialog component**

Create `entry/src/main/ets/components/HostKeyDialog.ets`:

```ts
@Component
export struct HostKeyDialog {
  host: string = '';
  fingerprintSha256: string = '';
  onAccept: () => void = () => {};
  onReject: () => void = () => {};

  build() {
    Column({ space: 12 }) {
      Text('Trust SSH Host')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#F4F7FB')
      Text(this.host)
        .fontSize(14)
        .fontColor('#CED8EA')
        .maxLines(1)
      Text(this.fingerprintSha256)
        .fontSize(12)
        .fontColor('#9AA7BD')
        .fontFamily('monospace')
        .copyOption(CopyOptions.InApp)
      Row({ space: 10 }) {
        Button('Reject')
          .height(36)
          .fontSize(13)
          .backgroundColor('#252D38')
          .fontColor('#DCE6F6')
          .borderRadius(6)
          .layoutWeight(1)
          .onClick(() => this.onReject())
        Button('Trust')
          .height(36)
          .fontSize(13)
          .backgroundColor('#1E6FFF')
          .fontColor('#FFFFFF')
          .borderRadius(6)
          .layoutWeight(1)
          .onClick(() => this.onAccept())
      }
      .width('100%')
    }
    .width(360)
    .padding(16)
    .backgroundColor('#11161D')
    .borderRadius(8)
    .border({ width: 1, color: '#2B3545' })
  }
}
```

- [ ] **Step 2: Add pending host-key state to `Index.ets`**

Add imports:

```ts
import { HostKeyDialog } from '../components/HostKeyDialog';
import { TrustedHostStore } from '../services/TrustedHostStore';
```

Add fields:

```ts
private trustedHostStore: TrustedHostStore = new TrustedHostStore();
@State private pendingHostKey: string = '';
@State private pendingHostLabel: string = '';
@State private hostKeyDialogOpen: boolean = false;
```

Render the dialog in the page `Stack`:

```ts
if (this.hostKeyDialogOpen) {
  HostKeyDialog({
    host: this.pendingHostLabel,
    fingerprintSha256: this.pendingHostKey,
    onAccept: () => this.acceptHostKey(),
    onReject: () => this.rejectHostKey()
  })
}
```

- [ ] **Step 3: Persist host-key acceptance**

Add methods to `Index.ets`:

```ts
private async acceptHostKey(): Promise<void> {
  if (!this.context || this.pendingHostLabel.length === 0 || this.pendingHostKey.length === 0) {
    this.hostKeyDialogOpen = false;
    return;
  }
  await this.trustedHostStore.trust(this.context, {
    profileId: this.pendingHostLabel,
    host: this.pendingHostLabel,
    port: 22,
    fingerprintSha256: this.pendingHostKey,
    acceptedAt: Date.now()
  });
  this.hostKeyDialogOpen = false;
}

private rejectHostKey(): void {
  this.hostKeyDialogOpen = false;
  this.driver.stop();
}
```

- [ ] **Step 4: Verify and commit**

Run:

```sh
rg -n "HostKeyDialog|TrustedHostStore|fingerprintSha256|hostKeyDialogOpen" entry/src/main/ets
```

Expected: host-key UI is reachable from `Index.ets`; trusted host records use SHA-256 fingerprint strings.

Commit:

```sh
git add entry/src/main/ets
git commit -m "feat: add SSH host key trust UI"
```

## Task 6: Decompose The ArkUI Workspace

**Files:**
- Create: `entry/src/main/ets/components/TopBar.ets`
- Create: `entry/src/main/ets/components/QuickKeyBar.ets`
- Create: `entry/src/main/ets/components/ConnectionSheet.ets`
- Create: `entry/src/main/ets/components/TerminalSettingsSheet.ets`
- Modify: `entry/src/main/ets/pages/Index.ets`

- [ ] **Step 1: Extract top bar**

Create `entry/src/main/ets/components/TopBar.ets`:

```ts
@Component
export struct TopBar {
  connected: boolean = false;
  statusMode: string = 'local';
  statusLabel: string = 'Idle';
  themeName: string = 'Catppuccin_Mocha';
  onOpenVm: () => void = () => {};
  onLocal: () => void = () => {};
  onSettings: () => void = () => {};

  build() {
    Row({ space: 10 }) {
      Text(this.connected ? '*' : 'o')
        .fontSize(18)
        .fontColor(this.connected ? '#30D158' : '#8B95A7')
        .width(22)
        .textAlign(TextAlign.Center)
      Column() {
        Text('FusionTerm')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#F4F7FB')
          .maxLines(1)
        Text(`${this.statusMode.toUpperCase()}  ${this.statusLabel}`)
          .fontSize(11)
          .fontColor('#9AA7BD')
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Button('VM').height(34).fontSize(13).backgroundColor('#1E6FFF').fontColor('#FFFFFF').borderRadius(6).onClick(() => this.onOpenVm())
      Button('Local').height(34).fontSize(13).backgroundColor('#232A33').fontColor('#DCE6F6').borderRadius(6).onClick(() => this.onLocal())
      Button('Settings').height(34).fontSize(13).backgroundColor('#232A33').fontColor('#DCE6F6').borderRadius(6).onClick(() => this.onSettings())
    }
    .height(52)
    .width('100%')
    .padding({ left: 12, right: 12 })
    .backgroundColor('#11161D')
    .border({ width: { bottom: 1 }, color: '#202936' })
  }
}
```

- [ ] **Step 2: Extract quick-key bar**

Create `entry/src/main/ets/components/QuickKeyBar.ets`:

```ts
import { QuickKey } from '../models/QuickKey';

@Component
export struct QuickKeyBar {
  keys: QuickKey[] = [];
  onSend: (sequence: string) => void = () => {};

  build() {
    Row({ space: 8 }) {
      ForEach(this.keys, (key: QuickKey) => {
        Button(key.label)
          .height(34)
          .fontSize(12)
          .fontColor('#CED8EA')
          .backgroundColor('#171D25')
          .borderRadius(6)
          .onClick(() => this.onSend(key.sequence))
      }, (key: QuickKey) => key.label)
    }
    .height(50)
    .width('100%')
    .padding({ left: 10, right: 10 })
    .backgroundColor('#11161D')
    .border({ width: { top: 1 }, color: '#202936' })
  }
}
```

- [ ] **Step 3: Extract connection sheet**

Create `entry/src/main/ets/components/ConnectionSheet.ets`:

```ts
@Component
export struct ConnectionSheet {
  host: string = 'bruce';
  port: string = '22';
  user: string = 'user';
  password: string = '';
  onHostChange: (value: string) => void = () => {};
  onPortChange: (value: string) => void = () => {};
  onUserChange: (value: string) => void = () => {};
  onPasswordChange: (value: string) => void = () => {};
  onClose: () => void = () => {};
  onConnect: () => void = () => {};

  build() {
    Column({ space: 12 }) {
      Row() {
        Text('Fusion VM').fontSize(18).fontWeight(FontWeight.Medium).fontColor('#F4F7FB').layoutWeight(1)
        Button('Close').height(32).fontSize(12).backgroundColor('#252D38').fontColor('#DCE6F6').borderRadius(6).onClick(() => this.onClose())
      }
      .width('100%')
      TextInput({ text: this.host, placeholder: 'host' }).height(42).fontSize(15).fontColor('#F4F7FB').backgroundColor('#171D25').borderRadius(6).onChange((value: string) => this.onHostChange(value))
      Row({ space: 10 }) {
        TextInput({ text: this.port, placeholder: 'port' }).height(42).fontSize(15).fontColor('#F4F7FB').backgroundColor('#171D25').borderRadius(6).layoutWeight(1).onChange((value: string) => this.onPortChange(value))
        TextInput({ text: this.user, placeholder: 'user' }).height(42).fontSize(15).fontColor('#F4F7FB').backgroundColor('#171D25').borderRadius(6).layoutWeight(2).onChange((value: string) => this.onUserChange(value))
      }
      .width('100%')
      TextInput({ text: this.password, placeholder: 'password' }).height(42).fontSize(15).fontColor('#F4F7FB').backgroundColor('#171D25').borderRadius(6).type(InputType.Password).onChange((value: string) => this.onPasswordChange(value))
      Button('Connect').height(42).width('100%').fontSize(15).fontColor('#FFFFFF').backgroundColor('#1E6FFF').borderRadius(6).onClick(() => this.onConnect())
    }
    .width(360)
    .padding(16)
    .backgroundColor('#11161D')
    .borderRadius(8)
    .border({ width: 1, color: '#2B3545' })
    .shadow({ radius: 24, color: '#99000000', offsetX: 0, offsetY: 10 })
  }
}
```

- [ ] **Step 4: Extract settings sheet**

Create `entry/src/main/ets/components/TerminalSettingsSheet.ets`:

```ts
@Component
export struct TerminalSettingsSheet {
  fontSize: number = 15;
  themeName: string = 'Catppuccin_Mocha';
  onFontSizeChange: (value: number) => void = () => {};
  onThemeChange: (value: string) => void = () => {};
  onClose: () => void = () => {};

  build() {
    Column({ space: 12 }) {
      Row() {
        Text('Settings').fontSize(18).fontWeight(FontWeight.Medium).fontColor('#F4F7FB').layoutWeight(1)
        Button('Close').height(32).fontSize(12).backgroundColor('#252D38').fontColor('#DCE6F6').borderRadius(6).onClick(() => this.onClose())
      }
      Text(`Font ${this.fontSize}`).fontSize(13).fontColor('#CED8EA').width('100%')
      Slider({ value: this.fontSize, min: 10, max: 28, step: 1 }).width('100%').onChange((value: number) => this.onFontSizeChange(value))
      Row({ space: 8 }) {
        Button('Mocha').height(34).fontSize(13).backgroundColor(this.themeName === 'Catppuccin_Mocha' ? '#1E6FFF' : '#232A33').fontColor('#FFFFFF').borderRadius(6).layoutWeight(1).onClick(() => this.onThemeChange('Catppuccin_Mocha'))
        Button('Aizen').height(34).fontSize(13).backgroundColor(this.themeName === 'Aizen_Dark' ? '#1E6FFF' : '#232A33').fontColor('#FFFFFF').borderRadius(6).layoutWeight(1).onClick(() => this.onThemeChange('Aizen_Dark'))
      }
    }
    .width(360)
    .padding(16)
    .backgroundColor('#11161D')
    .borderRadius(8)
    .border({ width: 1, color: '#2B3545' })
  }
}
```

- [ ] **Step 5: Reduce `Index.ets` to composition**

Replace top-bar, quick-bar, connection panel, and settings markup with component calls:

```ts
TopBar({
  connected: this.connected,
  statusMode: this.statusMode,
  statusLabel: this.statusLabel,
  themeName: this.settings.themeName,
  onOpenVm: () => { this.connectPanelOpen = true; },
  onLocal: () => { this.driver.startLocal(); },
  onSettings: () => { this.settingsPanelOpen = true; }
})
```

```ts
QuickKeyBar({
  keys: DEFAULT_QUICK_KEYS,
  onSend: (sequence: string) => { this.controller.write(sequence); }
})
```

```ts
ConnectionSheet({
  host: this.draftHost,
  port: this.draftPort,
  user: this.draftUser,
  password: this.draftPassword,
  onHostChange: (value: string) => { this.draftHost = value; },
  onPortChange: (value: string) => { this.draftPort = value; },
  onUserChange: (value: string) => { this.draftUser = value; },
  onPasswordChange: (value: string) => { this.draftPassword = value; },
  onClose: () => { this.connectPanelOpen = false; },
  onConnect: () => { this.connectFusionVm(); }
})
```

- [ ] **Step 6: Verify and commit**

Run:

```sh
rg -n "buildTopBar|buildQuickBar|buildConnectPanel|sendQuickKey|TopBar|QuickKeyBar|ConnectionSheet" entry/src/main/ets
```

Expected: `Index.ets` no longer contains the old builder methods; component imports are exact.

Commit:

```sh
git add entry/src/main/ets
git commit -m "refactor: split terminal workspace components"
```

## Task 7: Settings Persistence And Runtime Application

**Files:**
- Modify: `entry/src/main/ets/pages/Index.ets`
- Modify: `entry/src/main/ets/services/SettingsStore.ets`
- Modify: `entry/src/main/ets/models/TerminalSettings.ets`

- [ ] **Step 1: Load settings on page appear**

Add fields in `Index.ets`:

```ts
private settingsStore: SettingsStore = new SettingsStore();
@State private settings: TerminalSettings = DEFAULT_TERMINAL_SETTINGS;
@State private settingsPanelOpen: boolean = false;
```

Add imports:

```ts
import { SettingsStore } from '../services/SettingsStore';
import { DEFAULT_TERMINAL_SETTINGS, TerminalSettings } from '../models/TerminalSettings';
```

Add method:

```ts
private async loadSettings(): Promise<void> {
  if (!this.context) {
    return;
  }
  this.settings = await this.settingsStore.load(this.context);
  this.applySettings();
}
```

Call it from `aboutToAppear` after `context` is set:

```ts
void this.loadSettings();
```

- [ ] **Step 2: Apply settings to `TerminalController`**

Add method:

```ts
private applySettings(): void {
  this.controller.updateConfig({
    fontSize: this.settings.fontSize,
    scrollbackLines: this.settings.scrollbackLines,
    cursorBlink: this.settings.cursorBlink
  });
  this.controller.setTheme(this.settings.themeName);
}
```

- [ ] **Step 3: Persist settings changes**

Add method:

```ts
private async updateSettings(patch: Partial<TerminalSettings>): Promise<void> {
  if (!this.context) {
    return;
  }
  this.settings = {
    fontSize: patch.fontSize ?? this.settings.fontSize,
    themeName: patch.themeName ?? this.settings.themeName,
    scrollbackLines: patch.scrollbackLines ?? this.settings.scrollbackLines,
    cursorBlink: patch.cursorBlink ?? this.settings.cursorBlink
  };
  this.applySettings();
  await this.settingsStore.save(this.context, this.settings);
}
```

- [ ] **Step 4: Verify and commit**

Run:

```sh
rg -n "loadSettings|applySettings|updateSettings|SettingsStore|TerminalSettingsSheet" entry/src/main/ets
```

Expected: settings load once, settings changes apply to controller, and writes use `SettingsStore`.

Commit:

```sh
git add entry/src/main/ets
git commit -m "feat: persist terminal settings"
```

## Task 8: Session Lifecycle And Multiple Terminal Tabs

**Files:**
- Create: `entry/src/main/ets/services/SessionManager.ets`
- Create: `entry/src/main/ets/components/SessionTabs.ets`
- Modify: `entry/src/main/ets/pages/Index.ets`
- Modify: `entry/src/main/ets/drivers/FusionTerminalDriver.ets`

- [ ] **Step 1: Create session manager**

Create `entry/src/main/ets/services/SessionManager.ets`:

```ts
import { TerminalController } from 'libghostty-ohos';
import { ConnectionProfile } from '../models/ConnectionProfile';
import { createLocalSession, createSshSession, TerminalSession } from '../models/TerminalSession';

export interface ManagedSession {
  session: TerminalSession;
  controller: TerminalController;
}

export class SessionManager {
  private sessions: ManagedSession[] = [];
  private activeId: string = '';

  createLocal(): ManagedSession {
    const managed = { session: createLocalSession(), controller: new TerminalController() };
    this.sessions.push(managed);
    this.activeId = managed.session.id;
    return managed;
  }

  createSsh(profile: ConnectionProfile): ManagedSession {
    const managed = { session: createSshSession(profile), controller: new TerminalController() };
    this.sessions.push(managed);
    this.activeId = managed.session.id;
    return managed;
  }

  list(): ManagedSession[] {
    return this.sessions.slice();
  }

  active(): ManagedSession | null {
    return this.sessions.find((item) => item.session.id === this.activeId) ?? null;
  }

  activate(id: string): ManagedSession | null {
    const found = this.sessions.find((item) => item.session.id === id) ?? null;
    if (found) {
      this.activeId = id;
    }
    return found;
  }

  close(id: string): ManagedSession[] {
    this.sessions = this.sessions.filter((item) => item.session.id !== id);
    if (this.activeId === id) {
      this.activeId = this.sessions.length > 0 ? this.sessions[0].session.id : '';
    }
    return this.list();
  }
}
```

- [ ] **Step 2: Create tabs component**

Create `entry/src/main/ets/components/SessionTabs.ets`:

```ts
import { ManagedSession } from '../services/SessionManager';

@Component
export struct SessionTabs {
  sessions: ManagedSession[] = [];
  activeId: string = '';
  onActivate: (id: string) => void = () => {};
  onClose: (id: string) => void = () => {};

  build() {
    Row({ space: 6 }) {
      ForEach(this.sessions, (item: ManagedSession) => {
        Row({ space: 6 }) {
          Text(item.session.title)
            .fontSize(12)
            .fontColor(item.session.id === this.activeId ? '#FFFFFF' : '#B5C0D4')
            .maxLines(1)
            .layoutWeight(1)
          Button('x')
            .width(28)
            .height(28)
            .fontSize(11)
            .backgroundColor('#252D38')
            .fontColor('#DCE6F6')
            .borderRadius(6)
            .onClick(() => this.onClose(item.session.id))
        }
        .height(34)
        .width(160)
        .padding({ left: 8, right: 4 })
        .backgroundColor(item.session.id === this.activeId ? '#1E6FFF' : '#171D25')
        .borderRadius(6)
        .onClick(() => this.onActivate(item.session.id))
      }, (item: ManagedSession) => item.session.id)
    }
    .height(44)
    .width('100%')
    .padding({ left: 10, right: 10 })
    .backgroundColor('#0F141B')
  }
}
```

- [ ] **Step 3: Wire active session into `TerminalSurface`**

In `Index.ets`, create and use a `SessionManager`. The active `TerminalSurface` receives the active session controller:

```ts
private sessionManager: SessionManager = new SessionManager();
@State private sessions: ManagedSession[] = [];
@State private activeSessionId: string = '';
```

```ts
private refreshSessions(): void {
  this.sessions = this.sessionManager.list();
  this.activeSessionId = this.sessionManager.active()?.session.id ?? '';
}
```

```ts
const active = this.sessionManager.active();
if (active) {
  TerminalSurface({
    controller: active.controller,
    surfaceId: `fusionTermSurface-${active.session.id}`,
    surfaceColor: '#0B0D10'
  })
}
```

- [ ] **Step 4: Verify and commit**

Run:

```sh
rg -n "SessionManager|SessionTabs|activeSessionId|fusionTermSurface-" entry/src/main/ets
```

Expected: there is one controller per session and every mounted surface has a unique ID.

Commit:

```sh
git add entry/src/main/ets
git commit -m "feat: add terminal session tabs"
```

## Task 9: Native Driver Lifecycle Hardening

**Files:**
- Modify: `entry/src/main/cpp/terminal_driver.cpp`
- Modify: `entry/src/main/cpp/ssh/ssh_session.cpp`
- Modify: `entry/src/main/cpp/ssh/ssh_session.h`
- Modify: `entry/src/main/cpp/pty/pty_handler.cpp`

- [ ] **Step 1: Register N-API environment cleanup**

In `terminal_driver.cpp`, register cleanup in `Init`:

```cpp
napi_add_env_cleanup_hook(env, [](void*) {
    GetDriver().ClearOutputCallback();
    GetDriver().ClearEventCallback();
    GetDriver().Stop();
}, nullptr);
```

Add `ClearEventCallback()` using the same release pattern as `ClearOutputCallback()`.

- [ ] **Step 2: Avoid joining a blocked local PTY reader**

Before joining `m_localReadThread`, close `m_masterFd` under lock:

```cpp
int masterFdToClose = -1;
{
    std::lock_guard<std::mutex> lock(m_mutex);
    masterFdToClose = m_masterFd;
    m_masterFd = -1;
    m_running = false;
}
if (masterFdToClose >= 0) {
    ::close(masterFdToClose);
}
if (m_localReadThread.joinable()) {
    m_localReadThread.join();
}
```

- [ ] **Step 3: Add SSH socket timeout and clear disconnect state**

In `ssh_session.cpp`, after socket creation and before connect, set timeouts:

```cpp
struct timeval timeout;
timeout.tv_sec = 10;
timeout.tv_usec = 0;
setsockopt(m_socketFd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
setsockopt(m_socketFd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
```

In `disconnect()`, clear fingerprint:

```cpp
m_hostKeySha256.clear();
```

- [ ] **Step 4: Verify and commit**

Run on a DevEco/Harmony SDK machine:

```sh
hvigorw --mode module -p product=default -p module=entry@default assembleHap --no-daemon
```

Expected: native driver compiles; shutdown does not hang when launching and closing the app repeatedly.

Commit:

```sh
git add entry/src/main/cpp
git commit -m "fix: harden native terminal driver lifecycle"
```

## Task 10: Truecolor, Theme, And Terminal Capability Verification

**Files:**
- Create: `tools/terminal-smoke.sh`
- Create: `docs/build/manual-qa.md`
- Modify: `entry/src/main/cpp/ssh/ssh_session.cpp`
- Modify: `entry/src/main/cpp/pty/pty_handler.cpp`

- [ ] **Step 1: Add terminal smoke script for remote VM**

Create `tools/terminal-smoke.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

printf 'TERM=%s\n' "${TERM:-unset}"
printf 'COLORTERM=%s\n' "${COLORTERM:-unset}"
printf 'truecolor gradient:\n'
for i in $(seq 0 23); do
  r=$((i * 10))
  g=$((255 - i * 8))
  b=$((80 + i * 5))
  printf '\033[48;2;%d;%d;%dm  \033[0m' "$r" "$g" "$b"
done
printf '\n256-color row:\n'
for i in $(seq 16 51); do
  printf '\033[48;5;%dm%03d\033[0m ' "$i" "$i"
done
printf '\n'
```

- [ ] **Step 2: Keep environment values explicit**

Confirm both native paths set:

```cpp
setenv("TERM", usePipes ? "dumb" : "xterm-256color", 1);
setenv("COLORTERM", "truecolor", 1);
```

and:

```cpp
SetRemoteEnv(m_channel, "TERM", "xterm-256color");
SetRemoteEnv(m_channel, "COLORTERM", "truecolor");
```

- [ ] **Step 3: Add manual QA document**

Create `docs/build/manual-qa.md`:

````markdown
# FusionTerm Manual QA

## Local PTY

1. Launch app.
2. Select `Local`.
3. Type `echo $TERM $COLORTERM`.
4. Confirm output contains `xterm-256color` and `truecolor` when local PTY is available.

## Fusion VM SSH

1. Select `VM`.
2. Enter host `bruce`, port `22`, user, and password.
3. Accept the displayed SHA-256 host key after comparing with the VM.
4. Run `bash tools/terminal-smoke.sh` on the VM.
5. Confirm gradient blocks render as smooth truecolor bands.

## Resize

1. Resize the app window.
2. Run `stty size`.
3. Confirm rows and columns update after resize.

## Keyboard

1. Use hardware keys: arrows, Ctrl-C, Ctrl-D, Tab, Esc.
2. Use quick-key bar buttons.
3. Confirm shell behavior matches the same sequences in a desktop terminal.
````

- [ ] **Step 4: Verify and commit**

Run:

```sh
bash -n tools/terminal-smoke.sh
rg -n "COLORTERM|xterm-256color|terminal-smoke|Manual QA" entry/src/main/cpp tools docs
```

Expected: both native paths preserve truecolor env; smoke script syntax succeeds.

Commit:

```sh
git add entry/src/main/cpp tools docs/build/manual-qa.md
git commit -m "test: add terminal truecolor smoke checks"
```

## Task 11: Build, Install, And Runtime Verification Loop

**Files:**
- Create: `tools/ohos-run-loop.sh`
- Modify: `README.md`

- [ ] **Step 1: Add device run helper**

Create `tools/ohos-run-loop.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HDC="${OHOS_HDC:-hdc}"
HVIGOR="${OHOS_HVIGOR:-hvigorw}"
BUNDLE="${OHOS_APP_BUNDLE:-com.preview.fusionterm}"
ABILITY="${OHOS_APP_ABILITY:-EntryAbility}"
HAP_PATH="${OHOS_HAP_PATH:-$ROOT_DIR/entry/build/default/outputs/default/entry-default-signed.hap}"

case "${1:-build}" in
  build)
    cd "$ROOT_DIR"
    "$HVIGOR" --mode module -p product=default -p module=entry@default assembleHap --no-daemon
    ;;
  install)
    "$HDC" install -r "$HAP_PATH"
    ;;
  start)
    "$HDC" shell aa start -a "$ABILITY" -b "$BUNDLE"
    ;;
  logs)
    "$HDC" shell hilog | grep -E 'FusionTerm|fusion_terminal_driver|SSHSession|PTYHandler'
    ;;
  run)
    "$0" build
    "$0" install
    "$0" start
    ;;
  *)
    echo "usage: $0 build|install|start|logs|run"
    exit 2
    ;;
esac
```

- [ ] **Step 2: Document run helper**

Add to README:

````markdown
## Device Loop

```sh
bash tools/ohos-run-loop.sh build
bash tools/ohos-run-loop.sh install
bash tools/ohos-run-loop.sh start
bash tools/ohos-run-loop.sh logs
```

Override tool paths with `OHOS_HDC`, `OHOS_HVIGOR`, and `OHOS_HAP_PATH`.
````

- [ ] **Step 3: Verify and commit**

Run:

```sh
bash -n tools/ohos-run-loop.sh
rg -n "ohos-run-loop|OHOS_HDC|com.preview.fusionterm" README.md tools
```

Expected: helper syntax succeeds and README documents all supported commands.

Commit:

```sh
git add README.md tools/ohos-run-loop.sh
git commit -m "chore: add HarmonyOS run loop helper"
```

## Task 12: Final Quality Gates

**Files:**
- Modify: `docs/build/manual-qa.md`
- Modify: `README.md`

- [ ] **Step 1: Run local static checks**

Run:

```sh
bash -n tools/fetch-third-party.sh
bash -n tools/dev-env-check.sh
bash -n tools/terminal-smoke.sh
bash -n tools/ohos-run-loop.sh
python3 - <<'PY'
import json
from pathlib import Path
root = Path('.')
for rel in [
  'AppScope/app.json5',
  'build-profile.json5',
  'hvigor/hvigor-config.json5',
  'oh-package.json5',
  'entry/oh-package.json5',
  'entry/build-profile.json5',
  'entry/src/main/module.json5',
  'entry/src/main/resources/base/element/string.json',
  'entry/src/main/resources/base/element/color.json',
  'entry/src/main/resources/base/profile/main_pages.json',
]:
    json.loads((root / rel).read_text())
    print(f'json-ok {rel}')
PY
LC_ALL=C rg -n '[^\x00-\x7F]' . || true
```

Expected: shell and JSON checks succeed; ASCII scan only reports intentional non-ASCII text in documentation when present.

- [ ] **Step 2: Run DevEco build**

Run on the Harmony SDK machine:

```sh
bash tools/fetch-third-party.sh
ohpm install --all
hvigorw --mode module -p product=default -p module=entry@default assembleHap --no-daemon
```

Expected: HAP output exists under `entry/build/default/outputs/default/`.

- [ ] **Step 3: Run device smoke**

Run:

```sh
bash tools/ohos-run-loop.sh run
bash tools/ohos-run-loop.sh logs
```

Expected: the app launches; local PTY or VM SSH produces terminal output; logs show no native crash.

- [ ] **Step 4: Run Fusion VM acceptance**

On the terminal inside the app, run:

```sh
echo "$TERM $COLORTERM"
stty size
printf '\033[38;2;255;80;40mtruecolor-ok\033[0m\n'
```

Expected: environment reports `xterm-256color truecolor`; resize reports nonzero rows and columns; text color changes.

- [ ] **Step 5: Commit final docs**

Commit any verification notes:

```sh
git add README.md docs/build/manual-qa.md
git commit -m "docs: record FusionTerm verification flow"
```

## Scope Check

This plan keeps the first production milestone focused on one usable terminal workspace, SSH remote PTY for the Fusion Linux VM, local PTY fallback, settings, basic tabs, host-key trust, and reproducible build/run checks. General-purpose SSH key-agent support, SFTP, terminal multiplexing, and custom font packaging are separate milestones after this plan passes device QA.
