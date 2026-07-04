import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

// Persisted connection endpoint (passwords are intentionally NOT stored;
// they stay in runtime UI state only).
export interface ConnectionSettings {
  host: string;
  port: string;
  token: string;
  sshPort: string;
  user: string;
}

const STORE_NAME: string = 'fusionterm_connection';

export class ConnectionStore {
  private prefs: preferences.Preferences | null = null;

  async load(context: common.UIAbilityContext,
    fallback: ConnectionSettings): Promise<ConnectionSettings> {
    this.prefs = await preferences.getPreferences(context, STORE_NAME);
    const loaded: ConnectionSettings = {
      host: await this.readString('host', fallback.host),
      port: await this.readString('port', fallback.port),
      token: await this.readString('token', fallback.token),
      sshPort: await this.readString('sshPort', fallback.sshPort),
      user: await this.readString('user', fallback.user)
    };
    return loaded;
  }

  async save(settings: ConnectionSettings): Promise<void> {
    if (!this.prefs) {
      return;
    }
    await this.prefs.put('host', settings.host);
    await this.prefs.put('port', settings.port);
    await this.prefs.put('token', settings.token);
    await this.prefs.put('sshPort', settings.sshPort);
    await this.prefs.put('user', settings.user);
    await this.prefs.flush();
  }

  private async readString(key: string, fallback: string): Promise<string> {
    if (!this.prefs) {
      return fallback;
    }
    const value = await this.prefs.get(key, fallback);
    return typeof value === 'string' ? value : fallback;
  }
}
