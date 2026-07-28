import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

// Persisted appearance customization: user font, background image, acrylic
// blur, terminal background opacity, theme, font family, and font size.
export interface AppearanceSettings {
  fontSize: number;
  fontFamily: string;
  // Ghostty-style light/dark pairing: one theme per system color mode. The
  // legacy single 'themeName' key migrates into the dark slot on first load.
  darkThemeName: string;
  lightThemeName: string;
  // 'system' follows the OS color mode; 'dark' / 'light' pin the app to one
  // slot regardless of the OS setting.
  colorModeOverride: string;
  customFontPath: string;
  backgroundImagePath: string;
  backgroundOpacity: number;
  backgroundBlur: number;
  cursorStyle: number;
  cursorBlink: boolean;
  pasteDirUri: string;
}

// Defaults mirror the desktop Ghostty profile (font-size 13,
// background-opacity 0.91, background-blur 12, Catppuccin Mocha).
export const DEFAULT_APPEARANCE: AppearanceSettings = {
  fontSize: 13,
  fontFamily: 'FusionTerm Maple Mono',
  darkThemeName: 'Catppuccin_Mocha',
  lightThemeName: 'Catppuccin_Latte',
  colorModeOverride: 'system',
  customFontPath: '',
  backgroundImagePath: '',
  backgroundOpacity: 0.91,
  backgroundBlur: 12,
  cursorStyle: 2,
  cursorBlink: false,
  pasteDirUri: ''
};

const STORE_NAME: string = 'fusionterm_appearance';

export class AppearanceStore {
  private prefs: preferences.Preferences | null = null;

  async load(context: common.UIAbilityContext): Promise<AppearanceSettings> {
    this.prefs = await preferences.getPreferences(context, STORE_NAME);
    const loaded: AppearanceSettings = {
      fontSize: await this.readNumber('fontSize', DEFAULT_APPEARANCE.fontSize),
      fontFamily: await this.readString('fontFamily', DEFAULT_APPEARANCE.fontFamily),
      // Migration: an existing single-theme install keeps its theme as the
      // dark-mode choice; the light slot starts at the default pairing.
      darkThemeName: await this.readString('darkThemeName',
        await this.readString('themeName', DEFAULT_APPEARANCE.darkThemeName)),
      lightThemeName: await this.readString('lightThemeName', DEFAULT_APPEARANCE.lightThemeName),
      colorModeOverride: await this.readString('colorModeOverride', DEFAULT_APPEARANCE.colorModeOverride),
      customFontPath: await this.readString('customFontPath', DEFAULT_APPEARANCE.customFontPath),
      backgroundImagePath: await this.readString('backgroundImagePath', DEFAULT_APPEARANCE.backgroundImagePath),
      backgroundOpacity: await this.readNumber('backgroundOpacity', DEFAULT_APPEARANCE.backgroundOpacity),
      backgroundBlur: await this.readNumber('backgroundBlur', DEFAULT_APPEARANCE.backgroundBlur),
      cursorStyle: await this.readNumber('cursorStyle', DEFAULT_APPEARANCE.cursorStyle),
      cursorBlink: await this.readBoolean('cursorBlink', DEFAULT_APPEARANCE.cursorBlink),
      pasteDirUri: await this.readString('pasteDirUri', DEFAULT_APPEARANCE.pasteDirUri)
    };
    return loaded;
  }

  async save(settings: AppearanceSettings): Promise<void> {
    if (!this.prefs) {
      return;
    }
    await this.prefs.put('fontSize', settings.fontSize);
    await this.prefs.put('fontFamily', settings.fontFamily);
    await this.prefs.put('darkThemeName', settings.darkThemeName);
    await this.prefs.put('lightThemeName', settings.lightThemeName);
    await this.prefs.put('colorModeOverride', settings.colorModeOverride);
    await this.prefs.put('customFontPath', settings.customFontPath);
    await this.prefs.put('backgroundImagePath', settings.backgroundImagePath);
    await this.prefs.put('backgroundOpacity', settings.backgroundOpacity);
    await this.prefs.put('backgroundBlur', settings.backgroundBlur);
    await this.prefs.put('cursorStyle', settings.cursorStyle);
    await this.prefs.put('cursorBlink', settings.cursorBlink);
    await this.prefs.put('pasteDirUri', settings.pasteDirUri);
    await this.prefs.flush();
  }

  private async readNumber(key: string, fallback: number): Promise<number> {
    if (!this.prefs) {
      return fallback;
    }
    const value = await this.prefs.get(key, fallback);
    return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
  }

  private async readBoolean(key: string, fallback: boolean): Promise<boolean> {
    if (!this.prefs) {
      return fallback;
    }
    const value = await this.prefs.get(key, fallback);
    return typeof value === 'boolean' ? value : fallback;
  }

  private async readString(key: string, fallback: string): Promise<string> {
    if (!this.prefs) {
      return fallback;
    }
    const value = await this.prefs.get(key, fallback);
    return typeof value === 'string' ? value : fallback;
  }
}
