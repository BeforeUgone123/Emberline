# Agent Handoff Instructions

## Product North Star

FusionTerm lives in the GitHub repository `HMG`, but the app codename in this
workspace remains `FusionTerm`.

Build a HarmonyOS developer terminal whose first useful job is connecting to the
Fusion Development Engine Linux VM through a `ystyle/wand-agent`-compatible
WebSocket PTY transport. The expected default target is the Fusion Development
Engine VM bridge at `ws://172.16.100.2:8765/ws` with token `harmonyterm`, and
terminal environment values suitable for modern CLIs:
`TERM=xterm-256color` and `COLORTERM=truecolor`.

The product should feel like a desktop-grade terminal in the spirit of Ghostty,
not a demo screen or marketing page. The first screen is the terminal surface.
App chrome should stay minimal: connection state, VM action, local fallback,
theme/settings, and later session tabs. Decision 2026-07-03: no on-screen
quick-key bar — the target device is a 2-in-1 with a physical keyboard, and
all key handling goes through the native key encoder. Do not add soft key
rows back without an explicit user request.

## Architecture Boundary

- Keep `libghostty_ohos` as the reusable renderer HAR. Do not move app session
  state, SSH profiles, VM assumptions, or UI chrome into that library.
- Keep app-specific orchestration in `entry`: ArkTS owns UI/state and
  `libfusion_terminal_driver.so` owns native fallback byte-stream transports.
- Add wand-agent-compatible WebSocket orchestration in `entry`, not in
  `libghostty_ohos`.
- Treat local PTY as opportunistic. HarmonyOS app sandbox constraints can make
  local shell execution unreliable; Fusion Agent WebSocket remote PTY to the
  Fusion VM is the primary product path.
- Treat SSH remote PTY as fallback and later advanced mode, not the default VM
  path.
- Do not persist passwords. Host-key trust and safer credential handling are
  follow-up requirements before broad SSH-client positioning.

## Key Files

- `README.md`: project overview and build notes.
- `docs/product-positioning.md`: product goals, target users, and non-goals.
- `docs/handoff.md`: current implementation state and source conversation.
- `docs/fusion-agent-protocol.md`: wand-agent-compatible WebSocket PTY
  contract.
- `docs/superpowers/specs/2026-07-02-harmony-advanced-terminal-design.md`:
  original approved design.
- `docs/superpowers/plans/2026-07-02-harmony-advanced-terminal.md`: full
  implementation plan from scaffold to device QA.
- `entry/src/main/ets/pages/Index.ets`: current first-screen workspace.
- `entry/src/main/ets/drivers/FusionTerminalDriver.ets`: ArkTS driver wrapper.
- `entry/src/main/cpp/terminal_driver.cpp`: N-API bridge.
- `entry/src/main/cpp/ssh/ssh_session.cpp`: libssh2 remote PTY path.
- `entry/src/main/cpp/pty/pty_handler.cpp`: local PTY path.
- `libghostty_ohos`: vendored renderer HAR module.

## Current Build Assumptions

This Codex workspace does not provide the full HarmonyOS runtime toolchain. Full
HAP builds must run on a DevEco/Harmony SDK machine with `ohpm`, `hvigorw`,
`hdc`, signing material, CMake, and Ninja available.

The repository vendors `libghostty_ohos/prebuilt/arm64-v8a/libghostty_vt.a` so
the renderer HAR can configure in DevEco without rebuilding Ghostty VT first.
Third-party SSH fallback sources are intentionally not vendored; fetch them
with:

```sh
bash tools/fetch-third-party.sh
```

## Next Best Work

1. Run `ohpm install --all` and a full `hvigorw` build on the DevEco machine.
2. Run `wand-agent` or a hardened project fork inside the Fusion Development
   Engine Linux VM with token `harmonyterm`.
3. Verify the app can reach the agent at `172.16.100.2:8765/ws`, or update
   `DEFAULT_FUSION_AGENT_HOST` to the actual VM bridge address.
4. If the native SSH fallback build fails, fetch `third_party/libssh2` and
   `third_party/mbedtls`, then inspect `entry/src/main/cpp/CMakeLists.txt`.
5. Implement the first safety milestone: Fusion Agent authentication hardening,
   SSH host-key fingerprint reporting for fallback, and trust UI.
6. Split the ArkUI workspace into components only after the current end-to-end
   VM connection path compiles.
7. Keep docs updated whenever product scope changes; do not let the project
   drift back into a vague "terminal emulator" label.

## Source Conversation

Primary source thread:
`/home/user/.codex/sessions/2026/07/02/rollout-2026-07-02T15-16-20-019f21af-8a93-76b1-b60d-e2122790c83a.jsonl`

Important decision cues from that thread:

- The user asked to assess Ghostty migration feasibility for HarmonyOS.
- The recommended direction was not a full Ghostty GUI port, but a
  Ghostty-rendered HarmonyOS SSH terminal.
- The user confirmed: "do terminal emulator only", "target local shell through
  PTY", then refined the real target to the Fusion Development Engine Linux VM.
- The user asked to create the Harmony advanced terminal project under
  `/mnt/linux_share/preview`.
- The user later named the GitHub repository `HMG`.
- The user approved using a hardened `ystyle/wand-agent`-style WebSocket PTY
  agent as the preferred VM transport, with SSH retained as fallback.

Related earlier exploration threads discussed broader HarmonyOS ecosystem gaps
and other product ideas, but they are not the current HMG product source:

- `019e8d39-437f-7260-9b63-895bad7f4138`: HarmonyOS ecosystem and note/AI app
  exploration.
- `019ea70e-87d9-76f1-831e-414bae920875`: HarmonyOS project brainstorming,
  including education and lifestyle app branches.
