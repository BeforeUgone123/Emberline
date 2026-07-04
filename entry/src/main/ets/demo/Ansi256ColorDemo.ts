const ESC: string = '\u001b';
const RESET: string = `${ESC}[0m`;

function foreground(color: number): string {
  return `${ESC}[38;5;${color}m`;
}

function background(color: number): string {
  return `${ESC}[48;5;${color}m`;
}

function swatch(color: number): string {
  return `${background(color)}  ${RESET}`;
}

function pushRange(lines: Array<string>, start: number, count: number): void {
  const cells: Array<string> = [];
  for (let color = start; color < start + count; color += 1) {
    cells.push(swatch(color));
  }
  lines.push(cells.join(''));
}

export function buildAnsi256ColorDemo(): string {
  const lines: Array<string> = [];

  lines.push(`${ESC}[2J${ESC}[H${RESET}`);
  lines.push(`${ESC}[1m${foreground(45)}FusionTerm 256-color renderer mock${RESET}`);
  lines.push(`${foreground(245)}TERM=xterm-256color  COLORTERM=truecolor  source=mock${RESET}`);
  lines.push('');
  lines.push(`${ESC}[1mBase ANSI colors 0-15${RESET}`);
  pushRange(lines, 0, 16);
  lines.push('');
  lines.push(`${ESC}[1mXterm color cube 16-231${RESET}`);

  for (let red = 0; red < 6; red += 1) {
    const cells: Array<string> = [];
    for (let green = 0; green < 6; green += 1) {
      for (let blue = 0; blue < 6; blue += 1) {
        const color = 16 + red * 36 + green * 6 + blue;
        cells.push(swatch(color));
      }
    }
    lines.push(`r${red} ${cells.join('')}`);
  }

  lines.push('');
  lines.push(`${ESC}[1mGrayscale ramp 232-255${RESET}`);
  pushRange(lines, 232, 24);
  lines.push('');
  lines.push(
    `${foreground(39)}blue foreground${RESET}  ` +
      `${foreground(82)}green foreground${RESET}  ` +
      `${foreground(214)}amber foreground${RESET}  ` +
      `${foreground(201)}magenta foreground${RESET}`
  );
  lines.push(`${foreground(245)}Open Local or VM to replace this mock with a live PTY session.${RESET}`);
  lines.push(RESET);

  return lines.join('\r\n');
}
