import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'FusionTermAbility';
const FOREGROUND_FOCUS_EVENT: string = 'fusionTermForeground';

export default class EntryAbility extends UIAbility {
  private wasBackgrounded: boolean = false;

  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set color mode: %{public}s', JSON.stringify(err));
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err: BusinessError) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load page: %{public}s', JSON.stringify(err));
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
  }
}
