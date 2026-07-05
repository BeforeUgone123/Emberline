export interface CursorPosition {
  row: number;
  col: number;
}

export interface CellMetrics {
  width: number;
  height: number;
}

export interface TerminalSize {
  cols: number;
  rows: number;
}

export interface TerminalSearchStatus {
  active: boolean;
  total: number;
  selected: number;
  query: string;
}

export interface TerminalScrollbarState {
  total: number;
  offset: number;
  visible: number;
}

export type TerminalInputListener = (data: string) => void;
export type TerminalAttachmentListener = (attached: boolean) => void;
export type TerminalLinkListener = (url: string) => void;
export type TerminalContextMenuListener = (x: number, y: number) => void;
export type TerminalCopyRequestListener = (text: string) => void;
export type TerminalPasteRequestListener = () => void;
export type TerminalTitleListener = (title: string) => void;
// Desktop-notification events: text payload for OSC 9, empty string for BEL.
export type TerminalNotificationListener = (text: string) => void;

export interface TerminalConfig {
  fontSize: number;
  fontFamily: string;
  scrollbackLines: number;
  bgColor: number;
  fgColor: number;
  cursorStyle: number;
  cursorBlink: boolean;
  bgOpacity: number;
}

export interface TerminalConfigPatch {
  fontSize?: number;
  fontFamily?: string;
  scrollbackLines?: number;
  bgColor?: number;
  fgColor?: number;
  cursorStyle?: number;
  cursorBlink?: boolean;
  bgOpacity?: number;
}

export const DEFAULT_THEME_NAME: string = 'Aizen_Dark';

export const DEFAULT_TERMINAL_CONFIG: TerminalConfig = {
  fontSize: 14,
  fontFamily: 'FusionTerm Maple Mono',
  scrollbackLines: 10000,
  bgColor: 0xFF1A1A1A,
  fgColor: 0xFFD0D6F0,
  cursorStyle: 0,
  cursorBlink: true,
  bgOpacity: 1
};

export function cloneTerminalConfig(config: TerminalConfig): TerminalConfig {
  return {
    fontSize: config.fontSize,
    fontFamily: config.fontFamily,
    scrollbackLines: config.scrollbackLines,
    bgColor: config.bgColor,
    fgColor: config.fgColor,
    cursorStyle: config.cursorStyle,
    cursorBlink: config.cursorBlink,
    bgOpacity: config.bgOpacity
  };
}
