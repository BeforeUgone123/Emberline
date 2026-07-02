import { common } from '@kit.AbilityKit';
import { DEFAULT_TERMINAL_CONFIG, TerminalController, TerminalSurface } from 'libghostty-ohos';
import { FusionTerminalDriver } from '../drivers/FusionTerminalDriver';
import { createFusionVmProfile } from '../models/ConnectionProfile';

@Entry
@Component
struct Index {
  private controller: TerminalController = new TerminalController();
  private driver: FusionTerminalDriver = new FusionTerminalDriver();
  private context: common.UIAbilityContext | null = null;
  private readonly quickKeys: string[] = ['Esc', 'Tab', 'Ctrl-C', 'Ctrl-D', 'Up', 'Down', 'PgUp', 'PgDn'];

  @State private statusLabel: string = 'Idle';
  @State private statusMode: string = 'local';
  @State private connected: boolean = false;
  @State private connectPanelOpen: boolean = false;
  @State private draftHost: string = 'bruce';
  @State private draftPort: string = '22';
  @State private draftUser: string = 'user';
  @State private draftPassword: string = '';
  @State private fontSize: number = 15;
  @State private themeName: string = 'Catppuccin_Mocha';

  aboutToAppear(): void {
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.controller.setConfig({
      fontSize: this.fontSize,
      scrollbackLines: 50000,
      bgColor: DEFAULT_TERMINAL_CONFIG.bgColor,
      fgColor: DEFAULT_TERMINAL_CONFIG.fgColor,
      cursorStyle: DEFAULT_TERMINAL_CONFIG.cursorStyle,
      cursorBlink: true
    });
    this.controller.setTheme(this.themeName);
    this.driver.setStatusListener((status) => {
      this.connected = status.connected;
      this.statusMode = status.mode;
      this.statusLabel = status.error.length > 0 ? status.error : status.label;
    });
    if (this.context) {
      this.driver.attach(this.controller, this.context);
      this.driver.startLocal();
    }
  }

  aboutToDisappear(): void {
    this.driver.detach();
  }

