// Ghostty-style adaptive chrome: every chrome color is derived from the two
// colors of the active terminal theme (background / foreground) plus the
// theme's ANSI red for the failed connection dot. There are no fixed chrome
// colors anywhere else -- a light theme yields a genuinely light UI.
//
// Derivation formulas were approved on the interactive demo
// (preview/emberline-ghostty-chrome-demo.html, "材质轻" setting):
//   bar        = bg                   tab-bar fuses with the terminal (2026-07-28
//                                      immersion decision: zero seam, the pill
//                                      capsule alone carries the elevation)
//   capsule    = mix(bg, fg, 9%)      active pill tab face
//   panel      = mix(bg, fg, 3%)      inspector / overlay panels
//   panel2     = mix(bg, fg, 7%)      popups, hover surfaces, menus
// Text, borders, icons and dots are fg at fixed alphas so they track any
// theme automatically. The only luminance branch is the capsule shadow.

export const CHROME_TOKENS_KEY: string = 'emberChromeTokens';
export const SYS_DARK_KEY: string = 'emberSysDark';
// Both theme slots and the color-mode override travel together. Sharing only
// the currently effective name leaves sibling windows holding stale slot state;
// the next OS mode flip would then republish and persist the stale choice.
export const SHARED_THEME_CONFIG_KEY: string = 'emberSharedThemeConfig';

export interface SharedThemeConfig {
  darkThemeName: string;
  lightThemeName: string;
  colorModeOverride: string;
}

export const DEFAULT_SHARED_THEME_CONFIG: SharedThemeConfig = {
  darkThemeName: 'Catppuccin_Mocha',
  lightThemeName: 'Catppuccin_Latte',
  colorModeOverride: 'system'
};

export interface ChromeTokens {
  // Backdrops (opaque -- they sit over or beside the terminal surface).
  appBg: string;
  barBg: string;
  capBg: string;
  panelBg: string;
  panelBg2: string;
  // Lines and fills (fg-alpha -- composite over any backdrop).
  capBorder: string;
  panelBorder: string;
  divider: string;
  hoverBg: string;
  pressBg: string;
  // Text ramp.
  textPrimary: string;
  textSecondary: string;
  textFaint: string;
  icon: string;
  // Connection dot states (failed uses the theme's ANSI red).
  dotOn: string;
  dotOff: string;
  dotFailed: string;
  // Primary button: high-contrast neutral (fg face, bg label).
  primaryBtnBg: string;
  primaryBtnText: string;
  capShadowColor: string;
  isLight: boolean;
}

interface Rgb {
  r: number;
  g: number;
  b: number;
}

function parseHex(value: string, fallback: Rgb): Rgb {
  const hex: string = value.startsWith('#') ? value.slice(1) : value;
  if (hex.length !== 6) {
    return fallback;
  }
  const r: number = parseInt(hex.slice(0, 2), 16);
  const g: number = parseInt(hex.slice(2, 4), 16);
  const b: number = parseInt(hex.slice(4, 6), 16);
  if (!Number.isFinite(r) || !Number.isFinite(g) || !Number.isFinite(b)) {
    return fallback;
  }
  const rgb: Rgb = { r: r, g: g, b: b };
  return rgb;
}

function toHex2(v: number): string {
  const clamped: number = Math.max(0, Math.min(255, Math.round(v)));
  const s: string = clamped.toString(16);
  return s.length === 1 ? '0' + s : s;
}

function rgbHex(c: Rgb): string {
  return '#' + toHex2(c.r) + toHex2(c.g) + toHex2(c.b);
}

// Opaque blend of base toward tint.
function mixRgb(base: Rgb, tint: Rgb, t: number): Rgb {
  const mixed: Rgb = {
    r: base.r + (tint.r - base.r) * t,
    g: base.g + (tint.g - base.g) * t,
    b: base.b + (tint.b - base.b) * t
  };
  return mixed;
}

// #AARRGGBB string of color at the given opacity.
function withAlpha(c: Rgb, alpha: number): string {
  return '#' + toHex2(alpha * 255) + toHex2(c.r) + toHex2(c.g) + toHex2(c.b);
}

function luminance(c: Rgb): number {
  return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) / 255;
}

export function deriveChromeTokens(bgHex: string, fgHex: string, redHex: string): ChromeTokens {
  const fallbackBg: Rgb = { r: 30, g: 30, b: 46 };
  const fallbackFg: Rgb = { r: 205, g: 214, b: 244 };
  const bg: Rgb = parseHex(bgHex, fallbackBg);
  const fg: Rgb = parseHex(fgHex, fallbackFg);
  const isLight: boolean = luminance(bg) > 0.5;
  const red: string = redHex.length > 0 ? redHex : rgbHex(fg);
  const tokens: ChromeTokens = {
    appBg: rgbHex(bg),
    barBg: rgbHex(bg),
    capBg: rgbHex(mixRgb(bg, fg, 0.09)),
    panelBg: rgbHex(mixRgb(bg, fg, 0.03)),
    panelBg2: rgbHex(mixRgb(bg, fg, 0.07)),
    capBorder: withAlpha(fg, 0.10),
    panelBorder: withAlpha(fg, 0.12),
    divider: withAlpha(fg, 0.12),
    hoverBg: withAlpha(fg, 0.06),
    pressBg: withAlpha(fg, 0.10),
    textPrimary: rgbHex(fg),
    textSecondary: withAlpha(fg, 0.55),
    textFaint: withAlpha(fg, 0.35),
    icon: withAlpha(fg, 0.68),
    dotOn: withAlpha(fg, 0.60),
    dotOff: withAlpha(fg, 0.30),
    dotFailed: red,
    primaryBtnBg: rgbHex(mixRgb(bg, fg, 0.90)),
    primaryBtnText: rgbHex(bg),
    capShadowColor: isLight ? '#24000000' : '#59000000',
    isLight: isLight
  };
  return tokens;
}

// Boot fallback: Catppuccin Mocha derivation, replaced as soon as the real
// theme file is parsed. Also the safety net when a theme file fails to parse.
export const DEFAULT_CHROME_TOKENS: ChromeTokens =
  deriveChromeTokens('#1e1e2e', '#cdd6f4', '#f38ba8');
