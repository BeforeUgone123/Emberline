#include "ssh_session.h"
#include <libssh2.h>
#include <hilog/log.h>
#include <sys/socket.h>
#include <netdb.h>
#include <unistd.h>
#include <cstring>
#include <cerrno>
#include <sys/select.h>
#include "ssh_host_key.h"

#undef LOG_TAG
#define LOG_TAG "SSHSession"

namespace {
bool SetRemoteEnv(_LIBSSH2_CHANNEL* channel, const char* key, const char* value)
{
    if (!channel || !key || !value) {
        return false;
    }
    const int rc = libssh2_channel_setenv_ex(
        channel,
        key,
        static_cast<unsigned int>(std::strlen(key)),
        value,
        static_cast<unsigned int>(std::strlen(value)));
    return rc == 0;
}
}

SSHSession::SSHSession()
    : m_socketFd(-1), m_session(nullptr), m_channel(nullptr),
      m_connected(false), m_running(false),
      m_pendingWriteOffset(0), m_writeFailed(false) {}

SSHSession::~SSHSession() {
    disconnect();
}

bool SSHSession::connect(const std::string& host, int port, const std::string& user,
                         const std::string& password, int cols, int rows, std::string& error) {
    disconnect();

    // CR-010: one process-wide libssh2 init, never paired with a per-session
    // libssh2_exit() that would free global state other sessions still use.
    if (!EnsureLibssh2ProcessInit(error)) {
        return false;
    }

    struct addrinfo hints {};
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;

    struct addrinfo* result = nullptr;
    const std::string portString = std::to_string(port);
    int rc = getaddrinfo(host.c_str(), portString.c_str(), &hints, &result);
    if (rc != 0 || !result) {
        error = "Failed to resolve host";
        return false;
    }

    for (struct addrinfo* it = result; it; it = it->ai_next) {
        m_socketFd = socket(it->ai_family, it->ai_socktype, it->ai_protocol);
        if (m_socketFd < 0) {
            continue;
        }
        if (::connect(m_socketFd, it->ai_addr, it->ai_addrlen) == 0) {
            break;
        }
        ::close(m_socketFd);
        m_socketFd = -1;
    }
    freeaddrinfo(result);

    if (m_socketFd < 0) {
        error = "Failed to connect socket";
        return false;
    }

    m_session = libssh2_session_init();
    if (!m_session) {
        error = "Failed to create SSH session";
        ::close(m_socketFd);
        m_socketFd = -1;
        return false;
    }

    libssh2_session_set_blocking(m_session, 1);

    rc = libssh2_session_handshake(m_session, m_socketFd);
    if (rc != 0) {
        error = "SSH handshake failed";
        disconnect();
        return false;
    }

    // CR-002: authenticate the server — SHA-256 fingerprint against the TOFU
    // trust store — before any credential leaves the device. SFTP uploads pass
    // through the same verifier.
    if (!SSHVerifyHostKey(m_session, host, port, error)) {
        disconnect();
        return false;
    }

    rc = libssh2_userauth_password(m_session, user.c_str(), password.c_str());
    if (rc != 0) {
        error = "SSH password authentication failed";
        disconnect();
        return false;
    }

    m_channel = libssh2_channel_open_session(m_session);
    if (!m_channel) {
        error = "Failed to open SSH channel";
        disconnect();
        return false;
    }

    rc = libssh2_channel_request_pty_ex(m_channel, "xterm-256color", 14, nullptr, 0,
                                        cols, rows, 0, 0);
    if (rc != 0) {
        error = "Failed to request remote PTY";
        disconnect();
        return false;
    }

    SetRemoteEnv(m_channel, "TERM", "xterm-256color");
    SetRemoteEnv(m_channel, "COLORTERM", "truecolor");
    SetRemoteEnv(m_channel, "TERM_PROGRAM", "ghostty");
    SetRemoteEnv(m_channel, "TERM_PROGRAM_VERSION", "1.0.0");

    const char* loginShellCommand =
        "env TERM=xterm-256color "
        "COLORTERM=truecolor "
        "TERM_PROGRAM=ghostty "
        "TERM_PROGRAM_VERSION=1.0.0 "
        "/bin/sh -lc 'exec \"${SHELL:-/bin/sh}\" -l'";
    rc = libssh2_channel_exec(m_channel, loginShellCommand);
    if (rc != 0) {
        error = "Failed to start remote shell";
        disconnect();
        return false;
    }

    libssh2_session_set_blocking(m_session, 0);

    m_connected = true;
    m_running = true;
    m_readThread = std::thread(&SSHSession::readLoop, this);
    return true;
}

void SSHSession::disconnect() {
    m_running = false;

    if (m_readThread.joinable()) {
        m_readThread.join();
    }

    std::lock_guard<std::mutex> lock(m_ioMutex);

    // Close the write queue: bytes still queued for the dead transport are
    // dropped here exactly once, and later writes fail explicitly instead of
    // being accepted into a queue nobody will drain.
    m_pendingWrites.clear();
    m_pendingWriteOffset = 0;
    m_writeFailed = false;

    if (m_channel) {
        libssh2_channel_close(m_channel);
        libssh2_channel_free(m_channel);
        m_channel = nullptr;
    }

    if (m_session) {
        libssh2_session_disconnect(m_session, "Normal Shutdown");
        libssh2_session_free(m_session);
        m_session = nullptr;
    }

    if (m_socketFd >= 0) {
        ::close(m_socketFd);
        m_socketFd = -1;
    }

    m_connected = false;
    // No libssh2_exit() here: the library is initialized once per process via
    // EnsureLibssh2ProcessInit() and lives until process teardown (CR-010).
}

