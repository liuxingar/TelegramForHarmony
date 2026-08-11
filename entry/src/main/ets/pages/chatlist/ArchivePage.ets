import { router } from '@kit.ArkUI';
import { ChatListView } from './ChatListView';
import { CHAT_LIST_NOW } from './ChatListFreeze';
import { ChatEntry } from '../../store/ChatEntry';
import { getChatStore, getUnreadCountStore } from '../../tdkit/Globals';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

@Entry
@Preview
@Component
struct ArchivePage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @State archivedCount: number = 0;
  @State unreadCount: number = 0;
  private clockTimer: number = -1;
  private unsubscribeChats: (() => void) | null = null;
  private unsubscribeUnread: (() => void) | null = null;

  @Styles
  backNormalStyle() {
    .backgroundColor(Color.Transparent)
  }

  @Styles
  backPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
  }

  aboutToAppear(): void {
    this.unsubscribeChats = getChatStore().subscribe((chats: ChatEntry[]): void => {
      this.archivedCount = chats.length;
    }, 'archive');
    this.unsubscribeUnread = getUnreadCountStore().subscribe((): void => {
      this.unreadCount = getUnreadCountStore().getUnread('archive');
    });
    AppStorage.setOrCreate(CHAT_LIST_NOW, Math.floor(Date.now() / 1000));
    this.clockTimer = setInterval((): void => {
      AppStorage.setOrCreate(CHAT_LIST_NOW, Math.floor(Date.now() / 1000));
    }, 60000);
  }

  aboutToDisappear(): void {
    if (this.unsubscribeChats !== null) {
      this.unsubscribeChats();
      this.unsubscribeChats = null;
    }
    if (this.unsubscribeUnread !== null) {
      this.unsubscribeUnread();
      this.unsubscribeUnread = null;
    }
    if (this.clockTimer !== -1) {
      clearInterval(this.clockTimer);
      this.clockTimer = -1;
    }
  }

  private archiveSummary(): string {
    if (this.archivedCount === 0) { return '与首页分开整理暂时不看的聊天'; }
    if (this.unreadCount > 0) {
      return `${this.archivedCount} 个聊天 · ${this.unreadCount} 个未读`;
    }
    return `${this.archivedCount} 个聊天`;
  }

  build() {
    Column() {
      Row() {
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([COLOR_TEXT_PRIMARY]);
        }
        .width(44).height(44).borderRadius(22)
        .justifyContent(FlexAlign.Center)
        .stateStyles({
          normal: this.backNormalStyle,
          pressed: this.backPressedStyle
        })
        .onClick(() => { router.back(); });
        Column({ space: 1 }) {
          Text('已归档的聊天')
            .fontSize(20).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
          Text(this.archiveSummary())
            .fontSize(11).fontColor(this.unreadCount > 0 ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start).margin({ left: 4 });
      }
      .width('100%').height(this.topSafe + 62)
      .padding({ left: 6, right: 16, top: this.topSafe })
      .backgroundColor($r('app.color.surface'))
      .border({ width: { bottom: 0.5 }, color: $r('app.color.divider') });
      ChatListView({ listKey: 'archive', reserveDockSpace: false });
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}
