import { router, promptAction } from '@kit.ArkUI';
import {
  DetailedStorageUsage, StorageCategory, ChatStorageUsage, formatBytes,
  getDetailedStorageUsage, clearCacheSelection
} from '../../store/StorageApi';
import { getChatStore } from '../../tdkit/Globals';
import { ChatEntry } from '../../store/ChatEntry';
import { TdError } from '../../tdkit/TdTypes';
import {
  COLOR_DIVIDER, COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE,
  COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';

const CARD_RADIUS: number = 14;
const DANGER: string = '#E64646';

@Entry
@Component
struct StorageUsagePage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State usage: DetailedStorageUsage | null = null;
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State loadError: string = '';
  @State syncWarning: string = '';
  @State actionKey: string = '';
  private active: boolean = false;
  private sequence: number = 0;

  @Styles
  actionNormalStyle() {
    .backgroundColor(Color.Transparent).opacity(1).scale({ x: 1, y: 1 })
  }

  @Styles
  actionPressedStyle() {
    .backgroundColor($r('app.color.surface_alt')).opacity(0.74).scale({ x: 0.94, y: 0.94 })
  }

  @Styles
  rowNormalStyle() {
    .backgroundColor(COLOR_SURFACE).scale({ x: 1, y: 1 })
  }

  @Styles
  rowPressedStyle() {
    .backgroundColor($r('app.color.surface_alt')).scale({ x: 0.99, y: 0.99 })
  }

  aboutToAppear(): void {
    this.active = true;
    this.load(true);
  }

  aboutToDisappear(): void {
    this.active = false;
    this.sequence++;
  }

  private duration(value: number): number {
    return powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, value);
  }

  private load(initial: boolean): void {
    const current = ++this.sequence;
    if (initial && this.usage === null) { this.loading = true; this.loadError = ''; }
    else { this.refreshing = true; this.syncWarning = ''; }
    getDetailedStorageUsage(30).then((value: DetailedStorageUsage): void => {
      if (!this.active || current !== this.sequence) { return; }
      this.usage = value;
      this.loading = false;
      this.refreshing = false;
      this.loadError = '';
      this.syncWarning = '';
    }).catch((error: TdError): void => {
      if (!this.active || current !== this.sequence) { return; }
      this.loading = false;
      this.refreshing = false;
      if (this.usage === null) { this.loadError = '无法读取详细存储统计'; }
      else { this.syncWarning = '刷新失败，当前显示的是上次统计'; }
      console.error(`StorageUsagePage.load failed: ${error.message}`);
    });
  }

  private titleOf(chatId: number): string {
    if (chatId === 0) { return '其他会话'; }
    const entry: ChatEntry | undefined = getChatStore().entryOf(chatId);
    return entry !== undefined && entry.title !== '' ? entry.title : '未命名会话';
  }

  private initialsOf(chatId: number): string {
    if (chatId === 0) { return '其'; }
    const entry: ChatEntry | undefined = getChatStore().entryOf(chatId);
    return entry !== undefined ? entry.initials : '?';
  }

  private share(size: number): number {
    const total = this.usage !== null ? this.usage.size : 0;
    return total > 0 ? Math.max(0.02, Math.min(1, size / total)) : 0;
  }

  private confirmClear(key: string, title: string, message: string,
    category: string, chatId: number): void {
    if (this.actionKey !== '') { return; }
    promptAction.showDialog({
      title, message,
      buttons: [
        { text: '取消', color: COLOR_TEXT_SECONDARY as string },
        { text: '清理', color: DANGER }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (result.index !== 1 || this.actionKey !== '') { return; }
      this.actionKey = key;
      clearCacheSelection(category, chatId).then((): void => {
        this.actionKey = '';
        promptAction.showToast({ message: '缓存清理完成', duration: 1500 });
        this.load(false);
      }).catch((error: TdError): void => {
        this.actionKey = '';
        console.error(`StorageUsagePage.clear failed: ${error.message}`);
        promptAction.showToast({ message: '清理失败，请重试', duration: 1700 });
      });
    });
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(25).fontColor([COLOR_TEXT_PRIMARY]);
      }.width(44).height(44).borderRadius(22).justifyContent(FlexAlign.Center)
      .stateStyles({ normal: this.actionNormalStyle, pressed: this.actionPressedStyle })
      .onClick((): void => router.back());
      Text('存储使用情况').fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
      Row() {
        if (this.refreshing) { LoadingProgress().width(18).height(18).color(COLOR_PRIMARY); }
        else { SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(20).fontColor([COLOR_PRIMARY]); }
      }.width(44).height(44).borderRadius(22).justifyContent(FlexAlign.Center)
      .enabled(!this.loading && !this.refreshing && this.actionKey === '')
      .stateStyles({ normal: this.actionNormalStyle, pressed: this.actionPressedStyle })
      .onClick((): void => this.load(false));
    }.width('100%').height(56).padding({ left: 8, right: 8 }).alignItems(VerticalAlign.Center);
  }

  @Builder
  loadingState() {
    Column({ space: 12 }) {
      LoadingProgress().width(34).height(34).color(COLOR_PRIMARY);
      Text('正在分析媒体缓存…').fontSize(15).fontColor(COLOR_TEXT_PRIMARY);
      Text('详细统计会比首页概览稍慢').fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
    }.width('100%').padding({ top: 72, bottom: 72 }).backgroundColor(COLOR_SURFACE)
      .borderRadius(CARD_RADIUS);
  }

  @Builder
  errorState() {
    Column({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(34).fontColor([DANGER]);
      Text('详细统计加载失败').fontSize(18).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
      Text(this.loadError).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      Text('重新加载').fontSize(14).fontColor(Color.White).padding({ left: 17, right: 17, top: 10, bottom: 10 })
        .backgroundColor(COLOR_PRIMARY).borderRadius(20).onClick((): void => this.load(true));
    }.width('100%').padding({ top: 54, bottom: 54 }).backgroundColor(COLOR_SURFACE)
      .borderRadius(CARD_RADIUS);
  }

  @Builder
  summaryCard() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 3 }) {
          Text('可清理媒体').fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          Text(this.usage !== null ? formatBytes(this.usage.size) : '—')
            .fontSize(30).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
        }.layoutWeight(1).alignItems(HorizontalAlign.Start);
        Text(this.usage !== null ? `${this.usage.count} 个文件` : '')
          .fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      }.width('100%');
      Text('分类统计为精确结果；清理后云端消息和文件仍然保留。')
        .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).width('100%');
    }.width('100%').padding(16).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  @Builder
  categoryRow(item: StorageCategory) {
    Column({ space: 7 }) {
      Row() {
        Text(item.label).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
        if (this.actionKey === `category_${item.key}`) {
          LoadingProgress().width(17).height(17).color(COLOR_PRIMARY).margin({ right: 10 });
        }
        Text(formatBytes(item.size)).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
        Text('清理').fontSize(13).fontColor(COLOR_PRIMARY).margin({ left: 12 });
      }.width('100%');
      Stack({ alignContent: Alignment.Start }) {
        Row().width('100%').height(5).borderRadius(3).backgroundColor($r('app.color.surface_alt'));
        Row().width(`${Math.round(this.share(item.size) * 100)}%`).height(5).borderRadius(3)
          .backgroundColor(COLOR_PRIMARY);
      }.width('100%').height(5);
      Text(`${item.count} 个文件`).fontSize(11).fontColor(COLOR_TEXT_SECONDARY).width('100%');
    }
    .width('100%').padding({ left: 14, right: 14, top: 11, bottom: 11 })
    .enabled(this.actionKey === '')
    .stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
    .onClick((): void => this.confirmClear(`category_${item.key}`, `清理${item.label}缓存`,
      `将删除 ${formatBytes(item.size)} 的${item.label}缓存，需要时可以重新下载。`, item.key, 0));
  }

  @Builder
  categoriesCard() {
    Column() {
      Text('按类型').fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
        .width('100%').padding({ left: 14, right: 14, top: 12, bottom: 6 });
      if (this.usage !== null) {
        ForEach(this.usage.categories, (item: StorageCategory, index: number) => {
          if (index > 0) { Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 }); }
          this.categoryRow(item);
        }, (item: StorageCategory): string => item.key);
      }
    }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).clip(true);
  }

  @Builder
  chatRow(item: ChatStorageUsage) {
    Row({ space: 11 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: 40, height: 40 }).fill('#173478F6');
        Text(this.initialsOf(item.chatId)).fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY);
      }
      Column({ space: 3 }) {
        Text(this.titleOf(item.chatId)).fontSize(15).fontColor(COLOR_TEXT_PRIMARY).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(`${item.count} 个文件`).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      if (this.actionKey === `chat_${item.chatId}`) {
        LoadingProgress().width(17).height(17).color(COLOR_PRIMARY);
      } else {
        Text(formatBytes(item.size)).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      }
    }
    .width('100%').height(62).padding({ left: 12, right: 14 })
    .enabled(this.actionKey === '' && item.chatId !== 0)
    .opacity(item.chatId === 0 ? 0.72 : 1)
    .stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
    .onClick((): void => {
      if (item.chatId !== 0) {
        this.confirmClear(`chat_${item.chatId}`, `清理“${this.titleOf(item.chatId)}”缓存`,
          `将删除此会话中的 ${formatBytes(item.size)} 媒体缓存。`, '', item.chatId);
      }
    });
  }

  @Builder
  chatsCard() {
    Column() {
      Text('按会话').fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
        .width('100%').padding({ left: 14, right: 14, top: 12, bottom: 6 });
      if (this.usage !== null) {
        ForEach(this.usage.chats, (item: ChatStorageUsage, index: number) => {
          if (index > 0) { Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 62 }); }
          this.chatRow(item);
        }, (item: ChatStorageUsage): string => `${item.chatId}`);
      }
    }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).clip(true);
  }

  @Builder
  emptyState() {
    Column({ space: 9 }) {
      SymbolGlyph($r('sys.symbol.checkmark_circle')).fontSize(38).fontColor([COLOR_PRIMARY]);
      Text('暂无可清理缓存').fontSize(18).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
      Text('浏览图片、视频和文件后，占用会显示在这里。')
        .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center);
    }.width('100%').padding({ top: 52, bottom: 52 }).backgroundColor(COLOR_SURFACE)
      .borderRadius(CARD_RADIUS);
  }

  build() {
    Column() {
      this.header();
      Scroll() {
        Column({ space: 12 }) {
          if (this.syncWarning !== '') {
            Text(this.syncWarning).fontSize(12).fontColor('#FF9500').width('100%')
              .padding(10).backgroundColor('#12FF9500').borderRadius(10);
          }
          if (this.loading && this.usage === null) { this.loadingState(); }
          else if (this.loadError !== '' && this.usage === null) { this.errorState(); }
          else if (this.usage !== null && this.usage.size <= 0) { this.emptyState(); }
          else if (this.usage !== null) {
            this.summaryCard();
            if (this.usage.categories.length > 0) { this.categoriesCard(); }
            if (this.usage.chats.length > 0) { this.chatsCard(); }
          }
        }.width('100%').padding({ left: 12, right: 12, top: 6, bottom: this.bottomSafe + 24 });
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring);
    }.width('100%').height('100%').backgroundColor(COLOR_PAGE_BG)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .padding({ top: this.topSafe });
  }
}
