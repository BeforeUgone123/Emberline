#pragma once

#include <string>
#include <vector>
#include <thread>
#include <atomic>
#include <mutex>
#include <functional>
#include <memory>
#include "terminal_state.h"  // For Cell struct
#include "theme.h"
#include "../include/ghostty_vt.h"

class Renderer;
struct GhosttyMouseEncoder;
struct GhosttyMouseEvent;
using GhosttyMouseEncoderHandle = GhosttyMouseEncoder*;
using GhosttyMouseEventHandle = GhosttyMouseEvent*;

enum class TerminalMouseAction {
    Press,
    Release,
    Motion,
};

enum class TerminalMouseButton {
    None,
    Left,
    Right,
    Middle,
    WheelUp,
    WheelDown,
};

struct TerminalSearchStatus {
    bool active = false;
    size_t total = 0;
    int selected = -1;
    std::string query;
};

class Terminal {
public:
    Terminal(int cols, int rows);
    ~Terminal();

    bool start();
    void stop();

    void resize(int cols, int rows);
    void writeInput(const char* data, size_t len);
    void feedOutput(const char* data, size_t len);

    std::string getScreenContent() const;
    void getCursorPosition(int& row, int& col) const;
    std::string getLinkAt(int row, int col) const;

    // Returns and clears the most recent OSC 0/2 window title (empty when
    // nothing new arrived since the last drain).
    std::string drainPendingTitle();

    // Scrollback
    void scrollView(int delta);
    void resetViewScroll();
    int getScrollbackSize() const;

    // Terminal private-mode state used for key encoding and paste handling.
    bool cursorKeysApplicationMode() const;
    bool bracketedPasteEnabled() const;

    // Encode clipboard text (bracketed-paste aware, unsafe bytes stripped)
    // and write it to the terminal input path.
    void pasteText(const std::string& text);

    // Application mouse reporting for tmux/vim and other full-screen TUIs.
    bool isMouseTrackingEnabled() const;
    bool sendMouseEvent(TerminalMouseAction action,
                        TerminalMouseButton button,
                        uint16_t mods,
                        float x,
                        float y,
                        uint32_t screenWidth,
                        uint32_t screenHeight,
                        uint32_t cellWidth,
                        uint32_t cellHeight,
                        bool anyButtonPressed);

    // Selection
    bool hasSelection() const;
    bool isSelectionAt(int row, int col) const;
    void startSelection(int row, int col);
    void updateSelection(int row, int col);
    void selectWordAt(int row, int col);
    void selectLineAt(int row);
    void clearSelection();
    std::string getSelectedText() const;

    // Search
    void startSearch(const std::string& query = std::string());
    void searchSelection();
    void updateSearch(const std::string& query);
    void navigateSearch(bool next);
    void endSearch();
    TerminalSearchStatus getSearchStatus() const;

    int getCols() const { return m_cols; }
    int getRows() const { return m_rows; }

    void setRenderer(Renderer* renderer) { m_renderer = renderer; }
    void setMaxScrollback(int lines);
    void setTheme(const TerminalTheme& theme);
    const TerminalTheme& getTheme() const;

    void setInputCallback(std::function<void(const std::string&)> callback) {
        m_inputCallback = callback;
    }
    void setRenderRequestCallback(std::function<void()> callback) {
        m_renderRequestCallback = callback;
    }
    void drawFrame();

private:
    bool queryPrivateMode(uint16_t mode) const;
    void notifyRenderNeeded();
    void applyThemeLocked();
    void configureCallbacksLocked();
    void emitInput(const char* data, size_t len);
    void emitInput(const std::string& data);
    static bool IsSelectionBefore(int rowA, int colA, int rowB, int colB);
    static void HandleWritePty(ghostty_terminal_t terminal, void* userdata, const uint8_t* data, size_t len);
    static void HandleBell(ghostty_terminal_t terminal, void* userdata);
    static ghostty_string_t HandleEnquiry(ghostty_terminal_t terminal, void* userdata);
    static ghostty_string_t HandleXtversion(ghostty_terminal_t terminal, void* userdata);
    static void HandleTitleChanged(ghostty_terminal_t terminal, void* userdata);
    static bool HandleSize(ghostty_terminal_t terminal, void* userdata, ghostty_size_report_size_t* out_size);
    static bool HandleColorScheme(ghostty_terminal_t terminal, void* userdata, ghostty_color_scheme_t* out_scheme);
    static bool HandleDeviceAttributes(ghostty_terminal_t terminal, void* userdata, ghostty_device_attributes_t* out_attrs);
    void normalizeSelectionBounds(int& startRow, int& startCol, int& endRow, int& endCol) const;
    ghostty_terminal_scrollbar_t getScrollbarLocked() const;
    void scrollViewportLocked(ghostty_terminal_scroll_viewport_tag_t tag, int64_t delta = 0);
    int64_t determineScrollStepTowardsBottomLocked();
    std::vector<std::string> captureScrollbackSnapshotLocked(size_t& viewportTopRow);
    void rebuildSearchMatchesLocked();
    void syncSearchSelectionToViewportLocked();

    int m_cols;
    int m_rows;

    std::atomic<bool> m_running;

    ghostty_terminal_t m_vt;
    ghostty_render_state_t m_renderState;
    ghostty_row_iterator_t m_rowIterator;
    ghostty_row_cells_t m_rowCells;
    GhosttyMouseEncoderHandle m_mouseEncoder = nullptr;
    GhosttyMouseEventHandle m_mouseEvent = nullptr;
    TerminalTheme m_theme;
    mutable std::mutex m_stateMutex;

    Renderer* m_renderer;
    std::function<void(const std::string&)> m_inputCallback;
    std::function<void()> m_renderRequestCallback;
    bool m_selectionActive = false;
    int m_selStartRow = 0;
    int m_selStartCol = 0;
    int m_selEndRow = 0;
    int m_selEndCol = 0;

    struct SearchMatch {
        size_t row = 0;
        size_t startByte = 0;
        size_t endByte = 0;
    };

    bool m_searchActive = false;
    std::string m_searchQuery;
    std::vector<SearchMatch> m_searchMatches;
    size_t m_searchViewportTopRow = 0;
    int m_searchSelectedIndex = -1;

    // Dirty-row rendering state: drawFrame only snapshots and repaints rows
    // the VT marked dirty (plus cursor rows); these track frame-over-frame
    // context that the VT dirty flags cannot see.
    // OSC title updates arrive inside VT callbacks that already hold
    // m_stateMutex (feedOutput), so they get their own tiny lock.
    std::mutex m_titleMutex;
    std::string m_pendingTitle;
    bool m_titleDirty = false;

    bool m_forceFullFrame = true;
    int m_lastCursorRow = -1;
    int m_lastCursorCol = -1;
    bool m_lastCursorVisible = false;
    bool m_lastSelectionActive = false;
    bool m_lastSearchActive = false;
    size_t m_lastViewportTopRow = static_cast<size_t>(-1);
};
