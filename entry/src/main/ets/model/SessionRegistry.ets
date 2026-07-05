import { TerminalSessionHandle } from './TerminalSession';

// A session parked while its tab is being dragged out of one window, plus the
// safety timeout that reclaims it if the drop never lands.
interface ParkedSession {
  handle: TerminalSessionHandle;
  onExpire: (handle: TerminalSessionHandle) => void;
  timer: number;
}

// If the receiving window never claims a parked session within this window, the
// origin gets it back via onExpire (re-inserted / cleaned up), so a dropped or
// abandoned drag can never strand a live PTY in limbo.
const HANDOFF_EXPIRY_MS: number = 15000;

// Process-global session hand-off registry. Emberline multiton windows all run
// in the same VM and therefore share this module's scope (AppStorage-style
// shared heap), so a tab torn off one window can be parked here and claimed by
// the window that receives the drop -- without serializing or re-creating the
// live controller/driver/agent. `__probe` is a cross-window shared-heap identity
// canary read into logs while wiring up the drag-out / merge feature.
class SessionRegistry {
  private parked: Map<string, ParkedSession> = new Map();
  __probe: number = 42;

  park(token: string, handle: TerminalSessionHandle,
       onExpire: (handle: TerminalSessionHandle) => void): void {
    // A re-park under the same token supersedes the previous one cleanly.
    this.cancel(token);
    const timer = setTimeout(() => {
      const entry = this.parked.get(token);
      if (!entry) {
        return;
      }
      this.parked.delete(token);
      entry.onExpire(entry.handle);
    }, HANDOFF_EXPIRY_MS) as number;
    const parked: ParkedSession = { handle, onExpire, timer };
    this.parked.set(token, parked);
  }

  claim(token: string): TerminalSessionHandle | null {
    const entry = this.parked.get(token);
    if (!entry) {
      return null;
    }
    clearTimeout(entry.timer);
    this.parked.delete(token);
    return entry.handle;
  }

  generateToken(): string {
    return `ember-handoff-${Date.now()}-${Math.floor(Math.random() * 1000000000)}`;
  }

  readProbe(): number {
    return this.__probe;
  }

  private cancel(token: string): void {
    const entry = this.parked.get(token);
    if (!entry) {
      return;
    }
    clearTimeout(entry.timer);
    this.parked.delete(token);
  }
}

// Module-level singleton: one instance shared by every window in the process.
export const sessionRegistry: SessionRegistry = new SessionRegistry();
