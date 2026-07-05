import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'FusionTermAbility';
const FOREGROUND_FOCUS_EVENT: string = 'fusionTermForeground';
const BACKGROUND_EVENT: string = 'fusionTermBackground';
const WINDOW_CHROME_HEIGHT: number = 48;
// Tab drag-out hand-off: a window that receives a torn-off tab is launched (or
// re-fronted) with this Want parameter; the page reads the matching AppStorage
// key in aboutToAppear to claim the parked session instead of adding a blank tab.
const HANDOFF_TOKEN_KEY: string = 'emberHandoffToken';

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

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.captureHandoffToken(want);
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set color mode: %{public}s', JSON.stringify(err));
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

  onForeground(): void {
    if (!this.wasBackgrounded) {
      return;
    }
    this.wasBackgrounded = false;
    this.context.eventHub.emit(FOREGROUND_FOCUS_EVENT);
  }

  onBackground(): void {
    this.wasBackgrounded = true;
    // Task-finished notifications only fire for tabs the user cannot see;
    // the page needs to know "the whole app is hidden" so the ACTIVE tab
    // notifies too when its agent finishes while we are backgrounded.
    this.context.eventHub.emit(BACKGROUND_EVENT);
  }
}
