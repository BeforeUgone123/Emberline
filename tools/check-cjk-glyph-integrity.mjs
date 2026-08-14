import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

// Pins the CJK intermittent-blank fix (iteration A). Root cause: text runs
// were laid out in a box of exactly span * m_cellWidth with MaxLines(1);
// CJK glyphs shaped by a fallback face (m_cellWidth is probed from the
// primary face's "M") can exceed the box by a fraction of a pixel, the
// paragraph wraps the overflow to a second line, and MaxLines(1) drops it —
// the same char then renders blank in some runs and fine in others. Secondary
// fix: cells were snapshotted from the base codepoint only, losing grapheme
// clusters (review 2026-07-10 finding), and byte-level truncation could
// split a UTF-8 sequence into invalid text that paints nothing.

const terminal = await readFile('libghostty_ohos/src/main/cpp/terminal/terminal.cpp', 'utf8');
const renderer = await readFile('libghostty_ohos/src/main/cpp/renderer/native_drawing_renderer.cpp', 'utf8');

// ── Layout box slack: the paragraph box must never constrain the run. ──────
assert.match(renderer, /static_cast<double>\(m_cellWidth\) \* static_cast<double>\(span\) \* 2\.0/,
  'typography layout box carries 2x slack so CJK fallback advances never wrap');
assert.match(renderer, /OH_Drawing_SetTypographyTextMaxLines\(typographyStyle, 1\);/,
  'MaxLines(1) stays as the final guard against double-height paragraphs');
assert.match(renderer, /OH_Drawing_TypographyLayout\(typography, maxWidth\);/);

// ── Shaping failures must never blank a run silently. ──────────────────────
assert.match(renderer, /Typography handler creation failed frame=/,
  'handler creation failure logs instead of silently skipping the run');
assert.match(renderer, /CreateTypography failed frame=/,
  'typography creation failure logs instead of silently skipping the run');

// ── The 2026-07-05 CFI fix must keep trim strictly before insert. ──────────
assert.match(renderer, /trimGlyphCache\(\);\s*\n\s*auto \[inserted, _\] = m_glyphCache\.emplace\(key, layout\);/,
  'glyph cache trims before emplacing the entry the caller is about to paint');

// ── Grapheme clusters: full extraction, never a sub-buffer read. ───────────
assert.match(terminal, /constexpr size_t kGraphemeCodepointCap = 32;/);
assert.match(terminal, /size_t ReadCellGraphemes\(/);
assert.match(terminal, /GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_LEN, &len/,
  'drawFrame queries the grapheme length instead of trusting the base codepoint');
assert.match(terminal, /GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_BUF, out/,
  'drawFrame reads the full grapheme cluster buffer');
assert.match(terminal, /if \(len > outCap\) \{/,
  'GRAPHEMES_BUF writes graphemes_len entries: oversized clusters must fall back, never overflow');

// ── The render snapshot and the search table share one cluster read. ───────
assert.match(terminal, /cellCodepointCount = ReadCellGraphemes\(\s*\n\s*m_rowCells, codepoint, cellCodepoints, kGraphemeCodepointCap\);/,
  'the per-cell loop resolves the cluster once');
assert.match(terminal, /if \(cellCodepointCount == 0\) \{\s*\n\s*rowText\.push_back\(' '\);/,
  'search text keeps the blank-cell fallback for spacers and empty cells');
assert.match(terminal, /if \(cellCodepointCount > 0\) \{\s*\n\s*SetCellTextFromCodepoints\(dst, cellCodepoints, cellCodepointCount\);/,
  'cell text is set from the full cluster');
assert.doesNotMatch(terminal, /SetCellTextFromCodepoints\(dst, &codepoint, 1\)/,
  'base-codepoint-only snapshot must not return (review 2026-07-10 finding)');

// ── Spacer cells still contribute no text of their own. ────────────────────
assert.match(terminal, /const bool renderableText = hasText &&\s*\n\s*wide != GHOSTTY_CELL_WIDE_SPACER_TAIL &&\s*\n\s*wide != GHOSTTY_CELL_WIDE_SPACER_HEAD &&\s*\n\s*codepoint != 0;/,
  'spacer tail/head cells stay textless so the wide head owns both columns');

// ── UTF-8 truncation happens at a codepoint boundary. ──────────────────────
assert.match(terminal, /if \(utf8\.size\(\) \+ cpLen > kGhosttyTextCapacity - 1\) \{\s*\n\s*break;\s*\n\s*\}/,
  'cluster truncation stops before a codepoint that would not fit whole');
assert.doesNotMatch(terminal, /std::min\(utf8\.size\(\), kGhosttyTextCapacity - 1\)/,
  'byte-level truncation can split a UTF-8 sequence and blank the run');

// ── The grid_ref copy/search paths read full clusters too. ─────────────────
assert.match(terminal, /ghostty_result_t ghostty_grid_ref_graphemes\(const ghostty_grid_ref_t\* ref,/,
  'local declaration for the sized grapheme readback missing from ghostty_vt.h');
assert.match(terminal, /void AppendGridRefGraphemesUtf8\(std::string& out, const ghostty_grid_ref_t\* ref, uint32_t baseCodepoint\)/);
assert.match(terminal, /AppendGridRefGraphemesUtf8\(line, &ref, codepoint\);/,
  'scrollback snapshot lines carry the full cluster');
assert.match(terminal, /AppendGridRefGraphemesUtf8\(result, &ref, codepoint\);/,
  'selection copy carries the full cluster');
assert.doesNotMatch(terminal, /AppendCodepointUtf8\((line|result), codepoint\);/,
  'base-codepoint-only extraction must not remain in the copy/search paths');

console.log('check-cjk-glyph-integrity: OK');
