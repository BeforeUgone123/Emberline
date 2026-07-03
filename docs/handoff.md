# FusionTerm Handoff

## Source Thread

Primary discussion thread:

```text
/home/user/.codex/sessions/2026/07/02/rollout-2026-07-02T15-16-20-019f21af-8a93-76b1-b60d-e2122790c83a.jsonl
```

This is the thread where the product direction moved from Ghostty migration
research to a HarmonyOS advanced terminal project. The important decisions were:

- avoid a full desktop Ghostty GUI port;
- use `libghostty-ohos` as the HarmonyOS renderer/HAR;
- build a standalone HarmonyOS Stage app rather than bloating the renderer
  example app;
- target terminal use first, not note-taking or AI document workflows;
- prioritize connecting to the Fusion Development Engine Linux VM;
- keep local PTY as a fallback/prototype;
- create the project under `/mnt/linux_share/preview/harmony-advanced-terminal`;
- publish the repository as `HMG`.

Related exploratory threads:

- `019e8d39-437f-7260-9b63-895bad7f4138`: HarmonyOS ecosystem-gap discussion,
  including Obsidian-like note and AI folder-reading ideas.
- `019ea70e-87d9-76f1-831e-414bae920875`: broader HarmonyOS project
  brainstorming; those ideas are explicitly out of scope for HMG.

## Current State

The project is a HarmonyOS Stage scaffold with:

- app module `entry`;
- vendored renderer HAR module `libghostty_ohos`;
- prebuilt `libghostty_ohos/prebuilt/arm64-v8a/libghostty_vt.a`;
- first-screen ArkUI terminal workspace in `Index.ets`;
- `TerminalSurface` and `TerminalController` from `libghostty-ohos`;
- native N-API bridge in `entry/src/main/cpp/terminal_driver.cpp`;
- local PTY helper in `entry/src/main/cpp/pty`;
- SSH remote PTY helper in `entry/src/main/cpp/ssh`;
- password-based SSH prototype;
- quick-key row for Esc, Tab, Ctrl-C, Ctrl-D, arrows, PgUp, and PgDn;
- `ohos.permission.INTERNET` declared for SSH.

## Known Limits

- Full HAP build has not been verified in this Codex workspace because the
  local HarmonyOS SDK tools are not installed here.
- `third_party/libssh2` and `third_party/mbedtls` are not committed. Run
  `bash tools/fetch-third-party.sh` before native SSH builds.
- Host-key verification is not implemented yet.
- Passwords are currently kept only in UI/runtime state, but the model still
  carries a `password` field. Refactor before adding persistence.
- The ArkUI workspace is still in one page file; component split is planned.
- Local PTY may be blocked or degraded by HarmonyOS sandbox behavior.
- Driver lifecycle still needs hardening around blocked reads and cleanup hooks.

## Build Handoff

On a DevEco/Harmony SDK machine:

```sh
bash tools/fetch-third-party.sh
ohpm install --all
hvigorw assembleHap --mode module -p product=default -p module=entry@default --no-daemon
```

If DevEco reports `libghostty_vt.a` missing, confirm this file exists:

```text
libghostty_ohos/prebuilt/arm64-v8a/libghostty_vt.a
```

If SSH native build fails, inspect:

- `entry/src/main/cpp/CMakeLists.txt`;
- `third_party/libssh2`;
- `third_party/mbedtls`;
- Harmony native SDK CMake toolchain paths in the DevEco error output.

## Recommended Next Steps

1. Verify DevEco sync and HAP build with the vendored HAR and prebuilt VT
   static library.
2. Add native driver event callback and structured driver events.
3. Add SSH host-key fingerprint extraction and trust UI.
4. Remove password from persisted/profile model boundaries.
5. Add settings/profile stores only after password handling is separated.
6. Split UI into `TopBar`, `ConnectionSheet`, `QuickKeyBar`, and settings
   components.
7. Add manual QA scripts for truecolor, resize, and keyboard behavior.

## Do Not Drift

Keep the product focused on the Fusion VM terminal path. Earlier brainstorming
included AI note apps, PPT/PDF annotation, and lifestyle products, but those are
not part of HMG unless the user explicitly reopens that scope.
