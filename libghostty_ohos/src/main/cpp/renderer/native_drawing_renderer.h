#pragma once

#include <native_window/external_window.h>
#include <native_buffer/native_buffer.h>
#include <native_drawing/drawing_bitmap.h>
#include <native_drawing/drawing_brush.h>
#include <native_drawing/drawing_canvas.h>
#include <native_drawing/drawing_font_collection.h>
#include <native_drawing/drawing_rect.h>
#include <native_drawing/drawing_register_font.h>
#include <native_drawing/drawing_text_typography.h>
#include <unordered_map>
#include <string>
#include <cstdint>
#include "renderer.h"

class NativeDrawingRenderer : public Renderer {
public:
    NativeDrawingRenderer();
    ~NativeDrawingRenderer() override;

    bool init(OHNativeWindow* window, uint32_t width, uint32_t height) override;
    void cleanup() override;
    void resize(uint32_t width, uint32_t height) override;

    bool loadFontAtlas(NativeResourceManager* resourceManager, const std::string& filesDir) override;
    bool registerCustomFont(const std::string& fontPath) override;
    void setFontFamily(const std::string& family) override;

    void beginFrame() override;
    void renderGrid(const std::vector<Cell>& cells, int cols, int rows,
                    int cursorRow, int cursorCol, bool cursorVisible,
                    const std::vector<uint8_t>& dirtyRows) override;
    void shiftOffscreen(int rowDelta) override;
    void endFrame() override;

protected:
    void updateCellDimensions() override;
    void onFontMetricsChanged() override;

private:
    enum class LineStyle : uint8_t {
        None,
        Light,
        Heavy,
        Double,
    };

    struct BoxGlyphEdges {
        LineStyle up = LineStyle::None;
        LineStyle right = LineStyle::None;
        LineStyle down = LineStyle::None;
        LineStyle left = LineStyle::None;
    };

    struct GlyphKey {
        std::string text;
        uint32_t fg = 0;
        uint8_t styleBits = 0;
        uint8_t span = 1;

        bool operator==(const GlyphKey& other) const {
            return text == other.text &&
                   fg == other.fg &&
                   styleBits == other.styleBits &&
                   span == other.span;
        }
    };

    struct GlyphKeyHash {
        size_t operator()(const GlyphKey& key) const;
    };

    struct GlyphLayout {
        OH_Drawing_Typography* typography = nullptr;
        float width = 0.0f;
        float height = 0.0f;
    };

    bool configureWindow();
    bool ensureDrawingObjects();
    void destroyGlyphCache();
    void trimGlyphCache();
    GlyphLayout* getGlyphLayout(const std::string& text, const CellAttributes& attrs, uint8_t span);
    bool paintBuiltinGlyph(const Cell& cell, const CellAttributes& attrs, float left, float top, float width, float height);
    void paintCellBackground(float left, float top, float width, float height, uint32_t color);
    void paintCursor(float left, float top, float width, float height, uint32_t color);
    void paintBuiltinRect(float left, float top, float width, float height, uint32_t color);
    void paintBuiltinLineHorizontal(float left, float top, float width, float cellHeight, LineStyle style, bool upperHalf, bool lowerHalf, uint32_t color);
    void paintBuiltinLineVertical(float left, float top, float cellWidth, float height, LineStyle style, bool leftHalf, bool rightHalf, uint32_t color);
    void paintBuiltinDiagonal(float left, float top, float width, float height, bool forwardSlash, uint32_t color);
    static BoxGlyphEdges getBoxGlyphEdges(uint32_t codepoint);
    static uint32_t blendColor(uint32_t bg, uint32_t fg, uint8_t alpha);
    static uint8_t makeStyleBits(const CellAttributes& attrs);
    static std::string cellText(const Cell& cell);

    OHNativeWindow* m_window = nullptr;
    OHNativeWindowBuffer* m_currentBuffer = nullptr;
    OH_NativeBuffer* m_currentNativeBuffer = nullptr;
    void* m_currentPixels = nullptr;
    OH_NativeBuffer_Config m_currentConfig {};
    int m_currentFenceFd = -1;
    uint64_t m_currentFrameId = 0;

    OH_Drawing_Canvas* m_canvas = nullptr;
    OH_Drawing_Brush* m_brush = nullptr;
    OH_Drawing_Rect* m_rect = nullptr;
    OH_Drawing_FontCollection* m_fontCollection = nullptr;

    std::unordered_map<GlyphKey, GlyphLayout, GlyphKeyHash> m_glyphCache;
    std::string m_preferredFontFamily = "FusionTerm Maple Mono";
    std::string m_primaryFontFamily = "libghostty Mono";
    std::string m_symbolFontFamily = "libghostty Nerd Symbols";
    bool m_fontsConfigured = false;

    // Persistent offscreen frame: partial repaints draw only dirty rows here,
    // then endFrame blits the whole image into the window buffer (buffer
    // queues rotate buffers, so incremental drawing directly into the window
    // buffer would show stale frames).
    std::vector<uint8_t> m_offscreenPixels;
    uint32_t m_offscreenWidth = 0;
    uint32_t m_offscreenHeight = 0;
    int32_t m_offscreenFormat = -1;
    bool m_offscreenValid = false;

    // Persistent scratch marking which cells drew a built-in (box/line) glyph
    // in the first pass so the text pass can skip them. Reused across frames
    // (resized only when the grid geometry changes) and cleared per dirty row
    // instead of reallocated and zeroed every frame.
    std::vector<uint8_t> m_geometryMask;

    // --- Scroll-damage + partial-present bookkeeping ------------------------
    // Which offscreen grid rows actually changed *this* frame. Set by
    // renderGrid (dirty rows it repainted) / shiftOffscreen (whole offscreen
    // moved); consumed by endFrame to age each rotating window buffer.
    bool m_frameOffscreenFull = false;   // whole offscreen changed this frame
    bool m_shiftedThisFrame = false;     // shiftOffscreen ran this frame
    std::vector<uint8_t> m_frameOffscreenRows;  // per grid row, size == m_offscreenRows
    int m_offscreenRows = 0;             // grid rows behind the offscreen
    float m_offscreenRowHeight = 0.0f;   // cell height used for row->pixel mapping

    // Per rotating window buffer (keyed by OH_NativeBuffer_GetSeqNum): the set
    // of offscreen rows that changed since that buffer was last presented, plus
    // the smooth-scroll shift baked into it. A buffer whose content is unknown
    // or was shifted is marked full and gets a whole-surface blit.
    struct BufferBlitState {
        bool full = true;
        int lastShift = 0;
        std::vector<uint8_t> staleRows;  // size == m_offscreenRows; ignored when full
    };
    std::unordered_map<uint32_t, BufferBlitState> m_bufferBlit;

    // Smooth-scroll shift baked into the most recently *presented* frame. When
    // this frame's shift differs, every on-screen row changed relative to the
    // last flush, so the whole surface must be blitted and damaged.
    int m_lastPresentedShift = 0;

    // Damage rectangles handed to FlushBuffer; kept alive across the call.
    std::vector<Region::Rect> m_damageRects;

    bool ensureOffscreen(uint32_t width, uint32_t height);
    void resetBufferBlitHistory();
    uint32_t backgroundFillPixel() const;
    void pixelRowSpan(int row, int rowsTotal, int32_t& top, int32_t& bottom) const;
};
