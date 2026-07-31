import { getChatStore } from '../../tdkit/Globals';
import { ChatEntry } from '../../store/ChatEntry';
import { ChatRow } from './ChatRow';
import { CHAT_MENU_OPEN, ChatListFreeze } from './ChatListFreeze';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

@Component
export struct ChatListView {
  @Prop listKey: string;
  // Folder tabs sit behind MainScreen's floating dock; ArchivePage does not.
  @Prop reserveDockSpace: boolean = true;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  // Rebuilding rows while a row's context menu is open would close it.
  @StorageProp(CHAT_MENU_OPEN) @Watch('onMenuToggle') menuOpen: boolean = false;
  @State chats: ChatEntry[] = [];
  @State loading: boolean = true;
  @State loadFailed: boolean = false;
  @State paging: boolean = false;
  private updateGate: ChatListFreeze = new ChatListFreeze();
  private unsubscribe: (() => void) | null = null;

  aboutToAppear(): void {
    const store = getChatStore();
    this.unsubscribe = store.subscribe((list: ChatEntry[]) => {
      const next = this.updateGate.accept(list);
      if (next !== null) {
        this.applyChats(next);
      }
    }, this.listKey);
    this.loadInitial();
  }

  private loadInitial(): void {
    this.loading = true;
    this.loadFailed = false;
    getChatStore().ensureLoaded(this.listKey).then((success: boolean): void => {
      this.loading = false;
      this.loadFailed = !success;
    });
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
    const pinned = getChatStore().isPinned(this.listKey, item.id) ? 1 : 0;
    return `${item.id}_${item.revision}_${pinned}`;
  }

  private loadMore(): void {
    if (this.paging) {
      return;
    }
    this.paging = true;
    getChatStore().loadMore(this.listKey).then((): void => {
      this.paging = false;
    });
  }

  private endInset(): number {
    return this.bottomSafe + (this.reserveDockSpace ? 88 : 16);
  }

  private onMenuToggle(): void {
    if (this.menuOpen) {
      return;
    }
    const next = this.updateGate.flush();
    if (next !== null) {
      this.applyChats(next);
    }
  }

  aboutToDisappear(): void {
    if (this.unsubscribe !== null) {
      this.unsubscribe();
      this.unsubscribe = null;
    }
  }

  @Builder
  emptyState() {
    Column({ space: 10 }) {
      if (this.loading) {
        LoadingProgress().width(28).height(28).color(COLOR_PRIMARY);
        Text('正在加载聊天…').fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
      } else {
        Row() {
          SymbolGlyph($r('sys.symbol.message')).fontSize(27).fontColor([COLOR_TEXT_SECONDARY]);
        }
        .width(56).height(56).borderRadius(28)
        .backgroundColor($r('app.color.surface_alt'))
        .justifyContent(FlexAlign.Center);
        Text(this.listKey === 'archive' ? '暂无归档聊天' : '这个文件夹还没有聊天')
          .fontSize(17).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
        if (this.loadFailed) {
          Text('加载失败，点击重试')
            .fontSize(14).fontColor(COLOR_PRIMARY)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .onClick((): void => { this.loadInitial(); });
        } else if (this.listKey !== 'archive') {
          Text('可以从聊天的长按菜单中添加')
            .fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
        }
      }
    }
    .layoutWeight(1).width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ bottom: this.endInset() })
    .transition(TransitionEffect.OPACITY.animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160),
      curve: Curve.EaseOut
    }));
  }

  build() {
    if (this.chats.length === 0) {
      this.emptyState();
    } else {
      List() {
        ForEach(this.chats, (item: ChatEntry) => {
          ListItem() {
            ChatRow({ chat: item, listKey: this.listKey });
          }
        }, (item: ChatEntry) => this.rowKey(item));
        if (this.paging) {
          ListItem() {
            Row() {
              LoadingProgress().width(22).height(22).color(COLOR_PRIMARY);
            }.width('100%').height(44).justifyContent(FlexAlign.Center);
          }
        }
      }
      .layoutWeight(1).width('100%')
      .cachedCount(8)
      .edgeEffect(EdgeEffect.Spring)
      // Stop touch scrolling as soon as the long-press menu begins to appear.
      // This prevents residual spring/inertia from shifting the source row
      // while ArkUI captures its floating preview.
      .enableScrollInteraction(!this.menuOpen)
      .scrollBar(BarState.Off)
      .contentEndOffset(this.endInset())
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .onReachEnd(() => { this.loadMore(); });
    }
  }
}
