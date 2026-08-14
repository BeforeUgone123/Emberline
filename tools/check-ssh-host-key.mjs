import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

// CR-001/CR-002/CR-010 + CR-006 (SSH half): the SSH transport must pin a
// libssh2 revision containing every applicable CVE fix, authenticate the
// server via SHA-256 host-key fingerprint + TOFU before credentials leave the
// device, initialize libssh2 once per process, and never silently discard
// input on a nonblocking channel.

const fetchScript = await readFile('tools/fetch-third-party.sh', 'utf8');
const hostKeyHeaderRaw = await readFile('entry/src/main/cpp/ssh/ssh_host_key.h', 'utf8');
const sessionRaw = await readFile('entry/src/main/cpp/ssh/ssh_session.cpp', 'utf8');
const sessionHeader = await readFile('entry/src/main/cpp/ssh/ssh_session.h', 'utf8');
const hostKeyStore = await readFile('entry/src/main/ets/settings/HostKeyStore.ets', 'utf8');

// Call-site assertions must see code, not the comments that explain why the
// old calls (libssh2_exit, the lossy EAGAIN break) are gone.
const stripLineComments = (text) => text.replace(/\/\/[^\n]*/g, '');
const hostKeyHeader = stripLineComments(hostKeyHeaderRaw);
const session = stripLineComments(sessionRaw);

// --- CR-001: libssh2 is pinned to an immutable, verified master commit ------
// No release contains the fixes (latest is 1.11.1), so the pin must be the
// verified full SHA, not a movable tag.
assert.match(fetchScript, /LIBSSH2_PIN="4f271a3b8ebbcf204443d456210a6d6568682f6c"/,
  'libssh2 must be pinned to the verified master commit, not a movable tag');
assert.doesNotMatch(fetchScript, /libssh2-1\.11\.1/,
  'the CVE-affected 1.11.1 tag must stay unpinned');
for (const fix of [
  '97acf3dfda80c91c3a8c9f2372546301d4a1a7a8', // CVE-2026-55200
  '17626857d20b3c9a1addfa45979dadcee1cd84a4', // CVE-2026-55199
  '42e33d81577ed4b95d4b4f6f845e5ee8efe5eeb4' // CVE-2026-66035 / GHSA-6c79-444r-wx26
]) {
  assert.ok(fetchScript.includes(fix), `fetch script must name required fix commit ${fix}`);
}
assert.match(fetchScript, /merge-base --is-ancestor/,
  'the fetch must prove the pinned tree contains every required fix commit');
assert.match(fetchScript, /rev-parse HEAD/,
  'the fetch must verify the checked-out HEAD equals the pinned commit');

// --- CR-010: libssh2 global init happens once per process --------------------
assert.match(hostKeyHeader, /inline bool EnsureLibssh2ProcessInit\(std::string& error\)/,
  'process-wide init helper must exist for both SSH and SFTP workers');
