# FusionTerm Product Positioning

## One-Line Position

FusionTerm is a HarmonyOS developer terminal for connecting to the Fusion
Development Engine Linux VM with a Ghostty-grade renderer and a native-feeling
ArkUI shell.

## Target User

The first target user is a HarmonyOS developer or power user working from a
HarmonyOS NEXT / 2-in-1 environment who needs a reliable terminal into the
Fusion Linux VM, normally reachable as `bruce`.

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

## Primary Milestone

The first milestone is a working VM terminal:

- first screen is the terminal workspace;
- `VM` opens a compact connection panel;
- default host is `bruce`, port `22`;
- SSH requests a remote PTY;
- remote environment advertises `TERM=xterm-256color` and
  `COLORTERM=truecolor`;
- input, output, resize, and quick keys round-trip through the native driver;
- rendering goes through `libghostty-ohos` and `libghostty_vt.a`.

## Secondary Milestone

The local PTY path is a secondary capability. Keep it available as a prototype
for devices or runtimes where `forkpty` and shell execution are allowed, but do
not let it define the product promise until device QA proves it reliable.

## Non-Goals

- Do not port Ghostty desktop GUI directly.
- Do not rewrite terminal rendering from scratch.
- Do not position this milestone as a general-purpose SSH manager.
- Do not add SFTP, terminal multiplexing, SSH agent, or key management before
  the VM terminal path is stable.
- Do not persist passwords.
- Do not blend in unrelated AI note-taking, Obsidian-like, PPT/PDF annotation,
  or lifestyle-app ideas from earlier HarmonyOS brainstorming threads.

## Success Criteria

- DevEco sync and HAP build succeed on a Harmony SDK machine.
- The app opens directly to a terminal workspace.
- The VM path connects to `bruce` or a user-provided Fusion VM address.
- `echo "$TERM $COLORTERM"` reports `xterm-256color truecolor` inside the
  remote shell.
- A truecolor smoke command renders visibly distinct color output.
- Resize updates remote terminal dimensions.
- Ctrl-C, Ctrl-D, Tab, Esc, arrows, PgUp, and PgDn work through hardware input
  or quick keys.
- Known-host verification exists before the project is treated as a broad SSH
  client.

## Naming

`HMG` is the GitHub repository name. `FusionTerm` is the current app/product
codename in source, README, and UI resources.
