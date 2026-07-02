# Harmony Advanced Terminal Design

## Goal

Build a HarmonyOS Stage application that turns the existing `libghostty-ohos`
renderer into a practical terminal app for the Fusion Development Engine Linux
VM, while keeping the renderer library reusable and unpolluted by app chrome.

## Architecture

The project is an independent app under `/mnt/linux_share/preview`. It depends
on the local `libghostty-ohos` HAR for terminal rendering and owns session
orchestration in the entry module. ArkTS composes the shell UI, connection
panel, status bar, quick-key bar, and `TerminalSurface`; a native N-API module
owns PTY and SSH byte streams.

## Core Behavior

- First screen is the usable terminal workspace.
- The `VM` action opens a compact connection panel prefilled for host `bruce`.
- The SSH path requests a remote PTY and sets truecolor-friendly environment
  values through libssh2.
- The `Local` action starts a sandbox local PTY when the runtime permits it.
- One `TerminalController` maps terminal input to the native driver and feeds
  native output back into the Ghostty renderer.

## Boundaries

- No local Harmony runtime tools are installed in this workspace.
- Signing material is not committed.
- Third-party native SSH dependencies are fetched by script, not vendored in
  the initial scaffold.
- Host-key verification is a follow-up requirement before this becomes a
  general SSH client.

## Verification

Local verification checks the file structure, source references, ignored vendor
state, and shell script syntax. Full HAP compilation must run in DevEco Studio
or a Harmony SDK environment with `ohpm`, `hvigor`, and signing configured.

