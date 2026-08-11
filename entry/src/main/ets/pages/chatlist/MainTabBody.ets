import { router } from '@kit.ArkUI';
import { getChatStore, getStoryStore } from '../../tdkit/Globals';
import { StoryRingEntry } from '../../store/StoryStore';
import { AvatarView } from './AvatarView';
import { ChatEntry } from '../../store/ChatEntry';
import { ChatRow } from './ChatRow';
import { CHAT_MENU_OPEN, ChatListFreeze } from './ChatListFreeze';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

const ARCHIVE_ROW_HEIGHT: number = 56;

@Preview
@Component
export struct MainTabBody {
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  // Set when the floating folder bar overlays this list (see ChatListView).
  @Prop reserveFolderBarSpace: boolean = false;
  // Rebuilding rows while a row's context menu is open would close it.
  @StorageProp(CHAT_MENU_OPEN) @Watch('onMenuToggle') menuOpen: boolean = false;
  @State chats: ChatEntry[] = [];
  @State showArchive: boolean = false;
  @State archiveLoadFailed: boolean = false;
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
    store.ensureLoaded('archive').then((success: boolean): void => {
      this.archiveLoadFailed = !success;
    });
    this.bindStories();
  }

  aboutToDisappear(): void {
    if (this.unsubscribe !== null) { this.unsubscribe(); this.unsubscribe = null; }
    if (this.unsubArchive !== null) { this.unsubArchive(); this.unsubArchive = null; }
    if (this.unsubStories !== null) { this.unsubStories(); this.unsubStories = null; }
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

  private retryArchive(): void {
    this.archiveLoadFailed = false;
    getChatStore().ensureLoaded('archive').then((success: boolean): void => {
      this.archiveLoadFailed = !success;
    });
  }

  // Revealed only while the user over-scrolls (pulls down) at the top.
  @Builder
  archiveHeader() {
    Row() {
      SymbolGlyph(this.archiveLoadFailed
        ? $r('sys.symbol.exclamationmark_circle') : $r('sys.symbol.archivebox'))
        .fontSize(22).fontColor([COLOR_TEXT_SECONDARY]).margin({ right: 12 });
      Text(this.archiveLoadFailed ? '归档加载失败，点击重试' : '已归档的聊天')
        .fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
    }
    .width('100%').height(ARCHIVE_ROW_HEIGHT).padding({ left: 14, right: 14 })
    .onClick(() => {
      if (this.archiveLoadFailed) { this.retryArchive(); } else { this.openArchive(); }
    });
  }

  // --- 故事环 ---
  @State storyEntries: StoryRingEntry[] = [];
  private unsubStories: (() => void) | null = null;

  private bindStories(): void {
    if (this.unsubStories !== null) {
      return;
    }
    this.unsubStories = getStoryStore().subscribe((entries: StoryRingEntry[]): void => {
      this.storyEntries = entries;
    });
  }

  private openStoryViewer(chatId: number): void {
    const params: Record<string, Object> = { 'chatId': chatId };
    router.pushUrl({ url: 'pages/story/StoryViewerPage', params }).catch((error: Error): void => {
      console.error(`MainTabBody.openStoryViewer failed: ${error.message}`);
    });
  }

  @Builder
  storyRing() {
    Scroll() {
      Row({ space: 14 }) {
        ForEach(this.storyEntries, (entry: StoryRingEntry) => {
          Column({ space: 4 }) {
            Stack() {
              // 未读：主色渐变环；已读：灰环。
              Circle({ width: 62, height: 62 })
                .fill(Color.Transparent)
                .stroke(entry.hasUnread ? COLOR_PRIMARY : '#4D8E8E93')
                .strokeWidth(2.5);
              AvatarView({
                avatarPath: getChatStore().entryOf(entry.chatId)?.avatarPath ?? '',
                initials: getChatStore().entryOf(entry.chatId)?.initials ?? '?',
                colorSeed: entry.chatId, avatarSize: 54
              });
            }
            .width(62).height(62);
            Text(getChatStore().entryOf(entry.chatId)?.title ?? '')
              .fontSize(11).fontColor(COLOR_TEXT_SECONDARY)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 64 });
          }
          .onClick((): void => this.openStoryViewer(entry.chatId));
        }, (entry: StoryRingEntry): string =>
          `story_${entry.chatId}_${entry.hasUnread}_${entry.storyIds.length}`);
      }
      .padding({ left: 14, right: 14, top: 6, bottom: 4 });
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%');
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
    .contentStartOffset(this.reserveFolderBarSpace ? 54 : 0)
    .onReachEnd(() => { getChatStore().loadMore('main'); });
  }

  build() {
    Column() {
    if (this.storyEntries.length > 0) {
      this.storyRing();
    }
    if (this.showArchive || this.archiveLoadFailed) {
      Refresh({ refreshing: $$this.refreshing, builder: this.archiveHeader() }) {
        this.chatList();
      }
      .layoutWeight(1).width('100%')
      // 停留/触发高度钉在归档行高，否则默认下拉区比一行高得多（"很高"）。
      .refreshOffset(ARCHIVE_ROW_HEIGHT)
      .pullToRefresh(true)
      .onRefreshing(() => {
        // 同步复位会被 Refresh 忽略（进入 Refreshing 当帧的状态写丢失），
        // 下拉区就永远收不回去；下一帧异步复位。
        setTimeout((): void => {
          this.refreshing = false;
        }, 60);
        if (this.archiveLoadFailed) { this.retryArchive(); } else { this.openArchive(); }
      });
    } else {
      this.chatList();
    }
    }
    .width('100%').layoutWeight(1);
  }
}
