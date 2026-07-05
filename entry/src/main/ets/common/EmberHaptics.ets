// entry/src/main/ets/common/EmberHaptics.ets
//
// The single collection point for every haptic call (honours the "haptics go
// through a util" architecture rule). Only discrete "done / fail / boundary"
// moments get one preset pulse; continuous animations never buzz — no
// continuous or long vibrations. Every helper swallows unsupported-device and
// permission errors so a missing vibrator never breaks the feature it decorates.
import { vibrator } from '@kit.SensorServiceKit';

async function fire(effectId: string): Promise<void> {
  try {
    const supported: boolean = await vibrator.isSupportEffect(effectId);
    if (supported) {
      await vibrator.startVibration(
        { type: 'preset', effectId: effectId, count: 1, intensity: 60 },
        { usage: 'touch' }
      );
    }
  } catch (_err) {
    // Some devices have no vibrator, or the VIBRATE grant is missing; the
    // decorated action still succeeds silently.
  }
}

export const hapticCopy: () => void = () => { void fire('haptic.effect.sharp'); };       // 复制成功(沿用现有)
export const hapticIgnite: () => void = () => { void fire('haptic.notice.success'); };    // 连接建立,配「点燃」
export const hapticDisconnect: () => void = () => { void fire('haptic.effect.hard'); };   // 断开,配「熄灭」(一次厚重)
export const hapticClose: () => void = () => { void fire('haptic.effect.soft'); };        // 标签关闭
export const hapticBoundary: () => void = () => { void fire('haptic.effect.sharp'); };    // 字号/滚动到边界
