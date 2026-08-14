#include "native_drawing_renderer.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <hitrace/trace.h>
#include <hilog/log.h>
#include <inttypes.h>
#include <native_buffer/buffer_common.h>
#include <native_buffer/native_buffer.h>
#include <rawfile/raw_file_manager.h>
#include <sstream>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

#undef LOG_TAG
#define LOG_TAG "NativeDrawingRenderer"

namespace {
constexpr uint64_t kBufferUsage =
    NATIVEBUFFER_USAGE_CPU_WRITE;

constexpr size_t kMaxGlyphCacheEntries = 4096;
std::atomic<uint64_t> g_frameCounter {0};

constexpr const char* kDefaultTerminalFontFamily = "PingFang SC";

// Bundled fonts are each registered under their own family so the paragraph
// fallback chain can walk them in ghostty-style priority order instead of
// stopping at the first file that happens to extract.
struct BundledFontSpec {
    const char* rawPath;
    const char* family;
};

constexpr std::array<BundledFontSpec, 5> kBundledTerminalFonts = {{
    { "fonts/MapleMonoNormal-NF-CN-Regular.ttf", "FusionTerm Maple Mono" },
    { "fonts/JetBrainsMono-Regular.ttf", "FusionTerm JetBrains Mono" },
    { "fonts/SymbolsNerdFontMono-Regular.ttf", "FusionTerm Nerd Symbols" },
    { "fonts/CascadiaMono.ttf", "FusionTerm Cascadia Mono" },
    { "fonts/SarasaFixedSC-Regular.ttf", "FusionTerm Sarasa Fixed SC" },
}};

// Optional device-local Apple-style font files (never committed); the first
// one present is registered as a private CJK/system fallback family.
constexpr const char* kPrivateFallbackFontFamily = "FusionTerm Private Fallback";
constexpr std::array<const char*, 7> kPrivateFallbackFontRawFiles = {
    "fonts/PingFangSC-Regular.otf",
    "fonts/PingFangSC-Regular.ttf",
    "fonts/PingFangSC.ttf",
    "fonts/PingFang.ttc",
    "fonts/SF-Pro-Text-Regular.otf",
    "fonts/SFProText-Regular.otf",
    "fonts/FusionTerm-Regular.otf",
};

// A user-imported font can be selected as the primary face, or used as a
// later fallback when one of the bundled faces is selected.
constexpr const char* kCustomTerminalFontFamily = "FusionTerm Custom";

// Paragraph-level fallback chain for terminal cells. Bundled families first
// (Maple Mono NF CN covers Latin + CJK + Nerd Font glyphs in one file, which
// mirrors the user's desktop ghostty font stack), then platform families.
constexpr std::array<const char*, 7> kBundledFamilyFallbackOrder = {
    kCustomTerminalFontFamily,
    "FusionTerm Maple Mono",
    "FusionTerm JetBrains Mono",
    "FusionTerm Nerd Symbols",
    "FusionTerm Cascadia Mono",
    "FusionTerm Sarasa Fixed SC",
    kPrivateFallbackFontFamily,
};

constexpr std::array<const char*, 14> kSystemMonoFontCandidates = {
    "/system/fonts/PingFang.ttc",
    "/system/fonts/PingFangSC-Regular.otf",
    "/system/fonts/PingFangSC.ttf",
    "/system/fonts/NotoSansMono[wdth,wght].ttf",
    "/system/fonts/NotoSansMono-Regular.ttf",
    "/system/fonts/HarmonyOS_Sans_Mono.ttf",
    "/system/fonts/HarmonyOS_Sans_Mono_Regular.ttf",
    "/system/fonts/HarmonyOS_Sans.ttf",
    "/system/fonts/NotoSansCJK-Regular.ttc",
    "/system/fonts/DroidSansMono.ttf",
    "/system/fonts/RobotoMono-Regular.ttf",
    "/system/fonts/SFMono-Regular.otf",
    "/system/fonts/Menlo.ttc",
    "/system/fonts/Monaco.ttf",
};

constexpr std::array<const char*, 15> kTerminalFontFamilies = {
    "Sarasa Fixed SC",
    "JetBrains Mono",
    "Cascadia Mono",
    "PingFang SC",
    "SF Mono",
    "Menlo",
    "Monaco",
    "Apple Color Emoji",
    "HarmonyOS Sans Mono",
    "HarmonyOS Sans",
    "Noto Sans Mono",
    "Noto Sans CJK SC",
    "Droid Sans Mono",
    "monospace",
    "sans-serif",
};

void PushUniqueFontFamily(std::vector<const char*>& families, const char* family)
{
    if (!family || family[0] == '\0') {
        return;
    }
    const auto existing = std::find_if(families.begin(), families.end(), [family](const char* candidate) {
        return candidate && std::strcmp(candidate, family) == 0;
    });
    if (existing == families.end()) {
        families.push_back(family);
    }
}

bool IsSuspiciousCodepoint(uint32_t codepoint)
{
    return codepoint > 0x10FFFF || (codepoint >= 0xD800 && codepoint <= 0xDFFF);
}

std::string HexPreview(const std::string& text, size_t maxBytes = 24)
{
    std::ostringstream out;
    out << "len=" << text.size() << " hex=";
    const size_t limit = std::min(text.size(), maxBytes);
    for (size_t i = 0; i < limit; ++i) {
        char buf[4];
        std::snprintf(buf, sizeof(buf), "%02X", static_cast<unsigned char>(text[i]));
        if (i > 0) {
            out << ' ';
        }
        out << buf;
    }
    if (text.size() > limit) {
        out << " ...";
    }
    return out.str();
}

std::string Utf8FromCodepoint(uint32_t codepoint)
{
    std::string out;
    if (codepoint <= 0x7F) {
        out.push_back(static_cast<char>(codepoint));
    } else if (codepoint <= 0x7FF) {
        out.push_back(static_cast<char>(0xC0 | (codepoint >> 6)));
        out.push_back(static_cast<char>(0x80 | (codepoint & 0x3F)));
    } else if (codepoint <= 0xFFFF) {
        out.push_back(static_cast<char>(0xE0 | (codepoint >> 12)));
        out.push_back(static_cast<char>(0x80 | ((codepoint >> 6) & 0x3F)));
        out.push_back(static_cast<char>(0x80 | (codepoint & 0x3F)));
    } else {
        out.push_back(static_cast<char>(0xF0 | (codepoint >> 18)));
        out.push_back(static_cast<char>(0x80 | ((codepoint >> 12) & 0x3F)));
        out.push_back(static_cast<char>(0x80 | ((codepoint >> 6) & 0x3F)));
        out.push_back(static_cast<char>(0x80 | (codepoint & 0x3F)));
    }
    return out;
}

bool IsBlankText(const std::string& text)
{
    return text.empty() || (text.size() == 1 && text[0] == ' ');
}

bool IsBuiltinGeometryCodepoint(uint32_t codepoint)
{
    return (codepoint >= 0x2500 && codepoint <= 0x259F);
}

bool SameVisualTextStyle(const CellAttributes& lhs, const CellAttributes& rhs)
{
    return lhs.fg == rhs.fg &&
        lhs.bg == rhs.bg &&
        lhs.bold == rhs.bold &&
        lhs.italic == rhs.italic &&
        lhs.underline == rhs.underline &&
        lhs.strikethrough == rhs.strikethrough &&
        lhs.hidden == rhs.hidden &&
        lhs.blink == rhs.blink;
}

bool EnsureDirectory(const std::string& path)
{
    struct stat st {};
    if (stat(path.c_str(), &st) == 0) {
        return S_ISDIR(st.st_mode);
    }
    return mkdir(path.c_str(), 0755) == 0;
}

bool ExtractRawFileToPath(
    NativeResourceManager* resourceManager,
    const std::string& rawPath,
    const std::string& outputPath)
{
    if (!resourceManager || rawPath.empty() || outputPath.empty()) {
        return false;
    }

    RawFile* file = OH_ResourceManager_OpenRawFile(resourceManager, rawPath.c_str());
    if (!file) {
        return false;
    }

    const size_t fileSize = OH_ResourceManager_GetRawFileSize(file);
    if (fileSize == 0) {
        OH_ResourceManager_CloseRawFile(file);
        return false;
    }

    struct stat existing {};
    if (stat(outputPath.c_str(), &existing) == 0 &&
        static_cast<size_t>(existing.st_size) == fileSize) {
        OH_ResourceManager_CloseRawFile(file);
        return true;
    }

    std::vector<uint8_t> data(fileSize);
    const int readSize = OH_ResourceManager_ReadRawFile(file, data.data(), fileSize);
    OH_ResourceManager_CloseRawFile(file);
    if (readSize <= 0 || static_cast<size_t>(readSize) != fileSize) {
        return false;
    }

    FILE* out = fopen(outputPath.c_str(), "wb");
    if (!out) {
        return false;
    }
    const size_t written = fwrite(data.data(), 1, data.size(), out);
    fclose(out);
    return written == data.size();
}

std::string BaseNameFromRawPath(const char* rawPath)
{
    if (!rawPath) {
        return {};
    }
    const std::string path(rawPath);
    const size_t slash = path.find_last_of('/');
    return slash == std::string::npos ? path : path.substr(slash + 1);
}

template <size_t N>
bool ExtractFirstAvailableRawFileToPath(
    NativeResourceManager* resourceManager,
    const std::array<const char*, N>& rawPaths,
    const std::string& outputDir,
    std::string& outputPath,
    const char** usedRawPath)
{
    if (!resourceManager || outputDir.empty()) {
        return false;
    }

    for (const char* rawPath : rawPaths) {
        const std::string fileName = BaseNameFromRawPath(rawPath);
        if (fileName.empty()) {
            continue;
        }
        const std::string candidateOutputPath = outputDir + "/" + fileName;
        if (ExtractRawFileToPath(resourceManager, rawPath, candidateOutputPath)) {
            outputPath = candidateOutputPath;
            if (usedRawPath) {
                *usedRawPath = rawPath;
            }
            return true;
        }
    }
    return false;
}

size_t RegisterBundledTerminalFonts(
    OH_Drawing_FontCollection* fontCollection,
    NativeResourceManager* resourceManager,
    const std::string& fontDir)
{
    if (!fontCollection || !resourceManager || fontDir.empty() || !EnsureDirectory(fontDir)) {
        return 0;
    }

    size_t registered = 0;
    for (const BundledFontSpec& spec : kBundledTerminalFonts) {
        const std::string fileName = BaseNameFromRawPath(spec.rawPath);
        if (fileName.empty()) {
            continue;
        }
        const std::string outputPath = fontDir + "/" + fileName;
        if (!ExtractRawFileToPath(resourceManager, spec.rawPath, outputPath)) {
            OH_LOG_WARN(LOG_APP, "Bundled terminal font missing raw=%{public}s", spec.rawPath);
            continue;
        }
        const uint32_t rc = OH_Drawing_RegisterFont(fontCollection, spec.family, outputPath.c_str());
        OH_LOG_INFO(LOG_APP, "Registered bundled terminal font rc=%u family=%{public}s path=%{public}s",
            rc,
            spec.family,
            outputPath.c_str());
        if (rc == 0) {
            ++registered;
        }
    }
    return registered;
}

bool RegisterPrivateFallbackFontIfPresent(
    OH_Drawing_FontCollection* fontCollection,
    NativeResourceManager* resourceManager,
    const std::string& fontDir)
{
    if (!fontCollection || !resourceManager || fontDir.empty() || !EnsureDirectory(fontDir)) {
        return false;
    }

    std::string privateFontPath;
    const char* usedRawPath = nullptr;
    if (!ExtractFirstAvailableRawFileToPath(
            resourceManager,
            kPrivateFallbackFontRawFiles,
            fontDir,
            privateFontPath,
            &usedRawPath)) {
        return false;
    }

    uint32_t rc =
        OH_Drawing_RegisterFont(fontCollection, kPrivateFallbackFontFamily, privateFontPath.c_str());
    OH_LOG_INFO(LOG_APP, "Registered private fallback font rc=%u raw=%{public}s path=%{public}s",
        rc,
        usedRawPath ? usedRawPath : "",
        privateFontPath.c_str());
    return true;
}

size_t RegisterReadableFonts(OH_Drawing_FontCollection* fontCollection, const char* familyName)
{
    if (!fontCollection || !familyName) {
        return 0;
    }

    size_t registered = 0;
    for (const char* fontPath : kSystemMonoFontCandidates) {
        if (!fontPath || access(fontPath, R_OK) != 0) {
            continue;
        }

        uint32_t rc = OH_Drawing_RegisterFont(fontCollection, familyName, fontPath);
        OH_LOG_INFO(LOG_APP, "Registered terminal font rc=%u family=%{public}s path=%{public}s",
            rc,
            familyName,
            fontPath);
        ++registered;
    }
    return registered;
}
}

