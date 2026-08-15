import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { getTdClient, getUnreadCountStore, getCallSession } from '../../tdkit/Globals';
import { CallSnapshot } from '../../services/CallSession';
import { callKeepAliveTask } from '../../services/CallKeepAliveTask';
import { bindAccentPrimary } from '../../util/accentTheme';
import { ProfileStore } from '../../store/ProfileStore';
import { AvatarView } from '../chatlist/AvatarView';
import { ChatListPage } from '../chatlist/ChatListPage';
import { ContactsPage } from './ContactsPage';
import { SettingsPage } from './SettingsPage';
import { MyProfilePage } from './MyProfilePage';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { COLOR_DIVIDER, COLOR_PRIMARY, COLOR_TAB_PILL_BG, COLOR_TAB_UNSELECTED } from '../../util/theme';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { updateChecker, STORAGE_UPDATE_AVAILABLE } from '../../services/UpdateChecker';
import { str } from '../../util/strings';

// Translucent tint over a backdrop blur — the frosted-glass dock material.
const DOCK_BG: ResourceColor = $r('app.color.dock_glass');
const BADGE_BG: string = '#4CD964';
const DOCK_H: number = 64;      // capsule height
const DOCK_GAP: number = 12;    // gap below the capsule (above it: content padding)
const DOCK_ITEM_INSET: number = 5;
const DOCK_SWITCH_DURATION: number = 240;

// Root screen after login: a floating capsule dock (聊天/联系人/设置/个人资料)
// over four keep-alive tab bodies. The dock is a rounded pill that hovers above
// full-screen content; content reserves bottom space so nothing hides behind it.
// Tabs use scrollable(false) so swiping never fights ChatListPage's inner folder
// Tabs — only dock taps switch tabs.
@Component
export struct MainScreen {
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageProp(STORAGE_UPDATE_AVAILABLE) updateAvailable: boolean = false;
  // 回前台补偿：后台期间的来电 push 可能被系统拒绝，前台一刻重查一次。
  @StorageProp('appIsForeground') @Watch('onAppForegroundChanged') appIsForeground: boolean = true;
  @State tab: number = 0;
  @State unread: number = 0;
  @State myId: number = 0;
  @State meAvatar: string = '';
  @State meInitials: string = '?';
  @State dockWidth: number = 0;
  private controller: TabsController = new TabsController();
  private store: ProfileStore | null = null;
  private unsubStore: (() => void) | null = null;
  private unsubUnread: (() => void) | null = null;
  private unsubAccent: (() => void) | null = null;
  private unsubCall: (() => void) | null = null;
  private callPagePushed: boolean = false;

  aboutToAppear(): void {
    // 已登录才查更新（MainScreen 只在登录后渲染），内部按 6 小时节流。
    updateChecker.check(false).catch((): void => {});
    // 来电（应用存活时）：常驻订阅通话状态，响铃即弹入通话页。
    this.unsubCall = getCallSession().subscribe((s: CallSnapshot): void => {
      // 通话期保活：接通流程开始挂 voip 长时任务，结束即释放。
      if (s.phase === 'connecting' || s.phase === 'active') {
        callKeepAliveTask.start(getContext(this) as common.UIAbilityContext);
      } else if (s.phase === 'ended' || s.phase === 'idle') {
        callKeepAliveTask.stop();
      }
      if (s.phase === 'ringing' && !s.isOutgoing) {
        if (this.callPagePushed) {
          return;
        }
        this.callPagePushed = true;
        router.pushUrl({ url: 'pages/call/CallPage' }).catch((error: Error): void => {
          console.error(`MainScreen incoming call navigation failed: ${error.message}`);
        });
      } else if (s.phase === 'idle' || s.phase === 'ended') {
        this.callPagePushed = false;
      }
    });
    this.unsubAccent = bindAccentPrimary(getContext(this) as common.UIAbilityContext);
    this.unread = getUnreadCountStore().getUnread('main');
    this.unsubUnread = getUnreadCountStore().subscribe(() => {
      this.unread = getUnreadCountStore().getUnread('main');
    });
    const req: TdRequest = { '@type': 'getMe' };
    getTdClient().send(req).then((me: TdObject) => {
      this.myId = (me['id'] as number | undefined) ?? 0;
      if (this.myId === 0) {
        return;
      }
      const store = new ProfileStore(getTdClient(), this.myId);
      this.store = store;
      this.unsubStore = store.subscribe(() => {
        this.meAvatar = store.avatarPath;
        this.meInitials = store.initials;
      });
      store.open();
    }).catch((e: TdError) => {
      console.error(`MainScreen.getMe failed: ${e.message}`);
    });
  }

