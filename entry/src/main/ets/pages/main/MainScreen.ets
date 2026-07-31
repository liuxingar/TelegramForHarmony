import { getTdClient, getUnreadCountStore } from '../../tdkit/Globals';
import { ProfileStore } from '../../store/ProfileStore';
import { AvatarView } from '../chatlist/AvatarView';
import { ChatListPage } from '../chatlist/ChatListPage';
import { ContactsPage } from './ContactsPage';
import { SettingsPage } from './SettingsPage';
import { MyProfilePage } from './MyProfilePage';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { COLOR_DIVIDER, COLOR_PRIMARY, COLOR_TAB_PILL_BG, COLOR_TAB_UNSELECTED } from '../../util/theme';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';

const DOCK_BG: ResourceColor = $r('app.color.surface');
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

  aboutToAppear(): void {
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
    if (this.unsubUnread !== null) { this.unsubUnread(); this.unsubUnread = null; }
    if (this.unsubStore !== null) { this.unsubStore(); this.unsubStore = null; }
    if (this.store !== null) { this.store.close(); this.store = null; }
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
      ? `${label}，${this.unread} 个未读${this.tab === index ? '，已选中' : ''}`
      : `${label}${this.tab === index ? '，已选中' : ''}`)
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
      Text('个人资料').fontSize(10)
        .fontColor(this.tab === 3 ? COLOR_PRIMARY : COLOR_TAB_UNSELECTED);
    }
    .layoutWeight(1).height('100%')
    .justifyContent(FlexAlign.Center)
    .borderRadius((DOCK_H - DOCK_ITEM_INSET * 2) / 2)
    .stateStyles({
      normal: this.dockItemNormalStyle,
      pressed: this.dockItemPressedStyle
    })
    .accessibilityText(`个人资料${this.tab === 3 ? '，已选中' : ''}`)
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
          this.dockItem(0, 'sys.symbol.message', '聊天');
          this.dockItem(1, 'sys.symbol.person_2', '联系人');
          this.dockItem(2, 'sys.symbol.gearshape', '设置');
          this.profileDockItem();
        }
        .width('100%').height('100%')
        .alignItems(VerticalAlign.Center);
      }
      .width('100%').height(DOCK_H)
      .backgroundColor(DOCK_BG)
      .borderRadius(DOCK_H / 2)
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
