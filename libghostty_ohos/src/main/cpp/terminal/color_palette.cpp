#include "color_palette.h"

#include <cstddef>

namespace {

uint8_t XtermColorComponent(int value)
{
    return static_cast<uint8_t>(value == 0 ? 0 : 55 + value * 40);
}

uint32_t Argb(uint8_t red, uint8_t green, uint8_t blue)
{
    return 0xFF000000u |
        (static_cast<uint32_t>(red) << 16) |
        (static_cast<uint32_t>(green) << 8) |
        static_cast<uint32_t>(blue);
}

} // namespace

std::array<uint32_t, 256> BuildTerminalPalette(const TerminalTheme& theme)
{
    std::array<uint32_t, 256> palette {};

    for (std::size_t i = 0; i < theme.palette.size(); ++i) {
        palette[i] = theme.palette[i];
    }

    for (int index = 16; index <= 231; ++index) {
        const int offset = index - 16;
        const int red = offset / 36;
        const int green = (offset / 6) % 6;
        const int blue = offset % 6;
        palette[static_cast<std::size_t>(index)] = Argb(
            XtermColorComponent(red),
            XtermColorComponent(green),
            XtermColorComponent(blue));
    }

    for (int index = 232; index <= 255; ++index) {
        const uint8_t gray = static_cast<uint8_t>(8 + (index - 232) * 10);
        palette[static_cast<std::size_t>(index)] = Argb(gray, gray, gray);
    }

    return palette;
}
