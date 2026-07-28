// entry/src/main/ets/common/KeepAliveManager.ets
//
// Process-global keep-alive for live terminal sessions. When the app is sent to
// the background HarmonyOS otherwise freezes the JS/UI thread and its network
// sockets, which drops the Fusion Agent WebSocket / SSH PTY and swallows the
// "task finished" bell so the notification never fires. A "taskKeeping"
// continuous task keeps the process scheduled while at least one session is
// live -- an interactive developer terminal is the canonical taskKeeping
// scenario. On a 2in1 device (MatePad Edge) this needs no ACL from API 21 and
// only the normal, system-granted ohos.permission.KEEP_BACKGROUND_RUNNING.
//
// Every system call is wrapped in try/catch and degrades silently: if the grant
// or the platform refuses, sessions keep running exactly as before, just
// without background protection (we log via hilog and keep the current state).
//
// The app is multiton and shares one ArkTS VM, so this module-level singleton
// aggregates a reference count across every window: the process only needs one
// continuous task no matter how many windows/sessions are live.
//
// API provenance (verified against developer.huawei.com / OpenHarmony master
// docs; the configured SDK is 6.1.0(23) == API 23):
//   - backgroundTaskManager.startBackgroundRunning(context, BackgroundMode,
//     WantAgent): Promise<void>                         -- since API 9
//   - backgroundTaskManager.stopBackgroundRunning(context): Promise<void>
//                                                        -- since API 9
//   - backgroundTaskManager.BackgroundMode.TASK_KEEPING (=== 9)   -- since API 9
//   - wantAgent.getWantAgent(WantAgentInfo): Promise<WantAgent>   -- since API 9
//     WantAgentInfo.actionType / .actionFlags are the API 11+ replacements for
//     operationType / wantAgentFlags.
//   - on('continuousTaskCancel', Callback<ContinuousTaskCancelInfo>)  -- API 15+
//   - on('continuousTaskSuspend', Callback<ContinuousTaskSuspendInfo>) -- API 20+
//     Both events are available in the configured API 23 SDK.

import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { common, wantAgent, WantAgent, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'FusionTermKeepAlive';
// Reconnect jitter (a WebSocket drop + immediate backoff retry) briefly drives
// the active-session count to 0; deferring the stop a few seconds stops us
// thrashing start/stopBackgroundRunning on every reconnect bounce.
const STOP_DEBOUNCE_MS: number = 3000;





class KeepAliveController {
  // Number of live sessions currently requesting background protection.
  private activeCount: number = 0;
  // The continuous task is confirmed running.
  private running: boolean = false;
  // A startBackgroundRunning() call is in flight (its getWantAgent + start await).
  private starting: boolean = false;
  // Debounced stop timer handle (-1 == none pending).
  private stopTimer: number = -1;
  // Guards the one-time suspend/cancel subscription.
  private eventsSubscribed: boolean = false;
  // Last context that requested protection; the same app context stops the task.
  private lastContext: common.UIAbilityContext | null = null;

  // A session became live: the Fusion Agent connected, SSH connected, or the
  // native local PTY started (the native driver reports a started PTY as
  // connected, so this one edge covers all three transports). Idempotent per
  // session -- the caller holds a keepAliveHeld flag so this never double-counts.
  noteSessionActive(context: common.UIAbilityContext): void {
    this.lastContext = context;
    this.activeCount += 1;
    if (this.activeCount === 1) {
      this.cancelPendingStop();
      this.ensureRunning(context);
    }
  }

  // A previously-live session dropped, was closed, or was handed off to another
  // window. Guarded so a stray release can never drive the count negative (which
  // keeps the accounting self-healing even after a system cancel reset).
  noteSessionInactive(): void {
    if (this.activeCount <= 0) {
      return;
    }
    this.activeCount -= 1;
    if (this.activeCount === 0) {
      this.scheduleStop();
    }
  }

  private ensureRunning(context: common.UIAbilityContext): void {
    if (this.running || this.starting) {
      return;
    }
    this.starting = true;
    void this.startBackgroundRunning(context);
  }

  private async startBackgroundRunning(context: common.UIAbilityContext): Promise<void> {
    try {
      const wants: Array<Want> = [{
        bundleName: context.abilityInfo.bundleName,
        abilityName: context.abilityInfo.name
      }];
      const info: wantAgent.WantAgentInfo = {
        wants: wants,
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const agentObj: WantAgent = await wantAgent.getWantAgent(info);
      await backgroundTaskManager.startBackgroundRunning(
        context, backgroundTaskManager.BackgroundMode.TASK_KEEPING, agentObj);
      this.running = true;
      hilog.info(DOMAIN, TAG, 'continuous task started (taskKeeping)');
    } catch (err) {
      // Grant refused / platform unsupported: keep current state, no protection.
      this.running = false;
      hilog.warn(DOMAIN, TAG, 'startBackgroundRunning failed, degrading: %{public}s',
        JSON.stringify(err));
    }
    this.starting = false;
    // If every session dropped while the start was in flight, honour the stop
    // that scheduleStop() could not act on until the task actually existed.
    if (this.activeCount === 0 && this.running) {
      this.scheduleStop();
    }
  }

  private scheduleStop(): void {
    this.cancelPendingStop();
    this.stopTimer = setTimeout(() => {
      this.stopTimer = -1;
      if (this.activeCount === 0) {
        void this.stopBackgroundRunning();
      }
    }, STOP_DEBOUNCE_MS) as number;
  }

  private cancelPendingStop(): void {
    if (this.stopTimer < 0) {
      return;
    }
    clearTimeout(this.stopTimer);
    this.stopTimer = -1;
  }

  private async stopBackgroundRunning(): Promise<void> {
    if (this.starting) {
      // Start still resolving; retry the stop once it settles.
      this.scheduleStop();
      return;
    }
    if (!this.running) {
      return;
    }
    const context = this.lastContext;
    if (!context) {
      this.running = false;
      return;
    }
    try {
      await backgroundTaskManager.stopBackgroundRunning(context);
      hilog.info(DOMAIN, TAG, 'continuous task stopped');
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'stopBackgroundRunning failed: %{public}s', JSON.stringify(err));
    }
    this.running = false;
  }

}

// Module-level singleton shared across every window in the multiton VM.
export const keepAlive: KeepAliveController = new KeepAliveController();
