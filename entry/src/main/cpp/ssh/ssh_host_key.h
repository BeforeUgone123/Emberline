#pragma once

// Shared SSH server-authentication gate and process-wide libssh2 lifetime
// management (code review CR-002 / CR-010).
//
// Header-only on purpose: entry/src/main/cpp/CMakeLists.txt lists sources
// explicitly and is owned by another workstream, so this module ships as
// inline functions. The inline trust-store singleton is folded into exactly
// one instance across translation units, which is what lets the interactive
// SSH session (ssh_session.cpp) and the one-shot SFTP upload path
// (terminal_driver.cpp RunSftpUpload) share the same verifier and the same
// TOFU records: a host key trusted for one path is honored — and a mismatch
// refused — by the other.
//
// SFTP integration (terminal_driver.cpp owner): include this header, replace
// the per-upload `libssh2_init(0)` with `EnsureLibssh2ProcessInit`, and call
// `SSHVerifyHostKey(session, ctx->host, ctx->port, ctx->error)` right after
// `libssh2_session_handshake` succeeds, before `libssh2_userauth_password`.

#include <libssh2.h>
#include <mbedtls/base64.h>
#include <hilog/log.h>
#include <fstream>
#include <mutex>
#include <string>
#include <unordered_map>

#ifndef LOG_TAG
#define LOG_TAG "SSHHostKey"
#endif

// CR-010: libssh2 documents its global state as non-thread-safe, so the old
// per-connect libssh2_init() calls from concurrent session/upload workers
// raced each other, and per-session libssh2_exit() freed global state other
// sessions still used. Initialize exactly once per process and never call
// libssh2_exit(): the library documents it as optional cleanup, and no
// HarmonyOS module-unload hook could run it without racing live sessions, so
// the global state simply lives until process teardown.
inline bool EnsureLibssh2ProcessInit(std::string& error)
{
    static std::once_flag once;
    static int initResult = -1;
    std::call_once(once, []() {
        initResult = libssh2_init(0);
    });
    if (initResult != 0) {
        error = "libssh2_init failed";
        return false;
    }
    return true;
}

// OpenSSH-style SHA-256 fingerprint ("SHA256:<base64-no-padding>") of the host
// key negotiated during the handshake. Empty string when unavailable.
inline std::string SSHHostKeyFingerprintSha256(_LIBSSH2_SESSION* session)
{
    if (!session) {
        return "";
    }
    const char* hash = libssh2_hostkey_hash(session, LIBSSH2_HOSTKEY_HASH_SHA256);
    if (!hash) {
        return "";
    }
    constexpr size_t SHA256_DIGEST_LENGTH = 32;
    unsigned char encoded[64] = {};
    size_t encodedLen = 0;
    if (mbedtls_base64_encode(encoded, sizeof(encoded), &encodedLen,
                              reinterpret_cast<const unsigned char*>(hash),
                              SHA256_DIGEST_LENGTH) != 0) {
        return "";
    }
    std::string fingerprint = "SHA256:";
    fingerprint.append(reinterpret_cast<const char*>(encoded), encodedLen);
    while (!fingerprint.empty() && fingerprint.back() == '=') {
        fingerprint.pop_back();
    }
    return fingerprint;
}

enum class SSHHostKeyTrust {
    Trusted,   // known endpoint, fingerprint matches the trust record
    Unknown,   // first contact: no trust record yet (TOFU records + accepts)
    Mismatch   // known endpoint presented a different key: refuse
};

// Process-wide TOFU trust store keyed by "<host>:<port>". In-memory records
// are authoritative at runtime; SetStorageFile() adds a durable mirror once
// the app layer wires it to a file inside the app sandbox (e.g. filesDir +
// "/ssh_known_hosts"). The ArkTS-side HostKeyStore.ets keeps the same
// endpoint -> "SHA256:<base64>" shape in Preferences so the connection UI can
// display and forget records.
class SSHHostKeyTrustStore {
public:
    static SSHHostKeyTrustStore& Instance()
    {
        static SSHHostKeyTrustStore store;
        return store;
    }

