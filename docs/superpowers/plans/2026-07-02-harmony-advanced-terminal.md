# Harmony Advanced Terminal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a HarmonyOS terminal app scaffold that uses `libghostty-ohos` for rendering and a native driver for local PTY plus Fusion VM SSH sessions.

**Architecture:** Keep `libghostty-ohos` as a renderer dependency. Put app shell, connection state, and session lifecycle in `entry`; put byte-stream transport in `libfusion_terminal_driver.so`.

**Tech Stack:** HarmonyOS Stage model, ArkTS, ArkUI, XComponent-backed `libghostty-ohos`, N-API C++, POSIX PTY, libssh2, mbedTLS.

---

### Task 1: Project Skeleton

**Files:**
- Create: `AppScope/app.json5`
- Create: `build-profile.json5`
- Create: `hvigorfile.ts`
- Create: `hvigor/hvigor-config.json5`
- Create: `oh-package.json5`
- Create: `entry/oh-package.json5`
- Create: `entry/build-profile.json5`
- Create: `entry/hvigorfile.ts`
- Create: `entry/src/main/module.json5`

- [x] **Step 1:** Add a single `entry` Stage module targeting default and 2in1 devices.
- [x] **Step 2:** Add `ohos.permission.INTERNET` for SSH transport.
- [x] **Step 3:** Depend on local `file:/home/user/libghostty-ohos/libghostty_ohos`.

### Task 2: ArkTS Terminal Workspace

**Files:**
- Create: `entry/src/main/ets/entryability/EntryAbility.ets`
- Create: `entry/src/main/ets/pages/Index.ets`
- Create: `entry/src/main/ets/models/ConnectionProfile.ets`
- Create: `entry/src/main/ets/drivers/FusionTerminalDriver.ets`
- Create: `entry/src/main/ets/native-modules.d.ts`

- [x] **Step 1:** Load `pages/Index` from `EntryAbility`.
- [x] **Step 2:** Compose top status bar, full terminal surface, quick-key bar, and VM connection overlay.
- [x] **Step 3:** Wire `TerminalController` input/output to the ArkTS driver.
- [x] **Step 4:** Provide local and SSH start paths.

### Task 3: Native Session Driver

**Files:**
- Create: `entry/src/main/cpp/CMakeLists.txt`
- Create: `entry/src/main/cpp/terminal_driver.cpp`
- Create: `entry/src/main/cpp/pty/pty_handler.cpp`
- Create: `entry/src/main/cpp/pty/pty_handler.h`
- Create: `entry/src/main/cpp/ssh/ssh_session.cpp`
- Create: `entry/src/main/cpp/ssh/ssh_session.h`

- [x] **Step 1:** Export N-API methods `initialize`, `startLocal`, `connectSsh`, `stop`, `writeInput`, `drainOutput`, `setOutputCallback`, and `resize`.
- [x] **Step 2:** Feed local PTY output and remote SSH output through a thread-safe JS callback.
- [x] **Step 3:** Propagate terminal resize to local PTY and remote SSH PTY.
- [x] **Step 4:** Keep truecolor environment values for both local and remote sessions.

### Task 4: Dependency And Build Handoff

**Files:**
- Create: `tools/fetch-third-party.sh`
- Create: `third_party/README.md`
- Create: `README.md`

- [x] **Step 1:** Add a fetch script for mbedTLS and libssh2.
- [x] **Step 2:** Document DevEco build commands and current local limitation.
- [x] **Step 3:** Document the prototype SSH security boundary.

