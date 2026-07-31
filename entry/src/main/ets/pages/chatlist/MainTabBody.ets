import { router } from '@kit.ArkUI';
import { getChatStore } from '../../tdkit/Globals';
import { ChatEntry } from '../../store/ChatEntry';
import { ChatRow } from './ChatRow';
import { CHAT_MENU_OPEN, ChatListFreeze } from './ChatListFreeze';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

const ARCHIVE_ROW_HEIGHT: number = 56;

@Preview
@Component
export struct MainTabBody {
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  // Rebuilding rows while a row's context menu is open would close it.
  @StorageProp(CHAT_MENU_OPEN) @Watch('onMenuToggle') menuOpen: boolean = false;
  @State chats: ChatEntry[] = [];
  @State showArchive: boolean = false;
  @State refreshing: boolean = false;
  private updateGate: ChatListFreeze = new ChatListFreeze();
  private unsubscribe: (() => void) | null = null;
  private unsubArchive: (() => void) | null = null;

  private onMenuToggle(): void {
    if (this.menuOpen) {
      return;
    }
    const next = this.updateGate.flush();
    if (next !== null) {
      this.applyChats(next);
    }
  }

  aboutToAppear(): void {
    const store = getChatStore();
    this.unsubscribe = store.subscribe((list: ChatEntry[]) => {
      const next = this.updateGate.accept(list);
      if (next !== null) {
        this.applyChats(next);
      }
    }, 'main');
    this.showArchive = store.hasArchive();
    // The archive shortcut only needs an invalidation signal. Avoid sorting the
    // whole archive bucket for every update just to derive one boolean.
    this.unsubArchive = store.subscribeChanges(() => {
      this.showArchive = store.hasArchive();
    });
    store.ensureLoaded('main');
    store.ensureLoaded('archive');
  }

  aboutToDisappear(): void {
    if (this.unsubscribe !== null) { this.unsubscribe(); this.unsubscribe = null; }
    if (this.unsubArchive !== null) { this.unsubArchive(); this.unsubArchive = null; }
  }

  private applyChats(next: ChatEntry[]): void {
    const structureChanged = this.chats.length !== next.length ||
      this.chats.some((item: ChatEntry, index: number): boolean => item.id !== next[index]?.id);
    if (structureChanged && this.chats.length > 0) {
      animateTo({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }, (): void => { this.chats = next; });
    } else {
      this.chats = next;
    }
  }

  private rowKey(item: ChatEntry): string {
    const pinned = getChatStore().isPinned('main', item.id) ? 1 : 0;
    return `${item.id}_${item.revision}_${pinned}`;
  }

  private openArchive(): void {
    router.pushUrl({ url: 'pages/chatlist/ArchivePage' });
  }

  // Revealed only while the user over-scrolls (pulls down) at the top.
  @Builder
  archiveHeader() {
    Row() {
      SymbolGlyph($r('sys.symbol.archivebox')).fontSize(22).fontColor([COLOR_TEXT_SECONDARY]).margin({ right: 12 });
      Text('已归档的聊天').fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
    }
    .width('100%').height(ARCHIVE_ROW_HEIGHT).padding({ left: 14, right: 14 })
    .onClick(() => { this.openArchive(); });
  }

  @Builder
  chatList() {
    List() {
      ForEach(this.chats, (item: ChatEntry) => {
        ListItem() { ChatRow({ chat: item, listKey: 'main' }); }
      }, (item: ChatEntry) => this.rowKey(item));
    }
    .layoutWeight(1).width('100%')
    .cachedCount(8)
    .edgeEffect(EdgeEffect.Spring)
    .enableScrollInteraction(!this.menuOpen)
    .scrollBar(BarState.Off)
    .contentEndOffset(this.bottomSafe + 88)
    .onReachEnd(() => { getChatStore().loadMore('main'); });
  }

  build() {
    if (this.showArchive) {
      Refresh({ refreshing: $$this.refreshing, builder: this.archiveHeader() }) {
        this.chatList();
      }
      .layoutWeight(1).width('100%')
      .onRefreshing(() => {
        this.refreshing = false;
        this.openArchive();
      });
    } else {
      this.chatList();
    }
  }
}
