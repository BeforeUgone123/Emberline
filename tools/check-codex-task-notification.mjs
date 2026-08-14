import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const index = await readFile('entry/src/main/ets/pages/Index.ets', 'utf8');
const nativeBridge = await readFile('libghostty_ohos/src/main/cpp/napi_init.cpp', 'utf8');
const readme = await readFile('README.md', 'utf8');

function extractFunction(source, signature) {
  const start = source.indexOf(signature);
  assert.notEqual(start, -1, `missing function signature: ${signature}`);
  const braceStart = source.indexOf('{', start);
  assert.notEqual(braceStart, -1, `missing function body: ${signature}`);

  let depth = 0;
  for (let index = braceStart; index < source.length; index += 1) {
    const char = source[index];
    if (char === '{') {
      depth += 1;
    } else if (char === '}') {
      depth -= 1;
      if (depth === 0) {
        return source.slice(start, index + 1);
      }
    }
  }

  assert.fail(`unterminated function body: ${signature}`);
}

const captureOsc9 = extractFunction(nativeBridge, 'void CaptureOsc9Notifications(');
const rememberOsc9Tail = extractFunction(nativeBridge, 'void RememberOsc9PrefixTailLocked(');
const handleTerminal = extractFunction(index, 'private handleTerminalNotification(');
const enableAndTest = extractFunction(index, 'private async enableAndTestTaskNotification(');
const publishTerminal = extractFunction(index, 'private async publishTerminalNotification(');
const publishTask = extractFunction(index, 'private async publishTaskNotification(');

// PTY and WebSocket reads can split OSC 9 anywhere, including inside the
// prefix or immediately before BEL/ST. A completion event must survive that.
assert.match(nativeBridge, /static constexpr size_t kMaxOsc9SequenceBytes = \d+;/);
assert.match(nativeBridge, /std::mutex m_osc9Mutex;/);
assert.match(nativeBridge, /std::string m_pendingOsc9Sequence;/);
assert.match(captureOsc9, /std::lock_guard<std::mutex> parserLock\(m_osc9Mutex\);/);
assert.match(
  captureOsc9,
  /if \(!m_pendingOsc9Sequence\.empty\(\)\) \{[\s\S]*?joinedData = std::move\(m_pendingOsc9Sequence\);[\s\S]*?joinedData \+= data;[\s\S]*?scanData = &joinedData;/,
  'OSC 9 parser must prepend the partial sequence saved from the prior output chunk'
);
assert.match(
  captureOsc9,
  /if \(end == std::string::npos\) \{[\s\S]*?m_pendingOsc9Sequence = scanData->substr\(start\);[\s\S]*?return;/,
  'OSC 9 parser must retain an unterminated Codex completion notification'
);
assert.match(captureOsc9, /scanData->find\('\\x07', payloadStart\)/);
assert.match(captureOsc9, /scanData->find\("\\x1b\\\\", payloadStart\)/);
assert.match(
  captureOsc9,
  /m_pendingOsc9Sequence\.size\(\) > kMaxOsc9SequenceBytes[\s\S]*?m_pendingOsc9Sequence\.clear\(\)/,
  'an unterminated notification must not grow the cross-chunk carry buffer without bound'
);
assert.match(captureOsc9, /RememberOsc9PrefixTailLocked\(\*scanData\);/);
assert.match(rememberOsc9Tail, /osc9Prefix\.compare\(0, len, data, index, len\) == 0/);
assert.match(captureOsc9, /payload\.rfind\("4;", 0\) == 0/);
assert.match(captureOsc9, /m_pendingNotifications\.push_back\(std::move\(payload\)\);/);

// Codex does not promise to emit a terminal bell unless its TUI notification
// channel is enabled. The in-app setup must expose the official config that
// makes every completed turn emit OSC 9, even while Codex believes it is focused.
assert.match(index, /const CODEX_TASK_NOTIFICATION_CONFIG: string =/);
assert.match(index, /notifications = \["agent-turn-complete"\]/);
assert.match(index, /notification_method = "osc9"/);
assert.match(index, /notification_condition = "always"/);
assert.match(index, /this\.buildGroupTitle\('Codex 任务提醒'\)/u);
assert.match(index, /this\.buildGuideCommand\(CODEX_TASK_NOTIFICATION_CONFIG\)/);
assert.match(index, /保存配置后先退出当前 Codex/u);
assert.match(index, /this\.buildGuideCommand\('codex resume --last'\)/);
assert.match(index, /const CODEX_TMUX_NOTIFICATION_SETUP_COMMAND: string =/);
assert.match(index, /set -g allow-passthrough on/);
assert.match(index, /this\.buildGuideCommand\(CODEX_TMUX_NOTIFICATION_SETUP_COMMAND\)/);
assert.match(index, /const CODEX_TASK_NOTIFICATION_TEST_COMMAND: string =/);
assert.match(index, /printf '\\\\033Ptmux;/);
assert.match(index, /printf '\\\\033\]9;/);
assert.match(index, /this\.buildGuideCommand\(CODEX_TASK_NOTIFICATION_TEST_COMMAND\)/);

// `notification_condition = "always"` must stay meaningful after the event
// reaches Emberline: a foreground active tab shows a local toast, while every
// accepted completion still enters the system-notification path for watches.
assert.match(handleTerminal, /getPromptAction\(\)\.showToast\(/);
assert.match(handleTerminal, /this\.publishTerminalNotification\(session, text\)/);
assert.doesNotMatch(
  handleTerminal,
  /if \(session\.id === this\.activeSessionId && !this\.appInBackground\) \{[\s\S]*?return;/,
  'the active foreground tab must not silently discard a Codex completion event'
);

// Permission prompting is a foreground, user-initiated diagnostics action.
// A background completion may publish, but must never try to open a permission
// dialog after the app has already been hidden.
assert.match(enableAndTest, /const context = this\.context;/);
assert.match(enableAndTest, /notificationManager\.requestEnableNotification\(context\)/);
assert.match(enableAndTest, /this\.publishTaskNotification\(/);
assert.match(enableAndTest, /notificationManager\.getActiveNotificationCount\(\)/);
assert.match(enableAndTest, /getPromptAction\(\)\.showToast\(/);
assert.match(publishTerminal, /notificationManager\.isNotificationEnabled\(\)/);
assert.match(publishTerminal, /this\.publishTaskNotification\(/);
assert.match(publishTerminal, /session\.surfaceSeq/);
assert.doesNotMatch(publishTerminal, /requestEnableNotification/);
assert.match(index, /Button\(this\.taskNotificationActionLabel\(\)\)[\s\S]*?this\.enableAndTestTaskNotification\(\);/s);
assert.match(
  publishTask,
  /notificationManager\.addSlot\(notificationManager\.SlotType\.SERVICE_INFORMATION\)/,
  'task notifications must create a visible high-level service-reminder slot'
);
assert.match(
  publishTask,
  /notificationSlotType:\s*notificationManager\.SlotType\.SERVICE_INFORMATION/,
  'task notifications must not fall back to the silent UNKNOWN_TYPE slot'
);
assert.match(index, /error\.code === 1600004/);
assert.match(index, /error\.code === 1600005/);

// Keep setup reproducible outside the app as well as in Help & Diagnostics.
assert.match(readme, /notification_method = "osc9"/);
assert.match(readme, /notification_condition = "always"/);
assert.match(readme, /codex resume --last/);
assert.match(readme, /set -g allow-passthrough on/);
assert.match(readme, /终端输出 → OSC 9 解析 → Emberline 系统通知/u);

console.log('check-codex-task-notification: OK');
