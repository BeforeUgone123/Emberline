#include <hilog/log.h>
#include <napi/native_api.h>
#include <atomic>
#include <cerrno>
#include <csignal>
#include <cstdio>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <unistd.h>
#include <sys/wait.h>
#include "pty/pty_handler.h"
#include "ssh/ssh_session.h"

#undef LOG_TAG
#define LOG_TAG "fusion_terminal_driver"

namespace {

constexpr int DEFAULT_COLS = 120;
constexpr int DEFAULT_ROWS = 40;

enum class DriverMode {
    LocalPty,
    RemoteSsh,
};

class FusionTerminalDriver {
public:
    void Initialize(const std::string& filesDir)
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        m_filesDir = filesDir;
    }

    bool StartLocal(int cols, int rows)
    {
        Stop();
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            m_cols = cols > 0 ? cols : DEFAULT_COLS;
            m_rows = rows > 0 ? rows : DEFAULT_ROWS;
            m_mode = DriverMode::LocalPty;
            m_running = true;
        }

        PTYHandler::setHomeDir(m_filesDir.c_str());
        PTYHandler::setAppBinDir("");
        PTYHandler::setPreferredShellPath("");
        PTYHandler::setShellInitPath("");

        int masterFd = -1;
        int writeFd = -1;
        pid_t childPid = -1;
        if (!PTYHandler::openPTY(masterFd, writeFd, childPid, m_cols, m_rows)) {
            EmitOutput("Failed to start local PTY.\r\n");
            std::lock_guard<std::mutex> lock(m_mutex);
            m_running = false;
            return false;
        }

        {
            std::lock_guard<std::mutex> lock(m_mutex);
            m_masterFd = masterFd;
            m_writeFd = writeFd;
            m_childPid = childPid;
        }

        m_localReadThread = std::thread(&FusionTerminalDriver::LocalReadLoop, this);
        EmitOutput("Local PTY ready. TERM=xterm-256color COLORTERM=truecolor\r\n");
        return true;
    }

    bool ConnectSsh(const std::string& host, int port, const std::string& user,
                    const std::string& password, int cols, int rows)
    {
        Stop();
        if (host.empty() || user.empty()) {
            EmitOutput("SSH target requires a host and user.\r\n");
            return false;
        }

        {
            std::lock_guard<std::mutex> lock(m_mutex);
            m_cols = cols > 0 ? cols : DEFAULT_COLS;
            m_rows = rows > 0 ? rows : DEFAULT_ROWS;
            m_mode = DriverMode::RemoteSsh;
        }

        auto session = std::make_unique<SSHSession>();
        session->setOutputCallback([this](const std::string& output) {
            EmitOutput(output);
        });

        std::string error;
        const int safePort = port > 0 ? port : 22;
        if (!session->connect(host, safePort, user, password, m_cols, m_rows, error)) {
            EmitOutput("SSH connection failed: " + error + "\r\n");
            return false;
        }

        {
            std::lock_guard<std::mutex> lock(m_mutex);
            m_sshSession = std::move(session);
        }

        EmitOutput("SSH connected to " + user + "@" + host + ":" + std::to_string(safePort) + "\r\n");
        return true;
    }

    void Stop()
    {
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            m_running = false;
        }

        if (m_localReadThread.joinable()) {
            m_localReadThread.join();
        }

        std::unique_ptr<SSHSession> session;
        int masterFd = -1;
        int writeFd = -1;
        pid_t childPid = -1;
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            session = std::move(m_sshSession);
            masterFd = m_masterFd;
            writeFd = m_writeFd;
            childPid = m_childPid;
            m_masterFd = -1;
            m_writeFd = -1;
            m_childPid = -1;
        }

        if (session) {
            session->disconnect();
        }
        PTYHandler::close(masterFd, writeFd, childPid);

        {
            std::lock_guard<std::mutex> lock(m_outputMutex);
            m_pendingUtf8.clear();
        }
    }

    void Write(const std::string& data)
    {
        if (data.empty()) {
            return;
        }

        std::lock_guard<std::mutex> lock(m_mutex);
        if (m_mode == DriverMode::RemoteSsh && m_sshSession) {
            m_sshSession->write(data.c_str(), data.size());
            return;
        }
        WriteToLocalPtyLocked(data.c_str(), data.size());
    }

    void Resize(int cols, int rows)
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        m_cols = cols > 0 ? cols : m_cols;
        m_rows = rows > 0 ? rows : m_rows;
        if (m_masterFd >= 0) {
            PTYHandler::resize(m_masterFd, m_cols, m_rows);
            if (m_childPid > 0) {
                kill(m_childPid, SIGWINCH);
            }
        }
        if (m_sshSession && m_sshSession->isConnected()) {
            m_sshSession->resize(m_cols, m_rows);
        }
    }

    std::string DrainOutput()
    {
        std::lock_guard<std::mutex> lock(m_outputMutex);
        std::string result;
        result.swap(m_outputBuffer);
        return result;
    }

    void SetOutputCallback(napi_env env, napi_value callback)
    {
        napi_threadsafe_function previous = nullptr;
        napi_threadsafe_function next = nullptr;

        if (callback != nullptr) {
            napi_value resourceName;
            napi_create_string_utf8(env, "fusionTerminalOutput", NAPI_AUTO_LENGTH, &resourceName);
            napi_create_threadsafe_function(
                env,
                callback,
                nullptr,
                resourceName,
                0,
                1,
                nullptr,
                nullptr,
                nullptr,
                [](napi_env callbackEnv, napi_value jsCallback, void*, void* data) {
                    std::unique_ptr<std::string> output(static_cast<std::string*>(data));
                    if (!callbackEnv || !jsCallback || !output || output->empty()) {
                        return;
                    }

                    napi_value undefined;
                    napi_get_undefined(callbackEnv, &undefined);
                    napi_value argv[1];
                    napi_create_string_utf8(callbackEnv, output->c_str(), output->size(), &argv[0]);
                    napi_call_function(callbackEnv, undefined, jsCallback, 1, argv, nullptr);
                },
                &next);
        }

        std::string buffered;
        {
            std::lock_guard<std::mutex> lock(m_outputMutex);
            previous = m_outputTsfn;
            m_outputTsfn = next;
            if (m_outputTsfn != nullptr && !m_outputBuffer.empty()) {
                buffered.swap(m_outputBuffer);
            }
        }

        if (previous != nullptr) {
            napi_release_threadsafe_function(previous, napi_tsfn_abort);
        }
        if (m_outputTsfn != nullptr && !buffered.empty()) {
            EmitOutput(buffered);
        }
    }

    void ClearOutputCallback()
    {
        napi_threadsafe_function previous = nullptr;
        {
            std::lock_guard<std::mutex> lock(m_outputMutex);
            previous = m_outputTsfn;
            m_outputTsfn = nullptr;
        }
        if (previous != nullptr) {
            napi_release_threadsafe_function(previous, napi_tsfn_abort);
        }
    }

