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
//   - on('continuousTaskActive', Callback<ContinuousTaskActiveInfo>)   -- API 20+
//     All three events are available in the configured API 23 SDK.

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
  // A stopBackgroundRunning() call is in flight. A reconnect can make
  // activeCount positive while this await is pending, so its completion must
  // restart protection instead of leaving a live PTY unprotected.
  private stopping: boolean = false;
  // Monotonic guard for async start/stop completions and system callbacks.
  private transitionGeneration: number = 0;
  // Debounced stop timer handle (-1 == none pending).
  private stopTimer: number = -1;
  private cancelSubscribed: boolean = false;
  private suspendSubscribed: boolean = false;
  private activeSubscribed: boolean = false;
  // Last live window context is the preferred owner for a retry. The context
  // that successfully STARTED the task is kept separately and owns the stop.
  private lastContext: common.UIAbilityContext | null = null;
  private ownerContext: common.UIAbilityContext | null = null;
  // Removing the system notification is an explicit user cancellation. Do not
  // recreate it behind the user's back until a fresh 0 -> 1 session edge.
  private retrySuppressedByUser: boolean = false;

  private readonly continuousTaskCancelListener =
    (info: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
      this.transitionGeneration += 1;
      this.running = false;
      this.starting = false;
      this.stopping = false;
      this.ownerContext = null;
      this.retrySuppressedByUser =
        info.reason === backgroundTaskManager.ContinuousTaskCancelReason.USER_CANCEL ||
        info.reason === backgroundTaskManager.ContinuousTaskCancelReason.USER_CANCEL_REMOVE_NOTIFICATION;
      hilog.warn(DOMAIN, TAG,
        'continuous task cancelled id=%{public}d reason=%{public}d active=%{public}d',
        info.id, info.reason, this.activeCount);
    };

  private readonly continuousTaskSuspendListener =
    (info: backgroundTaskManager.ContinuousTaskSuspendInfo): void => {
      this.running = true;
      hilog.warn(DOMAIN, TAG,
        'continuous task suspend changed id=%{public}d suspended=%{public}s reason=%{public}d',
        info.continuousTaskId, info.suspendState ? 'true' : 'false', info.suspendReason);
    };

  private readonly continuousTaskActiveListener =
    (info: backgroundTaskManager.ContinuousTaskActiveInfo): void => {
      // Do not invalidate an explicit stop that is already in flight: its
      // completion remains the newest truth even if a delayed active event
      // arrives first.
      this.running = true;
      this.ownerContext = this.ownerContext ?? this.lastContext;
      hilog.info(DOMAIN, TAG, 'continuous task active id=%{public}d', info.id);
    };

  // A session became live: the Fusion Agent connected, SSH connected, or the
  // native local PTY started (the native driver reports a started PTY as
  // connected, so this one edge covers all three transports). Idempotent per
  // session -- the caller holds a keepAliveHeld flag so this never double-counts.
  noteSessionActive(context: common.UIAbilityContext): void {
    this.lastContext = context;
    this.subscribeSystemEvents();
    if (this.activeCount === 0) {
      this.retrySuppressedByUser = false;
    }
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
      this.retrySuppressedByUser = false;
      this.scheduleStop();
    }
  }

  // Ability lifecycle reconciliation covers two otherwise silent cases: the
  // initial request failed, or the system cancelled it during a long lock while
  // the WebSocket still looked connected. Background entry requests before the
  // scheduling budget disappears; foreground entry retries system cancellation.
  noteAppBackgrounded(context: common.UIAbilityContext): void {
    this.reconcileLifecycle(context);
  }

  noteAppForegrounded(context: common.UIAbilityContext): void {
    this.reconcileLifecycle(context);
  }

  private reconcileLifecycle(context: common.UIAbilityContext): void {
    this.lastContext = context;
    this.subscribeSystemEvents();
    if (this.activeCount > 0) {
      this.cancelPendingStop();
      this.ensureRunning(context);
    }
  }

  private ensureRunning(context: common.UIAbilityContext): void {
    if (this.activeCount <= 0 || this.retrySuppressedByUser ||
      this.running || this.starting || this.stopping) {
      return;
    }
    this.starting = true;
    const generation: number = ++this.transitionGeneration;
    void this.startBackgroundRunning(context, generation);
  }

  private async startBackgroundRunning(context: common.UIAbilityContext,
    generation: number): Promise<void> {
    let started: boolean = false;
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
      started = true;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'startBackgroundRunning failed, degrading: %{public}s',
        JSON.stringify(err));
    }
    if (generation !== this.transitionGeneration) {
      return;
    }
    this.starting = false;
    this.running = started || this.running;
    this.ownerContext = this.running ? context : null;
    if (started) {
      hilog.info(DOMAIN, TAG, 'continuous task started (taskKeeping)');
    }
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
    if (this.stopping || !this.running) {
      return;
    }
    const context = this.ownerContext;
    if (!context) {
      this.running = false;
      return;
    }
    this.stopping = true;
    const generation: number = ++this.transitionGeneration;
    let stopped: boolean = false;
    try {
      await backgroundTaskManager.stopBackgroundRunning(context);
      stopped = true;
      hilog.info(DOMAIN, TAG, 'continuous task stopped');
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'stopBackgroundRunning failed: %{public}s', JSON.stringify(err));
    }
    if (generation !== this.transitionGeneration) {
      return;
    }
    this.stopping = false;
    this.running = !stopped;
    if (stopped) {
      this.ownerContext = null;
    }
    // CR-011: a reconnect may have landed while stopBackgroundRunning awaited.
    // The stop belongs to the old generation; immediately protect the live
    // session with the most recent window context.
    if (this.activeCount > 0 && this.lastContext) {
      this.ensureRunning(this.lastContext);
    }
  }

  private subscribeSystemEvents(): void {
    if (!this.cancelSubscribed) {
      try {
        backgroundTaskManager.on('continuousTaskCancel', this.continuousTaskCancelListener);
        this.cancelSubscribed = true;
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'continuousTaskCancel subscription failed: %{public}s',
          JSON.stringify(err));
      }
    }
    if (!this.suspendSubscribed) {
      try {
        backgroundTaskManager.on('continuousTaskSuspend', this.continuousTaskSuspendListener);
        this.suspendSubscribed = true;
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'continuousTaskSuspend subscription failed: %{public}s',
          JSON.stringify(err));
      }
    }
    if (!this.activeSubscribed) {
      try {
        backgroundTaskManager.on('continuousTaskActive', this.continuousTaskActiveListener);
        this.activeSubscribed = true;
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'continuousTaskActive subscription failed: %{public}s',
          JSON.stringify(err));
      }
    }
  }
}

// Module-level singleton shared across every window in the multiton VM.
export const keepAlive: KeepAliveController = new KeepAliveController();