NativeDrawingRenderer::NativeDrawingRenderer() = default;

NativeDrawingRenderer::~NativeDrawingRenderer()
{
    cleanup();
}

size_t NativeDrawingRenderer::GlyphKeyHash::operator()(const GlyphKey& key) const
{
    size_t h = std::hash<std::string>{}(key.text);
    h = (h * 1315423911u) ^ static_cast<size_t>(key.fg);
    h = (h * 1315423911u) ^ static_cast<size_t>(key.styleBits);
    h = (h * 1315423911u) ^ static_cast<size_t>(key.span);
    return h;
}

bool NativeDrawingRenderer::init(OHNativeWindow* window, uint32_t width, uint32_t height)
{
    m_window = window;
    m_width = width;
    m_height = height;

    if (!m_window) {
        OH_LOG_ERROR(LOG_APP, "init failed: window is null");
        return false;
    }

    if (!configureWindow()) {
        return false;
    }

    if (!ensureDrawingObjects()) {
        return false;
    }

    if (!m_fontCollection) {
        m_fontCollection = OH_Drawing_CreateSharedFontCollection();
        if (!m_fontCollection) {
            m_fontCollection = OH_Drawing_CreateFontCollection();
        }
    }

    updateCellDimensions();
    OH_LOG_INFO(LOG_APP, "Native drawing renderer ready: %ux%u", m_width, m_height);
    return true;
}

void NativeDrawingRenderer::cleanup()
{
    if (m_currentBuffer && m_window) {
        if (m_currentNativeBuffer) {
            OH_NativeBuffer_Unmap(m_currentNativeBuffer);
        }
        OH_NativeWindow_NativeWindowAbortBuffer(m_window, m_currentBuffer);
    }
    if (m_currentFenceFd >= 0) {
        close(m_currentFenceFd);
    }
    m_currentFenceFd = -1;
    m_currentBuffer = nullptr;
    m_currentNativeBuffer = nullptr;
    m_currentPixels = nullptr;
    m_currentConfig = {};

    destroyGlyphCache();

    if (m_rect) {
        OH_Drawing_RectDestroy(m_rect);
        m_rect = nullptr;
    }
    if (m_brush) {
        OH_Drawing_BrushDestroy(m_brush);
        m_brush = nullptr;
    }
    if (m_canvas) {
        OH_Drawing_CanvasDestroy(m_canvas);
        m_canvas = nullptr;
    }
    if (m_fontCollection) {
        OH_Drawing_DestroyFontCollection(m_fontCollection);
        m_fontCollection = nullptr;
    }

    m_lastCursorRectValid = false;
    m_window = nullptr;
    m_fontsConfigured = false;
    m_offscreenPixels.clear();
    m_offscreenWidth = 0;
    m_offscreenHeight = 0;
    m_offscreenFormat = -1;
    m_offscreenValid = false;
    m_needFullRepaint = true;
    resetBufferBlitHistory();
    m_offscreenRows = 0;
    m_offscreenRowHeight = 0.0f;
}

void NativeDrawingRenderer::resize(uint32_t width, uint32_t height)
{
    m_width = width;
    m_height = height;
    m_needFullRepaint = true;
    configureWindow();
}

bool NativeDrawingRenderer::loadFontAtlas(NativeResourceManager* resourceManager, const std::string& filesDir)
{
    if (!m_fontCollection) {
        return false;
    }
    if (m_fontsConfigured) {
        return true;
    }

    if (RegisterReadableFonts(m_fontCollection, m_primaryFontFamily.c_str()) == 0) {
        OH_LOG_WARN(LOG_APP, "No readable bundled/system mono font candidate found; using platform font fallback");
    }

    if (resourceManager && !filesDir.empty()) {
        const std::string fontDir = filesDir + "/fonts";
        const size_t bundled = RegisterBundledTerminalFonts(m_fontCollection, resourceManager, fontDir);
        if (bundled == 0) {
            OH_LOG_WARN(LOG_APP, "No bundled terminal font registered; falling back to platform fonts");
        }
        RegisterPrivateFallbackFontIfPresent(m_fontCollection, resourceManager, fontDir);
    }

    m_fontsConfigured = true;
    updateCellDimensions();
    m_needFullRepaint = true;
    return true;
}

bool NativeDrawingRenderer::ensureOffscreen(uint32_t width, uint32_t height)
{
    if (width == 0 || height == 0) {
        return false;
    }
    if (m_offscreenWidth != width || m_offscreenHeight != height ||
        m_offscreenFormat != m_currentConfig.format) {
        m_offscreenPixels.assign(static_cast<size_t>(width) * height * 4, 0);
        m_offscreenWidth = width;
        m_offscreenHeight = height;
        m_offscreenFormat = m_currentConfig.format;
        m_offscreenValid = false;
        // Every rotating window buffer is now a different size/format, so their
        // recorded staleness no longer applies: force whole-surface blits until
        // each buffer has been fully repainted at least once.
        resetBufferBlitHistory();
    }
    return true;
}