    SSHHostKeyTrust Resolve(const std::string& host, int port, const std::string& fingerprint,
                            std::string* stored)
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        const auto it = m_records.find(EndpointKey(host, port));
        if (it == m_records.end()) {
            return SSHHostKeyTrust::Unknown;
        }
        if (stored) {
            *stored = it->second;
        }
        return FingerprintEquals(it->second, fingerprint) ? SSHHostKeyTrust::Trusted
                                                          : SSHHostKeyTrust::Mismatch;
    }

    void Trust(const std::string& host, int port, const std::string& fingerprint)
    {
        if (fingerprint.empty()) {
            return;
        }
        std::lock_guard<std::mutex> lock(m_mutex);
        m_records[EndpointKey(host, port)] = fingerprint;
        PersistLocked();
    }

    bool Forget(const std::string& host, int port)
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        if (m_records.erase(EndpointKey(host, port)) == 0) {
            return false;
        }
        PersistLocked();
        return true;
    }

    // Loads existing records from and mirrors future Trust()/Forget() calls to
    // the given file. Format per line: "<host>:<port> SHA256:<base64>".
    void SetStorageFile(const std::string& path)
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        m_storageFile = path;
        m_records.clear();
        std::ifstream in(path);
        std::string line;
        while (std::getline(in, line)) {
            const size_t space = line.find(' ');
            if (space == std::string::npos || space == 0 || space + 1 >= line.size()) {
                continue;
            }
            m_records[line.substr(0, space)] = line.substr(space + 1);
        }
    }

private:
    static std::string EndpointKey(const std::string& host, int port)
    {
        return host + ":" + std::to_string(port);
    }

    static bool FingerprintEquals(const std::string& a, const std::string& b)
    {
        if (a.size() != b.size()) {
            return false;
        }
        unsigned char diff = 0;
        for (size_t i = 0; i < a.size(); ++i) {
            diff |= static_cast<unsigned char>(a[i] ^ b[i]);
        }
        return diff == 0;
    }

    void PersistLocked()
    {
        if (m_storageFile.empty()) {
            return;
        }
        std::ofstream out(m_storageFile, std::ios::out | std::ios::trunc);
        for (const auto& record : m_records) {
            out << record.first << ' ' << record.second << '\n';
        }
    }

    std::mutex m_mutex;
    std::unordered_map<std::string, std::string> m_records;
    std::string m_storageFile;
};

// Shared server-authentication gate (code review CR-002): extract the host
// key's SHA-256 fingerprint right after the handshake and BEFORE credentials
// leave the device, then resolve it against the process-wide TOFU trust store.
// First contact is recorded and accepted (trust-on-first-use); a changed key
// fails the connection with an explicit error.
inline bool SSHVerifyHostKey(_LIBSSH2_SESSION* session, const std::string& host, int port,
                             std::string& error)
{
    const std::string endpoint = host + ":" + std::to_string(port);
    const std::string fingerprint = SSHHostKeyFingerprintSha256(session);
    if (fingerprint.empty()) {
        error = "SSH host key unavailable for " + endpoint +
                "; refusing to authenticate an unverifiable server";
        return false;
    }

    std::string stored;
    switch (SSHHostKeyTrustStore::Instance().Resolve(host, port, fingerprint, &stored)) {
    case SSHHostKeyTrust::Trusted:
        return true;
    case SSHHostKeyTrust::Unknown:
        SSHHostKeyTrustStore::Instance().Trust(host, port, fingerprint);
        OH_LOG_INFO(LOG_APP, "TOFU: trusted SSH host key %s for %s",
                    fingerprint.c_str(), endpoint.c_str());
        return true;
    case SSHHostKeyTrust::Mismatch:
        error = "SSH host key mismatch for " + endpoint + ": server presents " + fingerprint +
                " but the trust record holds " + stored +
                "; refusing to send credentials (possible MITM or host rekey; " +
                "forget the stored record to trust the new key)";
        OH_LOG_ERROR(LOG_APP, "SSH host key mismatch for %s", endpoint.c_str());
        return false;
    }
    error = "SSH host key verification failed for " + endpoint;
    return false;
}