// CR-006 (SSH half): every byte lands in the ordered pending queue first and
// is drained in FIFO order — inline right away so interactive input keeps its
// latency, otherwise by the writable-readiness pass in readLoop(). EAGAIN
// keeps the tail queued; a hard channel error latches m_writeFailed, surfaces
// one terminal-visible notice, and rejects this and later writes. No byte is
// dropped silently.
bool SSHSession::write(const char* data, size_t len) {
    if (!data || len == 0) {
        return false;
    }

    bool emitFailure = false;
    {
        std::lock_guard<std::mutex> lock(m_ioMutex);
        if (!m_connected || !m_channel || m_writeFailed) {
            return false;
        }
        m_pendingWrites.emplace_back(data, len);
        // Fast path: drain right away; whatever the nonblocking channel
        // refuses stays queued for readLoop() in the original order.
        if (drainPendingWritesLocked()) {
            return true;
        }
        m_writeFailed = true;
        emitFailure = true;
    }

    if (emitFailure) {
        notifyWriteFailure();
    }
    return false;
}

// Writes as much of the pending FIFO queue as the nonblocking channel accepts
// right now. EAGAIN keeps the remaining bytes queued for the next
// writable-ready pass; only a hard error returns false so the caller can
// propagate the failure instead of discarding the unwritten tail.
bool SSHSession::drainPendingWritesLocked() {
    while (!m_pendingWrites.empty()) {
        const std::string& head = m_pendingWrites.front();
        const size_t remaining = head.size() - m_pendingWriteOffset;
        const ssize_t written = libssh2_channel_write(m_channel, head.data() + m_pendingWriteOffset,
                                                      remaining);
        if (written == LIBSSH2_ERROR_EAGAIN) {
            return true;
        }
        if (written < 0) {
            OH_LOG_ERROR(LOG_APP, "SSH channel write failed: %d", static_cast<int>(written));
            return false;
        }
        if (written == 0) {
            // Should not happen for a non-empty buffer; treat it like
            // would-block so the queue survives for the next pass.
            return true;
        }
        m_pendingWriteOffset += static_cast<size_t>(written);
        if (m_pendingWriteOffset >= head.size()) {
            m_pendingWrites.pop_front();
            m_pendingWriteOffset = 0;
        }
    }
    return true;
}

// Surfaces a latched write failure once through the existing output callback
// so the rejection is visible on the terminal instead of silent.
void SSHSession::notifyWriteFailure() {
    if (m_outputCallback) {
        m_outputCallback("\r\n[SSH write failed]\r\n");
    }
}

void SSHSession::resize(int cols, int rows) {
    if (!m_connected || !m_channel) {
        return;
    }

    std::lock_guard<std::mutex> lock(m_ioMutex);
    libssh2_channel_request_pty_size_ex(m_channel, cols, rows, 0, 0);
}

void SSHSession::readLoop() {
    char buffer[4096];

    while (m_running && m_connected && m_channel) {
        std::string outputChunk;
        bool reachedEof = false;
        {
            std::lock_guard<std::mutex> lock(m_ioMutex);
            ssize_t n = libssh2_channel_read(m_channel, buffer, sizeof(buffer));
            if (n > 0) {
                outputChunk.assign(buffer, static_cast<size_t>(n));
            } else if (n == 0 && libssh2_channel_eof(m_channel)) {
                reachedEof = true;
            }
        }

        if (!outputChunk.empty()) {
            if (m_outputCallback) {
                m_outputCallback(outputChunk);
            }
            continue;
        }

        if (reachedEof) {
            break;
        }

        // Writable-readiness drive for the pending write queue: watch the
        // session socket for writability whenever backpressure left bytes
        // behind (select() on the session fd is the documented libssh2
        // nonblocking pattern), then drain the queue in order.
        bool wantWrite = false;
        {
            std::lock_guard<std::mutex> lock(m_ioMutex);
            wantWrite = !m_pendingWrites.empty() && !m_writeFailed;
        }

        fd_set readfds;
        FD_ZERO(&readfds);
        FD_SET(m_socketFd, &readfds);
        fd_set writefds;
        FD_ZERO(&writefds);
        if (wantWrite) {
            FD_SET(m_socketFd, &writefds);
        }
        struct timeval tv = {0, 16000};
        select(m_socketFd + 1, &readfds, wantWrite ? &writefds : nullptr, nullptr, &tv);

        if (wantWrite) {
            bool emitFailure = false;
            {
                std::lock_guard<std::mutex> lock(m_ioMutex);
                if (m_connected && m_channel && !m_writeFailed &&
                    !drainPendingWritesLocked()) {
                    m_writeFailed = true;
                    emitFailure = true;
                }
            }
            if (emitFailure) {
                notifyWriteFailure();
            }
        }
    }

    m_connected = false;
}
