import { common, Want } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { DEFAULT_TERMINAL_CONFIG, TerminalController, TerminalSurface } from 'libghostty-ohos';
import { buildAnsi256ColorDemo } from '../demo/Ansi256ColorDemo';
import { FusionAgentDriver } from '../drivers/FusionAgentDriver';
import {
  DEFAULT_FUSION_AGENT_HOST,
  DEFAULT_FUSION_AGENT_PATH,
  DEFAULT_FUSION_AGENT_PORT,
  DEFAULT_FUSION_AGENT_TOKEN,
  DEFAULT_FUSION_ENGINE_VM_LABEL
} from '../drivers/FusionAgentProtocol';
import { FusionTerminalDriver } from '../drivers/FusionTerminalDriver';
import { createFusionVmProfile } from '../models/ConnectionProfile';
import { AppearanceSettings, AppearanceStore, DEFAULT_APPEARANCE } from '../settings/AppearanceStore';
import { ConnectionSettings, ConnectionStore } from '../settings/ConnectionStore';

// Chrome palette tuned to match the desktop Ghostty profile
// (near-black background, Catppuccin Mocha foreground tones).
const COLOR_APP_BG: string = '#050507';
const COLOR_BAR_BG: string = '#0C0F14';
const COLOR_BAR_BORDER: string = '#1B222E';
const COLOR_TEXT_PRIMARY: string = '#CDD6F4';
const COLOR_TEXT_SECONDARY: string = '#8B95A7';
const COLOR_ACCENT: string = '#1E6FFF';
const COLOR_KEY_BG: string = '#161B24';
const COLOR_KEY_TEXT: string = '#C4CEE0';
const COLOR_PANEL_BG: string = '#10141B';
const COLOR_PANEL_BORDER: string = '#273042';
const COLOR_FIELD_BG: string = '#171D28';
const COLOR_STATUS_ON: string = '#A6E3A1';
const COLOR_STATUS_OFF: string = '#6C7086';
const MIN_TERMINAL_FONT_SIZE: number = 10;
const MAX_TERMINAL_FONT_SIZE: number = 26;
const MIN_BACKGROUND_OPACITY_PCT: number = 0;
const MAX_BACKGROUND_BLUR: number = 60;
const FOREGROUND_FOCUS_EVENT: string = 'fusionTermForeground';

// One in-app terminal tab: its renderer controller, transports, and status.
// @Observed so tab chips (@ObjectLink) re-render on title/connection changes.
@Observed
class TerminalSessionHandle {
  readonly id: number;
  readonly controller: TerminalController;
  readonly driver: FusionTerminalDriver;
  readonly agentDriver: FusionAgentDriver;
  statusMode: string = 'demo';
  statusLabel: string = '待机';
  title: string = '新标签页';
  oscTitle: string = '';
  lastCwd: string = '';
  connected: boolean = false;
  demoRendered: boolean = false;

  constructor(id: number) {
    this.id = id;
    this.controller = new TerminalController();
    this.driver = new FusionTerminalDriver();
    this.agentDriver = new FusionAgentDriver();
  }
}

// A desktop-terminal style tab: status dot, live title, close button.
@Component
struct TerminalTabChip {
  @ObjectLink session: TerminalSessionHandle;
  @Prop active: boolean;
  onSelect: () => void = () => {};
  onClose: () => void = () => {};

  build() {
    Row({ space: 6 }) {
      Circle({ width: 7, height: 7 })
        .fill(this.session.connected ? COLOR_STATUS_ON : COLOR_STATUS_OFF)
      Text(this.session.title)
        .fontSize(13)
        .fontColor(this.active ? COLOR_TEXT_PRIMARY : COLOR_TEXT_SECONDARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text('×')
        .fontSize(16)
        .fontColor(COLOR_TEXT_SECONDARY)
        .padding({ left: 4, right: 2 })
        .onClick(() => {
          this.onClose();
        })
    }
    .height(32)
    .constraintSize({ minWidth: 110, maxWidth: 190 })
    .padding({ left: 10, right: 6 })
    .borderRadius(8)
    .backgroundColor(this.active ? COLOR_KEY_BG : '#00000000')
    .focusable(false)
    .onClick(() => {
      this.onSelect();
    })
  }
}

@Entry
@Component
struct Index {
  @State private sessions: TerminalSessionHandle[] = [];
  @State private activeSessionId: number = 0;
  private nextSessionId: number = 1;
  private context: common.UIAbilityContext | null = null;
  @State private connectPanelOpen: boolean = false;
  @State private draftHost: string = DEFAULT_FUSION_AGENT_HOST;
  @State private draftPort: string = String(DEFAULT_FUSION_AGENT_PORT);
  @State private draftAgentToken: string = DEFAULT_FUSION_AGENT_TOKEN;
  @State private draftSshPort: string = '22';
  @State private draftUser: string = 'user';
  @State private draftPassword: string = '';
  @State private fontSize: number = 13;
  @State private themeName: string = 'Catppuccin_Mocha';
  @State private settingsPanelOpen: boolean = false;
  @State private themePanelOpen: boolean = false;
  @State private themeFilter: string = '';
  @State private themeList: string[] = [];
  @State private cursorStyle: number = DEFAULT_APPEARANCE.cursorStyle;
  @State private cursorBlink: boolean = DEFAULT_APPEARANCE.cursorBlink;
  @State private accessoryVisible: boolean = false;
  @State private ctrlArmed: boolean = false;
  @State private altArmed: boolean = false;
  @State private customFontPath: string = '';
  @State private backgroundImagePath: string = '';
  @State private backgroundOpacity: number = DEFAULT_APPEARANCE.backgroundOpacity;
  @State private backgroundBlur: number = DEFAULT_APPEARANCE.backgroundBlur;
  @State private foregroundFocusEpoch: number = 0;
  private appearanceStore: AppearanceStore = new AppearanceStore();
  private connectionStore: ConnectionStore = new ConnectionStore();
  private demoRendered: boolean = false;
  private foregroundFocusListener: () => void = (): void => {
    this.foregroundFocusEpoch += 1;
  };

