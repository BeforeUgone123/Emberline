#pragma once

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <string>
#include <vector>
#include "../terminal/terminal_state.h"

struct NativeResourceManager;
struct NativeWindow;
typedef struct NativeWindow OHNativeWindow;

class Renderer {
public:
    virtual ~Renderer() = default;

    virtual bool init(OHNativeWindow* window, uint32_t width, uint32_t height) = 0;
    virtual void cleanup() = 0;
    virtual void resize(uint32_t width, uint32_t height) = 0;
    virtual bool loadFontAtlas(NativeResourceManager* resourceManager, const std::string& filesDir) = 0;
    virtual void beginFrame() = 0;
    // dirtyRows: per-row repaint flags; an EMPTY vector means "repaint
    // everything". Rows whose flag is 0 keep their previous pixels (the
    // renderer maintains a persistent offscreen surface).
    virtual void renderGrid(const std::vector<Cell>& cells, int cols, int rows,
                            int cursorRow, int cursorCol, bool cursorVisible,
                            const std::vector<uint8_t>& dirtyRows) = 0;
    // Scroll-damage fast path: shift the persistent offscreen up/down by
    // rowDelta grid rows (positive = content moves up, exposing new rows at the
    // bottom; negative = content moves down, exposing rows at the top) so a
    // pure viewport scroll can reuse already-rasterized pixels and only repaint
    // the newly exposed rows. Must be called after beginFrame and before
    // renderGrid; the caller marks the exposed rows dirty for renderGrid.
    // Default no-op for renderers without a persistent offscreen.
    virtual void shiftOffscreen(int rowDelta) { (void)rowDelta; }
    virtual void endFrame() = 0;

    float getCellWidth() const { return m_cellWidth; }
    float getCellHeight() const { return m_cellHeight; }
    uint32_t getWidth() const { return m_width; }
    uint32_t getHeight() const { return m_height; }
    void getLastCursorRect(float& left, float& top, float& width, float& height, bool& valid) const {
        left = m_lastCursorLeft;
        top = m_lastCursorTop;
        width = m_lastCursorWidth;
        height = m_lastCursorHeight;
        valid = m_lastCursorRectValid;
    }

    void setFontSize(float size) {
        if (m_fontSize != size) {
            m_needFullRepaint = true;
            onFontMetricsChanged();
        }
        m_fontSize = size;
        updateCellDimensions();
    }

    virtual void setFontFamily(const std::string& family) {
        (void)family;
    }

    void setDensity(float density) {
        const float next = density > 0 ? density : 1.0f;
        if (m_density != next) {
            m_needFullRepaint = true;
            onFontMetricsChanged();
        }
        m_density = next;
        updateCellDimensions();
    }

    void setColors(uint32_t bgColor, uint32_t fgColor) {
        const uint32_t nextBg = bgColor | 0xFF000000u;
        if (m_defaultBgOpaque != nextBg || m_defaultFgColor != fgColor) {
            m_needFullRepaint = true;
        }
        m_defaultBgOpaque = nextBg;
        m_defaultFgColor = fgColor;
        applyBackgroundOpacity();
    }

    // Ghostty background-opacity semantics: only the default background is
    // translucent; cells that paint their own background stay opaque.
    void setBackgroundOpacity(float opacity) {
        const float next = std::clamp(opacity, 0.0f, 1.0f);
        if (m_bgOpacity != next) {
            m_needFullRepaint = true;
        }
        m_bgOpacity = next;
        applyBackgroundOpacity();
    }

    // Register a user-supplied font file at the head of the fallback chain.
    virtual bool registerCustomFont(const std::string& fontPath) {
        (void)fontPath;
        return false;
    }

    void setCursorColors(uint32_t cursorColor, uint32_t cursorTextColor) {
        m_cursorBgColor = cursorColor;
        m_cursorFgColor = cursorTextColor;
    }

    void setCursorStyle(int style, bool blink) {
        m_cursorStyle = style;
        m_cursorBlink = blink;
    }

    bool cursorBlinkEnabled() const { return m_cursorBlink; }