private:
    void LocalReadLoop()
    {
        char buffer[4096];
        while (true) {
            int masterFd = -1;
            {
                std::lock_guard<std::mutex> lock(m_mutex);
                if (!m_running || m_masterFd < 0) {
                    break;
                }
                masterFd = m_masterFd;
            }

            const ssize_t count = read(masterFd, buffer, sizeof(buffer));
            if (count > 0) {
                EmitOutput(std::string(buffer, static_cast<size_t>(count)));
                continue;
            }
            if (count == 0) {
                EmitOutput("\r\n[local PTY disconnected]\r\n");
                break;
            }
            if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
                usleep(16000);
                continue;
            }
            EmitOutput("\r\n[local PTY read failed]\r\n");
            break;
        }
    }

    void WriteToLocalPtyLocked(const char* data, size_t length)
    {
        if (m_writeFd < 0 || !data || length == 0) {
            return;
        }
        size_t offset = 0;
        while (offset < length) {
            const ssize_t written = write(m_writeFd, data + offset, length - offset);
            if (written < 0) {
                if (errno == EINTR) {
                    continue;
                }
                break;
            }
            offset += static_cast<size_t>(written);
        }
    }

    // Byte streams from the PTY/SSH reader are chunked arbitrarily, so a
    // multi-byte UTF-8 sequence can be split across reads. Returns the number
    // of trailing bytes that form an incomplete sequence (0 if none).
    static size_t TrailingIncompleteUtf8(const char* data, size_t len)
    {
        const size_t lookback = len < 3 ? len : 3;
        for (size_t back = 1; back <= lookback; ++back) {
            const unsigned char byte = static_cast<unsigned char>(data[len - back]);
            if ((byte & 0xC0) == 0x80) {
                continue; // continuation byte, keep scanning for the lead
            }
            size_t needed = 0;
            if ((byte & 0x80) == 0x00) {
                needed = 1;
            } else if ((byte & 0xE0) == 0xC0) {
                needed = 2;
            } else if ((byte & 0xF0) == 0xE0) {
                needed = 3;
            } else if ((byte & 0xF8) == 0xF0) {
                needed = 4;
            } else {
                return 0; // invalid lead; let the consumer replace it
            }
            return needed > back ? back : 0;
        }
        return 0;
    }

    void EmitOutput(const std::string& data)
    {
        if (data.empty()) {
            return;
        }

        std::string chunk;
        {
            std::lock_guard<std::mutex> lock(m_outputMutex);
            m_pendingUtf8 += data;
            const size_t tail = TrailingIncompleteUtf8(m_pendingUtf8.data(), m_pendingUtf8.size());
            if (tail >= m_pendingUtf8.size()) {
                return; // only an incomplete sequence buffered; wait for more
            }
            chunk = m_pendingUtf8.substr(0, m_pendingUtf8.size() - tail);
            m_pendingUtf8.erase(0, m_pendingUtf8.size() - tail);
        }

        napi_threadsafe_function tsfn = nullptr;
        {
            std::lock_guard<std::mutex> lock(m_outputMutex);
            if (m_outputTsfn == nullptr) {
                m_outputBuffer += chunk;
                return;
            }
            tsfn = m_outputTsfn;
        }

        auto* output = new std::string(std::move(chunk));
        const napi_status status = napi_call_threadsafe_function(tsfn, output, napi_tsfn_nonblocking);
        if (status != napi_ok) {
            std::lock_guard<std::mutex> lock(m_outputMutex);
            m_outputBuffer += *output;
            delete output;
        }
    }

    std::mutex m_mutex;
    std::mutex m_outputMutex;
    std::string m_outputBuffer;
    std::string m_pendingUtf8;
    napi_threadsafe_function m_outputTsfn = nullptr;
    std::string m_filesDir;
    std::thread m_localReadThread;
    std::unique_ptr<SSHSession> m_sshSession;
    std::atomic<bool> m_running {false};
    DriverMode m_mode = DriverMode::LocalPty;
    int m_masterFd = -1;
    int m_writeFd = -1;
    pid_t m_childPid = -1;
    int m_cols = DEFAULT_COLS;
    int m_rows = DEFAULT_ROWS;
};

