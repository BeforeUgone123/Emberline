# Emberline Product Positioning

## One-Line Position

Emberline is a HarmonyOS developer terminal for connecting to the Fusion
Development Engine Linux VM with a Ghostty-grade renderer and a native-feeling
ArkUI shell.

## Target User

The first target user is a HarmonyOS developer or power user working from a
HarmonyOS NEXT / 2-in-1 environment who needs a reliable terminal into the
Fusion Development Engine Linux VM.

This user values:

- fast access to a usable shell inside the Fusion VM;
- truecolor and 256-color rendering for modern CLI tools;
- hardware keyboard and quick-key ergonomics;
- resize behavior that matches terminal expectations;
- clear separation between renderer library and app session logic.

## Product Thesis

A full Ghostty GUI port is the wrong first product. HarmonyOS has different app
shell, rendering surface, input, sandbox, and process constraints. The practical
product is a HarmonyOS app that reuses `libghostty-ohos` for terminal rendering
and implements the session layer natively for HarmonyOS.

The first durable value is not "run every local shell command on every device".
It is "make the Fusion Development Engine Linux VM feel one tap away from a
native terminal".

The preferred VM transport is now a `ystyle/wand-agent`-compatible WebSocket
PTY: a small agent runs inside the Fusion VM, owns Linux PTY creation, and
streams terminal bytes to the HarmonyOS app. SSH remains a fallback and later
advanced mode, not the default product promise.

## Primary Milestone

The first milestone is a working VM terminal:

- first screen is the terminal workspace;
- `VM` opens a compact connection panel;
- default agent endpoint is the Fusion Development Engine VM bridge,
  `ws://172.16.100.2:8765/ws` with token `harmonyterm`;
- Fusion Agent creates a remote PTY in the Fusion VM;
- remote environment advertises `TERM=xterm-256color` and
  `COLORTERM=truecolor`;
- input, output, resize, and quick keys round-trip through WebSocket binary
  frames and protocol control messages;
- rendering goes through `libghostty-ohos` and `libghostty_vt.a`.

## Secondary Milestone

The SSH and local PTY paths are secondary capabilities. Keep SSH available as a
fallback for environments without Fusion Agent, and keep local PTY available as
a prototype for devices or runtimes where `forkpty` and shell execution are
allowed. Do not let either path define the product promise until device QA
proves it reliable.

## Non-Goals

- Do not port Ghostty desktop GUI directly.
- Do not rewrite terminal rendering from scratch.
- Do not position this milestone as a general-purpose SSH manager.
- Do not add SFTP, terminal multiplexing, SSH agent, or key management before
  the VM terminal path is stable.
- Do not expose Fusion Agent broadly without stronger authentication and TLS or
  tunneling.
- Do not persist passwords.
- Do not blend in unrelated AI note-taking, Obsidian-like, PPT/PDF annotation,
  or lifestyle-app ideas from earlier HarmonyOS brainstorming threads.

## Success Criteria

- DevEco sync and HAP build succeed on a Harmony SDK machine.
- The app opens directly to a terminal workspace.
- The VM path connects to Fusion Agent through the default Fusion Development
  Engine VM bridge or a user-provided VM address.
- `echo "$TERM $COLORTERM"` reports `xterm-256color truecolor` inside the
  remote shell.
- A truecolor smoke command renders visibly distinct color output.
- Resize updates remote terminal dimensions.
- Ctrl-C, Ctrl-D, Tab, Esc, arrows, PgUp, and PgDn work through hardware input
  or quick keys.
- Agent authentication is hardened before the endpoint is exposed outside the
  trusted VM bridge network.
- Known-host verification exists before the SSH fallback is treated as a broad
  SSH client.

## Naming

`Emberline` is both the GitHub repository name and the current app/product name
in source, README, and UI resources. Earlier project notes may refer to the
app as `FusionTerm` or to the repository as `HMG`.