assert.match(hostKeyHeader, /std::call_once\(once/,
  'libssh2_init must run under std::call_once');
assert.doesNotMatch(hostKeyHeader, /libssh2_exit\(\)/,
  'libssh2_exit must never run per session (frees shared global state)');
assert.match(session, /if \(!EnsureLibssh2ProcessInit\(error\)\)/,
  'SSHSession::connect must use the once-only process init');
assert.doesNotMatch(session, /libssh2_init\(/,
  'ssh_session.cpp must not call libssh2_init directly');
assert.doesNotMatch(session, /libssh2_exit\(\)/,
  'ssh_session.cpp must not call libssh2_exit on any path');

// --- CR-002: server authentication before credentials, shared verifier -------
assert.match(hostKeyHeader, /libssh2_hostkey_hash\(session, LIBSSH2_HOSTKEY_HASH_SHA256\)/,
  'the host key SHA-256 fingerprint must come from libssh2_hostkey_hash');
assert.match(hostKeyHeader, /"SHA256:"/,
  'fingerprints use the OpenSSH-style SHA256: display format');
assert.match(hostKeyHeader, /inline bool SSHVerifyHostKey\(/,
  'the verifier must be inline so SSH and SFTP translation units share one trust store');
assert.match(hostKeyHeader, /static SSHHostKeyTrustStore& Instance\(\)/,
  'the TOFU trust store must be a process-wide singleton');
assert.match(hostKeyHeader, /case SSHHostKeyTrust::Unknown:[\s\S]*?Trust\(host, port, fingerprint\)/,
  'first contact is recorded then accepted (trust-on-first-use)');
assert.match(hostKeyHeader, /case SSHHostKeyTrust::Mismatch:[\s\S]*?return false;/,
  'a changed host key must fail the connection');
assert.match(hostKeyHeader, /FingerprintEquals[\s\S]*?diff \|=/,
  'fingerprint comparison must be constant-time');
assert.match(hostKeyHeader, /void SetStorageFile\(const std::string& path\)/,
  'the trust store needs the durable-storage hook for the app files dir');
assert.match(hostKeyHeader, /bool Forget\(const std::string& host, int port\)/,
  'the trust store needs Forget() so a legitimate host rekey can recover');

assert.match(session, /#include "ssh_host_key\.h"/,
  'SSHSession must use the shared host-key verifier');
const handshakeAt = session.indexOf('libssh2_session_handshake(m_session, m_socketFd)');
const verifyAt = session.indexOf('SSHVerifyHostKey(m_session, host, port, error)');
const authAt = session.indexOf('libssh2_userauth_password');
assert.ok(handshakeAt > 0 && verifyAt > handshakeAt,
  'host-key verification runs only after the handshake produced a key');
assert.ok(authAt > verifyAt,
  'password auth must not run before host-key verification (credentials leak to MITM)');

// --- CR-006 (SSH half): lossless nonblocking channel writes ------------------
assert.match(sessionHeader, /std::deque<std::string> m_pendingWrites;/,
  'channel writes must land in an ordered pending-byte queue');
assert.match(sessionHeader, /size_t m_pendingWriteOffset;/,
  'partial head-chunk writes must be tracked with an offset, not dropped');
assert.match(sessionHeader, /bool m_writeFailed;/,
  'a write-failure latch must close the queue for later writes');
assert.match(session, /m_pendingWrites\.emplace_back\(data, len\);/,
  'write() must queue input before touching the channel');
assert.match(session, /m_pendingWrites\.pop_front\(\);/,
  'drain must consume queued chunks in FIFO order');
assert.match(session, /if \(written == LIBSSH2_ERROR_EAGAIN\) \{\s*return true;/,
  'EAGAIN must keep the remaining bytes queued for the writable-ready pass');
assert.doesNotMatch(session, /written == LIBSSH2_ERROR_EAGAIN\) \{\s*break;/,
  'the old lossy EAGAIN break that silently discarded input must stay removed');
assert.match(session, /FD_SET\(m_socketFd, &writefds\)/,
  'readLoop must watch socket writability while the queue is non-empty');
assert.match(session, /select\(m_socketFd \+ 1, &readfds, wantWrite \? &writefds : nullptr/,
  'drain must be driven by writable readiness, not blind retry');
assert.match(session, /"\\r\\n\[SSH write failed\]\\r\\n"/,
  'write failure must surface through the existing output callback');
assert.match(session, /m_writeFailed = true;\s*emitFailure = true;/,
  'a hard channel write error must latch the failure and notify once');
assert.match(session, /m_pendingWrites\.clear\(\);/,
  'disconnect() must close and clear the pending queue');

// --- ArkTS TOFU trust store (Preferences) ------------------------------------
assert.match(hostKeyStore, /const STORE_NAME: string = 'fusionterm_host_keys';/);
assert.match(hostKeyStore, /preferences\.getPreferences\(context, STORE_NAME\)/);
assert.match(hostKeyStore, /async lookup\(host: string, port: number\): Promise<string>/);
assert.match(hostKeyStore, /async remember\(host: string, port: number, fingerprint: string\): Promise<void>/);
assert.match(hostKeyStore, /async forget\(host: string, port: number\): Promise<void>/);
assert.ok(hostKeyStore.includes('SHA256:[A-Za-z0-9+/]+'),
  'HostKeyStore must parse the presented fingerprint out of verification errors');
assert.doesNotMatch(hostKeyStore, /password/i,
  'HostKeyStore persists trust records only — never credentials');

console.log('check-ssh-host-key: ok');
