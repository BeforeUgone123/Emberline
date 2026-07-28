import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

// The wand-agent deploy walkthrough must stay complete and explicitly
// reachable from the overflow menu, without blocking the terminal-first launch.

const index = await readFile('entry/src/main/ets/pages/Index.ets', 'utf8');

// (1) No automatic onboarding: the terminal is the first useful viewport.
assert.match(index, /@State private agentGuideOpen: boolean = false;/, 'guide overlay needs a visibility @State');
assert.doesNotMatch(index, /OnboardingStore|onboardingStore|loadOnboarding/, 'launch must not auto-open onboarding');

// (2) The top-bar overflow is the permanent entry point.
assert.match(
  index,
  /MenuItem\(\{ content: '帮助与诊断' \}\)[\s\S]*?this\.agentGuideOpen = true;/,
  'the overflow menu must open help and diagnostics'
);
assert.match(
  index,
  /if \(this\.agentGuideOpen\) \{\s*this\.buildAgentGuideScrim\(\);\s*this\.buildAgentGuidePanel\(\);\s*\}/s,
  'the guide overlay must be mounted in the root stack'
);
assert.match(index, /private dismissAgentGuide\(\): void \{\s*this\.agentGuideOpen = false;\s*this\.focusActiveTerminalSoon\(\);/s);

// (3) One walkthrough builder, embedded in the explicit help surface.
const panelUses = index.match(/this\.buildAgentGuideContent\(\)/g) ?? [];
assert.equal(panelUses.length, 1, 'the walkthrough must have one source of truth');
assert.match(index, /this\.buildGroupTitle\('部署 wand-agent\(Agent 会话\)'\)/u, 'help surface needs the deploy group');
assert.match(index, /private buildAgentGuidePanel\(\)[\s\S]*?this\.buildHelpPane\(\)/, 'the explicit panel must host the full help surface');

// (4) The walkthrough itself stays complete: install (both ways), run,
// systemd, app-side connect, copyable commands.
assert.match(index, /git clone https:\/\/github\.com\/beforeugone520\/wand-agent\.git/, 'guide must include the source build clone');
assert.match(index, /install -m 755 wand-agent \/usr\/local\/bin\//, 'guide must include the binary install step');
assert.match(index, /wand-agent --host 172\.16\.100\.2 --token/, 'guide must include the trial-run command');
assert.match(index, /const AGENT_GUIDE_SERVICE_UNIT: string =/, 'guide must ship the systemd unit');
assert.match(index, /WantedBy=multi-user\.target/, 'systemd unit must be complete');
assert.match(index, /systemctl daemon-reload && systemctl enable --now wand-agent/, 'guide must include the enable step');
assert.match(index, /ws:\/\/172\.16\.100\.2:8765\/ws/, 'guide must include the app-side endpoint');
assert.match(
  index,
  /private buildGuideCommand\(cmd: string\) \{[\s\S]*?\.copyOption\(CopyOptions\.LocalDevice\)/,
  'command blocks must be long-press copyable'
);

console.log('check-agent-setup-guide: OK');
