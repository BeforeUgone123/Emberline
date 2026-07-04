import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const surface = await readFile('libghostty_ohos/src/main/ets/TerminalSurface.ets', 'utf8');

assert.match(surface, /imeInputId: string = 'terminalImeInput'/);
assert.match(surface, /imeInputController: TextInputController = new TextInputController\(\)/);
assert.match(surface, /private readonly imeAnchorSentinel: string = '\\u200B'/);
assert.match(surface, /@State private imeText: string = this\.imeAnchorSentinel/);
assert.match(surface, /this\.buildImeInputAnchor\(\)/);
assert.match(surface, /private buildImeInputAnchor\(\)/);
assert.match(surface, /TextInput\(\{ text: this\.imeText, controller: this\.imeInputController \}\)/);
assert.match(surface, /\.id\(this\.imeInputId\)/);
assert.match(surface, /\.type\(InputType\.Normal\)/);
assert.match(surface, /\.opacity\(0\.01\)/);
assert.match(surface, /\.onWillInsert\(\(info: InsertValue\) => \{/);
assert.match(surface, /this\.handleImeAnchorInsert\(info\.insertValue\);/);
assert.match(surface, /return false;/);
assert.match(surface, /\.onWillDelete\(\(info: DeleteValue\) => \{/);
assert.match(surface, /this\.handleImeAnchorDelete\(info\.deleteValue\);/);
assert.match(surface, /\.onChange\(\(value: string\) => \{\s*this\.handleImeAnchorChange\(value\);/s);
assert.match(surface, /private handleImeAnchorChange\(value: string\): void/);
assert.match(surface, /private handleImeAnchorInsert\(value: string\): void/);
assert.match(surface, /private handleImeAnchorDelete\(value: string\): void/);
assert.match(surface, /this\.controller\.write\(this\.imeInputInterceptor \? this\.imeInputInterceptor\(value\) : value\)/);
assert.match(surface, /this\.controller\.write\(this\.imeInputInterceptor \? this\.imeInputInterceptor\(inserted\) : inserted\)/);
assert.match(surface, /this\.controller\.write\('\\x7f'\)/);
assert.match(surface, /this\.imeText = this\.imeAnchorSentinel/);
assert.match(surface, /this\.imeInputController\.caretPosition\(this\.imeAnchorSentinel\.length\)/);
assert.match(surface, /focusControl\.requestFocus\(this\.imeInputId\)/);
assert.match(
  surface,
  /private requestTerminalFocus\(\): void \{\s*focusControl\.requestFocus\(this\.surfaceId\);\s*this\.requestImeAnchorFocus\(\);/s,
  'terminal focus should also focus the hidden TextInput anchor so the system IME recognizes input'
);
