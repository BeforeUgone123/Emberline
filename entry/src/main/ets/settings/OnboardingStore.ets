import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

// One-shot onboarding flags. Currently a single bit: whether the first-launch
// wand-agent deploy guide has been shown (the same walkthrough stays reachable
// from the drawer help pane forever, so this only gates the auto-popup).
const STORE_NAME: string = 'fusionterm_onboarding';

export class OnboardingStore {
  private prefs: preferences.Preferences | null = null;

  async load(context: common.UIAbilityContext): Promise<boolean> {
    this.prefs = await preferences.getPreferences(context, STORE_NAME);
    const value = await this.prefs.get('agentGuideSeen', false);
    return typeof value === 'boolean' ? value : false;
  }

  async markSeen(): Promise<void> {
    if (!this.prefs) {
      return;
    }
    await this.prefs.put('agentGuideSeen', true);
    await this.prefs.flush();
  }
}
