import { router, promptAction } from '@kit.ArkUI';
import { TdError } from '../../tdkit/TdTypes';
import {
  SCOPE_CHANNEL, SCOPE_GROUP, SCOPE_PRIVATE, ScopeSettings, defaultScopeSettings,
  getScopeSettings, resetAllNotificationSettings, setScopeSettings
} from '../../store/NotificationApi';
import {
  COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';

const CARD_RADIUS: number = 14;

@Entry
@Component
struct NotificationSettingsPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State privateSettings: ScopeSettings = defaultScopeSettings();
  @State groupSettings: ScopeSettings = defaultScopeSettings();
  @State channelSettings: ScopeSettings = defaultScopeSettings();
  @State loadState: string = 'loading';
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.load();
  }

  aboutToDisappear(): void {
    this.active = false;
  }

  private load(): void {
    this.loadState = 'loading';
    Promise.all([
      getScopeSettings(SCOPE_PRIVATE), getScopeSettings(SCOPE_GROUP),
      getScopeSettings(SCOPE_CHANNEL)
    ]).then((all: ScopeSettings[]): void => {
      if (!this.active) { return; }
      this.privateSettings = all[0];
      this.groupSettings = all[1];
      this.channelSettings = all[2];
      this.loadState = 'ready';
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      console.error(`NotificationSettingsPage.load failed: ${error.message}`);
      this.loadState = 'error';
    });
  }

  private settingsOf(scope: string): ScopeSettings {
    if (scope === SCOPE_GROUP) { return this.groupSettings; }
    if (scope === SCOPE_CHANNEL) { return this.channelSettings; }
    return this.privateSettings;
  }

  private applyLocal(scope: string, value: ScopeSettings): void {
    if (scope === SCOPE_GROUP) { this.groupSettings = value; }
    else if (scope === SCOPE_CHANNEL) { this.channelSettings = value; }
    else { this.privateSettings = value; }
  }

  // TDLib replaces the whole scope object, so每次都发送完整设置并在失败时回滚。
  private update(scope: string, key: string, value: boolean): void {
    const current = this.settingsOf(scope);
    const next: ScopeSettings = {
      muted: key === 'muted' ? value : current.muted,
      showPreview: key === 'showPreview' ? value : current.showPreview,
      disablePinned: key === 'disablePinned' ? value : current.disablePinned,
      disableMentions: key === 'disableMentions' ? value : current.disableMentions
    };
    this.applyLocal(scope, next);
    setScopeSettings(scope, next).catch((error: TdError): void => {
      console.error(`NotificationSettingsPage.update failed: ${error.message}`);
      this.applyLocal(scope, current);
      promptAction.showToast({ message: '通知设置更新失败', duration: 1600 });
    });
  }

  private resetAll(): void {
    promptAction.showDialog({
      title: '恢复默认通知设置',
      message: '所有会话的通知例外也会被清除。',
      buttons: [
        { text: '取消', color: '#8E8E93' },
        { text: '恢复', color: '#E5484D' }
      ]
    }).then((result): void => {
      if (result.index !== 1) { return; }
      resetAllNotificationSettings().then((): void => {
        promptAction.showToast({ message: '已恢复默认', duration: 1500 });
        this.load();
      }).catch((): void => {
        promptAction.showToast({ message: '恢复失败，请重试', duration: 1600 });
      });
    }).catch((): void => {});
  }

  @Builder
  switchRow(label: string, value: boolean, onChange: (next: boolean) => void) {
    Row() {
      Text(label).fontSize(15).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
      Toggle({ type: ToggleType.Switch, isOn: value }).selectedColor(COLOR_PRIMARY)
        .onChange(onChange);
    }.width('100%').height(48).padding({ left: 14, right: 12 });
  }

  @Builder
  scopeCard(title: string, scope: string, settings: ScopeSettings, hasMentions: boolean) {
    Column() {
      Text(title).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
        .width('100%').padding({ left: 14, top: 12, bottom: 4 });
      this.switchRow('接收通知', !settings.muted,
        (next: boolean): void => this.update(scope, 'muted', !next));
      this.switchRow('显示消息预览', settings.showPreview,
        (next: boolean): void => this.update(scope, 'showPreview', next));
      if (hasMentions) {
        this.switchRow('置顶消息通知', !settings.disablePinned,
          (next: boolean): void => this.update(scope, 'disablePinned', !next));
        this.switchRow('提及我时通知', !settings.disableMentions,
          (next: boolean): void => this.update(scope, 'disableMentions', !next));
      }
    }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Button() {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([COLOR_TEXT_PRIMARY]);
        }.width(40).height(40).borderRadius(20).backgroundColor(Color.Transparent)
        .onClick((): void => { router.back(); });
        Text('通知').fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
          .layoutWeight(1);
      }.width('100%').height(52).padding({ left: 8, right: 16 }).alignItems(VerticalAlign.Center);
      if (this.loadState === 'loading') {
        Column({ space: 9 }) {
          LoadingProgress().width(32).height(32).color(COLOR_PRIMARY);
          Text('正在读取通知设置…').fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.loadState === 'error') {
        Column({ space: 10 }) {
          Text('加载失败').fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
          Button('重新加载').onClick((): void => this.load());
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else {
        Scroll() {
          Column({ space: 12 }) {
            this.scopeCard('私聊', SCOPE_PRIVATE, this.privateSettings, false);
            this.scopeCard('群组', SCOPE_GROUP, this.groupSettings, true);
            this.scopeCard('频道', SCOPE_CHANNEL, this.channelSettings, true);
            Row({ space: 10 }) {
              SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(17).fontColor(['#E5484D']);
              Text('恢复默认通知设置').fontSize(15).fontColor('#E5484D').layoutWeight(1);
            }
            .width('100%').height(48).padding({ left: 14, right: 14 })
            .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
            .onClick((): void => this.resetAll());
            Text('这里是账号级默认设置，会同步到你的所有设备；单个会话的静音设置优先生效。')
              .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(18).width('100%');
          }.width('100%').padding({ left: 12, right: 12, bottom: this.bottomSafe + 24 });
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
      }
    }
    .width('100%').height('100%').backgroundColor(COLOR_PAGE_BG)
    .padding({ top: this.topSafe });
  }
}
