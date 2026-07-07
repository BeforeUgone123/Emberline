import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

// The wand-agent deploy walkthrough must exist in BOTH surfaces from one
// shared builder: a one-shot first-launch overlay (persisted OnboardingStore
// flag) and the always-reachable drawer help pane. Guarded so the tutorial
// never silently drops out of either place or forks into two copies.

const index = await readFile('entry/src/main/ets/pages/Index.ets', 'utf8');
const store = await readFile('entry/src/main/ets/settings/OnboardingStore.ets', 'utf8');

// (1) Persisted one-shot flag with its own store (clearing other settings must
// never re-trigger onboarding).
assert.match(store, /const STORE_NAME: string = 'fusionterm_onboarding';/, 'onboarding needs its own preferences store');
assert.match(store, /get\('agentGuideSeen', false\)/, 'store must read the agentGuideSeen flag');
assert.match(store, /put\('agentGuideSeen', true\);\s*await this\.prefs\.flush\(\);/s, 'markSeen must persist and flush');

// (2) Index wiring: load on launch, open once, dismiss persists.
assert.match(index, /@State private agentGuideOpen: boolean = false;/, 'guide overlay needs a visibility @State');
assert.match(index, /private onboardingStore: OnboardingStore = new OnboardingStore\(\);/, 'Index must own an OnboardingStore');
assert.match(index, /void this\.loadOnboarding\(\);/, 'aboutToAppear must check the first-launch flag');
assert.match(
  index,
  /const seen = await this\.onboardingStore\.load\(this\.context\);\s*if \(!seen\) \{\s*this\.agentGuideOpen = true;\s*\}/s,
  'the guide must auto-open only while the flag is unset'
);
assert.match(
  index,
  /private dismissAgentGuide\(\): void \{\s*this\.agentGuideOpen = false;\s*this\.onboardingStore\.markSeen\(\)/s,
  'dismissing the guide must persist the seen flag'
);
assert.match(
  index,
  /if \(this\.agentGuideOpen\) \{\s*this\.buildAgentGuideScrim\(\);\s*this\.buildAgentGuidePanel\(\);\s*\}/s,
  'the guide overlay must be mounted in the root stack'
);

// (3) One shared walkthrough builder, embedded in BOTH the overlay and the
// help pane.
const panelUses = index.match(/this\.buildAgentGuideContent\(\)/g) ?? [];
assert.ok(panelUses.length >= 2, 'the walkthrough builder must be embedded in both the overlay and the help pane');
assert.match(index, /this\.buildGroupTitle\('部署 wand-agent\(Agent 会话\)'\)/u, 'help pane needs the deploy group');

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
