import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

// The wand-agent deploy walkthrough must open once on first launch and remain
// explicitly reachable from the overflow menu afterward.

const index = await readFile('entry/src/main/ets/pages/Index.ets', 'utf8');

// (1) A persisted, one-shot popup opens over the already-mounted terminal.
assert.match(index, /@State private agentGuideOpen: boolean = false;/, 'guide overlay needs a visibility @State');
assert.match(index, /import \{ OnboardingStore \} from '\.\.\/settings\/OnboardingStore';/);
assert.match(index, /private onboardingStore: OnboardingStore = new OnboardingStore\(\);/);
assert.match(index, /aboutToAppear\(\): void \{[\s\S]*?this\.addSession\(\);[\s\S]*?void this\.loadOnboarding\(\);/);
assert.match(index, /private async loadOnboarding\(\): Promise<void> \{[\s\S]*?this\.onboardingStore\.claimAgentGuide\(context\)[\s\S]*?this\.agentGuideMode = 'onboarding';[\s\S]*?this\.agentGuideOpen = true;/);

const onboarding = await readFile('entry/src/main/ets/settings/OnboardingStore.ets', 'utf8');
assert.match(onboarding, /let agentGuideClaimedInProcess: boolean = false;/, 'only one window may claim the popup');
assert.match(onboarding, /async claimAgentGuide\(context: common\.UIAbilityContext\): Promise<boolean>/);
assert.match(onboarding, /const AGENT_GUIDE_SEEN_KEY: string = 'wandAgentSetupSeenV2';/, 'the new setup prompt needs a versioned persistence key');
assert.match(onboarding, /this\.prefs\.put\(AGENT_GUIDE_SEEN_KEY, true\)/, 'first-launch display must persist');

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
assert.equal(panelUses.length, 2, 'the same walkthrough builder must serve onboarding and Help');
assert.match(index, /this\.buildGroupTitle\('部署 wand-agent\(Agent 会话\)'\)/u, 'help surface needs the deploy group');
assert.match(index, /private buildAgentGuidePanel\(\)[\s\S]*?this\.buildHelpPane\(\)/, 'the explicit panel must host the full help surface');
assert.match(index, /this\.agentGuideMode === 'onboarding'[\s\S]*?this\.buildAgentGuideContent\(\)[\s\S]*?this\.buildHelpPane\(\)/, 'first launch must open directly on the deploy walkthrough');
assert.match(index, /Button\('打开连接设置'\)[\s\S]*?this\.dismissAgentGuide\(\);[\s\S]*?this\.openDrawer\('conn'\);/, 'onboarding must lead directly to connection settings');

// (4) The walkthrough itself stays complete: npm/pnpm/curl one-line setup,
// Go auto-provisioning, systemd diagnostics, app-side connect, copyable commands.
assert.match(index, /pnpm add -g github:BeforeUgone123\/wand-agent && wand-agent service install/, 'guide must include pnpm one-line setup');
assert.match(index, /npm install -g github:BeforeUgone123\/wand-agent && wand-agent service install/, 'guide must include npm one-line setup');
assert.match(index, /curl -fsSL https:\/\/raw\.githubusercontent\.com\/BeforeUgone123\/Emberline\/main\/tools\/install-wand-agent\.sh/, 'guide must include curl one-line setup');
assert.match(index, /Go 缺失或版本过旧时会自动下载带 SHA-256 校验的工具链/u, 'guide must explain automatic verified Go provisioning');
assert.match(index, /systemctl status wand-agent --no-pager/, 'guide must include a service status check');
assert.match(index, /const AGENT_GUIDE_SERVICE_UNIT: string =/, 'guide must ship the systemd unit');
assert.match(index, /WantedBy=multi-user\.target/, 'systemd unit must be complete');
assert.match(index, /ws:\/\/172\.16\.100\.2:8765\/ws/, 'guide must include the app-side endpoint');
assert.match(
  index,
  /private buildGuideCommand\(cmd: string\) \{[\s\S]*?\.copyOption\(CopyOptions\.LocalDevice\)/,
  'command blocks must be long-press copyable'
);

const bootstrap = await readFile('tools/install-wand-agent.sh', 'utf8');
assert.match(bootstrap, /^#!\/bin\/sh\nset -eu/m, 'curl bootstrap must fail closed under POSIX sh');
assert.match(bootstrap, /Node\.js 16 or newer is required/, 'bootstrap must enforce the package runtime floor');
assert.match(bootstrap, /api\.github\.com\/repos\/\$\{WAND_AGENT_REPOSITORY\}\/tarball\/\$\{WAND_AGENT_REF\}/, 'bootstrap must download the selected agent source');
assert.match(bootstrap, /node "\$source_dir\/bin\/wand-agent\.js" service install "\$@"/, 'bootstrap must delegate Go, build and service ownership to the agent CLI');

console.log('check-agent-setup-guide: OK');
