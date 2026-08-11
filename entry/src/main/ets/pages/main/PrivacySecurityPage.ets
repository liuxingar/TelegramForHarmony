import { router, promptAction } from '@kit.ArkUI';
import { getTdClient } from '../../tdkit/Globals';
import { TdError, TdObject } from '../../tdkit/TdTypes';
import {
  ArchiveChatSettings, NewChatPrivacySettings, PrivacyValue,
  ruleLabel, setAccountTtlDays, setArchiveSettings, setAutoDeleteSeconds,
  setBoolOption, setNewChatPrivacy, setReadDatePrivacy
} from '../../store/PrivacyApi';
import {
  OPT_DISABLE_TOP_CHATS, OPT_IGNORE_SENSITIVE, PrivacyLoadState, PrivacyStore
} from '../../store/PrivacyStore';
import { PrivacyRuleParams } from './PrivacyRulePage';
import {
  COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE,
  COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';

const CARD_RADIUS: number = 16;
const COLOR_WARNING: string = '#D98914';
const COLOR_DANGER: string = '#E5484D';

interface Choice {
  label: string;
  value: number;
}

interface RuleRow {
  setting: string;
  title: string;
  hint: string;
  group: string;
  premiumOnly: boolean;
  allowNobody: boolean;
}

const AUTO_DELETE: Choice[] = [
  { label: '关闭', value: 0 },
  { label: '1 天', value: 86400 },
  { label: '1 周', value: 604800 },
  { label: '1 个月', value: 2678400 }
];

const ACCOUNT_TTL: Choice[] = [
  { label: '1 个月', value: 30 },
  { label: '3 个月', value: 90 },
  { label: '6 个月', value: 180 },
  { label: '12 个月', value: 365 },
  { label: '18 个月', value: 548 },
  { label: '24 个月', value: 730 }
];

const RULE_ROWS: RuleRow[] = [
  { setting: 'userPrivacySettingShowPhoneNumber', title: '手机号码', group: 'personal',
    hint: '选择谁可以看到你的手机号码。', premiumOnly: false, allowNobody: true },
  { setting: 'userPrivacySettingShowStatus', title: '最后上线时间', group: 'personal',
    hint: '看不到你上线时间的人，你也看不到他们的。', premiumOnly: false, allowNobody: true },
  { setting: 'userPrivacySettingShowProfilePhoto', title: '头像', group: 'personal',
    hint: '选择谁可以看到你的头像。', premiumOnly: false, allowNobody: true },
  { setting: 'userPrivacySettingShowBio', title: '简介', group: 'personal',
    hint: '选择谁可以看到你的简介。', premiumOnly: false, allowNobody: true },
  { setting: 'userPrivacySettingShowBirthdate', title: '出生日期', group: 'personal',
    hint: '选择谁可以看到你的出生日期。', premiumOnly: false, allowNobody: true },
  { setting: 'userPrivacySettingShowProfileAudio', title: '个人资料音乐', group: 'personal',
    hint: '选择谁可以看到你个人资料中的音乐。', premiumOnly: false, allowNobody: true },
  { setting: 'userPrivacySettingShowLinkInForwardedMessages', title: '转发消息中的账号链接', group: 'personal',
    hint: '你的消息被转发时，选择谁可以从转发标题打开你的账号。', premiumOnly: false, allowNobody: true },
  { setting: 'userPrivacySettingAllowChatInvites', title: '群组与频道邀请', group: 'interaction',
    hint: '选择谁可以把你加入群组和频道。', premiumOnly: false, allowNobody: true },
  { setting: 'userPrivacySettingAllowCalls', title: '语音和视频通话', group: 'interaction',
    hint: '选择谁可以给你打电话。', premiumOnly: false, allowNobody: true },
  { setting: 'userPrivacySettingAllowPeerToPeerCalls', title: '通话点对点连接', group: 'interaction',
    hint: '点对点连接可改善通话质量，但会向对方暴露你的 IP 地址。', premiumOnly: false, allowNobody: true },
  { setting: 'userPrivacySettingAllowPrivateVoiceAndVideoNoteMessages', title: '语音与视频消息', group: 'interaction',
    hint: '选择谁可以给你发送语音和圆形视频消息。', premiumOnly: true, allowNobody: true },
  { setting: 'userPrivacySettingAllowFindingByPhoneNumber', title: '通过手机号找到我', group: 'interaction',
    hint: '选择谁可以通过你的手机号找到你。此项只支持“所有人”和“我的联系人”。',
    premiumOnly: false, allowNobody: false }
];

@Entry
@Component
struct PrivacySecurityPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State loadState: PrivacyLoadState = 'loading';
  @State refreshing: boolean = false;
  @State syncError: string = '';
  @State rules: Map<string, PrivacyValue> = new Map();
  @State passwordState: TdObject | null = null;
  @State autoDelete: number = -1;
  @State blocked: number = -1;
  @State sessions: number = -1;
  @State websites: number = -1;
  @State accountTtl: number = -1;
  @State archiveSettings: ArchiveChatSettings | null = null;
  @State readDate: boolean | null = null;
  @State newChatPrivacy: NewChatPrivacySettings | null = null;
  @State suggestFrequent: boolean | null = null;
  @State canArchiveUnknown: boolean = false;
  @State canSetNewChatPrivacy: boolean = false;
  @State canIgnoreSensitive: boolean = false;
  @State ignoreSensitive: boolean | null = null;
  @State isPremium: boolean = false;
  @State actionKey: string = '';
  @State pressedKey: string = '';
  private store: PrivacyStore | null = null;
  private unsubscribe: (() => void) | null = null;
  private active: boolean = false;
  private navigationLocked: boolean = false;

  @Styles
  rowNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  rowPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.82)
    .scale({ x: 0.992, y: 0.97 })
  }

  aboutToAppear(): void {
    this.active = true;
    this.navigationLocked = false;
    const settings = RULE_ROWS.map((row: RuleRow): string => row.setting);
    const store = new PrivacyStore(getTdClient(), settings);
    this.store = store;
    this.unsubscribe = store.subscribe((): void => { this.sync(store); });
    store.open();
  }

  aboutToDisappear(): void {
    this.active = false;
    if (this.unsubscribe !== null) { this.unsubscribe(); this.unsubscribe = null; }
    if (this.store !== null) { this.store.close(); this.store = null; }
    this.actionKey = '';
    this.pressedKey = '';
  }

  private sync(store: PrivacyStore): void {
    this.loadState = store.loadState;
    this.refreshing = store.refreshing;
    this.syncError = store.syncError;
    this.rules = new Map(store.rules);
    this.passwordState = store.passwordState;
    this.autoDelete = store.autoDeleteSeconds;
    this.blocked = store.blockedCount;
    this.sessions = store.sessionCount;
    this.websites = store.websiteCount;
    this.accountTtl = store.accountTtlDays;
    this.archiveSettings = store.archiveSettings;
    this.readDate = store.readDate;
    this.newChatPrivacy = store.newChatPrivacy;
    this.suggestFrequent = store.suggestFrequent;
    this.canArchiveUnknown = store.canArchiveUnknown;
    this.canSetNewChatPrivacy = store.canSetNewChatPrivacy;
    this.canIgnoreSensitive = store.canIgnoreSensitive;
    this.ignoreSensitive = store.ignoreSensitive;
    this.isPremium = store.isPremium;
  }

  private route(url: string, params?: Object): void {
    if (this.navigationLocked || this.actionKey !== '') { return; }
    this.navigationLocked = true;
    const work = params !== undefined
      ? router.pushUrl({ url, params })
      : router.pushUrl({ url });
    work.catch((error: Error): void => {
      this.navigationLocked = false;
      console.error(`PrivacySecurityPage.route failed: ${error.message}`);
      promptAction.showToast({ message: '页面打开失败，请重试', duration: 1700 });
    });
    setTimeout((): void => { this.navigationLocked = false; }, 700);
  }

  private save(key: string, work: Promise<void>, rollback: () => void): void {
    if (this.actionKey !== '') { rollback(); return; }
    this.actionKey = key;
    work.then((): void => {
      if (!this.active) { return; }
      this.actionKey = '';
    }).catch((error: TdError): void => {
      console.error(`PrivacySecurityPage.${key} failed: ${error.message}`);
      if (!this.active) { return; }
      rollback();
      this.actionKey = '';
      promptAction.showToast({ message: '保存失败，设置已恢复', duration: 1800 });
    });
  }

  private applyAutoDelete(seconds: number): void {
    if (this.actionKey !== '' || seconds === this.autoDelete) { return; }
    const previous = this.autoDelete;
    this.autoDelete = seconds;
    this.save('auto_delete', setAutoDeleteSeconds(seconds), (): void => { this.autoDelete = previous; });
  }

  private confirmAccountTtl(days: number): void {
    if (this.actionKey !== '' || days === this.accountTtl) { return; }
    promptAction.showDialog({
      title: '更改账号自动删除时间',
      message: `如果连续 ${this.choiceLabel(ACCOUNT_TTL, days)} 未登录，账号、联系人和云端消息将被永久删除。`,
      buttons: [
        { text: '取消', color: COLOR_TEXT_SECONDARY as string },
        { text: '确认更改', color: COLOR_DANGER }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (!this.active || result.index !== 1 || this.actionKey !== '') { return; }
      const previous = this.accountTtl;
      this.accountTtl = days;
      this.save('account_ttl', setAccountTtlDays(days), (): void => { this.accountTtl = previous; });
    }).catch((): void => {});
  }

  private applyArchive(value: boolean): void {
    const previous = this.archiveSettings;
    if (previous === null || this.actionKey !== '' || (!value && !previous.archiveUnknown) ||
      (value && previous.archiveUnknown) || (value && !this.canArchiveUnknown)) { return; }
    const next: ArchiveChatSettings = {
      archiveUnknown: value,
      keepUnmutedArchived: previous.keepUnmutedArchived,
      keepFolderChatsArchived: previous.keepFolderChatsArchived
    };
    this.archiveSettings = next;
    this.save('archive_unknown', setArchiveSettings(next), (): void => { this.archiveSettings = previous; });
  }

  private applyReadDate(value: boolean): void {
    const previous = this.readDate;
    if (previous === null || previous === value || this.actionKey !== '') { return; }
    this.readDate = value;
    this.save('read_date', setReadDatePrivacy(value), (): void => { this.readDate = previous; });
  }

  private applyNewChat(value: boolean): void {
    const previous = this.newChatPrivacy;
    if (previous === null || previous.allowUnknown === value || !this.canSetNewChatPrivacy ||
      this.actionKey !== '') { return; }
    const next: NewChatPrivacySettings = { allowUnknown: value, paidStars: previous.paidStars };
    this.newChatPrivacy = next;
    this.save('new_chat', setNewChatPrivacy(next), (): void => { this.newChatPrivacy = previous; });
  }

  private applyFrequent(value: boolean): void {
    const previous = this.suggestFrequent;
    if (previous === null || previous === value || this.actionKey !== '') { return; }
    this.suggestFrequent = value;
    this.save('top_chats', setBoolOption(OPT_DISABLE_TOP_CHATS, !value),
      (): void => { this.suggestFrequent = previous; });
  }

  private applySensitive(value: boolean): void {
    const previous = this.ignoreSensitive;
    if (previous === null || previous === value || !this.canIgnoreSensitive || this.actionKey !== '') { return; }
    this.ignoreSensitive = value;
    this.save('sensitive', setBoolOption(OPT_IGNORE_SENSITIVE, value),
      (): void => { this.ignoreSensitive = previous; });
  }

  private choiceLabel(choices: Choice[], value: number): string {
    for (const choice of choices) { if (choice.value === value) { return choice.label; } }
    return value > 0 ? `${Math.round(value / 86400)} 天` : '未加载';
  }

  private valueText(value: number): string {
    return value >= 0 ? `${value}` : '—';
  }

  private ruleValue(row: RuleRow): string {
    const value = this.rules.get(row.setting);
    if (row.premiumOnly && !this.isPremium) { return 'Premium'; }
    return value !== undefined ? ruleLabel(value) : '—';
  }

  private openRule(row: RuleRow): void {
    if (row.premiumOnly && !this.isPremium) {
      promptAction.showToast({ message: '此隐私规则需要 Telegram Premium', duration: 1800 });
      return;
    }
    if (!this.rules.has(row.setting)) {
      promptAction.showToast({ message: '该项尚未加载，请刷新后重试', duration: 1600 });
      return;
    }
    const params: PrivacyRuleParams = {
      setting: row.setting, title: row.title, hint: row.hint, allowNobody: row.allowNobody
    };
    this.route('pages/main/PrivacyRulePage', params);
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([COLOR_TEXT_PRIMARY]);
      }
      .width(40).height(40).borderRadius(20).backgroundColor(Color.Transparent)
      .onClick((): void => { router.back(); });
      Text('隐私与安全').fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
      if (this.loadState === 'ready') {
        Button() {
          if (this.refreshing) {
            LoadingProgress().width(20).height(20).color(COLOR_PRIMARY);
          } else {
            SymbolGlyph($r('sys.symbol.arrow_counterclockwise')).fontSize(20).fontColor([COLOR_PRIMARY]);
          }
        }
        .width(40).height(40).borderRadius(20).backgroundColor(Color.Transparent)
        .enabled(!this.refreshing && this.actionKey === '')
        .onClick((): void => { this.store?.refresh(); });
      }
    }
    .width('100%').height(52).padding({ left: 8, right: 10 }).alignItems(VerticalAlign.Center);
  }

  @Builder
  sectionTitle(text: string) {
    Text(text).fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
      .width('100%').padding({ left: 16, right: 16, top: 13, bottom: 5 });
  }

  @Builder
  divider() {
    Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
  }

  @Builder
  disclosure() {
    SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([COLOR_TEXT_SECONDARY]);
  }

  @Builder
  autoDeleteMenu() {
    Menu() {
      ForEach(AUTO_DELETE, (choice: Choice) => {
        MenuItem({ content: choice.label }).selected(this.autoDelete === choice.value)
          .onClick((): void => { this.applyAutoDelete(choice.value); });
      }, (choice: Choice): string => `auto_${choice.value}`);
    }
  }

  @Builder
  accountTtlMenu() {
    Menu() {
      ForEach(ACCOUNT_TTL, (choice: Choice) => {
        MenuItem({ content: choice.label }).selected(this.accountTtl === choice.value)
          .onClick((): void => { this.confirmAccountTtl(choice.value); });
      }, (choice: Choice): string => `ttl_${choice.value}`);
    }
  }

  @Builder
  skeleton() {
    Column({ space: 14 }) {
      ForEach([0, 1, 2, 3], (index: number) => {
        Column({ space: 12 }) {
          Row().width(88).height(12).borderRadius(6).backgroundColor($r('app.color.surface_alt'));
          Row().width('100%').height(index === 1 ? 188 : 112).borderRadius(CARD_RADIUS)
            .backgroundColor(COLOR_SURFACE);
        }.width('100%').alignItems(HorizontalAlign.Start);
      }, (index: number): string => `privacy_skeleton_${index}`);
    }
    .width('100%').padding({ left: 12, right: 12, top: 8 });
  }

  @Builder
  errorState() {
    Column({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(48).fontColor([COLOR_TEXT_SECONDARY]);
      Text('隐私设置加载失败').fontSize(18).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
      Text('没有使用默认值替代账号状态，避免误操作。').fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
        .textAlign(TextAlign.Center);
      Button('重新加载').fontSize(15).fontColor(Color.White).backgroundColor(COLOR_PRIMARY)
        .height(42).padding({ left: 22, right: 22 }).borderRadius(21)
        .onClick((): void => { this.store?.refresh(); });
    }
    .layoutWeight(1).width('100%').padding({ left: 32, right: 32 }).justifyContent(FlexAlign.Center);
  }

  @Builder
  content() {
    Scroll() {
      Column({ space: 12 }) {
        if (this.syncError !== '') {
          Row({ space: 9 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill')).fontSize(17).fontColor([COLOR_WARNING]);
            Text(this.syncError).fontSize(13).fontColor(COLOR_TEXT_SECONDARY).layoutWeight(1);
            Text('重试').fontSize(13).fontColor(COLOR_PRIMARY)
              .onClick((): void => { this.store?.refresh(); });
          }
          .width('100%').padding(12).backgroundColor(COLOR_SURFACE).borderRadius(12);
        }

        Column() {
          this.sectionTitle('账号安全');
          Row({ space: 10 }) {
            Text('两步验证').fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
            Text(this.passwordState === null ? '—' :
              (((this.passwordState['has_password'] as boolean | undefined) ?? false) ? '已开启' : '未开启'))
              .fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
            this.disclosure();
          }
          .width('100%').constraintSize({ minHeight: 50 }).padding({ left: 16, right: 14 })
          .borderRadius(12).stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
          .onClick((): void => { this.route('pages/main/TwoStepVerificationPage'); });
          this.divider();
          Row({ space: 10 }) {
            Text('活跃设备').fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
            Text(this.valueText(this.sessions)).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
            this.disclosure();
          }
          .width('100%').constraintSize({ minHeight: 50 }).padding({ left: 16, right: 14 })
          .borderRadius(12).stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
          .onClick((): void => { this.route('pages/main/ActiveSessionsPage'); });
          this.divider();
          Row({ space: 10 }) {
            Text('已连接的网站').fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
            Text(this.valueText(this.websites)).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
            this.disclosure();
          }
          .width('100%').constraintSize({ minHeight: 50 }).padding({ left: 16, right: 14 })
          .borderRadius(12).stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
          .onClick((): void => { this.route('pages/main/ConnectedWebsitesPage'); });
        }
        .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).padding({ bottom: 5 });

        Column() {
          this.sectionTitle('个人信息');
          ForEach(RULE_ROWS.filter((row: RuleRow): boolean => row.group === 'personal'),
            (row: RuleRow, index: number) => {
              if (index > 0) { this.divider(); }
              Row({ space: 9 }) {
                Text(row.title).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                Text(this.ruleValue(row)).fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                this.disclosure();
              }
              .width('100%').constraintSize({ minHeight: 50 }).padding({ left: 16, right: 14 })
              .borderRadius(12).stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
              .onClick((): void => { this.openRule(row); });
            }, (row: RuleRow): string => `personal_${row.setting}_${this.ruleValue(row)}`);
        }
        .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).padding({ bottom: 5 });

        Column() {
          this.sectionTitle('互动权限');
          ForEach(RULE_ROWS.filter((row: RuleRow): boolean => row.group === 'interaction'),
            (row: RuleRow, index: number) => {
              if (index > 0) { this.divider(); }
              Row({ space: 9 }) {
                Text(row.title).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                Text(this.ruleValue(row)).fontSize(14)
                  .fontColor(row.premiumOnly && !this.isPremium ? COLOR_WARNING : COLOR_TEXT_SECONDARY)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                this.disclosure();
              }
              .width('100%').constraintSize({ minHeight: 50 }).padding({ left: 16, right: 14 })
              .borderRadius(12).stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
              .onClick((): void => { this.openRule(row); });
            }, (row: RuleRow): string => `interaction_${row.setting}_${this.ruleValue(row)}`);
        }
        .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).padding({ bottom: 5 });

        Column() {
          this.sectionTitle('消息隐私');
          if (this.readDate !== null) {
            Row({ space: 12 }) {
              Column({ space: 2 }) {
                Text('显示消息已读时间').fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
                Text('关闭后，部分情况下你也无法看到对方的已读时间')
                  .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).maxLines(2);
              }.layoutWeight(1).alignItems(HorizontalAlign.Start);
              Toggle({ type: ToggleType.Switch, isOn: this.readDate })
                .selectedColor(COLOR_PRIMARY).enabled(this.actionKey === '')
                .onChange((value: boolean): void => { this.applyReadDate(value); });
            }
            .width('100%').constraintSize({ minHeight: 62 }).padding({ left: 16, right: 14, top: 7, bottom: 7 });
          }
          if (this.newChatPrivacy !== null) {
            this.divider();
            Row({ space: 12 }) {
              Column({ space: 2 }) {
                Text('允许陌生人发起新聊天').fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
                Text(this.canSetNewChatPrivacy ? '限制非联系人主动发来私聊' : '当前账号暂不支持修改此项')
                  .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
              }.layoutWeight(1).alignItems(HorizontalAlign.Start);
              Toggle({ type: ToggleType.Switch, isOn: this.newChatPrivacy.allowUnknown })
                .selectedColor(COLOR_PRIMARY).enabled(this.canSetNewChatPrivacy && this.actionKey === '')
                .onChange((value: boolean): void => { this.applyNewChat(value); });
            }
            .width('100%').constraintSize({ minHeight: 62 }).padding({ left: 16, right: 14, top: 7, bottom: 7 });
          }
          if (this.archiveSettings !== null) {
            this.divider();
            Row({ space: 12 }) {
              Column({ space: 2 }) {
                Text('归档并静音陌生人新聊天').fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
                Text(this.canArchiveUnknown || this.archiveSettings.archiveUnknown
                  ? '保留其他归档行为，不覆盖账号原有设置' : '当前账号暂不能启用')
                  .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
              }.layoutWeight(1).alignItems(HorizontalAlign.Start);
              Toggle({ type: ToggleType.Switch, isOn: this.archiveSettings.archiveUnknown })
                .selectedColor(COLOR_PRIMARY)
                .enabled((this.canArchiveUnknown || this.archiveSettings.archiveUnknown) && this.actionKey === '')
                .onChange((value: boolean): void => { this.applyArchive(value); });
            }
            .width('100%').constraintSize({ minHeight: 62 }).padding({ left: 16, right: 14, top: 7, bottom: 7 });
          }
          if (this.autoDelete >= 0) {
            this.divider();
            Row({ space: 9 }) {
              Column({ space: 2 }) {
                Text('新聊天默认自动删除').fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
                Text('只影响开启后新建的聊天').fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
              }.layoutWeight(1).alignItems(HorizontalAlign.Start);
              Text(this.choiceLabel(AUTO_DELETE, this.autoDelete)).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
              this.disclosure();
            }
            .width('100%').constraintSize({ minHeight: 58 }).padding({ left: 16, right: 14 })
            .borderRadius(12).stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
            .bindMenu(this.autoDeleteMenu());
          }
        }
        .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).padding({ bottom: 5 });

        Column() {
          this.sectionTitle('联系人与账号');
          Row({ space: 9 }) {
            Text('已屏蔽的用户').fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
            Text(this.valueText(this.blocked)).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
            this.disclosure();
          }
          .width('100%').constraintSize({ minHeight: 50 }).padding({ left: 16, right: 14 })
          .borderRadius(12).stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
          .onClick((): void => { this.route('pages/main/BlockedUsersPage'); });
          if (this.suggestFrequent !== null) {
            this.divider();
            Row({ space: 12 }) {
              Column({ space: 2 }) {
                Text('推荐常用联系人').fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
                Text('在搜索中显示经常联系的人').fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
              }.layoutWeight(1).alignItems(HorizontalAlign.Start);
              Toggle({ type: ToggleType.Switch, isOn: this.suggestFrequent })
                .selectedColor(COLOR_PRIMARY).enabled(this.actionKey === '')
                .onChange((value: boolean): void => { this.applyFrequent(value); });
            }
            .width('100%').constraintSize({ minHeight: 58 }).padding({ left: 16, right: 14 });
          }
          if (this.canIgnoreSensitive && this.ignoreSensitive !== null) {
            this.divider();
            Row({ space: 12 }) {
              Column({ space: 2 }) {
                Text('显示敏感内容').fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
                Text('仅在服务器允许时显示此选项').fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
              }.layoutWeight(1).alignItems(HorizontalAlign.Start);
              Toggle({ type: ToggleType.Switch, isOn: this.ignoreSensitive })
                .selectedColor(COLOR_PRIMARY).enabled(this.actionKey === '')
                .onChange((value: boolean): void => { this.applySensitive(value); });
            }
            .width('100%').constraintSize({ minHeight: 58 }).padding({ left: 16, right: 14 });
          }
          if (this.accountTtl >= 0) {
            this.divider();
            Row({ space: 9 }) {
              Column({ space: 2 }) {
                Text('自动删除账号').fontSize(16).fontColor(COLOR_DANGER);
                Text('长期未登录后永久删除账号数据').fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
              }.layoutWeight(1).alignItems(HorizontalAlign.Start);
              Text(this.choiceLabel(ACCOUNT_TTL, this.accountTtl)).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
              this.disclosure();
            }
            .width('100%').constraintSize({ minHeight: 60 }).padding({ left: 16, right: 14 })
            .borderRadius(12).stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
            .bindMenu(this.accountTtlMenu());
          }
        }
        .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).padding({ bottom: 5 });

        Text('隐私规则按顺序由 Telegram 服务器执行；修改总规则时会完整保留已有例外。')
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(18)
          .width('100%').padding({ left: 16, right: 16, bottom: 4 });
      }
      .width('100%').padding({ left: 12, right: 12, top: 6, bottom: this.bottomSafe + 24 });
    }
    .layoutWeight(1).width('100%').align(Alignment.Top).scrollBar(BarState.Off);
  }

  build() {
    Column() {
      this.header();
      if (this.loadState === 'loading') { this.skeleton(); }
      else if (this.loadState === 'error') { this.errorState(); }
      else { this.content(); }
    }
    .width('100%').height('100%').backgroundColor(COLOR_PAGE_BG)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.topSafe });
  }
}