// Each ArkTS FusionTerminalDriver owns one native session so multiple app
// windows (multiton ability instances share this process) cannot stomp on a
// single global PTY/SSH connection.
std::mutex g_sessionsMutex;
std::unordered_map<int32_t, std::shared_ptr<FusionTerminalDriver>> g_sessions;
int32_t g_nextSessionId = 1;

std::shared_ptr<FusionTerminalDriver> FindSession(int32_t sessionId)
{
    std::lock_guard<std::mutex> lock(g_sessionsMutex);
    auto it = g_sessions.find(sessionId);
    return it == g_sessions.end() ? nullptr : it->second;
}

void SetNamedFunction(napi_env env, napi_value exports, const char* name, napi_callback callback)
{
    napi_property_descriptor descriptor {
        name, nullptr, callback, nullptr, nullptr, nullptr, napi_default, nullptr
    };
    napi_define_properties(env, exports, 1, &descriptor);
}

napi_value ReturnUndefined(napi_env env)
{
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

std::string ReadStringArg(napi_env env, napi_value value)
{
    size_t length = 0;
    napi_get_value_string_utf8(env, value, nullptr, 0, &length);
    std::string result(length + 1, '\0');
    napi_get_value_string_utf8(env, value, result.data(), result.size(), &length);
    result.resize(length);
    return result;
}

int32_t ReadIntArg(napi_env env, napi_value value, int32_t fallback)
{
    int32_t result = fallback;
    napi_get_value_int32(env, value, &result);
    return result;
}

napi_value CreateSession(napi_env env, napi_callback_info info)
{
    int32_t sessionId = 0;
    {
        std::lock_guard<std::mutex> lock(g_sessionsMutex);
        sessionId = g_nextSessionId++;
        g_sessions.emplace(sessionId, std::make_shared<FusionTerminalDriver>());
    }
    napi_value result;
    napi_create_int32(env, sessionId, &result);
    return result;
}

napi_value DestroySession(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) {
        return ReturnUndefined(env);
    }

    std::shared_ptr<FusionTerminalDriver> session;
    {
        std::lock_guard<std::mutex> lock(g_sessionsMutex);
        auto it = g_sessions.find(ReadIntArg(env, args[0], -1));
        if (it != g_sessions.end()) {
            session = std::move(it->second);
            g_sessions.erase(it);
        }
    }
    if (session) {
        session->ClearOutputCallback();
        session->Stop();
    }
    return ReturnUndefined(env);
}

napi_value Initialize(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 2) {
        return ReturnUndefined(env);
    }
    if (auto session = FindSession(ReadIntArg(env, args[0], -1))) {
        session->Initialize(ReadStringArg(env, args[1]));
    }
    return ReturnUndefined(env);
}

