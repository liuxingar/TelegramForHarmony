import { getChatStore } from '../../tdkit/Globals';
import { ChatEntry } from '../../store/ChatEntry';
import { ChatRow } from './ChatRow';
import { CHAT_MENU_OPEN, ChatListFreeze } from './ChatListFreeze';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';

@Component
export struct ChatListView {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @Prop listKey: string;
  // Folder tabs sit behind MainScreen's floating dock; ArchivePage does not.
  @Prop reserveDockSpace: boolean = true;
  // Floating frosted folder bar overlays the list top — start content below
  // it while still letting rows scroll (blurred) underneath.
  @Prop reserveFolderBarSpace: boolean = false;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  // Rebuilding rows while a row's context menu is open would close it.
  @StorageProp(CHAT_MENU_OPEN) @Watch('onMenuToggle') menuOpen: boolean = false;
  @State chats: ChatEntry[] = [];
  @State loading: boolean = true;
  @State loadFailed: boolean = false;
  @State paging: boolean = false;
  @State pagingFailed: boolean = false;
  private updateGate: ChatListFreeze = new ChatListFreeze();
  private unsubscribe: (() => void) | null = null;
  private active: boolean = false;

  @Styles
  actionNormalStyle() {
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  actionPressedStyle() {
    .opacity(0.72)
    .scale({ x: 0.96, y: 0.96 })
  }

  aboutToAppear(): void {
    this.active = true;
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
    const store = getChatStore();
    store.ensureLoaded(this.listKey).then((success: boolean): void => {
      if (!this.active) { return; }
      // TDLib normally emits the positions before resolving loadChats. Read
      // the bucket once here as well so the empty state can't flash while the
      // coalesced store notification is still waiting for the next frame.
      const next = this.updateGate.accept(store.getChats(this.listKey));
      if (next !== null) { this.applyChats(next); }
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

  // langEpoch in the key: see MainTabBody.rowKey.
  private rowKey(item: ChatEntry): string {
    const pinned = getChatStore().isPinned(this.listKey, item.id) ? 1 : 0;
    return `${item.id}_${item.revision}_${pinned}_${this.langEpoch}`;
  }

  private loadMore(): void {
    const store = getChatStore();
    if (this.paging || store.isListExhausted(this.listKey)) {
      return;
    }
    this.paging = true;
    this.pagingFailed = false;
    store.loadMore(this.listKey).then((success: boolean): void => {
      if (!this.active) { return; }
      this.paging = false;
      this.pagingFailed = !success;
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
    this.active = false;
    if (this.unsubscribe !== null) {
      this.unsubscribe();
      this.unsubscribe = null;
    }
  }

  @Builder
  emptyState() {
    Column({ space: 10 }) {
      if (this.loading) {
        Stack({ alignContent: Alignment.Center }) {
          Circle({ width: 58, height: 58 }).fill($r('app.color.surface_alt'));
          LoadingProgress().width(28).height(28).color(COLOR_PRIMARY);
        }
        Text(this.listKey === 'archive' ? $r('app.string.cl_syncing_archive') : $r('app.string.cl_loading_chats'))
          .fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
        Text($r('app.string.cl_content_appears'))
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
      } else if (this.loadFailed) {
        Row() {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
            .fontSize(28).fontColor([COLOR_PRIMARY]);
        }
        .width(58).height(58).borderRadius(29)
        .backgroundColor($r('app.color.surface_alt'))
        .justifyContent(FlexAlign.Center);
        Text(this.listKey === 'archive' ? $r('app.string.cl_archive_failed') : $r('app.string.cl_chats_failed'))
          .fontSize(17).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
        Text($r('app.string.cl_check_network'))
          .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center);
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(14).fontColor([Color.White]);
          Text($r('app.string.settings_reload')).fontSize(14).fontWeight(FontWeight.Medium).fontColor(Color.White);
        }
        .height(38).padding({ left: 15, right: 16 }).borderRadius(19)
        .backgroundColor(COLOR_PRIMARY)
        .stateStyles({ normal: this.actionNormalStyle, pressed: this.actionPressedStyle })
        .onClick((): void => this.loadInitial());
      } else {
        Row() {
          SymbolGlyph(this.listKey === 'archive'
            ? $r('sys.symbol.archivebox') : $r('sys.symbol.message'))
            .fontSize(27).fontColor([COLOR_TEXT_SECONDARY]);
        }
        .width(56).height(56).borderRadius(28)
        .backgroundColor($r('app.color.surface_alt'))
        .justifyContent(FlexAlign.Center);
        Text(this.listKey === 'archive' ? $r('app.string.cl_no_archived') : $r('app.string.cl_folder_empty'))
          .fontSize(17).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
        if (this.listKey === 'archive') {
          Text($r('app.string.cl_archive_hint'))
            .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center);
        } else {
          Text($r('app.string.cl_add_hint'))
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
        if (this.loadFailed) {
          ListItem() {
            Row({ space: 7 }) {
              SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
                .fontSize(14).fontColor([COLOR_PRIMARY]);
              Text($r('app.string.cl_archive_sync_failed'))
                .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).layoutWeight(1);
              Text($r('app.string.settings_retry')).fontSize(12).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY);
            }
            .height(40).padding({ left: 14, right: 14 })
            .backgroundColor($r('app.color.surface_alt'))
            .onClick((): void => this.loadInitial());
          }
        }
        ForEach(this.chats, (item: ChatEntry) => {
          ListItem() {
            ChatRow({ chat: item, listKey: this.listKey });
          }
          .transition(
            TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: 12 })).animation({
              duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
              curve: Curve.EaseOut
            })
          )
        }, (item: ChatEntry) => this.rowKey(item));
        if (this.paging) {
          ListItem() {
            Row() {
              LoadingProgress().width(22).height(22).color(COLOR_PRIMARY);
            }.width('100%').height(44).justifyContent(FlexAlign.Center);
          }
        } else if (this.pagingFailed) {
          ListItem() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(13).fontColor([COLOR_PRIMARY]);
              Text($r('app.string.load_more_failed')).fontSize(12).fontColor(COLOR_PRIMARY);
            }
            .width('100%').height(44).justifyContent(FlexAlign.Center)
            .stateStyles({ normal: this.actionNormalStyle, pressed: this.actionPressedStyle })
            .onClick((): void => this.loadMore());
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
      .contentStartOffset(this.reserveFolderBarSpace ? 54 : 0)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .onReachEnd(() => { this.loadMore(); });
    }
  }
}
