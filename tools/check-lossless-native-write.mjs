import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

// CR-006 (local PTY half): nonblocking writes must never silently discard
// unwritten bytes. The local write path is an ordered pending-byte queue
// drained by writable readiness (poll/POLLOUT); queue closure and transport
// failures are propagated explicitly to ArkTS instead of dropping the tail.
const driver = await readFile('entry/src/main/cpp/terminal_driver.cpp', 'utf8');

// Ordered pending-byte queue backs every local write.
assert.match(driver, /#include <deque>/,
  'lossless local write path should keep its ordered queue header explicit');
assert.match(driver, /std::deque<std::string> m_pendingWrites;/,
  'local writes should land in an ordered pending-byte queue');
assert.match(driver, /m_pendingWrites\.emplace_back\(data\);/,
  'Write() should append input to the pending queue before touching the fd');
assert.match(driver, /m_pendingWrites\.pop_front\(\);/,
  'drain should consume queued chunks in FIFO order');
assert.match(driver, /size_t m_pendingWriteOffset = 0;/,
  'partial head-chunk writes should be tracked with an offset, not dropped');

// Drain keeps bytes queued on backpressure; only hard errors fail.
assert.match(driver, /bool DrainPendingWritesLocked\(int writeFd, std::string& error\)/,
  'drain should report hard failures to the caller instead of breaking silently');
assert.match(driver, /errno == EAGAIN \|\| errno == EWOULDBLOCK/,
  'EAGAIN/EWOULDBLOCK must keep the remaining bytes queued');
assert.match(driver, /error = strerror\(errno\);/,
  'hard write errors should be captured for explicit propagation');

// Writable-readiness-driven drain thread lifecycle.
assert.match(driver, /#include <poll\.h>/,
  'drain should be driven by poll() writable readiness');
assert.match(driver, /void LocalWriteLoop\(\)/,
  'a drain loop should flush the pending queue after backpressure');
assert.match(driver, /pfd\.events = POLLOUT;/,
  'drain should wait for POLLOUT writable readiness');
assert.match(driver, /poll\(&pfd, 1, 25\)/,
  'drain poll should stay responsive so Stop() can join promptly');
assert.match(driver, /pfd\.revents & \(POLLERR \| POLLHUP \| POLLNVAL\)/,
  'hangup/error poll events must be treated as explicit write failure');
assert.match(driver, /m_localWriteThread = std::thread\(&FusionTerminalDriver::LocalWriteLoop, this\);/,
  'StartLocal should start the write-drain thread next to the read thread');
assert.match(driver, /if \(m_localWriteThread\.joinable\(\)\) \{\s*m_localWriteThread\.join\(\);\s*\}/,
  'Stop() should join the drain thread before closing the descriptors');

// Queue closure on Stop(): leftover bytes are dropped exactly once, after the
// drain thread joined, and later writes are rejected instead of queued to die.
assert.match(driver, /m_pendingWrites\.clear\(\);/,
  'Stop() should close and clear the pending queue');
assert.match(driver, /m_writeFailed = false;/,
  'Stop() should reset the write-failure latch for the next session');

// No bare tail drop: the lossy helper is gone and writes are never cut short
// by a plain break on error.
assert.doesNotMatch(driver, /WriteToLocalPtyLocked/,
  'the lossy write helper that discarded the unwritten tail must stay removed');

// Explicit failure propagation: failure latch, terminal-visible notice through
// the existing output callback, and a boolean acceptance result at the NAPI
// boundary (writeInput) — no new large interface.
assert.match(driver, /bool m_writeFailed = false;/,
  'a write-failure latch should close the queue for later writes');
assert.match(driver, /EmitOutput\("\\r\\n\[local PTY write failed\]\\r\\n"\)/,
  'write failure should reach ArkTS through the existing output callback');
assert.match(driver, /return m_sshSession->write\(data\.c_str\(\), data\.size\(\)\);/,
  'the SSH branch should forward its acceptance result instead of discarding it');

const writeInputBody = driver.match(/napi_value WriteInput\(napi_env env, napi_callback_info info\)\n\{[\s\S]*?\n\}/)?.[0] ?? '';
assert.match(writeInputBody, /accepted = session->Write\(/,
  'writeInput should capture the acceptance result of the write');
assert.match(writeInputBody, /napi_get_boolean\(env, accepted, &result\);/,
  'writeInput should return the acceptance boolean to ArkTS');
assert.doesNotMatch(writeInputBody, /return ReturnUndefined\(env\);/,
  'writeInput must not hide write rejection behind an undefined return');
