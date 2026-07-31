import { router, promptAction } from '@kit.ArkUI';
import {
  addTdAccount, getActiveTdAccountSlot, getTdAccounts, getTdClient,
  logoutCurrentTdAccount, removeDuplicateTdAccountsForActive,
  switchTdAccount, updateActiveTdAccountProfile
} from '../../tdkit/Globals';
import { TdAccountSummary } from '../../tdkit/AccountRegistry';
import { ProfileStore } from '../../store/ProfileStore';
import { AvatarView } from '../chatlist/AvatarView';
import { TgsStickerView } from '../chat/TgsStickerView';
import { WebmStickerView } from '../chat/WebmStickerView';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import {
  COLOR_DIVIDER, COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { floatingLiveWindow } from '../chat/LiveFloatingWindow';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';

const CARD_BG: ResourceColor = $r('app.color.surface');
const CARD_RADIUS: number = 14;
const PAGE_BG: ResourceColor = $r('app.color.page_bg');
const TOP_BAR_HEIGHT: number = 56;
const TOP_ACTION_SIZE: number = 44;
const PROFILE_LOAD_TIMEOUT_MS: number = 8000;

interface SettingItem {
  icon: string;
  bg: string;
  title: string;
  subtitle: string;
  page: string; // route to open ('' = not implemented yet)
}

interface SettingGroup {
  title: string;
  items: SettingItem[];
}

// 账号 opens the same editor as 个人资料 → 编辑信息 (name, bio, username,
// birthday) — one page, two entry points, as in the official clients.
const SETTING_GROUPS: SettingGroup[] = [
  {
    title: '账号与聊天',
    items: [
      { icon: 'sys.symbol.person_fill', bg: '#3478F6', title: '账号', subtitle: '电话、用户名与简介',
        page: 'pages/main/AccountEditPage' },
      { icon: 'sys.symbol.message_fill', bg: '#FF9500', title: '聊天设置',
        subtitle: '字号、圆角、夜间模式与动画效果', page: 'pages/main/ChatSettingsPage' },
      { icon: 'sys.symbol.folder_fill', bg: '#34AADC', title: '聊天文件夹',
        subtitle: '将聊天分类到文件夹中', page: 'pages/main/ChatFoldersPage' }
    ]
  },
  {
    title: '隐私与设备',
    items: [
      { icon: 'sys.symbol.lock_fill', bg: '#34C759', title: '隐私与安全',
        subtitle: '最后上线时间、屏蔽名单、登录设备', page: 'pages/main/PrivacySecurityPage' },
      { icon: 'sys.symbol.computer', bg: '#5AC8FA', title: '设备',
        subtitle: '管理已连接的设备', page: 'pages/main/ActiveSessionsPage' }
    ]
  },
  {
    title: '存储与性能',
    items: [
      { icon: 'sys.symbol.data_proportion', bg: '#007AFF', title: '数据与存储',
        subtitle: '存储占用、流量与代理', page: 'pages/main/DataStoragePage' },
      { icon: 'sys.symbol.battery_100percent', bg: '#FF9500', title: '省电',
        subtitle: '低电量时降低功耗', page: 'pages/main/PowerUsagePage' }
    ]
  }
];

// The settings tab: user header (avatar with camera badge, name, phone·username)
// followed by the grouped list of setting entries.
@Preview
@Component
export struct SettingsPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageLink('tdAccountRegistryEpoch') @Watch('onAccountRegistryEpoch')
  accountRegistryEpoch: number = 0;
  @State myId: number = 0;
  @State name: string = '';
  @State initials: string = '?';
  @State avatarPath: string = '';
  @State avatarAnimPath: string = '';
  @State statusEmojiPath: string = '';
  @State statusEmojiFormat: string = '';
  @State phone: string = '';
  @State usernames: string[] = [];
  @State accounts: TdAccountSummary[] = [];
  @State activeSlotId: string = '';
  @State switchingSlotId: string = '';
  @State profileLoading: boolean = true;
  @State profileError: string = '';
  @State profileSkeletonBright: boolean = false;
  @State accountActionError: string = '';
  @State accountActionRetry: string = '';
  @State accountActionTarget: string = '';
  @State settingsSearchOpen: boolean = false;
  @State settingsQuery: string = '';
  @State moreMenuOpen: boolean = false;
  @State logoutDialogOpen: boolean = false;
  @State accountNavigationLocked: boolean = false;
  @State pressedSettingTitle: string = '';
  @State openingSettingPage: string = '';
  private store: ProfileStore | null = null;
  private unsub: (() => void) | null = null;
  private profileLoadSequence: number = 0;
  private profileLoadTimer: number = -1;
  private accountNavigationTimer: number = -1;
  private settingNavigationTimer: number = -1;
  private moreActionTimer: number = -1;
  private profileSkeletonTimer: number = -1;

  aboutToAppear(): void {
    this.reloadAccounts();
    this.loadProfile();
  }

  aboutToDisappear(): void {
    this.profileLoadSequence++;
    this.clearProfileLoadTimer();
    this.closeProfileStore();
    this.releaseAccountNavigation();
    this.releaseSettingNavigation();
    this.pressedSettingTitle = '';
    this.settingsSearchOpen = false;
    this.settingsQuery = '';
    this.moreMenuOpen = false;
    this.logoutDialogOpen = false;
    this.stopProfileSkeletonPulse();
    this.accountActionError = '';
    this.accountActionRetry = '';
    this.accountActionTarget = '';
    if (this.moreActionTimer !== -1) {
      clearTimeout(this.moreActionTimer);
      this.moreActionTimer = -1;
    }
  }

  private loadProfile(): void {
    const sequence = ++this.profileLoadSequence;
    this.clearProfileLoadTimer();
    this.closeProfileStore();
    this.profileLoading = true;
    this.profileError = '';
    this.startProfileSkeletonPulse();
    const req: TdRequest = { '@type': 'getMe' };
    getTdClient().send(req, PROFILE_LOAD_TIMEOUT_MS).then((me: TdObject): void => {
      if (sequence !== this.profileLoadSequence) {
        return;
      }
      this.myId = (me['id'] as number | undefined) ?? 0;
      if (this.myId === 0) {
        this.profileLoading = false;
        this.profileError = '暂时无法读取当前账号';
        this.stopProfileSkeletonPulse();
        return;
      }
      const store = new ProfileStore(getTdClient(), this.myId);
      this.store = store;
      this.unsub = store.subscribe(() => { this.refresh(); });
      store.open();
      this.profileLoadTimer = setTimeout((): void => {
        this.profileLoadTimer = -1;
        if (sequence === this.profileLoadSequence && this.profileLoading) {
          this.profileLoading = false;
          this.profileError = '账号资料加载超时';
          this.stopProfileSkeletonPulse();
        }
      }, PROFILE_LOAD_TIMEOUT_MS);
    }).catch((e: TdError): void => {
      if (sequence !== this.profileLoadSequence) {
        return;
      }
      this.clearProfileLoadTimer();
      this.profileLoading = false;
      this.profileError = '账号资料加载失败';
      this.stopProfileSkeletonPulse();
      console.error(`SettingsPage.getMe failed: ${e.message}`);
    });
  }

  private startProfileSkeletonPulse(): void {
    if (this.profileSkeletonTimer !== -1 ||
      powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 1) === 0) {
      return;
    }
    this.profileSkeletonTimer = setInterval((): void => {
      this.profileSkeletonBright = !this.profileSkeletonBright;
    }, 680);
  }

  private stopProfileSkeletonPulse(): void {
    if (this.profileSkeletonTimer !== -1) {
      clearInterval(this.profileSkeletonTimer);
      this.profileSkeletonTimer = -1;
    }
    this.profileSkeletonBright = false;
  }

  private closeProfileStore(): void {
    if (this.unsub !== null) { this.unsub(); this.unsub = null; }
    if (this.store !== null) { this.store.close(); this.store = null; }
  }

  private clearProfileLoadTimer(): void {
    if (this.profileLoadTimer !== -1) {
      clearTimeout(this.profileLoadTimer);
      this.profileLoadTimer = -1;
    }
  }

  private refresh(): void {
    const s = this.store;
    if (s === null) {
      return;
    }
    this.name = s.name;
    this.initials = s.initials;
    this.avatarPath = s.avatarPath;
    this.avatarAnimPath = s.avatarAnimPath;
    this.statusEmojiPath = s.statusEmojiPath;
    this.statusEmojiFormat = s.statusEmojiFormat;
    this.phone = s.phone;
    this.usernames = s.usernames;
    if (this.name !== '') {
      this.clearProfileLoadTimer();
      this.profileLoading = false;
      this.profileError = '';
      this.stopProfileSkeletonPulse();
    }
    updateActiveTdAccountProfile(
      this.myId,
      this.name,
      this.phone,
      this.usernames.length > 0 ? this.usernames[0] : '',
      this.avatarPath
    );
  }

  private onAccountRegistryEpoch(): void {
    this.reloadAccounts();
  }

  private reloadAccounts(): void {
    removeDuplicateTdAccountsForActive();
    this.accounts = getTdAccounts();
    this.activeSlotId = getActiveTdAccountSlot();
  }

  private accountInitials(account: TdAccountSummary): string {
    const trimmed = account.name.trim();
    if (trimmed === '') { return '?'; }
    const parts = trimmed.split(' ').filter((part: string): boolean => part !== '');
    if (parts.length >= 2) {
      return `${parts[0].substring(0, 1)}${parts[parts.length - 1].substring(0, 1)}`.toUpperCase();
    }
    return trimmed.substring(0, Math.min(2, trimmed.length)).toUpperCase();
  }

  private accountSubtitle(account: TdAccountSummary): string {
    if (account.pendingLogin) { return '点击继续登录'; }
    const parts: string[] = [];
    if (account.phone !== '') { parts.push(`+${account.phone}`); }
    if (account.username !== '') { parts.push(`@${account.username}`); }
    return parts.length > 0 ? parts.join('  ·  ') : 'Telegram 账号';
  }

  private otherAccounts(): TdAccountSummary[] {
    return this.accounts.filter(
      (account: TdAccountSummary): boolean =>
        account.slotId !== this.activeSlotId && !account.pendingLogin
    );
  }

  private filteredSettingGroups(): SettingGroup[] {
    const query = this.settingsQuery.trim().toLowerCase();
    if (query === '') {
      return SETTING_GROUPS;
    }
    const groups: SettingGroup[] = [];
    for (const group of SETTING_GROUPS) {
      const items = group.items.filter((item: SettingItem): boolean =>
        item.title.toLowerCase().includes(query) ||
        item.subtitle.toLowerCase().includes(query) ||
        group.title.toLowerCase().includes(query)
      );
      if (items.length > 0) {
        groups.push({ title: group.title, items });
      }
    }
    return groups;
  }

  private closeSettingsSearch(): void {
    this.settingsSearchOpen = false;
    this.settingsQuery = '';
  }

  private openAccountEditor(): void {
    if (this.profileError !== '') {
      this.loadProfile();
      return;
    }
    if (this.profileLoading || this.switchingSlotId !== '' ||
      this.accountNavigationLocked || this.openingSettingPage !== '') {
      return;
    }
    this.accountNavigationLocked = true;
    this.accountNavigationTimer = setTimeout((): void => {
      this.accountNavigationTimer = -1;
      this.accountNavigationLocked = false;
    }, 600);
    router.pushUrl({ url: 'pages/main/AccountEditPage' }).catch((error: Error): void => {
      console.error(`SettingsPage.openAccountEditor failed: ${error.message}`);
      promptAction.showToast({ message: '无法打开账号资料，请稍后重试', duration: 1800 });
      this.releaseAccountNavigation();
    });
  }

  private releaseAccountNavigation(): void {
    if (this.accountNavigationTimer !== -1) {
      clearTimeout(this.accountNavigationTimer);
      this.accountNavigationTimer = -1;
    }
    this.accountNavigationLocked = false;
  }

  private openSetting(item: SettingItem): void {
    if (this.switchingSlotId !== '' || this.openingSettingPage !== '' ||
      this.accountNavigationLocked) {
      return;
    }
    if (item.page === '') {
      promptAction.showToast({ message: `${item.title}暂未支持`, duration: 1500 });
      return;
    }
    this.openingSettingPage = item.title;
    this.settingNavigationTimer = setTimeout((): void => {
      this.settingNavigationTimer = -1;
      this.openingSettingPage = '';
    }, 800);
    router.pushUrl({ url: item.page }).catch((error: Error): void => {
      console.error(`SettingsPage.openSetting(${item.title}) failed: ${error.message}`);
      promptAction.showToast({ message: `无法打开${item.title}，请稍后重试`, duration: 1800 });
      this.releaseSettingNavigation();
    });
  }

  private releaseSettingNavigation(): void {
    if (this.settingNavigationTimer !== -1) {
      clearTimeout(this.settingNavigationTimer);
      this.settingNavigationTimer = -1;
    }
    this.openingSettingPage = '';
  }

  @Styles
  topActionNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  topActionPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.72)
    .scale({ x: 0.92, y: 0.92 })
  }

  @Styles
  accountRowNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  accountRowPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.8)
    .scale({ x: 0.985, y: 0.985 })
  }

  @Styles
  retryActionNormalStyle() {
    .backgroundColor('#143478F6')
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  retryActionPressedStyle() {
    .backgroundColor('#243478F6')
    .opacity(0.72)
    .scale({ x: 0.96, y: 0.96 })
  }

  @Styles
  settingRowNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  settingRowPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.78)
    .scale({ x: 0.985, y: 0.985 })
  }

  @Styles
  dangerActionNormalStyle() {
    .backgroundColor('#14E64646')
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  dangerActionPressedStyle() {
    .backgroundColor('#24E64646')
    .opacity(0.72)
    .scale({ x: 0.98, y: 0.98 })
  }

  private switchAccount(slotId: string): void {
    if (this.switchingSlotId !== '' || slotId === this.activeSlotId ||
      this.accountNavigationLocked || this.openingSettingPage !== '' ||
      this.moreMenuOpen || this.logoutDialogOpen) { return; }
    this.clearAccountActionError();
    this.switchingSlotId = slotId;
    floatingLiveWindow.closeForAccountSwitch()
      .then((): Promise<void> => switchTdAccount(slotId))
      .catch((caught: Error): void => {
        console.error(`SettingsPage.switchAccount failed: ${caught.message}`);
        promptAction.showToast({ message: '账号切换失败，请重试', duration: 1800 });
        this.switchingSlotId = '';
        this.accountActionError = '账号切换失败，请检查网络后重试';
        this.accountActionRetry = 'switch';
        this.accountActionTarget = slotId;
      });
  }

  private addAccount(): void {
    if (this.switchingSlotId !== '' || this.accountNavigationLocked ||
      this.openingSettingPage !== '' || this.moreMenuOpen || this.logoutDialogOpen) { return; }
    this.clearAccountActionError();
    this.switchingSlotId = 'new';
    floatingLiveWindow.closeForAccountSwitch()
      .then((): Promise<void> => addTdAccount())
      .catch((caught: Error): void => {
        console.error(`SettingsPage.addAccount failed: ${caught.message}`);
        promptAction.showToast({ message: '暂时无法添加账号，请重试', duration: 1800 });
        this.switchingSlotId = '';
        this.accountActionError = '暂时无法启动账号登录';
        this.accountActionRetry = 'add';
        this.accountActionTarget = '';
      });
  }

  private clearAccountActionError(): void {
    this.accountActionError = '';
    this.accountActionRetry = '';
    this.accountActionTarget = '';
  }

  private retryAccountAction(): void {
    if (this.switchingSlotId !== '') {
      return;
    }
    const action = this.accountActionRetry;
    const target = this.accountActionTarget;
    this.clearAccountActionError();
    if (action === 'switch' && target !== '') {
      this.switchAccount(target);
    } else if (action === 'add') {
      this.addAccount();
    } else if (action === 'logout') {
      this.performLogout();
    }
  }

  private showMoreMenu(): void {
    if (this.switchingSlotId !== '' || this.moreMenuOpen ||
      this.accountNavigationLocked || this.openingSettingPage !== '') { return; }
    this.moreMenuOpen = true;
  }

  private requestLogoutFromSheet(): void {
    if (this.logoutDialogOpen || this.switchingSlotId !== '') {
      return;
    }
    this.moreMenuOpen = false;
    if (this.moreActionTimer !== -1) {
      clearTimeout(this.moreActionTimer);
    }
    this.moreActionTimer = setTimeout((): void => {
      this.moreActionTimer = -1;
      this.confirmLogout();
    }, powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160));
  }

  private confirmLogout(): void {
    if (this.logoutDialogOpen || this.switchingSlotId !== '') {
      return;
    }
    this.logoutDialogOpen = true;
    const hasAnotherAccount = this.accounts.some(
      (account: TdAccountSummary): boolean =>
        account.slotId !== this.activeSlotId && !account.pendingLogin && account.userId !== 0
    );
    promptAction.showDialog({
      title: '退出登录',
      message: hasAnotherAccount
        ? '确定退出当前账号吗？退出后将自动切换到另一个账号。'
        : '确定退出当前账号吗？退出后需要重新登录。',
      buttons: [
        { text: '取消', color: COLOR_TEXT_SECONDARY as string },
        { text: '退出', color: '#FF3B30' }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      this.logoutDialogOpen = false;
      if (result.index === 1) { this.performLogout(); }
    }).catch((): void => {
      this.logoutDialogOpen = false;
    });
  }

  private performLogout(): void {
    if (this.switchingSlotId !== '') { return; }
    this.clearAccountActionError();
    this.switchingSlotId = 'logout';
    floatingLiveWindow.closeForAccountSwitch()
      .then((): Promise<void> => logoutCurrentTdAccount())
      .catch((caught: Error): void => {
        console.error(`SettingsPage.logout failed: ${caught.message}`);
        promptAction.showToast({ message: '退出登录失败，请重试', duration: 1800 });
        this.switchingSlotId = '';
        this.accountActionError = '退出登录失败，账号仍保持登录';
        this.accountActionRetry = 'logout';
        this.accountActionTarget = '';
      });
  }

  private subtitleLine(): string {
    const parts: string[] = [];
    if (this.phone !== '') {
      parts.push(`+${this.phone}`);
    }
    if (this.usernames.length > 0) {
      parts.push(`@${this.usernames[0]}`);
    }
    return parts.join('  ·  ');
  }

  @Builder
  topBar() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.settingsSearchOpen) {
        Row({ space: 8 }) {
          Row() {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(23)
              .fontColor([COLOR_TEXT_PRIMARY]);
          }
          .width(TOP_ACTION_SIZE)
          .height(TOP_ACTION_SIZE)
          .borderRadius(TOP_ACTION_SIZE / 2)
          .justifyContent(FlexAlign.Center)
          .stateStyles({
            normal: this.topActionNormalStyle,
            pressed: this.topActionPressedStyle
          })
          .accessibilityText('关闭设置搜索')
          .onClick((): void => { this.closeSettingsSearch(); });

          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(17)
              .fontColor([COLOR_TEXT_SECONDARY]);
            TextInput({ text: this.settingsQuery, placeholder: '搜索设置' })
              .layoutWeight(1)
              .height(44)
              .fontSize(16)
              .fontColor(COLOR_TEXT_PRIMARY)
              .placeholderColor(COLOR_TEXT_SECONDARY)
              .caretColor(COLOR_PRIMARY)
              .backgroundColor(Color.Transparent)
              .padding(0)
              .enterKeyType(EnterKeyType.Search)
              .onChange((value: string): void => { this.settingsQuery = value; });
            if (this.settingsQuery !== '') {
              Row() {
                SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
                  .fontSize(17)
                  .fontColor([COLOR_TEXT_SECONDARY]);
              }
              .width(32)
              .height(36)
              .justifyContent(FlexAlign.Center)
              .accessibilityText('清除设置搜索')
              .onClick((): void => { this.settingsQuery = ''; });
            }
          }
          .height(44)
          .layoutWeight(1)
          .padding({ left: 14, right: 8 })
          .backgroundColor($r('app.color.surface_alt'))
          .borderRadius(14);
        }
        .width('100%')
        .height(TOP_BAR_HEIGHT)
        .padding({ left: 8, right: 12 })
        .alignItems(VerticalAlign.Center)
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.translate({ x: 12 }))
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
            curve: Curve.EaseOut
          }));
      } else {
        Row({ space: 4 }) {
          Text('设置')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT_PRIMARY)
            .layoutWeight(1);
          Row() {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(21)
              .fontColor([COLOR_TEXT_SECONDARY]);
          }
          .width(TOP_ACTION_SIZE)
          .height(TOP_ACTION_SIZE)
          .borderRadius(TOP_ACTION_SIZE / 2)
          .justifyContent(FlexAlign.Center)
          .stateStyles({
            normal: this.topActionNormalStyle,
            pressed: this.topActionPressedStyle
          })
          .enabled(this.switchingSlotId === '' &&
            !this.accountNavigationLocked && this.openingSettingPage === '')
          .accessibilityText('搜索设置')
          .onClick((): void => {
            if (this.switchingSlotId === '') {
              this.settingsSearchOpen = true;
              this.settingsQuery = '';
            }
          });
          Stack({ alignContent: Alignment.Center }) {
            if (this.switchingSlotId === 'logout') {
              LoadingProgress().width(21).height(21).color(COLOR_PRIMARY);
            } else {
              SymbolGlyph($r('sys.symbol.more'))
                .fontSize(22)
                .fontColor([COLOR_TEXT_SECONDARY]);
            }
          }
          .width(TOP_ACTION_SIZE)
          .height(TOP_ACTION_SIZE)
          .borderRadius(TOP_ACTION_SIZE / 2)
          .stateStyles({
            normal: this.topActionNormalStyle,
            pressed: this.topActionPressedStyle
          })
          .enabled(this.switchingSlotId === '' && !this.moreMenuOpen &&
            !this.accountNavigationLocked && this.openingSettingPage === '')
          .accessibilityText('设置更多操作')
          .onClick((): void => { this.showMoreMenu(); });
        }
        .width('100%')
        .height(TOP_BAR_HEIGHT)
        .padding({ left: 16, right: 8 })
        .alignItems(VerticalAlign.Center)
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.translate({ x: -8 }))
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
            curve: Curve.EaseOut
          }));
      }
    }
    .width('100%')
    .height(TOP_BAR_HEIGHT)
    .backgroundColor(PAGE_BG);
  }

  @Builder
  profileLoadingCard() {
    Row({ space: 14 }) {
      Circle({ width: 72, height: 72 })
        .fill($r('app.color.surface_alt'));
      Column({ space: 9 }) {
        Rect({ width: 132, height: 16, radius: 8 })
          .fill($r('app.color.surface_alt'));
        Rect({ width: 188, height: 10, radius: 5 })
          .fill($r('app.color.surface_alt'));
        Rect({ width: 92, height: 9, radius: 4.5 })
          .fill($r('app.color.surface_alt'));
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
      LoadingProgress()
        .width(22)
        .height(22)
        .color(COLOR_PRIMARY);
    }
    .width('calc(100% - 24vp)')
    .height(108)
    .margin({ left: 12, right: 12 })
    .padding({ left: 16, right: 14 })
    .borderRadius(CARD_RADIUS)
    .alignItems(VerticalAlign.Center)
    .opacity(this.profileSkeletonBright ? 0.56 : 0.92)
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 640),
      curve: Curve.EaseInOut
    })
    .accessibilityText('正在加载账号资料')
    .transition(TransitionEffect.OPACITY.animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160),
      curve: Curve.EaseOut
    }));
  }

  @Builder
  profileErrorCard() {
    Row({ space: 14 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: 58, height: 58 }).fill('#18E64646');
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(28)
          .fontColor(['#E64646']);
      }
      Column({ space: 3 }) {
        Text('账号资料加载失败')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY);
        Text(this.profileError)
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Row({ space: 5 }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(14)
            .fontColor([COLOR_PRIMARY]);
          Text('重新加载')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_PRIMARY);
        }
        .height(34)
        .padding({ left: 12, right: 12 })
        .margin({ top: 2 })
        .borderRadius(17)
        .stateStyles({
          normal: this.retryActionNormalStyle,
          pressed: this.retryActionPressedStyle
        });
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
    }
    .width('calc(100% - 24vp)')
    .height(118)
    .margin({ left: 12, right: 12 })
    .padding({ left: 16, right: 14 })
    .borderRadius(CARD_RADIUS)
    .alignItems(VerticalAlign.Center)
    .stateStyles({
      normal: this.accountRowNormalStyle,
      pressed: this.accountRowPressedStyle
    })
    .enabled(this.switchingSlotId === '' &&
      !this.accountNavigationLocked && this.openingSettingPage === '')
    .accessibilityText('账号资料加载失败，重新加载')
    .onClick((): void => { this.loadProfile(); })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 0.97, y: 0.97 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  activeAccountRow() {
    Row({ space: 14 }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        AvatarView({
          avatarPath: this.avatarPath, initials: this.initials,
          colorSeed: this.myId, avatarSize: 72,
          animPath: this.avatarAnimPath
        });
        Row() {
          SymbolGlyph($r('sys.symbol.pencil_line'))
            .fontSize(13)
            .fontColor([Color.White]);
        }
        .width(26).height(26).borderRadius(13)
        .backgroundColor(COLOR_PRIMARY)
        .border({ width: 2.5, color: CARD_BG })
        .justifyContent(FlexAlign.Center);
      }

      Column({ space: 4 }) {
        Row({ space: 5 }) {
          Text(this.name !== '' ? this.name : (this.profileLoading ? '正在加载账号…' : '当前账号'))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .flexShrink(1);
          if (!this.profileLoading && this.statusEmojiPath !== '') {
            if (this.statusEmojiFormat === 'tgs') {
              TgsStickerView({
                tgsPath: this.statusEmojiPath, boxWidth: 22, boxHeight: 22, powerCategory: 'emojiStatus'
              });
            } else if (this.statusEmojiFormat === 'webm') {
              WebmStickerView({
                webmPath: this.statusEmojiPath, boxWidth: 22, boxHeight: 22, powerCategory: 'emojiStatus'
              });
            } else {
              Image(`file://${this.statusEmojiPath}`).width(22).height(22).objectFit(ImageFit.Contain);
            }
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center);
        Text(this.profileError !== ''
          ? this.profileError
          : (this.subtitleLine() !== '' ? this.subtitleLine() : 'Telegram 账号'))
          .fontSize(13)
          .fontColor(this.profileError !== '' ? '#E64646' : COLOR_TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(this.profileError !== '' ? '点击重新加载' : '编辑个人资料')
          .fontSize(12)
          .fontColor(COLOR_PRIMARY);
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);

      if (this.profileLoading) {
        LoadingProgress().width(22).height(22).color(COLOR_PRIMARY);
      } else {
        SymbolGlyph(this.profileError !== ''
          ? $r('sys.symbol.arrow_clockwise')
          : $r('sys.symbol.chevron_right'))
          .fontSize(17)
          .fontColor([this.profileError !== '' ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY]);
      }
    }
    .width('calc(100% - 24vp)')
    .height(108)
    .margin({ left: 12, right: 12 })
    .padding({ left: 16, right: 14 })
    .borderRadius(CARD_RADIUS)
    .alignItems(VerticalAlign.Center)
    .stateStyles({
      normal: this.accountRowNormalStyle,
      pressed: this.accountRowPressedStyle
    })
    .enabled(this.switchingSlotId === '' &&
      !this.accountNavigationLocked && this.openingSettingPage === '')
    .accessibilityText(this.profileError !== ''
      ? '账号信息加载失败，点击重试'
      : `${this.name !== '' ? this.name : '当前账号'}，编辑个人资料`)
    .onClick((): void => { this.openAccountEditor(); });
  }

  @Builder
  accountRow(account: TdAccountSummary) {
    Row({ space: 12 }) {
      AvatarView({
        avatarPath: account.avatarPath,
        initials: this.accountInitials(account),
        colorSeed: account.userId !== 0 ? account.userId : account.slotId.length,
        avatarSize: 40
      });
      Column({ space: 2 }) {
        Text(account.name !== '' ? account.name : 'Telegram 账号')
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(this.accountSubtitle(account))
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
      if (this.switchingSlotId === account.slotId) {
        LoadingProgress().width(22).height(22).color(COLOR_PRIMARY);
      } else {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16).fontColor([COLOR_TEXT_SECONDARY]);
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .stateStyles({
      normal: this.accountRowNormalStyle,
      pressed: this.accountRowPressedStyle
    })
    .enabled(this.switchingSlotId === '' &&
      !this.accountNavigationLocked && this.openingSettingPage === '')
    .accessibilityText(`${account.name !== '' ? account.name : 'Telegram 账号'}，切换账号`)
    .onClick((): void => this.switchAccount(account.slotId));
  }

  @Builder
  accountActionErrorBanner() {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(21)
        .fontColor(['#E64646']);
      Column({ space: 2 }) {
        Text('账号操作未完成')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY);
        Text(this.accountActionError)
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
      Row({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(13)
          .fontColor([COLOR_PRIMARY]);
        Text('重试')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_PRIMARY);
      }
      .height(34)
      .padding({ left: 10, right: 10 })
      .borderRadius(17)
      .stateStyles({
        normal: this.retryActionNormalStyle,
        pressed: this.retryActionPressedStyle
      })
      .enabled(this.switchingSlotId === '')
      .accessibilityText('重试账号操作')
      .onClick((): void => { this.retryAccountAction(); });
      Row() {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(14)
          .fontColor([COLOR_TEXT_SECONDARY]);
      }
      .width(32)
      .height(32)
      .borderRadius(16)
      .justifyContent(FlexAlign.Center)
      .stateStyles({
        normal: this.topActionNormalStyle,
        pressed: this.topActionPressedStyle
      })
      .accessibilityText('关闭错误提示')
      .onClick((): void => { this.clearAccountActionError(); });
    }
    .width('calc(100% - 24vp)')
    .height(66)
    .margin({ left: 12, right: 12 })
    .padding({ left: 12, right: 8 })
    .backgroundColor('#10E64646')
    .border({ width: 0.7, color: '#30E64646' })
    .borderRadius(CARD_RADIUS)
    .alignItems(VerticalAlign.Center)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: -6 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  accountsCard() {
    Column({ space: 10 }) {
      if (this.profileLoading) {
        this.profileLoadingCard();
      } else if (this.profileError !== '') {
        this.profileErrorCard();
      } else {
        this.activeAccountRow();
      }

      Column() {
        if (this.otherAccounts().length > 0) {
          Text('切换账号')
            .width('100%')
            .height(34)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_PRIMARY)
            .padding({ left: 14, right: 14, top: 10 });
          ForEach(this.otherAccounts(), (account: TdAccountSummary, index: number): void => {
            if (index > 0) {
              Divider()
                .color(COLOR_DIVIDER)
                .strokeWidth(0.7)
                .margin({ left: 66, right: 14 });
            }
            this.accountRow(account);
          }, (account: TdAccountSummary): string =>
            `${account.slotId}_${account.userId}_${account.name}_${account.phone}_${account.username}_${account.avatarPath}`);
          Divider()
            .color(COLOR_DIVIDER)
            .strokeWidth(0.7)
            .margin({ left: 14, right: 14 });
        }

        Row({ space: 12 }) {
          Stack({ alignContent: Alignment.Center }) {
            SymbolGlyph($r('sys.symbol.plus')).fontSize(19).fontColor([Color.White]);
          }
          .width(40).height(40).borderRadius(20).backgroundColor(COLOR_PRIMARY);
          Column({ space: 2 }) {
            Text('添加账号').fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
            Text('登录另一个 Telegram 账号').fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1);
          if (this.switchingSlotId === 'new') {
            LoadingProgress().width(22).height(22).color(COLOR_PRIMARY);
          } else {
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16).fontColor([COLOR_TEXT_SECONDARY]);
          }
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 10, bottom: 12 })
        .alignItems(VerticalAlign.Center)
        .stateStyles({
          normal: this.accountRowNormalStyle,
          pressed: this.accountRowPressedStyle
        })
        .enabled(this.switchingSlotId === '' &&
          !this.accountNavigationLocked && this.openingSettingPage === '')
        .accessibilityText('添加账号')
        .onClick((): void => this.addAccount());
      }
      .width('calc(100% - 24vp)')
      .margin({ left: 12, right: 12 })
      .backgroundColor(CARD_BG)
      .borderRadius(CARD_RADIUS)
      .clip(true);

      if (this.accountActionError !== '') {
        this.accountActionErrorBanner();
      }
    }
    .width('100%')
    .margin({ top: 8, bottom: 12 })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 0.98, y: 0.98 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 200),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  settingsActionSheet() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 2 }) {
          Text('设置选项')
            .fontSize(21)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT_PRIMARY);
          Text(this.name !== '' ? `当前账号：${this.name}` : '当前 Telegram 账号')
            .fontSize(12)
            .fontColor(COLOR_TEXT_SECONDARY);
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1);
        Row() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(18)
            .fontColor([COLOR_TEXT_SECONDARY]);
        }
        .width(38)
        .height(38)
        .borderRadius(19)
        .justifyContent(FlexAlign.Center)
        .stateStyles({
          normal: this.topActionNormalStyle,
          pressed: this.topActionPressedStyle
        })
        .accessibilityText('关闭设置选项')
        .onClick((): void => { this.moreMenuOpen = false; });
      }
      .width('100%')
      .height(52)
      .alignItems(VerticalAlign.Center);

      Row({ space: 12 }) {
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.xmark_circle'))
            .fontSize(21)
            .fontColor(['#E64646']);
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor('#18E64646');
        Column({ space: 2 }) {
          Text('退出登录')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#E64646');
          Text('退出当前账号，不会删除云端消息')
            .fontSize(12)
            .fontColor(COLOR_TEXT_SECONDARY);
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1);
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor(['#E64646']);
      }
      .width('100%')
      .height(64)
      .padding({ left: 12, right: 12 })
      .borderRadius(14)
      .stateStyles({
        normal: this.dangerActionNormalStyle,
        pressed: this.dangerActionPressedStyle
      })
      .enabled(!this.logoutDialogOpen && this.switchingSlotId === '' &&
        !this.accountNavigationLocked && this.openingSettingPage === '')
      .accessibilityText('退出当前账号')
      .onClick((): void => { this.requestLogoutFromSheet(); });
    }
    .width('100%')
    .padding({
      left: 20,
      right: 20,
      top: 6,
      bottom: Math.max(18, this.bottomSafe + 10)
    })
    .backgroundColor(CARD_BG);
  }

  @Builder
  settingRow(item: SettingItem) {
    Row({ space: 14 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r(item.icon))
          .fontSize(18)
          .fontColor([Color.White])
          .scale({
            x: this.pressedSettingTitle === item.title ? 0.88 : 1,
            y: this.pressedSettingTitle === item.title ? 0.88 : 1
          })
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
            curve: Curve.EaseOut
          });
      }
      .width(34).height(34).borderRadius(9).backgroundColor(item.bg);
      Column({ space: 3 }) {
        Text(item.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(item.subtitle)
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
      if (this.openingSettingPage === item.title) {
        LoadingProgress().width(19).height(19).color(COLOR_PRIMARY);
      } else {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([COLOR_TEXT_SECONDARY])
          .translate({ x: this.pressedSettingTitle === item.title ? 2 : 0 })
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
            curve: Curve.EaseOut
          });
      }
    }
    .width('100%')
    .height(64)
    .padding({ left: 14, right: 14 })
    .alignItems(VerticalAlign.Center)
    .stateStyles({
      normal: this.settingRowNormalStyle,
      pressed: this.settingRowPressedStyle
    })
    .enabled(this.switchingSlotId === '' && this.openingSettingPage === '' &&
      !this.accountNavigationLocked)
    .accessibilityText(`${item.title}，${item.subtitle}`)
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down && this.openingSettingPage === '') {
        this.pressedSettingTitle = item.title;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        if (this.pressedSettingTitle === item.title) {
          this.pressedSettingTitle = '';
        }
      }
    })
    .onClick((): void => {
      this.pressedSettingTitle = '';
      this.openSetting(item);
    });
  }

  @Builder
  settingGroupCard(group: SettingGroup) {
    Column() {
      Text(group.title)
        .width('100%')
        .height(32)
        .padding({ left: 4, top: 8 })
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLOR_TEXT_SECONDARY);
      Column() {
        ForEach(group.items, (item: SettingItem, index: number): void => {
          if (index > 0) {
            Divider()
              .color(COLOR_DIVIDER)
              .strokeWidth(0.7)
              .margin({ left: 62, right: 14 });
          }
          this.settingRow(item);
        }, (item: SettingItem): string => `${group.title}_${item.title}`);
      }
      .width('100%')
      .backgroundColor(CARD_BG)
      .borderRadius(CARD_RADIUS)
      .clip(true);
    }
    .width('calc(100% - 24vp)')
    .margin({ left: 12, right: 12, bottom: 6 })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: 6 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  settingsCard() {
    Column() {
      if (this.filteredSettingGroups().length === 0) {
        Column({ space: 8 }) {
          Stack({ alignContent: Alignment.Center }) {
            Circle({ width: 52, height: 52 }).fill($r('app.color.surface_alt'));
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(25)
              .fontColor([COLOR_TEXT_SECONDARY]);
          }
          Text(`没有匹配“${this.settingsQuery.trim()}”的设置`)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_TEXT_PRIMARY);
          Text('可以搜索设置名称、说明或分组')
            .fontSize(12)
            .fontColor(COLOR_TEXT_SECONDARY);
          Row({ space: 5 }) {
            SymbolGlyph($r('sys.symbol.xmark_circle'))
              .fontSize(14)
              .fontColor([COLOR_PRIMARY]);
            Text('清除关键词')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(COLOR_PRIMARY);
          }
          .height(34)
          .padding({ left: 13, right: 13 })
          .margin({ top: 3 })
          .borderRadius(17)
          .stateStyles({
            normal: this.retryActionNormalStyle,
            pressed: this.retryActionPressedStyle
          })
          .accessibilityText('清除设置搜索关键词')
          .onClick((): void => { this.settingsQuery = ''; });
        }
        .width('calc(100% - 24vp)')
        .height(194)
        .margin({ left: 12, right: 12, top: 12 })
        .justifyContent(FlexAlign.Center)
        .backgroundColor(CARD_BG)
        .borderRadius(CARD_RADIUS)
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.97, y: 0.97 }))
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
            curve: Curve.EaseOut
          }));
      } else {
        ForEach(this.filteredSettingGroups(), (group: SettingGroup): void => {
          this.settingGroupCard(group);
        }, (group: SettingGroup): string =>
          `${group.title}_${this.settingsQuery.trim().toLowerCase()}`);
      }
    }
    .width('100%');
  }

  build() {
    Column() {
      this.topBar();
      Scroll() {
        Column() {
          if (!this.settingsSearchOpen) {
            this.accountsCard();
          }
          this.settingsCard();
        }
        .width('100%')
        .padding({ bottom: this.bottomSafe + 88 });
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off);
    }
    .width('100%').height('100%')
    .backgroundColor(PAGE_BG)
    .padding({ top: this.topSafe })
    .bindSheet($$this.moreMenuOpen, this.settingsActionSheet(), {
      height: SheetSize.FIT_CONTENT,
      backgroundColor: CARD_BG,
      dragBar: true
    });
  }
}