napi_value StartLocal(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    const int32_t cols = argc >= 2 ? ReadIntArg(env, args[1], DEFAULT_COLS) : DEFAULT_COLS;
    const int32_t rows = argc >= 3 ? ReadIntArg(env, args[2], DEFAULT_ROWS) : DEFAULT_ROWS;
    bool started = false;
    if (argc >= 1) {
        if (auto session = FindSession(ReadIntArg(env, args[0], -1))) {
            started = session->StartLocal(cols, rows);
        }
    }
    napi_value result;
    napi_get_boolean(env, started, &result);
    return result;
}

napi_value ConnectSsh(napi_env env, napi_callback_info info)
{
    size_t argc = 7;
    napi_value args[7] = {nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    const std::string host = argc >= 2 ? ReadStringArg(env, args[1]) : "";
    const int32_t port = argc >= 3 ? ReadIntArg(env, args[2], 22) : 22;
    const std::string user = argc >= 4 ? ReadStringArg(env, args[3]) : "";
    const std::string password = argc >= 5 ? ReadStringArg(env, args[4]) : "";
    const int32_t cols = argc >= 6 ? ReadIntArg(env, args[5], DEFAULT_COLS) : DEFAULT_COLS;
    const int32_t rows = argc >= 7 ? ReadIntArg(env, args[6], DEFAULT_ROWS) : DEFAULT_ROWS;
    bool connected = false;
    if (argc >= 1) {
        if (auto session = FindSession(ReadIntArg(env, args[0], -1))) {
            connected = session->ConnectSsh(host, port, user, password, cols, rows);
        }
    }
    napi_value result;
    napi_get_boolean(env, connected, &result);
    return result;
}

napi_value Stop(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc >= 1) {
        if (auto session = FindSession(ReadIntArg(env, args[0], -1))) {
            session->Stop();
        }
    }
    return ReturnUndefined(env);
}

napi_value WriteInput(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc >= 2) {
        if (auto session = FindSession(ReadIntArg(env, args[0], -1))) {
            session->Write(ReadStringArg(env, args[1]));
        }
    }
    return ReturnUndefined(env);
}

napi_value DrainOutput(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string output;
    if (argc >= 1) {
        if (auto session = FindSession(ReadIntArg(env, args[0], -1))) {
            output = session->DrainOutput();
        }
    }
    napi_value result;
    napi_create_string_utf8(env, output.c_str(), output.length(), &result);
    return result;
}

napi_value SetOutputCallback(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) {
        return ReturnUndefined(env);
    }

    auto session = FindSession(ReadIntArg(env, args[0], -1));
    if (!session) {
        return ReturnUndefined(env);
    }

    napi_valuetype valueType = napi_undefined;
    if (argc >= 2) {
        napi_typeof(env, args[1], &valueType);
    }
    if (valueType == napi_function) {
        session->SetOutputCallback(env, args[1]);
    } else {
        session->ClearOutputCallback();
    }
    return ReturnUndefined(env);
}

napi_value Resize(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    const int32_t cols = argc >= 2 ? ReadIntArg(env, args[1], DEFAULT_COLS) : DEFAULT_COLS;
    const int32_t rows = argc >= 3 ? ReadIntArg(env, args[2], DEFAULT_ROWS) : DEFAULT_ROWS;
    if (argc >= 1) {
        if (auto session = FindSession(ReadIntArg(env, args[0], -1))) {
            session->Resize(cols, rows);
        }
    }
    return ReturnUndefined(env);
}

napi_value Init(napi_env env, napi_value exports)
{
    SetNamedFunction(env, exports, "createSession", CreateSession);
    SetNamedFunction(env, exports, "destroySession", DestroySession);
    SetNamedFunction(env, exports, "initialize", Initialize);
    SetNamedFunction(env, exports, "startLocal", StartLocal);
    SetNamedFunction(env, exports, "connectSsh", ConnectSsh);
    SetNamedFunction(env, exports, "stop", Stop);
    SetNamedFunction(env, exports, "writeInput", WriteInput);
    SetNamedFunction(env, exports, "drainOutput", DrainOutput);
    SetNamedFunction(env, exports, "setOutputCallback", SetOutputCallback);
    SetNamedFunction(env, exports, "resize", Resize);
    return exports;
}

} // namespace

EXTERN_C_START
static napi_module g_fusionTerminalDriverModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "fusion_terminal_driver",
    .nm_priv = nullptr,
    .reserved = {0},
};
EXTERN_C_END

extern "C" __attribute__((constructor)) void RegisterFusionTerminalDriverModule(void)
{
    napi_module_register(&g_fusionTerminalDriverModule);
}