void NativeDrawingRenderer::beginFrame()
{
    if (!m_window || !m_canvas) {
        return;
    }

    m_currentFrameId = ++g_frameCounter;
    OH_HiTrace_CountTrace(
        "Emberline.SurfacePixels",
        static_cast<int64_t>(m_width) * static_cast<int64_t>(m_height));
    // Reset this frame's offscreen-change accounting; shiftOffscreen may set it
    // before renderGrid, and renderGrid records the rows it repaints.
    m_shiftedThisFrame = false;

    if (m_currentFenceFd >= 0) {
        close(m_currentFenceFd);
        m_currentFenceFd = -1;
    }

    m_currentBuffer = nullptr;
    m_currentNativeBuffer = nullptr;
    m_currentPixels = nullptr;
    m_currentConfig = {};
    int fenceFd = -1;
    if (OH_NativeWindow_NativeWindowRequestBuffer(m_window, &m_currentBuffer, &fenceFd) != 0 || !m_currentBuffer) {
        OH_LOG_ERROR(LOG_APP, "RequestBuffer failed frame=%{public}" PRIu64 " window=%{public}p",
            m_currentFrameId, m_window);
        return;
    }

    m_currentFenceFd = fenceFd;

    if (OH_NativeBuffer_FromNativeWindowBuffer(m_currentBuffer, &m_currentNativeBuffer) != 0 || !m_currentNativeBuffer) {
        OH_LOG_ERROR(LOG_APP, "FromNativeWindowBuffer failed frame=%{public}" PRIu64 " buffer=%{public}p fence=%{public}d",
            m_currentFrameId, m_currentBuffer, m_currentFenceFd);
        OH_NativeWindow_NativeWindowAbortBuffer(m_window, m_currentBuffer);
        if (m_currentFenceFd >= 0) {
            close(m_currentFenceFd);
        }
        m_currentFenceFd = -1;
        m_currentBuffer = nullptr;
        m_currentNativeBuffer = nullptr;
        return;
    }

    OH_NativeBuffer_GetConfig(m_currentNativeBuffer, &m_currentConfig);
    const uint32_t seqNum = OH_NativeBuffer_GetSeqNum(m_currentNativeBuffer);
    if (OH_NativeBuffer_Map(m_currentNativeBuffer, &m_currentPixels) != 0 || !m_currentPixels) {
        OH_LOG_ERROR(LOG_APP, "NativeBuffer map failed frame=%{public}" PRIu64 " seq=%{public}u",
            m_currentFrameId, seqNum);
        OH_NativeWindow_NativeWindowAbortBuffer(m_window, m_currentBuffer);
        if (m_currentFenceFd >= 0) {
            close(m_currentFenceFd);
        }
        m_currentFenceFd = -1;
        m_currentBuffer = nullptr;
        m_currentNativeBuffer = nullptr;
        m_currentPixels = nullptr;
        m_currentConfig = {};
        return;
    }

    // Draw into the persistent offscreen image, not the freshly dequeued
    // window buffer: buffer queues rotate buffers, so partial repaints must
    // accumulate somewhere stable and be blitted whole in endFrame().
    if (!ensureOffscreen(static_cast<uint32_t>(m_currentConfig.width),
                         static_cast<uint32_t>(m_currentConfig.height))) {
        OH_NativeBuffer_Unmap(m_currentNativeBuffer);
        OH_NativeWindow_NativeWindowAbortBuffer(m_window, m_currentBuffer);
        if (m_currentFenceFd >= 0) {
            close(m_currentFenceFd);
        }
        m_currentFenceFd = -1;
        m_currentBuffer = nullptr;
        m_currentNativeBuffer = nullptr;
        m_currentPixels = nullptr;
        m_currentConfig = {};
        return;
    }

    OH_Drawing_Image_Info info;
    info.width = m_currentConfig.width;
    info.height = m_currentConfig.height;
    info.colorType = m_currentConfig.format == NATIVEBUFFER_PIXEL_FMT_BGRA_8888
        ? COLOR_FORMAT_BGRA_8888
        : COLOR_FORMAT_RGBA_8888;
    info.alphaType = ALPHA_FORMAT_PREMUL;

    OH_Drawing_Bitmap* bitmap = OH_Drawing_BitmapCreateFromPixels(
        &info,
        m_offscreenPixels.data(),
        m_offscreenWidth * 4);
    if (!bitmap) {
        OH_LOG_ERROR(LOG_APP, "BitmapCreateFromPixels failed frame=%{public}" PRIu64 " seq=%{public}u stride=%{public}d",
            m_currentFrameId, seqNum, m_currentConfig.stride);
        OH_NativeBuffer_Unmap(m_currentNativeBuffer);
        OH_NativeWindow_NativeWindowAbortBuffer(m_window, m_currentBuffer);
        if (m_currentFenceFd >= 0) {
            close(m_currentFenceFd);
        }
        m_currentFenceFd = -1;
        m_currentBuffer = nullptr;
        m_currentNativeBuffer = nullptr;
        m_currentPixels = nullptr;
        m_currentConfig = {};
        return;
    }

    OH_Drawing_CanvasBind(m_canvas, bitmap);
    OH_Drawing_BitmapDestroy(bitmap);
}

void NativeDrawingRenderer::renderGrid(const std::vector<Cell>& cells, int cols, int rows,
                                       int cursorRow, int cursorCol, bool cursorVisible,
                                       const std::vector<uint8_t>& dirtyRows)
{
    if (!m_canvas || !m_currentPixels) {
        return;
    }

    const bool fullRepaint = m_needFullRepaint || !m_offscreenValid ||
        dirtyRows.empty() || dirtyRows.size() != static_cast<size_t>(rows);
    if (fullRepaint) {
        OH_Drawing_CanvasClear(m_canvas, m_defaultBgColor);
    }

    const bool drawCursor = shouldRenderCursor(cursorVisible);

    const float cellWidth = getCellWidth();
    const float cellHeight = getCellHeight();
    m_lastCursorRectValid = false;
    if (drawCursor && cursorRow >= 0 && cursorRow < rows && cursorCol >= 0 && cursorCol < cols) {
        m_lastCursorLeft = static_cast<float>(cursorCol) * cellWidth;
        m_lastCursorTop = static_cast<float>(cursorRow) * cellHeight;
        m_lastCursorWidth = cellWidth;
        m_lastCursorHeight = cellHeight;
        m_lastCursorRectValid = true;
    }
    // Persistent geometry mask: reused across frames and resized only when the
    // grid geometry changes, so a partial repaint never reallocates/zeroes the
    // whole rows*cols scratch. Each processed row is cleared just below.
    const size_t geometryCells = static_cast<size_t>(rows) * static_cast<size_t>(cols);
    if (m_geometryMask.size() != geometryCells) {
        m_geometryMask.assign(geometryCells, 0);
    }
    uint8_t* geometryMask = m_geometryMask.data();

    for (int row = 0; row < rows; ++row) {
        if (!fullRepaint && dirtyRows[static_cast<size_t>(row)] == 0) {
            continue;
        }
        // Clear only this row's marks before the first pass repopulates them;
        // stale marks in non-dirty rows are never read (the text pass skips the
        // same rows).
        std::fill_n(geometryMask + static_cast<size_t>(row) * static_cast<size_t>(cols),
                    static_cast<size_t>(cols), static_cast<uint8_t>(0));
        uint32_t rowBg = m_defaultBgColor;
        bool rowBgSeen = false;
        for (int col = 0; col < cols; ++col) {
            const Cell& cell = cells[row * cols + col];
            if (cell.width == 3 || cell.width == 4) {
                continue;
            }

            const uint8_t span = cell.width == 2 ? 2 : 1;
            uint32_t fg = cell.attrs.inverse ? cell.attrs.bg : cell.attrs.fg;
            uint32_t bg = cell.attrs.inverse ? cell.attrs.fg : cell.attrs.bg;
            const bool cursorHere = drawCursor && row == cursorRow && col == cursorCol;

            if (cursorHere && m_cursorStyle == 0) {
                fg = m_cursorFgColor;
                bg = m_cursorBgColor;
            }

            const float left = col * cellWidth;
            const float top = row * cellHeight;
            const float width = cellWidth * span;
            CellAttributes visualAttrs = cell.attrs;
            visualAttrs.fg = fg;
            visualAttrs.bg = bg;
            visualAttrs.inverse = false;
            // Default-background cells honor the configured background
            // opacity; explicitly colored cells stay opaque
            // (ghostty background-opacity-cells = false).
            const uint32_t paintBg =
                (bg | 0xFF000000u) == m_defaultBgOpaque ? m_defaultBgColor : bg;
            rowBg = paintBg;
            rowBgSeen = true;

            paintCellBackground(left, top, width, cellHeight, paintBg);

            if (paintBuiltinGlyph(cell, visualAttrs, left, top, width, cellHeight)) {
                geometryMask[static_cast<size_t>(row * cols + col)] = 1;
            }

            if (cursorHere && m_cursorStyle != 0) {
                const uint32_t cursorColor = m_cursorBgColor ? m_cursorBgColor : m_defaultFgColor;
                if (m_cursorStyle == 1) {
                    paintCursor(left, top + cellHeight - std::max(2.0f, cellHeight * 0.08f),
                                width, std::max(2.0f, cellHeight * 0.08f), cursorColor);
                } else {
                    paintCursor(left, top, std::max(2.0f, width * 0.12f), cellHeight, cursorColor);
                }
            }

            if (span == 2) {
                ++col;
            }
        }

        const float paintedWidth = cols * cellWidth;
        if (paintedWidth < static_cast<float>(m_width)) {
            paintCellBackground(
                paintedWidth,
                row * cellHeight,
                static_cast<float>(m_width) - paintedWidth,
                cellHeight,
                rowBgSeen ? rowBg : m_defaultBgColor);
        }
    }

    for (int row = 0; row < rows; ++row) {
        if (!fullRepaint && dirtyRows[static_cast<size_t>(row)] == 0) {
            continue;
        }
        int col = 0;
        while (col < cols) {
            const Cell& cell = cells[row * cols + col];
            if (cell.width == 3 || cell.width == 4) {
                ++col;
                continue;
            }
            if (geometryMask[static_cast<size_t>(row * cols + col)] != 0) {
                col += (cell.width == 2 ? 2 : 1);
                continue;
            }

            const uint8_t span = cell.width == 2 ? 2 : 1;
            CellAttributes visualAttrs = cell.attrs;
            visualAttrs.fg = cell.attrs.inverse ? cell.attrs.bg : cell.attrs.fg;
            visualAttrs.bg = cell.attrs.inverse ? cell.attrs.fg : cell.attrs.bg;
            visualAttrs.inverse = false;
            const bool cursorHere = drawCursor && row == cursorRow && col == cursorCol;
            if (cursorHere && m_cursorStyle == 0) {
                visualAttrs.fg = m_cursorFgColor;
                visualAttrs.bg = m_cursorBgColor;
            }

            const std::string firstText = cellText(cell);
            if (visualAttrs.hidden || IsBlankText(firstText)) {
                col += span;
                continue;
            }

            const int startCol = col;
            int runCols = span;
            std::string runText = firstText;
            int nextCol = col + span;

            while (nextCol < cols) {
                const Cell& nextCell = cells[row * cols + nextCol];
                if (nextCell.width == 3 || nextCell.width == 4) {
                    break;
                }
                if (geometryMask[static_cast<size_t>(row * cols + nextCol)] != 0) {
                    break;
                }

                const uint8_t nextSpan = nextCell.width == 2 ? 2 : 1;
                CellAttributes nextAttrs = nextCell.attrs;
                nextAttrs.fg = nextCell.attrs.inverse ? nextCell.attrs.bg : nextCell.attrs.fg;
                nextAttrs.bg = nextCell.attrs.inverse ? nextCell.attrs.fg : nextCell.attrs.bg;
                nextAttrs.inverse = false;
                const bool nextCursorHere = drawCursor && row == cursorRow && nextCol == cursorCol;
                if (nextCursorHere && m_cursorStyle == 0) {
                    std::swap(nextAttrs.fg, nextAttrs.bg);
                }

                const std::string nextText = cellText(nextCell);
                if (nextAttrs.hidden || IsBlankText(nextText) || !SameVisualTextStyle(visualAttrs, nextAttrs)) {
                    break;
                }

                runText += nextText;
                runCols += nextSpan;
                nextCol += nextSpan;
            }

            GlyphLayout* layout = getGlyphLayout(runText, visualAttrs, static_cast<uint8_t>(std::min(runCols, 255)));
            if (layout && layout->typography) {
                const float left = startCol * cellWidth;
                const float top = row * cellHeight;
                const float y = top + std::max(0.0f, (cellHeight - layout->height) * 0.5f);
                OH_Drawing_TypographyPaint(layout->typography, m_canvas, left, y);
            }

            col = nextCol;
        }
    }

    m_needFullRepaint = false;
    m_offscreenValid = true;

    // Record which offscreen rows changed this frame so endFrame can age the
    // rotating window buffers. A whole-surface repaint or an offscreen shift
    // (scroll damage) touches the whole image; otherwise only the dirty rows
    // renderGrid actually repainted changed.
    m_offscreenRows = rows;
    m_offscreenRowHeight = cellHeight;
    if (fullRepaint || m_shiftedThisFrame) {
        m_frameOffscreenFull = true;
    } else {
        m_frameOffscreenFull = false;
        if (static_cast<int>(m_frameOffscreenRows.size()) != rows) {
            m_frameOffscreenRows.assign(static_cast<size_t>(rows), 0);
        }
        // !fullRepaint implies dirtyRows.size() == rows (see the guard above).
        for (int r = 0; r < rows; ++r) {
            m_frameOffscreenRows[static_cast<size_t>(r)] = dirtyRows[static_cast<size_t>(r)] ? 1 : 0;
        }
    }
}