    // Stamp "there was input/output just now" so the cursor holds solid while
    // typing/printing and, once idle, resumes blinking from the lit phase.
    // Called from the input/feed threads (Terminal::writeInput / feedOutput);
    // read on the render thread by shouldRenderCursor. Atomic, lock-free.
    void noteActivity() {
        using namespace std::chrono;
        const uint64_t nowMs = static_cast<uint64_t>(
            duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count());
        m_lastActivityMs.store(nowMs, std::memory_order_relaxed);
    }

    // Smooth-scroll presentation offset in physical px, applied at blit time
    // in endFrame: positive shifts content up (dst row y shows offscreen row
    // y + shift). Holds the sub-line remainder of pixel scrolling so the
    // viewport glides between full-line scrolls instead of stepping.
    // Written from input threads, read on the render thread.
    void setScrollFraction(float px) {
        m_scrollFraction.store(px, std::memory_order_relaxed);
    }
    float getScrollFraction() const {
        return m_scrollFraction.load(std::memory_order_relaxed);
    }

    bool shouldRenderCursor(bool cursorVisible) const {
        if (!cursorVisible) {
            return false;
        }
        if (!m_cursorBlink) {
            return true;
        }

        using namespace std::chrono;
        const uint64_t nowMs = static_cast<uint64_t>(
            duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count());
        const uint64_t lastActivity = m_lastActivityMs.load(std::memory_order_relaxed);
        const uint64_t sinceActivity = nowMs > lastActivity ? nowMs - lastActivity : 0;

        // Typing or program output: hold the cursor solid (no flicker) for a
        // short grace window after the last input/output.
        if (sinceActivity < kCursorActivitySolidMs) {
            return true;
        }

        // Idle: original 500/500 square wave, but with the end of the grace
        // window as the phase origin so blinking resumes from the lit
        // half-period — the cursor stays lit straight through the grace window
        // into the first blink instead of snapping dark.
        const uint64_t phase =
            (sinceActivity - kCursorActivitySolidMs) % kCursorBlinkPeriodMs;
        return phase < (kCursorBlinkPeriodMs / 2);
    }

protected:
    // Cursor stays solid for this grace window after the last activity, then
    // blinks with this full period (half lit / half dark). 500/1000 keeps the
    // pre-existing idle square wave unchanged.
    static constexpr uint64_t kCursorActivitySolidMs = 500;
    static constexpr uint64_t kCursorBlinkPeriodMs = 1000;

    virtual void onFontMetricsChanged() {}

    virtual void updateCellDimensions() {
        m_cellWidth = m_fontSize * 0.6f * m_density;
        m_cellHeight = m_fontSize * 1.2f * m_density;
    }

    void applyBackgroundOpacity() {
        const uint32_t alpha =
            static_cast<uint32_t>(std::lround(m_bgOpacity * 255.0f)) & 0xFFu;
        m_defaultBgColor = (alpha << 24) | (m_defaultBgOpaque & 0x00FFFFFFu);
    }

    uint32_t m_width = 0;
    uint32_t m_height = 0;
    float m_cellWidth = 10.0f;
    float m_cellHeight = 20.0f;
    float m_fontSize = 14.0f;
    float m_density = 1.0f;
    float m_bgOpacity = 1.0f;
    bool m_needFullRepaint = true;
    uint32_t m_defaultBgOpaque = 0xFF000000;
    uint32_t m_defaultBgColor = 0xFF000000;
    uint32_t m_defaultFgColor = 0xFFFFFFFF;
    uint32_t m_cursorBgColor = 0xFFFFFFFF;
    uint32_t m_cursorFgColor = 0xFF000000;
    int m_cursorStyle = 0;
    bool m_cursorBlink = true;
    float m_lastCursorLeft = 0.0f;
    float m_lastCursorTop = 0.0f;
    float m_lastCursorWidth = 0.0f;
    float m_lastCursorHeight = 0.0f;
    bool m_lastCursorRectValid = false;
    std::atomic<float> m_scrollFraction { 0.0f };
    // steady_clock ms of the most recent input/output; 0 = none yet. Written by
    // noteActivity(), read by shouldRenderCursor across threads.
    std::atomic<uint64_t> m_lastActivityMs { 0 };
};
