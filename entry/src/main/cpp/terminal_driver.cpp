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

    void EmitOutput(const std::string& data)
    {
        if (data.empty()) {
            return;
        }

        napi_threadsafe_function tsfn = nullptr;
        {
            std::lock_guard<std::mutex> lock(m_outputMutex);
            if (m_outputTsfn == nullptr) {
                m_outputBuffer += data;
                return;
            }
            tsfn = m_outputTsfn;
        }

        auto* output = new std::string(data);
        const napi_status status = napi_call_threadsafe_function(tsfn, output, napi_tsfn_nonblocking);
        if (status != napi_ok) {
            delete output;
            std::lock_guard<std::mutex> lock(m_outputMutex);
            m_outputBuffer += data;
        }
    }

    std::mutex m_mutex;
    std::mutex m_outputMutex;
    std::string m_outputBuffer;
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

FusionTerminalDriver& GetDriver()
{
    static FusionTerminalDriver driver;
    return driver;
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

napi_value Initialize(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc >= 1) {
        GetDriver().Initialize(ReadStringArg(env, args[0]));
    }
    return ReturnUndefined(env);
}

napi_value StartLocal(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    const int32_t cols = argc >= 1 ? ReadIntArg(env, args[0], DEFAULT_COLS) : DEFAULT_COLS;
    const int32_t rows = argc >= 2 ? ReadIntArg(env, args[1], DEFAULT_ROWS) : DEFAULT_ROWS;
    napi_value result;
    napi_get_boolean(env, GetDriver().StartLocal(cols, rows), &result);
    return result;
}

napi_value ConnectSsh(napi_env env, napi_callback_info info)
{
    size_t argc = 6;
    napi_value args[6] = {nullptr, nullptr, nullptr, nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    const std::string host = argc >= 1 ? ReadStringArg(env, args[0]) : "";
    const int32_t port = argc >= 2 ? ReadIntArg(env, args[1], 22) : 22;
    const std::string user = argc >= 3 ? ReadStringArg(env, args[2]) : "";
    const std::string password = argc >= 4 ? ReadStringArg(env, args[3]) : "";
    const int32_t cols = argc >= 5 ? ReadIntArg(env, args[4], DEFAULT_COLS) : DEFAULT_COLS;
    const int32_t rows = argc >= 6 ? ReadIntArg(env, args[5], DEFAULT_ROWS) : DEFAULT_ROWS;
    napi_value result;
    napi_get_boolean(env, GetDriver().ConnectSsh(host, port, user, password, cols, rows), &result);
    return result;
}

napi_value Stop(napi_env env, napi_callback_info info)
{
    GetDriver().Stop();
    return ReturnUndefined(env);
}

napi_value WriteInput(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc >= 1) {
        GetDriver().Write(ReadStringArg(env, args[0]));
    }
    return ReturnUndefined(env);
}

napi_value DrainOutput(napi_env env, napi_callback_info info)
{
    const std::string output = GetDriver().DrainOutput();
    napi_value result;
    napi_create_string_utf8(env, output.c_str(), output.length(), &result);
    return result;
}

napi_value SetOutputCallback(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) {
        GetDriver().ClearOutputCallback();
        return ReturnUndefined(env);
    }

    napi_valuetype valueType = napi_undefined;
    napi_typeof(env, args[0], &valueType);
    if (valueType == napi_function) {
        GetDriver().SetOutputCallback(env, args[0]);
    } else {
        GetDriver().ClearOutputCallback();
    }
    return ReturnUndefined(env);
}

napi_value Resize(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    const int32_t cols = argc >= 1 ? ReadIntArg(env, args[0], DEFAULT_COLS) : DEFAULT_COLS;
    const int32_t rows = argc >= 2 ? ReadIntArg(env, args[1], DEFAULT_ROWS) : DEFAULT_ROWS;
    GetDriver().Resize(cols, rows);
    return ReturnUndefined(env);
}

napi_value Init(napi_env env, napi_value exports)
{
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