  build() {
    Stack() {
      Column() {
        this.buildTopBar();
        Stack() {
          TerminalSurface({
            controller: this.controller,
            surfaceId: 'fusionTermSurface',
            surfaceColor: '#0B0D10'
          })
        }
        .layoutWeight(1)
        .width('100%')
        .backgroundColor('#0B0D10')

        this.buildQuickBar();
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#0B0D10')

      if (this.connectPanelOpen) {
        this.buildConnectPanel();
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0B0D10')
  }

  @Builder
  private buildTopBar() {
    Row({ space: 10 }) {
      Text(this.connected ? '*' : 'o')
        .fontSize(18)
        .fontColor(this.connected ? '#30D158' : '#8B95A7')
        .width(22)
        .textAlign(TextAlign.Center)

      Column() {
        Text('FusionTerm')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#F4F7FB')
          .maxLines(1)
        Text(`${this.statusMode.toUpperCase()}  ${this.statusLabel}`)
          .fontSize(11)
          .fontColor('#9AA7BD')
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button('VM')
        .height(34)
        .fontSize(13)
        .backgroundColor('#1E6FFF')
        .fontColor('#FFFFFF')
        .borderRadius(6)
        .onClick(() => {
          this.connectPanelOpen = true;
        })

      Button('Local')
        .height(34)
        .fontSize(13)
        .backgroundColor('#232A33')
        .fontColor('#DCE6F6')
        .borderRadius(6)
        .onClick(() => {
          this.driver.startLocal();
        })

      Button(this.themeName === 'Catppuccin_Mocha' ? 'Dark' : 'Soft')
        .height(34)
        .fontSize(13)
        .backgroundColor('#232A33')
        .fontColor('#DCE6F6')
        .borderRadius(6)
        .onClick(() => {
          this.toggleTheme();
        })
    }
    .height(52)
    .width('100%')
    .padding({ left: 12, right: 12 })
    .backgroundColor('#11161D')
    .border({ width: { bottom: 1 }, color: '#202936' })
  }

  @Builder
  private buildQuickBar() {
    Row({ space: 8 }) {
      ForEach(this.quickKeys, (key: string) => {
        Button(key)
          .height(34)
          .fontSize(12)
          .fontColor('#CED8EA')
          .backgroundColor('#171D25')
          .borderRadius(6)
          .onClick(() => {
            this.sendQuickKey(key);
          })
      }, (key: string) => key)
    }
    .height(50)
    .width('100%')
    .padding({ left: 10, right: 10 })
    .backgroundColor('#11161D')
    .border({ width: { top: 1 }, color: '#202936' })
  }

  @Builder
  private buildConnectPanel() {
    Column({ space: 12 }) {
      Row() {
        Text('Fusion VM')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#F4F7FB')
          .layoutWeight(1)
        Button('Close')
          .height(32)
          .fontSize(12)
          .backgroundColor('#252D38')
          .fontColor('#DCE6F6')
          .borderRadius(6)
          .onClick(() => {
            this.connectPanelOpen = false;
          })
      }
      .width('100%')

      TextInput({ text: this.draftHost, placeholder: 'host' })
        .height(42)
        .fontSize(15)
        .fontColor('#F4F7FB')
        .backgroundColor('#171D25')
        .borderRadius(6)
        .onChange((value: string) => {
          this.draftHost = value;
        })

      Row({ space: 10 }) {
        TextInput({ text: this.draftPort, placeholder: 'port' })
          .height(42)
          .fontSize(15)
          .fontColor('#F4F7FB')
          .backgroundColor('#171D25')
          .borderRadius(6)
          .layoutWeight(1)
          .onChange((value: string) => {
            this.draftPort = value;
          })
        TextInput({ text: this.draftUser, placeholder: 'user' })
          .height(42)
          .fontSize(15)
          .fontColor('#F4F7FB')
          .backgroundColor('#171D25')
          .borderRadius(6)
          .layoutWeight(2)
          .onChange((value: string) => {
            this.draftUser = value;
          })
      }
      .width('100%')

      TextInput({ text: this.draftPassword, placeholder: 'password' })
        .height(42)
        .fontSize(15)
        .fontColor('#F4F7FB')
        .backgroundColor('#171D25')
        .borderRadius(6)
        .type(InputType.Password)
        .onChange((value: string) => {
          this.draftPassword = value;
        })

      Button('Connect')
        .height(42)
        .width('100%')
        .fontSize(15)
        .fontColor('#FFFFFF')
        .backgroundColor('#1E6FFF')
        .borderRadius(6)
        .onClick(() => {
          this.connectFusionVm();
        })
    }
    .width(360)
    .padding(16)
    .backgroundColor('#11161D')
    .borderRadius(8)
    .border({ width: 1, color: '#2B3545' })
    .shadow({ radius: 24, color: '#99000000', offsetX: 0, offsetY: 10 })
  }

  private connectFusionVm(): void {
    const port = Number(this.draftPort);
    const profile = createFusionVmProfile(
      this.draftHost,
      Number.isFinite(port) ? port : 22,
      this.draftUser,
      this.draftPassword
    );
    this.connectPanelOpen = false;
    this.driver.connectSsh(profile);
  }

  private sendQuickKey(key: string): void {
    let value = '';
    switch (key) {
      case 'Esc':
        value = '\u001b';
        break;
      case 'Tab':
        value = '\t';
        break;
      case 'Ctrl-C':
        value = '\u0003';
        break;
      case 'Ctrl-D':
        value = '\u0004';
        break;
      case 'Up':
        value = '\u001b[A';
        break;
      case 'Down':
        value = '\u001b[B';
        break;
      case 'PgUp':
        value = '\u001b[5~';
        break;
      case 'PgDn':
        value = '\u001b[6~';
        break;
      default:
        value = '';
        break;
    }
    if (value.length > 0) {
      this.controller.write(value);
    }
  }

  private toggleTheme(): void {
    this.themeName = this.themeName === 'Catppuccin_Mocha' ? 'Aizen_Dark' : 'Catppuccin_Mocha';
    this.controller.setTheme(this.themeName);
  }
}