  aboutToDisappear(): void {
    if (this.unsubAccent !== null) { this.unsubAccent(); this.unsubAccent = null; }
    if (this.unsubUnread !== null) { this.unsubUnread(); this.unsubUnread = null; }
    if (this.unsubStore !== null) { this.unsubStore(); this.unsubStore = null; }
    if (this.unsubCall !== null) { this.unsubCall(); this.unsubCall = null; }
    if (this.store !== null) { this.store.close(); this.store = null; }
  }

  onAppForegroundChanged(): void {
    if (!this.appIsForeground) {
      return;
    }
    const s = getCallSession().current();
    if (s.phase === 'ringing' && !s.isOutgoing && !this.callPagePushed) {
      this.callPagePushed = true;
      router.pushUrl({ url: 'pages/call/CallPage' }).catch((error: Error): void => {
        this.callPagePushed = false;
        console.error(`MainScreen foreground call check failed: ${error.message}`);
      });
    }
  }

  private select(index: number): void {
    if (index === this.tab) {
      return;
    }
    animateTo({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, DOCK_SWITCH_DURATION),
      curve: Curve.EaseOut
    }, (): void => { this.tab = index; });
    this.controller.changeIndex(index);
  }

  private dockItemWidth(): number {
    return this.dockWidth > 0 ? this.dockWidth / 4 : 0;
  }

  @Styles
  dockItemNormalStyle() {
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  dockItemPressedStyle() {
    .opacity(0.72)
    .scale({ x: 0.92, y: 0.92 })
  }

  @Builder
  dockItem(index: number, icon: string, label: string) {
    Column({ space: 2 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        SymbolGlyph($r(icon)).fontSize(24)
          .fontColor([this.tab === index ? COLOR_PRIMARY : COLOR_TAB_UNSELECTED])
          .scale({
            x: this.tab === index ? 1.06 : 1,
            y: this.tab === index ? 1.06 : 1
          })
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
            curve: Curve.EaseOut
        });
        // 设置页签的红点：和「关于」那一行是同一个信号，一路引到更新入口。
        if (index === 2 && this.updateAvailable) {
          Circle({ width: 8, height: 8 }).fill(BADGE_BG).offset({ x: 6, y: -2 });
        }
        if (index === 0 && this.unread > 0) {
          Row() {
            Text(this.unread > 99 ? '99+' : `${this.unread}`)
              .fontSize(10).fontColor(Color.White).fontWeight(FontWeight.Medium);
          }
            .constraintSize({ minWidth: 18 }).height(18)
            .padding({ left: 5, right: 5 })
            .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
            .backgroundColor(BADGE_BG).borderRadius(9)
            .offset({ x: 12, y: -7 });
        }
      }
      Text(label).fontSize(10)
        .fontColor(this.tab === index ? COLOR_PRIMARY : COLOR_TAB_UNSELECTED);
    }
    .layoutWeight(1).height('100%')
    .justifyContent(FlexAlign.Center)
    .borderRadius((DOCK_H - DOCK_ITEM_INSET * 2) / 2)
    .stateStyles({
      normal: this.dockItemNormalStyle,
      pressed: this.dockItemPressedStyle
    })
    .accessibilityText(index === 0 && this.unread > 0
      ? str('a11y_tab_unread', label, this.unread, this.tab === index ? str('a11y_selected') : '')
      : str('a11y_option_state', label, this.tab === index ? str('a11y_selected') : ''))
    .onClick(() => { this.select(index); });
  }

  @Builder
  profileDockItem() {
    Column({ space: 2 }) {
      Stack() {
        AvatarView({ avatarPath: this.meAvatar, initials: this.meInitials, colorSeed: this.myId, avatarSize: 24 });
      }
      .width(32).height(32).borderRadius(16).padding(2)
      // A constant border width avoids a size jump when this tab is selected.
      .border({ width: 2, color: this.tab === 3 ? COLOR_PRIMARY : Color.Transparent });
      Text($r('app.string.tab_profile')).fontSize(10)
        .fontColor(this.tab === 3 ? COLOR_PRIMARY : COLOR_TAB_UNSELECTED);
    }
    .layoutWeight(1).height('100%')
    .justifyContent(FlexAlign.Center)
    .borderRadius((DOCK_H - DOCK_ITEM_INSET * 2) / 2)
    .stateStyles({
      normal: this.dockItemNormalStyle,
      pressed: this.dockItemPressedStyle
    })
    .accessibilityText(str('a11y_option_state', str('tab_profile'), this.tab === 3 ? str('a11y_selected') : ''))
    .onClick(() => { this.select(3); });
  }

  // Floating capsule: outer Column carries the horizontal padding + bottom
  // margin (width('100%') + horizontal margin conflict on the same node in
  // ArkUI), inner Row is the pill itself.
  @Builder
  dock() {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.dockWidth > 0) {
          Row()
            .width(Math.max(0, this.dockItemWidth() - DOCK_ITEM_INSET * 2))
            .height(DOCK_H - DOCK_ITEM_INSET * 2)
            .backgroundColor(COLOR_TAB_PILL_BG)
            .borderRadius((DOCK_H - DOCK_ITEM_INSET * 2) / 2)
            .position({
              x: this.tab * this.dockItemWidth() + DOCK_ITEM_INSET,
              y: DOCK_ITEM_INSET
            })
            .animation({
              duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, DOCK_SWITCH_DURATION),
              curve: Curve.EaseOut
            })
            .hitTestBehavior(HitTestMode.None);
        }
        Row() {
          this.dockItem(0, 'sys.symbol.message', str('tab_chats'));
          this.dockItem(1, 'sys.symbol.person_2', str('tab_contacts'));
          this.dockItem(2, 'sys.symbol.gearshape', str('settings_title'));
          this.profileDockItem();
        }
        .width('100%').height('100%')
        .alignItems(VerticalAlign.Center);
      }
      .width('100%').height(DOCK_H)
      .backgroundColor(DOCK_BG)
      // backdropBlur over a light tint: COMPONENT_* material styles carry an
      // opaque built-in backboard that reads as solid gray, so blur the
      // backdrop directly instead.
      .backdropBlur(22)
      .borderRadius(DOCK_H / 2)
      .clip(true)
      .border({ width: 0.5, color: COLOR_DIVIDER })
      .shadow({ radius: 14, color: '#24000000', offsetX: 0, offsetY: 4 })
      .onAreaChange((_old: Area, area: Area) => {
        this.dockWidth = area.width as number;
      });
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .margin({ bottom: this.bottomSafe + DOCK_GAP });
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Tabs({ controller: this.controller }) {
        TabContent() { ChatListPage(); }
        TabContent() { ContactsPage(); }
        TabContent() { SettingsPage(); }
        TabContent() {
          MyProfilePage({
            active: this.tab === 3,
            onOpenSettings: (): void => { this.select(2); }
          });
        }
      }
      .barHeight(0)
      .scrollable(false)
      .animationDuration(powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, DOCK_SWITCH_DURATION))
      .onAnimationStart((_currentIndex: number, targetIndex: number) => {
        if (this.tab !== targetIndex) {
          animateTo({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, DOCK_SWITCH_DURATION),
            curve: Curve.EaseOut
          }, (): void => { this.tab = targetIndex; });
        }
      })
      .onChange((index: number) => {
        // Keep the dock synced if Tabs changes its final index after a rapid
        // sequence of taps.
        if (this.tab !== index) {
          this.tab = index;
        }
      })
      .width('100%').height('100%');

      this.dock();
    }
    .width('100%').height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}
