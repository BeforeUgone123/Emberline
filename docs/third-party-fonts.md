# Third-Party Fonts

FusionTerm bundles open terminal fonts in:

```text
libghostty_ohos/src/main/resources/rawfile/fonts
```

The renderer tries these bundled fonts before device/system fallbacks so CJK
text, box drawing, Powerline glyphs, and terminal symbols are less likely to
render as blank boxes on HarmonyOS devices.

## Bundled Open Fonts

| File | Upstream | Version/source | License |
| --- | --- | --- | --- |
| `MapleMonoNormal-NF-CN-Regular.ttf` | Maple Mono | `MapleMonoNormal-NF-CN-unhinted.zip` from `subframe7536/maple-font` release `v7.9` | SIL Open Font License 1.1 |
| `SarasaFixedSC-Regular.ttf` | Sarasa Gothic | `SarasaFixedSC-TTF-1.0.40.7z` from `be5invis/Sarasa-Gothic` release `v1.0.40` | SIL Open Font License 1.1 |
| `JetBrainsMono-Regular.ttf` | JetBrains Mono | `fonts/ttf/JetBrainsMono-Regular.ttf` from `JetBrains/JetBrainsMono` release `v2.304` | SIL Open Font License 1.1 |
| `CascadiaMono.ttf` | Cascadia Code | `CascadiaCode-2407.24.zip` from `microsoft/cascadia-code` release `v2407.24` | SIL Open Font License 1.1 |
| `SymbolsNerdFontMono-Regular.ttf` | Nerd Fonts Symbols | Nerd Fonts symbols-only mono font | Nerd Fonts project licensing; font assets are covered by their upstream font licenses and OFL/MIT notices as documented upstream |

## Default Fallback Order

Each bundled file is registered as its own font family, and the renderer walks
this paragraph fallback chain (mirroring the developer's desktop Ghostty
config, which prefers `Maple Mono Normal NF CN`):

1. `FusionTerm Maple Mono` — Latin + CJK + Nerd Font glyphs in one file
2. `FusionTerm JetBrains Mono`
3. `FusionTerm Nerd Symbols`
4. `FusionTerm Cascadia Mono`
5. `FusionTerm Sarasa Fixed SC`
6. optional private fallback (Apple placeholder files below)
7. platform families (PingFang SC, HarmonyOS Sans, Noto, ...)

## Apple Font Placeholders

The renderer also looks for optional Apple-style font files such as:

```text
PingFangSC-Regular.otf
PingFangSC-Regular.ttf
PingFangSC.ttf
PingFang.ttc
SF-Pro-Text-Regular.otf
SFProText-Regular.otf
```

Do not commit proprietary Apple font binaries unless the project has explicit
redistribution rights. These names are only optional rawfile candidates for
private/device-local testing.

## Upstream Links

- Sarasa Gothic: https://github.com/be5invis/Sarasa-Gothic
- JetBrains Mono: https://github.com/JetBrains/JetBrainsMono
- Cascadia Code: https://github.com/microsoft/cascadia-code
- Nerd Fonts: https://github.com/ryanoasis/nerd-fonts