void NativeDrawingRenderer::resetBufferBlitHistory()
{
    m_bufferBlit.clear();
    m_frameOffscreenFull = true;
    m_frameOffscreenRows.clear();
}

uint32_t NativeDrawingRenderer::backgroundFillPixel() const
{
    const uint32_t c = m_defaultBgColor;  // 0xAARRGGBB
    const uint32_t a = (c >> 24) & 0xFFu;
    const uint32_t r = (c >> 16) & 0xFFu;
    const uint32_t g = (c >> 8) & 0xFFu;
    const uint32_t b = c & 0xFFu;
    return m_currentConfig.format == NATIVEBUFFER_PIXEL_FMT_BGRA_8888
        ? ((a << 24) | (r << 16) | (g << 8) | b)
        : ((a << 24) | (b << 16) | (g << 8) | r);
}

// Half-open pixel span top..bottom covering grid row `row`. Over-covers the
// boundaries via floor-top / ceil-bottom so a partial blit never leaves a seam,
// pins row 0 to the top edge and the last row to the offscreen bottom so the
// sub-row strip below the grid is always included.
void NativeDrawingRenderer::pixelRowSpan(int row, int rowsTotal, int32_t& top, int32_t& bottom) const
{
    const float h = m_offscreenRowHeight > 0.0f ? m_offscreenRowHeight : getCellHeight();
    int32_t ti = static_cast<int32_t>(std::floor(static_cast<float>(row) * h));
    int32_t bi = static_cast<int32_t>(std::ceil(static_cast<float>(row + 1) * h));
    if (row <= 0) {
        ti = 0;
    }
    if (row >= rowsTotal - 1) {
        bi = static_cast<int32_t>(m_offscreenHeight);
    }
    if (ti < 0) {
        ti = 0;
    }
    if (bi > static_cast<int32_t>(m_offscreenHeight)) {
        bi = static_cast<int32_t>(m_offscreenHeight);
    }
    top = ti;
    bottom = bi;
}

void NativeDrawingRenderer::shiftOffscreen(int rowDelta)
{
    // Only shift when a buffer is actually bound this frame; if beginFrame
    // failed (no m_currentPixels) renderGrid will bail too, so leaving the
    // offscreen untouched keeps it consistent with what gets presented.
    if (rowDelta == 0 || !m_offscreenValid || !m_currentPixels) {
        return;
    }
    const float h = getCellHeight();
    const int32_t pixelShift =
        static_cast<int32_t>(std::lround(static_cast<double>(rowDelta) * static_cast<double>(h)));
    const int32_t height = static_cast<int32_t>(m_offscreenHeight);
    if (pixelShift == 0 || (pixelShift > 0 ? pixelShift : -pixelShift) >= height) {
        return;
    }

    const size_t rowBytes = static_cast<size_t>(m_offscreenWidth) * 4;
    uint8_t* base = m_offscreenPixels.data();
    if (pixelShift > 0) {
        // Content moves up: offscreen row y takes old row y + pixelShift; the
        // bottom pixelShift rows are the newly exposed band (repainted later).
        std::memmove(base,
                     base + static_cast<size_t>(pixelShift) * rowBytes,
                     static_cast<size_t>(height - pixelShift) * rowBytes);
    } else {
        const int32_t a = -pixelShift;
        // Content moves down: offscreen row y takes old row y - a; the top a
        // rows are the newly exposed band.
        std::memmove(base + static_cast<size_t>(a) * rowBytes,
                     base,
                     static_cast<size_t>(height - a) * rowBytes);
    }

    // Keep the sub-row strip below the last grid row at the background color;
    // the memmove otherwise drags scrolled content into it.
    if (m_offscreenRows > 0 && m_offscreenRowHeight > 0.0f) {
        int32_t gridBottom = static_cast<int32_t>(std::lround(
            static_cast<double>(m_offscreenRows) * static_cast<double>(m_offscreenRowHeight)));
        if (gridBottom < 0) {
            gridBottom = 0;
        }
        if (gridBottom < height) {
            const uint32_t fillPx = backgroundFillPixel();
            for (int32_t y = gridBottom; y < height; ++y) {
                uint32_t* px = reinterpret_cast<uint32_t*>(base + static_cast<size_t>(y) * rowBytes);
                std::fill(px, px + m_offscreenWidth, fillPx);
            }
        }
    }

    m_shiftedThisFrame = true;
}

