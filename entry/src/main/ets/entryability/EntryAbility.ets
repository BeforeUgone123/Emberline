import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SYS_DARK_KEY } from '../theme/ChromeTheme';

const DOMAIN = 0x0001;
const TAG = 'FusionTermAbility';
const FOREGROUND_FOCUS_EVENT: string = 'fusionTermForeground';
const BACKGROUND_EVENT: string = 'fusionTermBackground';
const WINDOW_CHROME_HEIGHT: number = 48;
// Tab drag-out hand-off: a window that receives a torn-off tab is launched (or
// re-fronted) with this Want parameter; the page reads the matching AppStorage
// key in aboutToAppear to claim the parked session instead of adding a blank tab.
const HANDOFF_TOKEN_KEY: string = 'emberHandoffToken';
// Page -> ability: the adaptive chrome turned light/dark, restyle the system
// window decor buttons to match (they are not part of the ArkTS tree).
const CHROME_MODE_EVENT: string = 'fusionTermChromeMode';

interface WindowChromeController {
  setWindowDecorVisible(visible: boolean): void;
  setWindowDecorHeight(height: number): void;
  setDecorButtonStyle(style: WindowDecorButtonStyle): void;
}

interface WindowDecorButtonStyle {
  colorMode?: ConfigurationConstant.ColorMode;
}

export default class EntryAbility extends UIAbility {
  private wasBackgrounded: boolean = false;
  private windowForeground: boolean = false;
  private mainWindow: window.Window | null = null;

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.captureHandoffToken(want);
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set color mode: %{public}s', JSON.stringify(err));
    }
    this.publishSystemColorMode(this.context.config.colorMode);
    this.context.eventHub.on(CHROME_MODE_EVENT, (isLight: boolean): void => {
      this.applyDecorButtonMode(isLight);
    });
  }

  // System light/dark switched while running: publish it for the page, which
  // re-resolves the effective theme (ghostty theme = light:...,dark:... model).
  onConfigurationUpdate(newConfig: Configuration): void {
    this.publishSystemColorMode(newConfig.colorMode);
  }

  private publishSystemColorMode(mode: ConfigurationConstant.ColorMode | undefined): void {
    const sysDark: boolean = mode !== ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    AppStorage.setOrCreate(SYS_DARK_KEY, sysDark);
  }

  private applyDecorButtonMode(isLight: boolean): void {
    const mainWindow: window.Window | null = this.mainWindow;
    if (!mainWindow) {
      return;
    }
    try {
      const chromeWindow = mainWindow as WindowChromeController;
      chromeWindow.setDecorButtonStyle({
        colorMode: isLight
          ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
          : ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to restyle decor buttons: %{public}s', JSON.stringify(err));
    }
  }

  // A singleton/reused ability instance is re-fronted through onNewWant rather
  // than onCreate, so read the hand-off token here too; the page picks it up on
  // its next aboutToAppear / foreground pass.
  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.captureHandoffToken(want);
  }

  // Stash a tab drag-out hand-off token from the launch Want into AppStorage so
  // the ArkTS page (a different context) can claim the parked session. No token
  // means an ordinary cold launch -- leave AppStorage untouched.
  private captureHandoffToken(want: Want): void {
    const raw: Object | undefined = want.parameters?.[HANDOFF_TOKEN_KEY];
    if (typeof raw === 'string' && raw.length > 0) {
      AppStorage.setOrCreate(HANDOFF_TOKEN_KEY, raw);
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err: BusinessError) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load page: %{public}s', JSON.stringify(err));
        return;
      }
      this.enableWindowChromeImmersion(windowStage);
    });
  }

  private enableWindowChromeImmersion(windowStage: window.WindowStage): void {
    windowStage.getMainWindow((err: BusinessError, mainWindow: window.Window) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to get main window: %{public}s', JSON.stringify(err));
        return;
      }
      this.mainWindow = mainWindow;
      this.applyForegroundScreenPolicy();
      try {
        const chromeWindow = mainWindow as WindowChromeController;
        chromeWindow.setWindowDecorVisible(false);
        chromeWindow.setWindowDecorHeight(WINDOW_CHROME_HEIGHT);
        chromeWindow.setDecorButtonStyle({
          colorMode: ConfigurationConstant.ColorMode.COLOR_MODE_DARK
        });
      } catch (decorErr) {
        hilog.error(DOMAIN, TAG, 'Failed to enable immersive window chrome: %{public}s', JSON.stringify(decorErr));
      }
    });
  }

  private applyForegroundScreenPolicy(): void {
    const mainWindow: window.Window | null = this.mainWindow;
    if (!mainWindow) {
      return;
    }
    const enabled: boolean = this.windowForeground;
    void mainWindow.setWindowKeepScreenOn(enabled).catch((err: Object) => {
      hilog.warn(DOMAIN, TAG, 'Failed to set foreground screen policy (%{public}s): %{public}s',
        enabled ? 'awake' : 'system-default', JSON.stringify(err));
    });
  }

  onForeground(): void {
    this.windowForeground = true;
    this.applyForegroundScreenPolicy();
    if (!this.wasBackgrounded) {
      return;
    }
    this.wasBackgrounded = false;
    this.context.eventHub.emit(FOREGROUND_FOCUS_EVENT);
  }

  onBackground(): void {
    this.windowForeground = false;
    this.applyForegroundScreenPolicy();
    this.wasBackgrounded = true;
    // Task-finished notifications only fire for tabs the user cannot see;
    // the page needs to know "the whole app is hidden" so the ACTIVE tab
    // notifies too when its agent finishes while we are backgrounded.
    this.context.eventHub.emit(BACKGROUND_EVENT);
  }

  onWindowStageDestroy(): void {
    this.windowForeground = false;
    this.applyForegroundScreenPolicy();
    this.mainWindow = null;
  }
}
