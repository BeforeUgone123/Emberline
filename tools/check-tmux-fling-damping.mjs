import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const napi = await readFile('libghostty_ohos/src/main/cpp/napi_init.cpp', 'utf8');

function readFloat(name) {
  const match = napi.match(new RegExp(`constexpr float ${name} = ([0-9.]+)f;`));
  assert.ok(match, `missing ${name}`);
  return Number(match[1]);
}

const maxVelocity = readFloat('FLING_MAX_VELOCITY');
const wheelScale = readFloat('TRACKED_WHEEL_FLING_VELOCITY_SCALE');
const wheelDecay = readFloat('TRACKED_WHEEL_FLING_DECAY_PER_SECOND');
const wheelStop = readFloat('TRACKED_WHEEL_FLING_STOP_VELOCITY');

assert.ok(wheelScale > 0 && wheelScale <= 0.25,
  'tmux wheel fling must retain a short tail without inheriting full local-scroll velocity');
assert.ok(wheelDecay >= 8.0,
  'discrete wheel inertia must decay substantially faster than pixel scrollback inertia');
assert.ok(wheelStop >= 100.0,
  'low-speed wheel tails should stop before banking another tmux wheel step');

// Integral of v0*exp(-k*t) is v0/k. Keep the absolute worst-case tail near
// 200 physical pixels; at normal terminal cell heights this is only a handful
// of wheel events, rather than the old 150+ event upper bound.
assert.ok(maxVelocity * wheelScale / wheelDecay <= 225.0,
  'worst-case tracked-wheel fling tail is still too long');

const startFling = napi.match(/bool StartFling\(float velocityY[\s\S]*?\n    void CancelFling\(\)/)?.[0] ?? '';
assert.match(startFling,
  /const float adjusted = asWheel\s*\? clamped \* TRACKED_WHEEL_FLING_VELOCITY_SCALE\s*: clamped;/,
  'only mouse-tracking wheel fling should receive the reduced release velocity');
assert.match(startFling, /m_flingVelocityY = adjusted;/);

const renderLoop = napi.match(/if \(m_flingActive\) \{[\s\S]*?\n                const bool shouldResize/)?.[0] ?? '';
assert.match(renderLoop,
  /const float decayPerSecond = m_flingAsWheel\s*\? TRACKED_WHEEL_FLING_DECAY_PER_SECOND\s*: FLING_DECAY_PER_SECOND;/,
  'tmux wheel tail must use its own faster decay');
assert.match(renderLoop,
  /const float stopVelocity = m_flingAsWheel\s*\? TRACKED_WHEEL_FLING_STOP_VELOCITY\s*: FLING_STOP_VELOCITY;/,
  'tmux wheel tail must stop at a mode-specific speed');
assert.match(renderLoop, /std::exp\(-decayPerSecond \* dt\)/);
assert.match(renderLoop, /std::abs\(m_flingVelocityY\) < stopVelocity/);

assert.match(napi, /StartFling\(m_touchVelocityY, true, touchEvent\.x, touchEvent\.y\)/,
  'touch swipes in tmux must still get the shortened wheel fling');
assert.match(napi, /StartFling\(m_touchVelocityY, false, touchEvent\.x, touchEvent\.y\)/,
  'ordinary local scrollback must retain its existing pixel fling');

console.log('tmux fling damping checks passed.');