void NativeDrawingRenderer::endFrame()
{
    if (!m_window || !m_currentBuffer) {
        return;
    }

    m_damageRects.clear();
    bool fullDamage = true;  // default to whole-surface damage (always safe)

    const bool dimsOk = m_currentPixels && m_offscreenValid &&
        m_offscreenWidth == static_cast<uint32_t>(m_currentConfig.width) &&
        m_offscreenHeight == static_cast<uint32_t>(m_currentConfig.height);
    const uint32_t seqNum = m_currentNativeBuffer ? OH_NativeBuffer_GetSeqNum(m_currentNativeBuffer) : 0;
    const int shift = static_cast<int>(std::lround(getScrollFraction()));

    if (dimsOk) {
        const uint32_t rowBytes = m_offscreenWidth * 4;
        const uint32_t dstStride = static_cast<uint32_t>(m_currentConfig.stride);
        uint8_t* dst = static_cast<uint8_t*>(m_currentPixels);
        const uint8_t* srcPixels = m_offscreenPixels.data();
        const int32_t height = static_cast<int32_t>(m_offscreenHeight);
        const int rows = m_offscreenRows;
        // If the per-row change map is missing or mis-sized, treat this frame as
        // a whole-surface change (safe over-report) rather than index into it.
        const bool frameFull = m_frameOffscreenFull ||
            static_cast<int>(m_frameOffscreenRows.size()) != rows;

        // A healthy buffer queue rotates a handful of buffers; if their seq
        // numbers ever churn without an offscreen resize, drop the history to
        // bound memory (the next presents just fall back to full blits).
        if (m_bufferBlit.size() > 32) {
            m_bufferBlit.clear();
        }

        // Age every known rotating buffer by this frame's offscreen changes so
        // each records exactly the rows that went stale while it was off screen.
        for (auto& kv : m_bufferBlit) {
            if (frameFull) {
                kv.second.full = true;
            } else if (!kv.second.full) {
                if (static_cast<int>(kv.second.staleRows.size()) != rows) {
                    kv.second.full = true;
                } else {
                    for (int r = 0; r < rows; ++r) {
                        if (m_frameOffscreenRows[static_cast<size_t>(r)]) {
                            kv.second.staleRows[static_cast<size_t>(r)] = 1;
                        }
                    }
                }
            }
        }

        BufferBlitState& cur = m_bufferBlit[seqNum];
        if (static_cast<int>(cur.staleRows.size()) != rows) {
            cur.staleRows.assign(static_cast<size_t>(rows > 0 ? rows : 0), 0);
            cur.full = true;  // freshly sized / never seen -> unknown content
        }

        // A change in the presented shift moves every on-screen row relative to
        // the previous flush, so partial damage would tear: force a full frame.
        const bool needFull = cur.full || shift != 0 || cur.lastShift != shift ||
            shift != m_lastPresentedShift || frameFull || rows <= 0;

        if (needFull) {
            if (shift == 0) {
                if (dstStride == rowBytes) {
                    std::memcpy(dst, srcPixels, static_cast<size_t>(rowBytes) * m_offscreenHeight);
                } else {
                    for (uint32_t y = 0; y < m_offscreenHeight; ++y) {
                        std::memcpy(dst + static_cast<size_t>(y) * dstStride,
                                    srcPixels + static_cast<size_t>(y) * rowBytes,
                                    rowBytes);
                    }
                }
            } else {
                // Smooth-scroll presentation: dst row y shows offscreen row
                // y + shift; rows shifted past the offscreen edge become default
                // background (the gap is at most one cell tall and only visible
                // while a scroll gesture or fling is in motion).
                const uint32_t fillPx = backgroundFillPixel();
                for (int32_t y = 0; y < height; ++y) {
                    uint8_t* dstRow = dst + static_cast<size_t>(y) * dstStride;
                    const int32_t srcY = y + shift;
                    if (srcY >= 0 && srcY < height) {
                        std::memcpy(dstRow, srcPixels + static_cast<size_t>(srcY) * rowBytes, rowBytes);
                    } else {
                        uint32_t* px = reinterpret_cast<uint32_t*>(dstRow);
                        std::fill(px, px + m_offscreenWidth, fillPx);
                    }
                }
            }
            fullDamage = true;
            if (!cur.staleRows.empty()) {
                std::fill(cur.staleRows.begin(), cur.staleRows.end(), 0);
            }
            // A shifted blit is not a clean 1:1 copy of the offscreen, so the
            // buffer must be fully rewritten when it is reused.
            cur.full = (shift != 0);
            cur.lastShift = shift;
        } else {
            // Partial present (shift == 0): copy only the rows that went stale
            // in *this* buffer, and report them as the damage region.
            fullDamage = false;
            int r = 0;
            while (r < rows) {
                if (!cur.staleRows[static_cast<size_t>(r)]) {
                    ++r;
                    continue;
                }
                int r1 = r;
                while (r1 + 1 < rows && cur.staleRows[static_cast<size_t>(r1 + 1)]) {
                    ++r1;
                }
                int32_t ytop = 0;
                int32_t dummy = 0;
                int32_t ybot = 0;
                pixelRowSpan(r, rows, ytop, dummy);
                pixelRowSpan(r1, rows, dummy, ybot);
                if (ytop < 0) {
                    ytop = 0;
                }
                if (ybot > height) {
                    ybot = height;
                }
                for (int32_t y = ytop; y < ybot; ++y) {
                    std::memcpy(dst + static_cast<size_t>(y) * dstStride,
                                srcPixels + static_cast<size_t>(y) * rowBytes,
                                rowBytes);
                }
                if (ybot > ytop) {
                    Region::Rect rect;
                    rect.x = 0;
                    rect.y = ytop;
                    rect.w = m_offscreenWidth;
                    rect.h = static_cast<uint32_t>(ybot - ytop);
                    m_damageRects.push_back(rect);
                }
                r = r1 + 1;
            }
            std::fill(cur.staleRows.begin(), cur.staleRows.end(), 0);
            cur.full = false;
            cur.lastShift = 0;
            // No rows actually differed for this buffer: fall back to a
            // whole-surface damage flush (0 rects == full) since the API cannot
            // express an empty region.
            if (m_damageRects.empty()) {
                fullDamage = true;
            }
        }
    } else {
        // Could not reconcile this buffer with the offscreen this frame; present
        // whatever it holds and mark it stale so it gets a full blit later.
        if (seqNum != 0) {
            m_bufferBlit[seqNum].full = true;
        }
        fullDamage = true;
    }

    // Always report whole-surface damage to the compositor. When this opaque
    // SURFACE is fullscreen and focused it can be promoted to hardware direct
    // composition, and on that path frames flushed with a small partial
    // dirtyRegion do not refresh the display at all: with tmux idle, the
    // per-second timer row (a 1-2 rect partial frame) stays frozen until a
    // scroll produces a full-damage frame, while a small or unfocused window
    // (GPU composition) presents the same frames fine. The pre-buffer-age
    // stable build always flushed full frames and never showed this. The
    // incremental blit above still skips unchanged rows, so only the damage
    // *report* is widened; m_damageRects stays collected in case partial
    // reporting can return behind a direct-composition check.
    Region dirtyRegion {};
    dirtyRegion.rects = nullptr;
    dirtyRegion.rectNumber = 0;
    (void)fullDamage;
    if (m_currentNativeBuffer) {
        OH_NativeBuffer_Unmap(m_currentNativeBuffer);
        m_currentPixels = nullptr;
    }
    const int32_t flushRet =
        OH_NativeWindow_NativeWindowFlushBuffer(m_window, m_currentBuffer, m_currentFenceFd, dirtyRegion);
    if (flushRet != 0) {
        OH_LOG_ERROR(LOG_APP, "FlushBuffer failed frame=%{public}" PRIu64 " seq=%{public}u ret=%{public}d fence=%{public}d",
            m_currentFrameId, seqNum, flushRet, m_currentFenceFd);
        OH_NativeWindow_NativeWindowAbortBuffer(m_window, m_currentBuffer);
        if (m_currentFenceFd >= 0) {
            close(m_currentFenceFd);
        }
    } else {
        // Successfully presented: remember the shift now on screen so the next
        // frame can detect a shift transition and damage the whole surface.
        m_lastPresentedShift = shift;
    }

    m_currentFenceFd = -1;
    m_currentBuffer = nullptr;
    if (m_currentNativeBuffer) {
        m_currentNativeBuffer = nullptr;
    }
    m_currentPixels = nullptr;
    m_currentConfig = {};
}

bool NativeDrawingRenderer::registerCustomFont(const std::string& fontPath)
{
    if (!m_fontCollection || fontPath.empty() || access(fontPath.c_str(), R_OK) != 0) {
        return false;
    }

    const uint32_t rc =
        OH_Drawing_RegisterFont(m_fontCollection, kCustomTerminalFontFamily, fontPath.c_str());
    OH_LOG_INFO(LOG_APP, "Registered custom terminal font rc=%u path=%{public}s", rc, fontPath.c_str());
    if (rc != 0) {
        return false;
    }

    destroyGlyphCache();
    updateCellDimensions();
    m_needFullRepaint = true;
    return true;
}

void NativeDrawingRenderer::setFontFamily(const std::string& family)
{
    const std::string nextFamily = family.empty() ? "FusionTerm Maple Mono" : family;
    if (m_preferredFontFamily == nextFamily) {
        return;
    }

    m_preferredFontFamily = nextFamily;
    destroyGlyphCache();
    updateCellDimensions();
    m_needFullRepaint = true;
}

void NativeDrawingRenderer::onFontMetricsChanged()
{
    destroyGlyphCache();
}

