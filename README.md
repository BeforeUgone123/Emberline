# FusionTerm

FusionTerm is a HarmonyOS Stage app scaffold for an advanced terminal emulator.
It embeds `libghostty-ohos` for rendering and owns the session layer for local
PTY and Fusion Development Engine Linux VM SSH sessions.

## What Is In This Project

- `entry/src/main/ets/pages/Index.ets`: first-screen terminal workspace.
- `entry/src/main/ets/drivers/FusionTerminalDriver.ets`: ArkTS session bridge.
- `entry/src/main/cpp/terminal_driver.cpp`: native N-API driver for PTY and SSH.
- `entry/src/main/cpp/pty`: local PTY helper copied from the current
  `libghostty-ohos` experiment.
- `entry/src/main/cpp/ssh`: libssh2 remote PTY helper.
- `docs/superpowers/specs`: the approved product design.
- `docs/superpowers/plans`: the implementation plan used for this scaffold.

## Local Dependency

The app vendors the renderer HAR module inside this project:

```json5
"libghostty-ohos": "file:../libghostty_ohos"
```

This keeps DevEco sync self-contained when the project is copied to
`/storage/Users/currentUser/Desktop/preview/harmony-advanced-terminal`.

## Third-Party Native Dependencies

The SSH driver expects libssh2 and mbedTLS sources under `third_party/`.
Fetch them with:

```sh
bash tools/fetch-third-party.sh
```

They are intentionally not vendored by default.

## Build In DevEco Studio

This machine intentionally does not have the local Harmony runtime tools
installed right now. On a DevEco/Harmony SDK machine:

```sh
ohpm install --all
hvigorw assembleHap --mode module -p product=default -p module=entry@default --no-daemon
```

Add signing material in root `build-profile.json5` before packaging for a
device.

## DevEco Sync Notes

The root `build-profile.json5` uses Huawei HarmonyOS SDK version strings:

```json5
"compatibleSdkVersion": "5.0.0(12)",
"targetSdkVersion": "5.0.0(12)",
"runtimeOS": "HarmonyOS"
```

`compileSdkVersion` is intentionally omitted so DevEco can use the installed
SDK. If sync reports an invalid SDK value again, install the matching HarmonyOS
SDK in DevEco or change `compatibleSdkVersion` and `targetSdkVersion` to values
shown in DevEco's SDK Manager.

## Security Notes

This first native SSH path supports password authentication and does not yet
perform host-key pinning. Treat it as a working prototype for the Fusion Linux
VM target; add known-host verification before using it as a general SSH client.