  aboutToAppear(): void {
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.context.eventHub.on(FOREGROUND_FOCUS_EVENT, this.foregroundFocusListener);
    this.addSession();
    void this.loadAppearance();
  }

  aboutToDisappear(): void {
    this.context?.eventHub.off(FOREGROUND_FOCUS_EVENT, this.foregroundFocusListener);
    for (const session of this.sessions) {
      session.controller.setAttachmentListener(null);
      session.agentDriver.terminate();
      session.driver.detach();
    }
  }

  private activeSession(): TerminalSessionHandle {
    for (const session of this.sessions) {
      if (session.id === this.activeSessionId) {
        return session;
      }
    }
    return this.sessions[0];
  }

  private addSession(refocus: boolean = false): void {
    const session = new TerminalSessionHandle(this.nextSessionId);
    this.nextSessionId += 1;
    session.controller.setConfig({
      fontSize: this.fontSize,
      scrollbackLines: 50000,
      bgColor: DEFAULT_TERMINAL_CONFIG.bgColor,
      fgColor: DEFAULT_TERMINAL_CONFIG.fgColor,
      cursorStyle: this.cursorStyle,
      cursorBlink: this.cursorBlink,
      bgOpacity: this.backgroundImagePath.length > 0 ? this.backgroundOpacity : 1
    });
    session.controller.setTitleListener((title: string) => {
      session.oscTitle = title;
      session.title = this.composeTabTitle(session, session.lastCwd);
    });
    session.controller.setTheme(this.themeName);
    session.driver.setStatusListener((status) => {
      session.connected = status.connected;
      session.statusMode = status.mode || 'local';
      session.statusLabel = this.formatStatusLabel(status.label, status.error);
      session.title = this.composeTabTitle(session, '');
    });
    session.agentDriver.setStatusListener((status) => {
      session.connected = status.connected;
      session.statusMode = status.mode || 'agent';
      session.statusLabel = this.formatStatusLabel(status.label, status.error);
      session.lastCwd = status.cwd || '';
      session.title = this.composeTabTitle(session, session.lastCwd);
    });
    session.controller.setAttachmentListener((attached: boolean) => {
      if (attached) {
        this.applyCustomFontTo(session);
        this.showStartupDemo(session);
      }
    });
    this.sessions.push(session);
    this.activateSession(session.id, refocus);
  }

  private closeSession(id: number): void {
    const index = this.sessions.findIndex((session: TerminalSessionHandle) => session.id === id);
    if (index < 0) {
      return;
    }
    const session = this.sessions[index];
    session.controller.setTitleListener(null);
    session.controller.setAttachmentListener(null);
    session.agentDriver.terminate();
    session.driver.detach();
    this.sessions.splice(index, 1);
    if (this.sessions.length === 0) {
      this.addSession(true);
      return;
    }
    if (this.activeSessionId === id) {
      const fallback = this.sessions[Math.min(index, this.sessions.length - 1)];
      this.activateSession(fallback.id, true);
    }
  }

  private activateSession(id: number, refocus: boolean = false): void {
    this.activeSessionId = id;
    if (refocus) {
      this.focusActiveTerminalSoon();
    }
  }

  private terminalInputActive(): boolean {
    return this.sessions.length > 0 &&
      !this.connectPanelOpen &&
      !this.settingsPanelOpen &&
      !this.themePanelOpen;
  }

  private focusActiveTerminalSoon(): void {
    const sessionId = this.activeSessionId;
    setTimeout(() => {
      if (sessionId !== this.activeSessionId || !this.terminalInputActive()) {
        return;
      }
      try {
        focusControl.requestFocus(`fusionTermSurface-${sessionId}`);
      } catch (err) {
        console.error('Failed to restore terminal focus: ' + JSON.stringify(err));
      }
      const session = this.activeSession();
      session.controller.setImeActive(true);
    }, 80);
  }