void NativeDrawingRenderer::updateCellDimensions()
{
    Renderer::updateCellDimensions();

    if (!m_fontCollection || !m_fontsConfigured) {
        return;
    }

    Cell probeCell;
    probeCell.codepoint = 'M';
    const char probe[] = "M";
    std::memcpy(probeCell.text, probe, sizeof(probe));
    probeCell.textLen = 1;
    probeCell.attrs.fg = m_defaultFgColor;
    GlyphLayout* layout = getGlyphLayout("M", probeCell.attrs, 1);
    if (layout && layout->width > 0.0f && layout->height > 0.0f) {
        // Keep the measured advance EXACT (no ceil): text runs are painted as
        // one shaped paragraph whose glyphs step by the font's fractional
        // advance, while the grid (run origins, cursor, selection) steps by
        // m_cellWidth. Rounding up made every column drift ~1px apart, so
        // long lines showed growing gaps between runs and the cursor floated
        // away from the text -- worse at larger font sizes.
        m_cellWidth = std::max(layout->width, 1.0f);
        m_cellHeight = std::ceil(std::max(layout->height * 1.05f, 1.0f));
    }
}

bool NativeDrawingRenderer::configureWindow()
{
    if (!m_window) {
        return false;
    }

    if (OH_NativeWindow_NativeWindowHandleOpt(m_window, SET_BUFFER_GEOMETRY,
                                              static_cast<int32_t>(m_width),
                                              static_cast<int32_t>(m_height)) != 0) {
        OH_LOG_ERROR(LOG_APP, "SET_BUFFER_GEOMETRY failed");
        return false;
    }
    if (OH_NativeWindow_NativeWindowHandleOpt(m_window, SET_FORMAT,
                                              static_cast<int32_t>(NATIVEBUFFER_PIXEL_FMT_RGBA_8888)) != 0) {
        OH_LOG_ERROR(LOG_APP, "SET_FORMAT failed");
        return false;
    }
    if (OH_NativeWindow_NativeWindowHandleOpt(m_window, SET_USAGE, static_cast<uint64_t>(kBufferUsage)) != 0) {
        OH_LOG_ERROR(LOG_APP, "SET_USAGE failed");
        return false;
    }
    return true;
}

bool NativeDrawingRenderer::ensureDrawingObjects()
{
    if (!m_canvas) {
        m_canvas = OH_Drawing_CanvasCreate();
    }
    if (!m_brush) {
        m_brush = OH_Drawing_BrushCreate();
    }
    if (!m_rect) {
        m_rect = OH_Drawing_RectCreate(0.0f, 0.0f, 0.0f, 0.0f);
    }
    return m_canvas && m_brush && m_rect;
}

void NativeDrawingRenderer::destroyGlyphCache()
{
    for (auto& entry : m_glyphCache) {
        if (entry.second.typography) {
            OH_Drawing_DestroyTypography(entry.second.typography);
        }
    }
    m_glyphCache.clear();
}

void NativeDrawingRenderer::trimGlyphCache()
{
    if (m_glyphCache.size() <= kMaxGlyphCacheEntries) {
        return;
    }
    // Evict roughly half instead of nuking the whole cache: a full clear
    // forces every visible glyph to re-shape on the next frame (a visible
    // stutter), while partial eviction keeps the hot set warm.
    size_t index = 0;
    for (auto it = m_glyphCache.begin(); it != m_glyphCache.end();) {
        if ((index++ & 1) == 0) {
            if (it->second.typography) {
                OH_Drawing_DestroyTypography(it->second.typography);
            }
            it = m_glyphCache.erase(it);
        } else {
            ++it;
        }
    }
}

NativeDrawingRenderer::GlyphLayout* NativeDrawingRenderer::getGlyphLayout(
    const std::string& text,
    const CellAttributes& attrs,
    uint8_t span)
{
    if (!m_fontCollection) {
        return nullptr;
    }

    GlyphKey key;
    key.text = text;
    key.fg = attrs.fg;
    key.styleBits = makeStyleBits(attrs);
    key.span = span;

    auto it = m_glyphCache.find(key);
    if (it != m_glyphCache.end()) {
        return &it->second;
    }

    OH_Drawing_TypographyStyle* typographyStyle = OH_Drawing_CreateTypographyStyle();
    OH_Drawing_TextStyle* textStyle = OH_Drawing_CreateTextStyle();
    if (!typographyStyle || !textStyle) {
        if (typographyStyle) {
            OH_Drawing_DestroyTypographyStyle(typographyStyle);
        }
        if (textStyle) {
            OH_Drawing_DestroyTextStyle(textStyle);
        }
        return nullptr;
    }

    OH_Drawing_SetTypographyTextDirection(typographyStyle, TEXT_DIRECTION_LTR);
    OH_Drawing_SetTypographyTextAlign(typographyStyle, TEXT_ALIGN_START);
    OH_Drawing_SetTypographyTextMaxLines(typographyStyle, 1);

    OH_Drawing_SetTextStyleColor(textStyle, attrs.fg);
    OH_Drawing_SetTextStyleFontSize(textStyle, std::max(1.0, static_cast<double>(m_fontSize * m_density)));
    OH_Drawing_SetTextStyleFontWeight(textStyle, attrs.bold ? FONT_WEIGHT_700 : FONT_WEIGHT_400);
    OH_Drawing_SetTextStyleFontStyle(textStyle, attrs.italic ? FONT_STYLE_ITALIC : FONT_STYLE_NORMAL);
    OH_Drawing_SetTextStyleBaseLine(textStyle, TEXT_BASELINE_ALPHABETIC);
    if (attrs.underline) {
        OH_Drawing_AddTextStyleDecoration(textStyle, TEXT_DECORATION_UNDERLINE);
    }
    if (attrs.strikethrough) {
        OH_Drawing_AddTextStyleDecoration(textStyle, TEXT_DECORATION_LINE_THROUGH);
    }
    OH_Drawing_SetTextStyleDecorationColor(textStyle, attrs.fg);
    OH_Drawing_TextStyleAddFontFeature(textStyle, "liga", 0);
    OH_Drawing_TextStyleAddFontFeature(textStyle, "clig", 0);
    OH_Drawing_TextStyleAddFontFeature(textStyle, "calt", 0);
    std::vector<const char*> families;
    families.reserve(kBundledFamilyFallbackOrder.size() + kTerminalFontFamilies.size() + 3);
    PushUniqueFontFamily(families, m_preferredFontFamily.c_str());
    for (const char* family : kBundledFamilyFallbackOrder) {
        PushUniqueFontFamily(families, family);
    }
    PushUniqueFontFamily(families, kDefaultTerminalFontFamily);
    PushUniqueFontFamily(families, m_primaryFontFamily.c_str());
    PushUniqueFontFamily(families, m_symbolFontFamily.c_str());
    for (const char* family : kTerminalFontFamilies) {
        PushUniqueFontFamily(families, family);
    }
    OH_Drawing_SetTextStyleFontFamilies(textStyle,
                                        static_cast<int>(families.size()),
                                        families.data());
    OH_Drawing_SetTextStyleLocale(textStyle, "zh-Hans");

    OH_Drawing_TypographyCreate* handler = OH_Drawing_CreateTypographyHandler(typographyStyle, m_fontCollection);
    if (!handler) {
        OH_LOG_ERROR(LOG_APP,
            "Typography handler creation failed frame=%{public}" PRIu64 " span=%{public}u: run paints blank",
            m_currentFrameId,
            span);
        OH_Drawing_DestroyTextStyle(textStyle);
        OH_Drawing_DestroyTypographyStyle(typographyStyle);
        return nullptr;
    }

    const std::string glyph = key.text.empty() ? std::string(" ") : key.text;
    OH_Drawing_TypographyHandlerPushTextStyle(handler, textStyle);
    OH_Drawing_TypographyHandlerAddText(handler, glyph.c_str());
    OH_Drawing_TypographyHandlerPopTextStyle(handler);

    OH_Drawing_Typography* typography = OH_Drawing_CreateTypography(handler);
    OH_Drawing_DestroyTypographyHandler(handler);
    OH_Drawing_DestroyTextStyle(textStyle);
    OH_Drawing_DestroyTypographyStyle(typographyStyle);
    if (!typography) {
        OH_LOG_ERROR(LOG_APP,
            "CreateTypography failed frame=%{public}" PRIu64 " span=%{public}u preview=%{public}s: run paints blank",
            m_currentFrameId,
            span,
            HexPreview(glyph).c_str());
        return nullptr;
    }

    // The layout box must never constrain the run: glyphs are shaped by
    // fallback faces whose advances are NOT guaranteed to equal
    // span * m_cellWidth (m_cellWidth is measured from the primary face's
    // "M"; CJK usually resolves to a different face with its own full-width
    // advance). If the shaped width exceeds the box by even a fraction of a
    // pixel, the paragraph wraps the overflow onto a second line and
    // MaxLines(1) then silently drops those glyphs -- the reported
    // intermittent blank CJK cells (same char visible in one run, blank in
    // another, because run grouping changes the cumulative slack). Double
    // the box instead: painting is anchored at the cell origin with
    // TEXT_ALIGN_START, so slack never shifts output, and an oversized glyph
    // simply bleeds into the next cell (the same overhang ghostty allows)
    // instead of vanishing.
    const double maxWidth =
        std::max(1.0, static_cast<double>(m_cellWidth) * static_cast<double>(span) * 2.0);
    OH_Drawing_TypographyLayout(typography, maxWidth);
    const size_t unresolvedCount = OH_Drawing_TypographyGetUnresolvedGlyphsCount(typography);
    if (unresolvedCount > 0) {
        const std::string preview = HexPreview(glyph);
        OH_LOG_ERROR(LOG_APP,
            "Unresolved glyphs frame=%{public}" PRIu64 " count=%{public}zu cp=0x%{public}X span=%{public}u text=%{public}s preview=%{public}s",
            m_currentFrameId,
            unresolvedCount,
            0u,
            span,
            glyph.c_str(),
            preview.c_str());
    }
    if (glyph.size() == 1 && IsSuspiciousCodepoint(static_cast<uint8_t>(glyph[0]))) {
        const std::string preview = HexPreview(glyph);
        OH_LOG_ERROR(LOG_APP,
            "Suspicious cell frame=%{public}" PRIu64 " cp=0x%{public}X span=%{public}u preview=%{public}s",
            m_currentFrameId,
            static_cast<unsigned int>(static_cast<uint8_t>(glyph[0])),
            span,
            preview.c_str());
    }

    GlyphLayout layout;
    layout.typography = typography;
    layout.width = static_cast<float>(std::max(0.0, OH_Drawing_TypographyGetLongestLine(typography)));
    layout.height = static_cast<float>(std::max(0.0, OH_Drawing_TypographyGetHeight(typography)));

    // Trim BEFORE inserting: trimming after handed back a dangling pointer
    // whenever the every-other-entry eviction happened to delete the entry
    // just emplaced (~50% odds once the cache hits its cap), and the caller
    // immediately painted the destroyed Typography — the recurring CFI abort
    // in renderGrid after ~30 minutes of colorful TUI output.
    trimGlyphCache();
    auto [inserted, _] = m_glyphCache.emplace(key, layout);
    return &inserted->second;
}

