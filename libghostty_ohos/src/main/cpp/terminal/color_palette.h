#pragma once

#include "theme.h"

#include <array>
#include <cstdint>

std::array<uint32_t, 256> BuildTerminalPalette(const TerminalTheme& theme);
