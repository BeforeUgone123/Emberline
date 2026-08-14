import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

// TOFU trust database for SSH/SFTP server host keys (code review CR-002).
// Values are OpenSSH-style SHA-256 fingerprints ("SHA256:<base64-no-padding>")
// keyed by "host:port" — the same shape the native SSHHostKeyTrustStore keeps
// — so the connection UI can display trusted endpoints and forget a record
// after a legitimate host rekey. Trust metadata only: credentials are never
// stored, here or anywhere else.
export interface HostKeyRecord {
  endpoint: string;
  fingerprint: string;
}

const STORE_NAME: string = 'fusionterm_host_keys';
const KEY_PREFIX: string = 'hostkey/';

export class HostKeyStore {
  private prefs: preferences.Preferences | null = null;

  async load(context: common.UIAbilityContext): Promise<void> {
    this.prefs = await preferences.getPreferences(context, STORE_NAME);
  }

  static endpointKey(host: string, port: number): string {
    return host + ':' + port;
  }

  // The stored fingerprint for an endpoint, or '' when it has never been
  // trusted (first contact).
  async lookup(host: string, port: number): Promise<string> {
    if (!this.prefs) {
      return '';
    }
    const key = KEY_PREFIX + HostKeyStore.endpointKey(host, port);
    const value = await this.prefs.get(key, '');
    return typeof value === 'string' ? value : '';
  }

  async remember(host: string, port: number, fingerprint: string): Promise<void> {
    if (!this.prefs || fingerprint.length === 0) {
      return;
    }
    await this.prefs.put(KEY_PREFIX + HostKeyStore.endpointKey(host, port), fingerprint);
    await this.prefs.flush();
  }

  async forget(host: string, port: number): Promise<void> {
    if (!this.prefs) {
      return;
    }
    await this.prefs.delete(KEY_PREFIX + HostKeyStore.endpointKey(host, port));
    await this.prefs.flush();
  }

  async list(): Promise<HostKeyRecord[]> {
    const records: HostKeyRecord[] = [];
    if (!this.prefs) {
      return records;
    }
    const all = await this.prefs.getAll() as Record<string, preferences.ValueType>;
    for (const key of Object.keys(all)) {
      if (!key.startsWith(KEY_PREFIX)) {
        continue;
      }
      const value = all[key];
      if (typeof value === 'string' && value.length > 0) {
        records.push({ endpoint: key.substring(KEY_PREFIX.length), fingerprint: value });
      }
    }
    return records;
  }

  // Extracts the presented "SHA256:..." fingerprint from a native host-key
  // verification error so the connection UI can offer forget-and-retry on a
  // mismatch.
  static fingerprintFromError(error: string): string {
    const match = error.match(/SHA256:[A-Za-z0-9+/]+/);
    return match ? match[0] : '';
  }
}