void NativeDrawingRenderer::paintCellBackground(float left, float top, float width, float height, uint32_t color)
{
    OH_Drawing_BrushSetColor(m_brush, color);
    // SRC: replace destination pixels. Repainted rows must not blend the
    // translucent default background onto last frame's pixels.
    OH_Drawing_BrushSetBlendMode(m_brush, BLEND_MODE_SRC);
    OH_Drawing_CanvasAttachBrush(m_canvas, m_brush);
    OH_Drawing_RectSetLeft(m_rect, left);
    OH_Drawing_RectSetTop(m_rect, top);
    OH_Drawing_RectSetRight(m_rect, left + width);
    OH_Drawing_RectSetBottom(m_rect, top + height);
    OH_Drawing_CanvasDrawRect(m_canvas, m_rect);
    OH_Drawing_CanvasDetachBrush(m_canvas);
}

void NativeDrawingRenderer::paintCursor(float left, float top, float width, float height, uint32_t color)
{
    paintCellBackground(left, top, width, height, color);
}

void NativeDrawingRenderer::paintBuiltinRect(float left, float top, float width, float height, uint32_t color)
{
    if (width <= 0.0f || height <= 0.0f) {
        return;
    }
    paintCellBackground(left, top, width, height, color);
}

uint32_t NativeDrawingRenderer::blendColor(uint32_t bg, uint32_t fg, uint8_t alpha)
{
    const uint32_t inv = 255 - alpha;
    const uint32_t br = (bg >> 16) & 0xFF;
    const uint32_t bgc = (bg >> 8) & 0xFF;
    const uint32_t bb = bg & 0xFF;
    const uint32_t fr = (fg >> 16) & 0xFF;
    const uint32_t fgc = (fg >> 8) & 0xFF;
    const uint32_t fb = fg & 0xFF;
    const uint32_t r = (br * inv + fr * alpha) / 255;
    const uint32_t g = (bgc * inv + fgc * alpha) / 255;
    const uint32_t b = (bb * inv + fb * alpha) / 255;
    return 0xFF000000u | (r << 16) | (g << 8) | b;
}

void NativeDrawingRenderer::paintBuiltinLineHorizontal(
    float left, float top, float width, float cellHeight, LineStyle style,
    bool upperHalf, bool lowerHalf, uint32_t color)
{
    if (style == LineStyle::None) {
        return;
    }
    const float light = std::max(1.0f, std::round(cellHeight * 0.08f));
    const float heavy = std::max(light + 1.0f, std::round(cellHeight * 0.14f));
    const float thick = style == LineStyle::Heavy ? heavy : light;
    const float centerY = top + std::floor((cellHeight - thick) * 0.5f);
    if (style == LineStyle::Double) {
        const float gap = std::max(1.0f, light);
        paintBuiltinRect(left, centerY - gap, width, light, color);
        paintBuiltinRect(left, centerY + gap, width, light, color);
        return;
    }
    if (upperHalf || lowerHalf) {
        const float lineTop = upperHalf ? centerY : (centerY + thick * 0.5f);
        const float lineHeight = upperHalf && lowerHalf ? thick : std::max(1.0f, thick * 0.5f);
        paintBuiltinRect(left, lineTop, width, lineHeight, color);
        return;
    }
    paintBuiltinRect(left, centerY, width, thick, color);
}

void NativeDrawingRenderer::paintBuiltinLineVertical(
    float left, float top, float cellWidth, float height, LineStyle style,
    bool leftHalf, bool rightHalf, uint32_t color)
{
    if (style == LineStyle::None) {
        return;
    }
    const float light = std::max(1.0f, std::round(cellWidth * 0.08f));
    const float heavy = std::max(light + 1.0f, std::round(cellWidth * 0.14f));
    const float thick = style == LineStyle::Heavy ? heavy : light;
    const float centerX = left + std::floor((cellWidth - thick) * 0.5f);
    if (style == LineStyle::Double) {
        const float gap = std::max(1.0f, light);
        paintBuiltinRect(centerX - gap, top, light, height, color);
        paintBuiltinRect(centerX + gap, top, light, height, color);
        return;
    }
    if (leftHalf || rightHalf) {
        const float lineLeft = leftHalf ? centerX : (centerX + thick * 0.5f);
        const float lineWidth = leftHalf && rightHalf ? thick : std::max(1.0f, thick * 0.5f);
        paintBuiltinRect(lineLeft, top, lineWidth, height, color);
        return;
    }
    paintBuiltinRect(centerX, top, thick, height, color);
}

void NativeDrawingRenderer::paintBuiltinDiagonal(
    float left, float top, float width, float height, bool forwardSlash, uint32_t color)
{
    const float thickness = std::max(1.0f, std::round(std::min(width, height) * 0.08f));
    const int steps = std::max(1, static_cast<int>(std::ceil(std::max(width, height))));
    for (int i = 0; i < steps; ++i) {
        const float t = steps == 1 ? 0.0f : static_cast<float>(i) / static_cast<float>(steps - 1);
        const float x = left + t * (width - thickness);
        const float y = forwardSlash
            ? top + (1.0f - t) * (height - thickness)
            : top + t * (height - thickness);
        paintBuiltinRect(x, y, thickness, thickness, color);
    }
}

NativeDrawingRenderer::BoxGlyphEdges NativeDrawingRenderer::getBoxGlyphEdges(uint32_t codepoint)
{
    using S = LineStyle;
    switch (codepoint) {
        case 0x2500: return { S::None, S::Light, S::None, S::Light };
        case 0x2501: return { S::None, S::Heavy, S::None, S::Heavy };
        case 0x2502: return { S::Light, S::None, S::Light, S::None };
        case 0x2503: return { S::Heavy, S::None, S::Heavy, S::None };
        case 0x250C: return { S::None, S::Light, S::Light, S::None };
        case 0x2510: return { S::None, S::None, S::Light, S::Light };
        case 0x2514: return { S::Light, S::Light, S::None, S::None };
        case 0x2518: return { S::Light, S::None, S::None, S::Light };
        case 0x251C: return { S::Light, S::Light, S::Light, S::None };
        case 0x2524: return { S::Light, S::None, S::Light, S::Light };
        case 0x252C: return { S::None, S::Light, S::Light, S::Light };
        case 0x2534: return { S::Light, S::Light, S::None, S::Light };
        case 0x253C: return { S::Light, S::Light, S::Light, S::Light };
        case 0x2550: return { S::None, S::Double, S::None, S::Double };
        case 0x2551: return { S::Double, S::None, S::Double, S::None };
        case 0x2554: return { S::None, S::Double, S::Double, S::None };
        case 0x2557: return { S::None, S::None, S::Double, S::Double };
        case 0x255A: return { S::Double, S::Double, S::None, S::None };
        case 0x255D: return { S::Double, S::None, S::None, S::Double };
        case 0x2560: return { S::Double, S::Double, S::Double, S::None };
        case 0x2563: return { S::Double, S::None, S::Double, S::Double };
        case 0x2566: return { S::None, S::Double, S::Double, S::Double };
        case 0x2569: return { S::Double, S::Double, S::None, S::Double };
        case 0x256C: return { S::Double, S::Double, S::Double, S::Double };
        case 0x2574: return { S::None, S::None, S::None, S::Light };
        case 0x2575: return { S::Light, S::None, S::None, S::None };
        case 0x2576: return { S::None, S::Light, S::None, S::None };
        case 0x2577: return { S::None, S::None, S::Light, S::None };
        case 0x2578: return { S::None, S::None, S::None, S::Heavy };
        case 0x2579: return { S::Heavy, S::None, S::None, S::None };
        case 0x257A: return { S::None, S::Heavy, S::None, S::None };
        case 0x257B: return { S::None, S::None, S::Heavy, S::None };
        case 0x257C: return { S::None, S::Heavy, S::None, S::Light };
        case 0x257D: return { S::Light, S::None, S::Heavy, S::None };
        case 0x257E: return { S::None, S::Light, S::None, S::Heavy };
        case 0x257F: return { S::Heavy, S::None, S::Light, S::None };
        default: return {};
    }
}