  // Desktop-terminal tab title: cwd basename when connected, transport name
  // otherwise; unconnected fresh tabs read as a new tab, failures show the
  // status text so the tab itself is the status surface.
  private composeTabTitle(session: TerminalSessionHandle, cwd: string): string {
    if (session.connected && session.oscTitle.length > 0) {
      return session.oscTitle;
    }
    if (session.connected) {
      if (cwd.length > 0) {
        const base = this.fileDisplayName(cwd);
        return base.length > 0 ? base : cwd;
      }
      switch (session.statusMode) {
        case 'agent':
          return 'VM';
        case 'ssh':
          return 'SSH';
        case 'local':
          return '本地';
        default:
          return '终端';
      }
    }
    if (session.statusMode === 'demo') {
      return '新标签页';
    }
    return session.statusLabel.length > 0 ? session.statusLabel : '已断开';
  }

  build() {
    Stack() {
      if (this.backgroundImagePath.length > 0) {
        Image(`file://${this.backgroundImagePath}`)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .blur(this.backgroundBlur)
      }

      Column() {
        this.buildTabBar();
        this.buildTerminalLayer();
        if (this.accessoryVisible) {
          this.buildAccessoryBar();
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.surfaceBackdropColor())

      if (this.connectPanelOpen) {
        this.buildConnectScrim();
        this.buildConnectPanel();
      }

      if (this.settingsPanelOpen) {
        this.buildSettingsScrim();
        this.buildSettingsPanel();
      }

      if (this.themePanelOpen) {
        this.buildThemeScrim();
        this.buildThemePanel();
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLOR_APP_BG)
  }

  @Builder
  private buildTerminalLayer() {
    Stack() {
      ForEach(this.sessions, (session: TerminalSessionHandle) => {
        Stack() {
          TerminalSurface({
            controller: session.controller,
            surfaceId: `fusionTermSurface-${session.id}`,
            searchInputId: `fusionTermSearch-${session.id}`,
            surfaceColor: this.surfaceBackdropColor(),
            active: session.id === this.activeSessionId &&
              !this.connectPanelOpen &&
              !this.settingsPanelOpen &&
              !this.themePanelOpen,
            foregroundFocusEpoch: this.foregroundFocusEpoch
          })
        }
        .width('100%')
        .height('100%')
        .visibility(session.id === this.activeSessionId ? Visibility.Visible : Visibility.Hidden)
      }, (session: TerminalSessionHandle) => String(session.id))
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor(this.surfaceBackdropColor())
  }

  @Builder
  private buildTabBar() {
    Row({ space: 8 }) {
      Scroll() {
        Row({ space: 4 }) {
          ForEach(this.sessions, (session: TerminalSessionHandle) => {
            TerminalTabChip({
              session: session,
              active: session.id === this.activeSessionId,
              onSelect: (): void => {
                this.activateSession(session.id, true);
              },
              onClose: (): void => {
                this.closeSession(session.id);
              }
            })
          }, (session: TerminalSessionHandle) => `tab-${session.id}`)

          Button('+')
            .height(30)
            .fontSize(16)
            .backgroundColor('#00000000')
            .fontColor(COLOR_KEY_TEXT)
            .borderRadius(8)
            .focusable(false)
            .onClick(() => {
              this.addSession(true);
            })
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .align(Alignment.Start)
      .layoutWeight(1)

      Button('⌘')
        .height(30)
        .fontSize(13)
        .backgroundColor(this.accessoryVisible ? COLOR_ACCENT : COLOR_KEY_BG)
        .fontColor(this.accessoryVisible ? '#FFFFFF' : COLOR_KEY_TEXT)
        .borderRadius(8)
        .focusable(false)
        .onClick(() => {
          this.accessoryVisible = !this.accessoryVisible;
          this.focusActiveTerminalSoon();
        })

      Button('连接')
        .height(30)
        .fontSize(12)
        .backgroundColor(COLOR_KEY_BG)
        .fontColor(COLOR_KEY_TEXT)
        .borderRadius(8)
        .focusable(false)
        .onClick(() => {
          this.connectPanelOpen = true;
        })

      Button('设置')
        .height(30)
        .fontSize(12)
        .backgroundColor(COLOR_KEY_BG)
        .fontColor(COLOR_KEY_TEXT)
        .borderRadius(8)
        .focusable(false)
        .onClick(() => {
          this.settingsPanelOpen = true;
        })
    }
    .height(40)
    .width('100%')
    .padding({ left: 8, right: 8 })
    .backgroundColor(COLOR_BAR_BG)
    .border({ width: { bottom: 1 }, color: COLOR_BAR_BORDER })
  }

  @Builder
  private buildConnectScrim() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor('#A6000000')
      .onClick(() => {
        this.connectPanelOpen = false;
        this.focusActiveTerminalSoon();
      })
  }

  @Builder
  private buildSettingsScrim() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor('#A6000000')
      .onClick(() => {
        this.settingsPanelOpen = false;
        this.focusActiveTerminalSoon();
      })
  }

  @Builder
  private buildSettingsPanel() {
    Column({ space: 10 }) {
      Row() {
        Text('外观')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY)
          .layoutWeight(1)
        Button('关闭')
          .height(32)
          .fontSize(12)
          .backgroundColor(COLOR_KEY_BG)
          .fontColor(COLOR_KEY_TEXT)
          .borderRadius(8)
          .focusable(false)
          .onClick(() => {
            this.settingsPanelOpen = false;
            this.focusActiveTerminalSoon();
          })
      }
      .width('100%')

      this.buildFieldLabel('终端字体')
      Row({ space: 10 }) {
        Text(this.customFontLabel())
          .fontSize(13)
          .fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Button('导入')
          .height(34)
          .fontSize(12)
          .backgroundColor(COLOR_ACCENT)
          .fontColor('#FFFFFF')
          .borderRadius(8)
          .focusable(false)
          .onClick(() => {
            void this.pickCustomFont();
          })
        if (this.customFontPath.length > 0) {
          Button('重置')
            .height(34)
            .fontSize(12)
            .backgroundColor(COLOR_KEY_BG)
            .fontColor(COLOR_KEY_TEXT)
            .borderRadius(8)
            .focusable(false)
            .onClick(() => {
              this.clearCustomFont();
            })
        }
      }
      .width('100%')

      this.buildFieldLabel('背景图片')
      Row({ space: 10 }) {
        Text(this.backgroundImagePath.length > 0 ? this.fileDisplayName(this.backgroundImagePath) : '无')
          .fontSize(13)
          .fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Button('选择')
          .height(34)
          .fontSize(12)
          .backgroundColor(COLOR_ACCENT)
          .fontColor('#FFFFFF')
          .borderRadius(8)
          .focusable(false)
          .onClick(() => {
            void this.pickBackgroundImage();
          })
        if (this.backgroundImagePath.length > 0) {
          Button('清除')
            .height(34)
            .fontSize(12)
            .backgroundColor(COLOR_KEY_BG)
            .fontColor(COLOR_KEY_TEXT)
            .borderRadius(8)
            .focusable(false)
            .onClick(() => {
              this.clearBackgroundImage();
            })
        }
      }
      .width('100%')

      if (this.backgroundImagePath.length > 0) {
        this.buildFieldLabel(`背景遮罩 ${Math.round(this.backgroundOpacity * 100)}%(0 = 完全透出图片)`)
        Slider({
          value: Math.round(this.backgroundOpacity * 100),
          min: MIN_BACKGROUND_OPACITY_PCT,
          max: 100,
          step: 1
        })
          .width('100%')
          .onChange((value: number, mode: SliderChangeMode) => {
            this.backgroundOpacity = value / 100;
            this.applyBackgroundConfig();
            if (mode === SliderChangeMode.End) {
              this.persistAppearance();
            }
          })

        this.buildFieldLabel(`背景模糊 ${Math.round(this.backgroundBlur)}`)
        Slider({
          value: this.backgroundBlur,
          min: 0,
          max: MAX_BACKGROUND_BLUR,
          step: 2
        })
          .width('100%')
          .onChange((value: number, mode: SliderChangeMode) => {
            this.backgroundBlur = value;
            if (mode === SliderChangeMode.End) {
              this.persistAppearance();
            }
          })
      }

      this.buildFieldLabel(`字号 ${this.fontSize}`)
      Slider({
        value: this.fontSize,
        min: MIN_TERMINAL_FONT_SIZE,
        max: MAX_TERMINAL_FONT_SIZE,
        step: 1
      })
        .width('100%')
        .onChange((value: number, mode: SliderChangeMode) => {
          this.fontSize = value;
          for (const session of this.sessions) {
            session.controller.updateConfig({ fontSize: value });
          }
          if (mode === SliderChangeMode.End) {
            this.persistAppearance();
          }
        })

      this.buildFieldLabel('光标样式')
      Row({ space: 8 }) {
        ForEach([2, 0, 1] as number[], (style: number) => {
          Button(style === 2 ? '竖线' : style === 0 ? '方块' : '下划线')
            .height(32)
            .fontSize(12)
            .backgroundColor(this.cursorStyle === style ? COLOR_ACCENT : COLOR_KEY_BG)
            .fontColor(this.cursorStyle === style ? '#FFFFFF' : COLOR_KEY_TEXT)
            .borderRadius(8)
            .focusable(false)
            .onClick(() => {
              this.cursorStyle = style;
              this.applyCursorConfig();
            })
        }, (style: number) => `cursor-${style}`)

        Text('闪烁')
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY)
          .margin({ left: 8 })
        Toggle({ type: ToggleType.Switch, isOn: this.cursorBlink })
          .onChange((isOn: boolean) => {
            this.cursorBlink = isOn;
            this.applyCursorConfig();
          })
      }
      .width('100%')

      this.buildFieldLabel('主题')
      Row({ space: 10 }) {
        Button(this.themeName.split('_').join(' '))
          .height(34)
          .fontSize(12)
          .backgroundColor(COLOR_KEY_BG)
          .fontColor(COLOR_KEY_TEXT)
          .borderRadius(8)
          .focusable(false)
          .onClick(() => {
            this.openThemePanel();
          })
      }
      .width('100%')
    }
    .width(400)
    .padding(18)
    .backgroundColor(COLOR_PANEL_BG)
    .borderRadius(14)
    .border({ width: 1, color: COLOR_PANEL_BORDER })
    .shadow({ radius: 28, color: '#B3000000', offsetX: 0, offsetY: 12 })
  }

  @Builder
  private buildFieldLabel(label: string) {
    Text(label)
      .fontSize(11)
      .fontColor(COLOR_TEXT_SECONDARY)
      .width('100%')
      .textAlign(TextAlign.Start)
  }

  @Builder
  private buildConnectPanel() {
    Column({ space: 10 }) {
      Row() {
        Text(DEFAULT_FUSION_ENGINE_VM_LABEL)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Button('关闭')
          .height(32)
          .fontSize(12)
          .backgroundColor(COLOR_KEY_BG)
          .fontColor(COLOR_KEY_TEXT)
          .borderRadius(8)
          .focusable(false)
          .onClick(() => {
            this.connectPanelOpen = false;
            this.focusActiveTerminalSoon();
          })
      }
      .width('100%')

      this.buildFieldLabel('主机')
      TextInput({ text: this.draftHost, placeholder: '172.16.100.2' })
        .height(42)
        .fontSize(15)
        .fontColor(COLOR_TEXT_PRIMARY)
        .backgroundColor(COLOR_FIELD_BG)
        .borderRadius(8)
        .onChange((value: string) => {
          this.draftHost = value;
        })

      this.buildFieldLabel('Agent 端口 / 令牌')
      Row({ space: 10 }) {
        TextInput({ text: this.draftPort, placeholder: '端口' })
          .height(42)
          .fontSize(15)
          .fontColor(COLOR_TEXT_PRIMARY)
          .backgroundColor(COLOR_FIELD_BG)
          .borderRadius(8)
          .layoutWeight(1)
          .type(InputType.Number)
          .onChange((value: string) => {
            this.draftPort = value;
          })
        TextInput({ text: this.draftAgentToken, placeholder: '令牌' })
          .height(42)
          .fontSize(15)
          .fontColor(COLOR_TEXT_PRIMARY)
          .backgroundColor(COLOR_FIELD_BG)
          .borderRadius(8)
          .layoutWeight(2)
          .type(InputType.Password)
          .onChange((value: string) => {
            this.draftAgentToken = value;
          })
      }
      .width('100%')

      this.buildFieldLabel('SSH 备用(端口 / 用户 / 密码)')
      Row({ space: 10 }) {
        TextInput({ text: this.draftSshPort, placeholder: '22' })
          .height(42)
          .fontSize(15)
          .fontColor(COLOR_TEXT_PRIMARY)
          .backgroundColor(COLOR_FIELD_BG)
          .borderRadius(8)
          .layoutWeight(1)
          .type(InputType.Number)
          .onChange((value: string) => {
            this.draftSshPort = value;
          })
        TextInput({ text: this.draftUser, placeholder: '用户名' })
          .height(42)
          .fontSize(15)
          .fontColor(COLOR_TEXT_PRIMARY)
          .backgroundColor(COLOR_FIELD_BG)
          .borderRadius(8)
          .layoutWeight(2)
          .onChange((value: string) => {
            this.draftUser = value;
          })
        TextInput({ text: this.draftPassword, placeholder: '密码' })
          .height(42)
          .fontSize(15)
          .fontColor(COLOR_TEXT_PRIMARY)
          .backgroundColor(COLOR_FIELD_BG)
          .borderRadius(8)
          .layoutWeight(2)
          .type(InputType.Password)
          .onChange((value: string) => {
            this.draftPassword = value;
          })
      }
      .width('100%')

      Row({ space: 10 }) {
        Button('连接 Agent')
          .height(42)
          .layoutWeight(2)
          .fontSize(15)
          .fontColor('#FFFFFF')
          .backgroundColor(COLOR_ACCENT)
          .borderRadius(8)
          .focusable(false)
          .onClick(() => {
            this.connectFusionAgent();
          })

        Button('SSH 备用')
          .height(42)
          .layoutWeight(1)
          .fontSize(13)
          .fontColor(COLOR_KEY_TEXT)
          .backgroundColor(COLOR_KEY_BG)
          .borderRadius(8)
          .focusable(false)
          .onClick(() => {
            this.connectFusionVm();
          })

        Button('本地')
          .height(42)
          .layoutWeight(1)
          .fontSize(13)
          .fontColor(COLOR_KEY_TEXT)
          .backgroundColor(COLOR_KEY_BG)
          .borderRadius(8)
          .focusable(false)
          .onClick(() => {
            this.connectPanelOpen = false;
            this.startLocalSession();
            this.focusActiveTerminalSoon();
          })
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .width(380)
    .padding(18)
    .backgroundColor(COLOR_PANEL_BG)
    .borderRadius(14)
    .border({ width: 1, color: COLOR_PANEL_BORDER })
    .shadow({ radius: 28, color: '#B3000000', offsetX: 0, offsetY: 12 })
  }

  private connectFusionVm(): void {
    const session = this.activeSession();
    const sshPort = Number(this.draftSshPort);
    const profile = createFusionVmProfile(
      this.draftHost,
      Number.isFinite(sshPort) ? sshPort : 22,
      this.draftUser,
      this.draftPassword
    );
    this.connectPanelOpen = false;
    this.focusActiveTerminalSoon();
    this.persistConnection();
    session.agentDriver.disconnect();
    this.ensureDriverAttached(session);
    this.clearTerminalForLiveSession(session);
    session.driver.connectSsh(profile);
  }

  private connectFusionAgent(): void {
    const session = this.activeSession();
    const port = Number(this.draftPort);
    const size = session.controller.getTerminalSize();
    this.connectPanelOpen = false;
    this.focusActiveTerminalSoon();
    this.persistConnection();
    session.driver.detach();
    session.agentDriver.attach(session.controller);
    this.clearTerminalForLiveSession(session);
    session.agentDriver.connect({
      host: this.draftHost,
      port: Number.isFinite(port) && port > 0 ? port : DEFAULT_FUSION_AGENT_PORT,
      path: DEFAULT_FUSION_AGENT_PATH,
      cols: size.cols,
      rows: size.rows,
      token: this.draftAgentToken
    });
  }

  private startLocalSession(): void {
    const session = this.activeSession();
    session.agentDriver.disconnect();
    this.ensureDriverAttached(session);
    this.clearTerminalForLiveSession(session);
    session.driver.startLocal();
  }

  private ensureDriverAttached(session: TerminalSessionHandle): void {
    if (this.context) {
      session.driver.attach(session.controller, this.context);
    }
  }

  private formatStatusLabel(label: string, error: string): string {
    const safeError = error || '';
    const safeLabel = label || '';
    return safeError.length > 0 ? safeError : safeLabel;
  }

  private showStartupDemo(session: TerminalSessionHandle): void {
    if (session.demoRendered || !session.controller.isAttached()) {
      return;
    }

    session.controller.feed(buildAnsi256ColorDemo());
    session.demoRendered = true;
  }

  private clearTerminalForLiveSession(session: TerminalSessionHandle): void {
    if (session.controller.isAttached()) {
      session.controller.feed('\u001b[2J\u001b[H\u001b[0m');
    }
  }

  @Builder
  private buildAccessoryBar() {
    Row({ space: 6 }) {
      Scroll() {
        Row({ space: 6 }) {
          Button('Esc')
            .height(32).fontSize(12).borderRadius(8)
            .backgroundColor(COLOR_KEY_BG).fontColor(COLOR_KEY_TEXT)
            .focusable(false)
            .onClick(() => {
              this.activeSession().controller.write('\u001b');
              this.focusActiveTerminalSoon();
            })
          Button('Tab')
            .height(32).fontSize(12).borderRadius(8)
            .backgroundColor(COLOR_KEY_BG).fontColor(COLOR_KEY_TEXT)
            .focusable(false)
            .onClick(() => {
              this.activeSession().controller.write('\t');
              this.focusActiveTerminalSoon();
            })
          Button('Ctrl')
            .height(32).fontSize(12).borderRadius(8)
            .backgroundColor(this.ctrlArmed ? COLOR_ACCENT : COLOR_KEY_BG)
            .fontColor(this.ctrlArmed ? '#FFFFFF' : COLOR_KEY_TEXT)
            .focusable(false)
            .onClick(() => {
              this.ctrlArmed = !this.ctrlArmed;
              this.focusActiveTerminalSoon();
            })
          Button('Alt')
            .height(32).fontSize(12).borderRadius(8)
            .backgroundColor(this.altArmed ? COLOR_ACCENT : COLOR_KEY_BG)
            .fontColor(this.altArmed ? '#FFFFFF' : COLOR_KEY_TEXT)
            .focusable(false)
            .onClick(() => {
              this.altArmed = !this.altArmed;
              this.focusActiveTerminalSoon();
            })
          ForEach(['←', '↑', '↓', '→', 'PgUp', 'PgDn'] as string[], (key: string) => {
            Button(key)
              .height(32).fontSize(12).borderRadius(8)
              .backgroundColor(COLOR_KEY_BG).fontColor(COLOR_KEY_TEXT)
              .focusable(false)
              .onClick(() => {
                this.sendAccessoryKey(key);
                this.focusActiveTerminalSoon();
              })
          }, (key: string) => `acc-${key}`)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .align(Alignment.Start)
      .layoutWeight(1)
    }
    .height(44)
    .width('100%')
    .padding({ left: 8, right: 8 })
    .backgroundColor(COLOR_BAR_BG)
    .border({ width: { top: 1 }, color: COLOR_BAR_BORDER })
  }

  @Builder
  private buildThemeScrim() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor('#A6000000')
      .onClick(() => {
        this.themePanelOpen = false;
        this.focusActiveTerminalSoon();
      })
  }

  @Builder
  private buildThemePanel() {
    Column({ space: 10 }) {
      Row() {
        Text('主题')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY)
          .layoutWeight(1)
        Button('关闭')
          .height(32)
          .fontSize(12)
          .backgroundColor(COLOR_KEY_BG)
          .fontColor(COLOR_KEY_TEXT)
          .borderRadius(8)
          .focusable(false)
          .onClick(() => {
            this.themePanelOpen = false;
            this.focusActiveTerminalSoon();
          })
      }
      .width('100%')

      TextInput({ text: this.themeFilter, placeholder: '搜索主题…' })
        .height(38)
        .fontSize(14)
        .fontColor(COLOR_TEXT_PRIMARY)
        .backgroundColor(COLOR_FIELD_BG)
        .borderRadius(8)
        .onChange((value: string) => {
          this.themeFilter = value;
        })

      List({ space: 2 }) {
        ForEach(this.filteredThemes(), (theme: string) => {
          ListItem() {
            Text(theme.split('_').join(' '))
              .width('100%')
              .height(38)
              .fontSize(13)
              .padding({ left: 12 })
              .fontColor(theme === this.themeName ? '#FFFFFF' : COLOR_TEXT_PRIMARY)
              .backgroundColor(theme === this.themeName ? COLOR_ACCENT : '#00000000')
              .borderRadius(8)
              .onClick(() => {
                this.applyTheme(theme);
              })
          }
        }, (theme: string) => theme)
      }
      .width('100%')
      .height(360)
      .scrollBar(BarState.Auto)
    }
    .width(420)
    .padding(18)
    .backgroundColor(COLOR_PANEL_BG)
    .borderRadius(14)
    .border({ width: 1, color: COLOR_PANEL_BORDER })
    .shadow({ radius: 28, color: '#B3000000', offsetX: 0, offsetY: 12 })
  }

  private filteredThemes(): string[] {
    const filter = this.themeFilter.trim().toLowerCase();
    if (filter.length === 0) {
      return this.themeList;
    }
    return this.themeList.filter((theme: string) => theme.toLowerCase().includes(filter));
  }

  private openThemePanel(): void {
    const list = this.activeSession().controller.getThemeList();
    if (list.length > 0) {
      this.themeList = list;
    }
    this.themeFilter = '';
    this.themePanelOpen = true;
  }

  private applyTheme(theme: string): void {
    this.themeName = theme;
    for (const session of this.sessions) {
      session.controller.setTheme(theme);
    }
    this.persistAppearance();
  }

  private applyCursorConfig(): void {
    for (const session of this.sessions) {
      session.controller.updateConfig({ cursorStyle: this.cursorStyle, cursorBlink: this.cursorBlink });
    }
    this.persistAppearance();
  }

  private persistConnection(): void {
    const snapshot: ConnectionSettings = {
      host: this.draftHost,
      port: this.draftPort,
      token: this.draftAgentToken,
      sshPort: this.draftSshPort,
      user: this.draftUser
    };
    this.connectionStore.save(snapshot).catch((err: Object) => {
      console.error('Failed to persist connection settings: ' + JSON.stringify(err));
    });
  }

  // Sticky Ctrl/Alt from the accessory bar transform the next IME-committed
  // character (Ctrl-C without a physical keyboard).
  private transformImeInput(value: string): string {
    let out = value;
    if (this.ctrlArmed && out.length > 0) {
      const code = out.toLowerCase().charCodeAt(0);
      let control = '';
      if (code >= 97 && code <= 122) {
        control = String.fromCharCode(code - 96);
      } else if (out[0] === ' ') {
        control = '\u0000';
      } else if (out[0] === '[') {
        control = '\u001b';
      }
      if (control.length > 0) {
        out = control + out.substring(1);
      }
      this.ctrlArmed = false;
    }
    if (this.altArmed && out.length > 0) {
      out = '\u001b' + out;
      this.altArmed = false;
    }
    return out;
  }

  private sendAccessoryKey(key: string): void {
    let value = '';
    switch (key) {
      case '←':
        value = '\u001b[D';
        break;
      case '↑':
        value = '\u001b[A';
        break;
      case '↓':
        value = '\u001b[B';
        break;
      case '→':
        value = '\u001b[C';
        break;
      case 'PgUp':
        value = '\u001b[5~';
        break;
      case 'PgDn':
        value = '\u001b[6~';
        break;
      default:
        break;
    }
    if (value.length > 0) {
      this.activeSession().controller.write(value);
    }
  }

  private surfaceBackdropColor(): string {
    return this.backgroundImagePath.length > 0 ? '#00000000' : COLOR_APP_BG;
  }

  private customFontLabel(): string {
    if (this.customFontPath.length === 0) {
      return 'Maple Mono NF CN(默认)';
    }
    return this.fileDisplayName(this.customFontPath);
  }

  private fileDisplayName(path: string): string {
    const slash = path.lastIndexOf('/');
    return slash >= 0 ? path.substring(slash + 1) : path;
  }

  private openNewWindow(): void {
    if (!this.context) {
      return;
    }
    const want: Want = {
      bundleName: this.context.abilityInfo.bundleName,
      abilityName: this.context.abilityInfo.name
    };
    this.context.startAbility(want).catch((err: Object) => {
      console.error('Failed to open new terminal window: ' + JSON.stringify(err));
    });
  }

  private async loadAppearance(): Promise<void> {
    if (!this.context) {
      return;
    }
    try {
      const settings = await this.appearanceStore.load(this.context);
      this.fontSize = settings.fontSize;
      this.themeName = settings.themeName;
      this.customFontPath = settings.customFontPath;
      this.backgroundImagePath = settings.backgroundImagePath;
      this.backgroundOpacity = settings.backgroundOpacity;
      this.backgroundBlur = settings.backgroundBlur;
      this.cursorStyle = settings.cursorStyle;
      this.cursorBlink = settings.cursorBlink;
      const conn = await this.connectionStore.load(this.context, {
        host: this.draftHost,
        port: this.draftPort,
        token: this.draftAgentToken,
        sshPort: this.draftSshPort,
        user: this.draftUser
      });
      this.draftHost = conn.host;
      this.draftPort = conn.port;
      this.draftAgentToken = conn.token;
      this.draftSshPort = conn.sshPort;
      this.draftUser = conn.user;
      for (const session of this.sessions) {
        session.controller.setTheme(this.themeName);
        session.controller.updateConfig({
          fontSize: this.fontSize,
          cursorStyle: this.cursorStyle,
          cursorBlink: this.cursorBlink
        });
      }
      this.applyBackgroundConfig();
      this.applyCustomFont();
    } catch (err) {
      console.error('Failed to load appearance settings: ' + JSON.stringify(err));
    }
  }

  private persistAppearance(): void {
    const snapshot: AppearanceSettings = {
      fontSize: this.fontSize,
      themeName: this.themeName,
      customFontPath: this.customFontPath,
      backgroundImagePath: this.backgroundImagePath,
      backgroundOpacity: this.backgroundOpacity,
      backgroundBlur: this.backgroundBlur,
      cursorStyle: this.cursorStyle,
      cursorBlink: this.cursorBlink
    };
    this.appearanceStore.save(snapshot).catch((err: Object) => {
      console.error('Failed to persist appearance settings: ' + JSON.stringify(err));
    });
  }

  private applyBackgroundConfig(): void {
    const effectiveOpacity = this.backgroundImagePath.length > 0 ? this.backgroundOpacity : 1;
    for (const session of this.sessions) {
      session.controller.updateConfig({ bgOpacity: effectiveOpacity });
    }
  }

  private applyCustomFont(): void {
    for (const session of this.sessions) {
      this.applyCustomFontTo(session);
    }
  }

  private applyCustomFontTo(session: TerminalSessionHandle): void {
    if (this.customFontPath.length === 0 || !session.controller.isAttached()) {
      return;
    }
    try {
      if (!fs.accessSync(this.customFontPath)) {
        return;
      }
    } catch (_err) {
      return;
    }
    if (!session.controller.registerCustomFont(this.customFontPath)) {
      console.error('Failed to register custom terminal font: ' + this.customFontPath);
    }
  }

  private async pickCustomFont(): Promise<void> {
    if (!this.context) {
      return;
    }
    try {
      const documentPicker = new picker.DocumentViewPicker();
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['.ttf', '.otf'];
      const uris = await documentPicker.select(options);
      if (!uris || uris.length === 0) {
        return;
      }

      const fontDir = `${this.context.filesDir}/fonts`;
      if (!fs.accessSync(fontDir)) {
        fs.mkdirSync(fontDir);
      }
      const suffix = uris[0].toLowerCase().endsWith('.otf') ? '.otf' : '.ttf';
      const destPath = `${fontDir}/CustomTerminalFont-${Date.now()}${suffix}`;
      const srcFile = fs.openSync(uris[0], fs.OpenMode.READ_ONLY);
      fs.copyFileSync(srcFile.fd, destPath);
      fs.closeSync(srcFile);

      const previousPath = this.customFontPath;
      this.customFontPath = destPath;
      this.applyCustomFont();
      this.persistAppearance();
      this.removeOwnedFile(previousPath);
    } catch (err) {
      console.error('Failed to import custom font: ' + JSON.stringify(err));
    }
  }

  private clearCustomFont(): void {
    const previousPath = this.customFontPath;
    this.customFontPath = '';
    this.persistAppearance();
    this.removeOwnedFile(previousPath);
    console.info('Custom font cleared; default font returns after restart');
  }

  private async pickBackgroundImage(): Promise<void> {
    if (!this.context) {
      return;
    }
    try {
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result = await photoPicker.select(options);
      if (!result || result.photoUris.length === 0) {
        return;
      }

      const destPath = `${this.context.filesDir}/background-${Date.now()}.img`;
      const srcFile = fs.openSync(result.photoUris[0], fs.OpenMode.READ_ONLY);
      fs.copyFileSync(srcFile.fd, destPath);
      fs.closeSync(srcFile);

      const previousPath = this.backgroundImagePath;
      this.backgroundImagePath = destPath;
      this.applyBackgroundConfig();
      this.persistAppearance();
      this.removeOwnedFile(previousPath);
    } catch (err) {
      console.error('Failed to choose background image: ' + JSON.stringify(err));
    }
  }

  private clearBackgroundImage(): void {
    const previousPath = this.backgroundImagePath;
    this.backgroundImagePath = '';
    this.applyBackgroundConfig();
    this.persistAppearance();
    this.removeOwnedFile(previousPath);
  }

  private removeOwnedFile(path: string): void {
    if (!this.context || path.length === 0 || !path.startsWith(this.context.filesDir)) {
      return;
    }
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (err) {
      console.error('Failed to remove replaced file: ' + JSON.stringify(err));
    }
  }
}
