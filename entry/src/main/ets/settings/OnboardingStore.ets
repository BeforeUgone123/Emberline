import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

// One-shot onboarding flags. The same wand-agent walkthrough stays reachable
// from Help forever, so this store only arbitrates the first-launch auto-popup.
const STORE_NAME: string = 'fusionterm_onboarding';
const AGENT_GUIDE_SEEN_KEY: string = 'wandAgentSetupSeenV2';
let agentGuideClaimedInProcess: boolean = false;

export class OnboardingStore {
  private prefs: preferences.Preferences | null = null;

  async claimAgentGuide(context: common.UIAbilityContext): Promise<boolean> {
    if (agentGuideClaimedInProcess) {
      return false;
    }
    agentGuideClaimedInProcess = true;
    try {
      this.prefs = await preferences.getPreferences(context, STORE_NAME);
      const value = await this.prefs.get(AGENT_GUIDE_SEEN_KEY, false);
      if (value === true) {
        return false;
      }
      await this.prefs.put(AGENT_GUIDE_SEEN_KEY, true);
      await this.prefs.flush();
    } catch (err) {
      // Storage failure must not hide the setup path on a fresh install. The
      // process claim still prevents duplicate popups across sibling windows.
      console.error('Failed to persist onboarding state: ' + JSON.stringify(err));
    }
    return true;
  }
}