bool NativeDrawingRenderer::paintBuiltinGlyph(
    const Cell& cell,
    const CellAttributes& attrs,
    float left,
    float top,
    float width,
    float height)
{
    if (cell.selected || cell.attrs.hidden || !IsBuiltinGeometryCodepoint(cell.codepoint)) {
        return false;
    }

    const uint32_t fg = attrs.fg;
    const uint32_t bg = attrs.bg;
    const uint32_t cp = cell.codepoint;

    if (cp >= 0x2580 && cp <= 0x259F) {
        switch (cp) {
            case 0x2580: paintBuiltinRect(left, top, width, height * 0.5f, fg); return true;
            case 0x2581: paintBuiltinRect(left, top + height * 0.875f, width, std::ceil(height * 0.125f), fg); return true;
            case 0x2582: paintBuiltinRect(left, top + height * 0.75f, width, std::ceil(height * 0.25f), fg); return true;
            case 0x2583: paintBuiltinRect(left, top + height * 0.625f, width, std::ceil(height * 0.375f), fg); return true;
            case 0x2584: paintBuiltinRect(left, top + height * 0.5f, width, std::ceil(height * 0.5f), fg); return true;
            case 0x2585: paintBuiltinRect(left, top + height * 0.375f, width, std::ceil(height * 0.625f), fg); return true;
            case 0x2586: paintBuiltinRect(left, top + height * 0.25f, width, std::ceil(height * 0.75f), fg); return true;
            case 0x2587: paintBuiltinRect(left, top + height * 0.125f, width, std::ceil(height * 0.875f), fg); return true;
            case 0x2588: paintBuiltinRect(left, top, width, height, fg); return true;
            case 0x2589: paintBuiltinRect(left, top, width * 0.875f, height, fg); return true;
            case 0x258A: paintBuiltinRect(left, top, width * 0.75f, height, fg); return true;
            case 0x258B: paintBuiltinRect(left, top, width * 0.625f, height, fg); return true;
            case 0x258C: paintBuiltinRect(left, top, width * 0.5f, height, fg); return true;
            case 0x258D: paintBuiltinRect(left, top, width * 0.375f, height, fg); return true;
            case 0x258E: paintBuiltinRect(left, top, width * 0.25f, height, fg); return true;
            case 0x258F: paintBuiltinRect(left, top, width * 0.125f, height, fg); return true;
            case 0x2590: paintBuiltinRect(left + width * 0.5f, top, width * 0.5f, height, fg); return true;
            case 0x2591: paintBuiltinRect(left, top, width, height, blendColor(bg, fg, 64)); return true;
            case 0x2592: paintBuiltinRect(left, top, width, height, blendColor(bg, fg, 128)); return true;
            case 0x2593: paintBuiltinRect(left, top, width, height, blendColor(bg, fg, 192)); return true;
            case 0x2594: paintBuiltinRect(left, top, width, std::ceil(height * 0.125f), fg); return true;
            case 0x2595: paintBuiltinRect(left + width * 0.875f, top, std::ceil(width * 0.125f), height, fg); return true;
            case 0x2596: paintBuiltinRect(left, top + height * 0.5f, width * 0.5f, height * 0.5f, fg); return true;
            case 0x2597: paintBuiltinRect(left + width * 0.5f, top + height * 0.5f, width * 0.5f, height * 0.5f, fg); return true;
            case 0x2598: paintBuiltinRect(left, top, width * 0.5f, height * 0.5f, fg); return true;
            case 0x2599:
                paintBuiltinRect(left, top, width * 0.5f, height, fg);
                paintBuiltinRect(left + width * 0.5f, top + height * 0.5f, width * 0.5f, height * 0.5f, fg);
                return true;
            case 0x259A:
                paintBuiltinRect(left, top, width * 0.5f, height * 0.5f, fg);
                paintBuiltinRect(left + width * 0.5f, top + height * 0.5f, width * 0.5f, height * 0.5f, fg);
                return true;
            case 0x259B:
                paintBuiltinRect(left, top, width, height * 0.5f, fg);
                paintBuiltinRect(left, top + height * 0.5f, width * 0.5f, height * 0.5f, fg);
                return true;
            case 0x259C:
                paintBuiltinRect(left, top, width, height * 0.5f, fg);
                paintBuiltinRect(left + width * 0.5f, top + height * 0.5f, width * 0.5f, height * 0.5f, fg);
                return true;
            case 0x259D: paintBuiltinRect(left + width * 0.5f, top, width * 0.5f, height * 0.5f, fg); return true;
            case 0x259E:
                paintBuiltinRect(left + width * 0.5f, top, width * 0.5f, height * 0.5f, fg);
                paintBuiltinRect(left, top + height * 0.5f, width * 0.5f, height * 0.5f, fg);
                return true;
            case 0x259F:
                paintBuiltinRect(left + width * 0.5f, top, width * 0.5f, height, fg);
                paintBuiltinRect(left, top + height * 0.5f, width * 0.5f, height * 0.5f, fg);
                return true;
            default:
                break;
        }
    }

    if (cp == 0x2571 || cp == 0x2572 || cp == 0x2573) {
        if (cp == 0x2571 || cp == 0x2573) {
            paintBuiltinDiagonal(left, top, width, height, true, fg);
        }
        if (cp == 0x2572 || cp == 0x2573) {
            paintBuiltinDiagonal(left, top, width, height, false, fg);
        }
        return true;
    }

    BoxGlyphEdges edges = getBoxGlyphEdges(cp);
    if (edges.up != LineStyle::None || edges.right != LineStyle::None ||
        edges.down != LineStyle::None || edges.left != LineStyle::None) {
        // Half-length strokes meet at the cell center; extend each stroke by
        // half the maximum stroke thickness so corners join without a notch.
        const float joinOverlap = std::max(1.0f, std::round(std::min(width, height) * 0.07f));
        if (edges.left != LineStyle::None) {
            paintBuiltinLineHorizontal(left, top, width * 0.5f + joinOverlap, height, edges.left, false, false, fg);
        }
        if (edges.right != LineStyle::None) {
            paintBuiltinLineHorizontal(left + width * 0.5f - joinOverlap, top, width * 0.5f + joinOverlap,
                                       height, edges.right, false, false, fg);
        }
        if (edges.up != LineStyle::None) {
            paintBuiltinLineVertical(left, top, width, height * 0.5f + joinOverlap, edges.up, false, false, fg);
        }
        if (edges.down != LineStyle::None) {
            paintBuiltinLineVertical(left, top + height * 0.5f - joinOverlap, width, height * 0.5f + joinOverlap,
                                     edges.down, false, false, fg);
        }
        return true;
    }

    if (cp >= 0x2500 && cp <= 0x257F) {
        switch (cp) {
            case 0x256D:
                paintBuiltinLineHorizontal(left + width * 0.5f, top, width * 0.5f, height, LineStyle::Light, false, false, fg);
                paintBuiltinLineVertical(left, top + height * 0.5f, width, height * 0.5f, LineStyle::Light, false, false, fg);
                return true;
            case 0x256E:
                paintBuiltinLineHorizontal(left, top, width * 0.5f, height, LineStyle::Light, false, false, fg);
                paintBuiltinLineVertical(left, top + height * 0.5f, width, height * 0.5f, LineStyle::Light, false, false, fg);
                return true;
            case 0x256F:
                paintBuiltinLineHorizontal(left, top, width * 0.5f, height, LineStyle::Light, false, false, fg);
                paintBuiltinLineVertical(left, top, width, height * 0.5f, LineStyle::Light, false, false, fg);
                return true;
            case 0x2570:
                paintBuiltinLineHorizontal(left + width * 0.5f, top, width * 0.5f, height, LineStyle::Light, false, false, fg);
                paintBuiltinLineVertical(left, top, width, height * 0.5f, LineStyle::Light, false, false, fg);
                return true;
            default:
                break;
        }
    }

    return false;
}

uint8_t NativeDrawingRenderer::makeStyleBits(const CellAttributes& attrs)
{
    return static_cast<uint8_t>((attrs.bold ? 1 : 0) |
                                (attrs.italic ? 2 : 0) |
                                (attrs.underline ? 4 : 0) |
                                (attrs.strikethrough ? 8 : 0));
}

std::string NativeDrawingRenderer::cellText(const Cell& cell)
{
    if (cell.textLen > 0) {
        return std::string(cell.text, cell.text + cell.textLen);
    }
    if (cell.codepoint != 0) {
        return Utf8FromCodepoint(cell.codepoint);
    }
    return {};
}
