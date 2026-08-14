// entry/src/main/ets/common/AppResumeEvents.ets
//
// Process-global "we may have just come back from a suspension edge" signal
// for socket-owning transports (the Fusion Agent driver). Two sources:
//
//   1. EntryAbility publishes a real background -> foreground edge (lock
//      screen -> unlock). Screen lock can freeze the JS thread and its sockets
//      without ever raising close/error, so a stale "connected" flag is not
//      proof of life.
//   2. NetworkKit netAvailable, i.e. network recovery/roaming.
//
// Subscribers run their own cheap checks (probe ping with a short deadline, or
// an immediate reconnect when a backoff retry is already pending), so
// publishing stays synchronous and side-effect free. All platform calls are
// wrapped in try/catch and degrade to "foreground events only", mirroring the
// KeepAliveManager philosophy.
//
// The app is multiton and shares one ArkTS VM; every window's drivers
// subscribe here and each probes only its own socket.

import { connection } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'FusionTermResumeEvents';

type ResumeListener = () => void;

class AppResumeEventsController {
  private listeners: Set<ResumeListener> = new Set();
  private netConnection: connection.NetConnection | null = null;

  subscribe(listener: ResumeListener): void {
    const wasIdle: boolean = this.listeners.size === 0;
    this.listeners.add(listener);
    if (wasIdle) {
      this.startNetworkWatch();
    }
  }

  unsubscribe(listener: ResumeListener): void {
    this.listeners.delete(listener);
    if (this.listeners.size === 0) {
      this.stopNetworkWatch();
    }
  }

  // EntryAbility reports a real background -> foreground edge here.
  publishForeground(): void {
    this.publish();
  }

  private publish(): void {
    this.listeners.forEach((listener: ResumeListener) => {
      try {
        listener();
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'resume listener failed: %{public}s', JSON.stringify(err));
      }
    });
  }

  private startNetworkWatch(): void {
    if (this.netConnection) {
      return;
    }
    try {
      const net: connection.NetConnection = connection.createNetConnection();
      void net.register()
        .then(() => {
          net.on('netAvailable', (_info: connection.NetHandle) => {
            this.publish();
          });
          this.netConnection = net;
        })
        .catch((err: Object) => {
          hilog.warn(DOMAIN, TAG, 'network watch registration failed: %{public}s', JSON.stringify(err));
        });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'network watch unavailable: %{public}s', JSON.stringify(err));
    }
  }

  private stopNetworkWatch(): void {
    const net: connection.NetConnection | null = this.netConnection;
    this.netConnection = null;
    if (!net) {
      return;
    }
    try {
      void net.unregister()
        .catch((err: Object) => {
          hilog.warn(DOMAIN, TAG, 'network watch teardown failed: %{public}s', JSON.stringify(err));
        });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'network watch teardown failed: %{public}s', JSON.stringify(err));
    }
  }
}

// Module-level singleton shared across every window in the multiton VM.
export const appResumeEvents: AppResumeEventsController = new AppResumeEventsController();
