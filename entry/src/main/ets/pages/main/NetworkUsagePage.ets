import { router, promptAction } from '@kit.ArkUI';
import {
  NetworkUsage, NetworkBreakdown, formatBytes, formatDuration,
  getNetworkUsage, resetNetworkUsage
} from '../../store/StorageApi';
import { TdError } from '../../tdkit/TdTypes';
import {
  COLOR_DIVIDER, COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE,
  COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';

const CARD_RADIUS: number = 14;
const DANGER: string = '#E64646';

@Entry
@Component
struct NetworkUsagePage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State usage: NetworkUsage | null = null;
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State errorText: string = '';
  @State warning: string = '';
  @State resetting: boolean = false;
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

  aboutToAppear(): void { this.active = true; this.load(true); }
  aboutToDisappear(): void { this.active = false; this.sequence++; }

  private load(initial: boolean): void {
    const current = ++this.sequence;
    if (initial && this.usage === null) { this.loading = true; this.errorText = ''; }
    else { this.refreshing = true; this.warning = ''; }
    getNetworkUsage().then((value: NetworkUsage): void => {
      if (!this.active || current !== this.sequence) { return; }
      this.usage = value;
      this.loading = false;
      this.refreshing = false;
      this.errorText = '';
      this.warning = '';
    }).catch((error: TdError): void => {
      if (!this.active || current !== this.sequence) { return; }
      this.loading = false;
      this.refreshing = false;
      if (this.usage === null) { this.errorText = '无法读取流量统计'; }
      else { this.warning = '刷新失败，正在显示上次统计'; }
      console.error(`NetworkUsagePage.load failed: ${error.message}`);
    });
  }

  private sinceLabel(): string {
    if (this.usage === null || this.usage.sinceDate <= 0) { return '统计起始时间不可用'; }
    const date = new Date(this.usage.sinceDate * 1000);
    return `统计自 ${date.getFullYear()}-${date.getMonth() + 1}-${date.getDate()}`;
  }

  private reset(): void {
    if (this.resetting) { return; }
    promptAction.showDialog({
      title: '重置流量统计', message: '所有网络和媒体分类的上传、下载计数都会归零。',
      buttons: [
        { text: '取消', color: COLOR_TEXT_SECONDARY as string },
        { text: '重置', color: DANGER }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (result.index !== 1 || this.resetting) { return; }
      this.resetting = true;
      resetNetworkUsage().then((): void => {
        this.resetting = false;
        promptAction.showToast({ message: '流量统计已重置', duration: 1500 });
        this.load(false);
      }).catch((error: TdError): void => {
        this.resetting = false;
        console.error(`NetworkUsagePage.reset failed: ${error.message}`);
        promptAction.showToast({ message: '重置失败，请重试', duration: 1700 });
        this.load(false);
      });
    });
  }

  private maxTotal(items: NetworkBreakdown[]): number {
    let max = 1;
    for (const item of items) { max = Math.max(max, item.sent + item.received); }
    return max;
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Row() { SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(25).fontColor([COLOR_TEXT_PRIMARY]); }
      .width(44).height(44).borderRadius(22).justifyContent(FlexAlign.Center)
      .stateStyles({ normal: this.actionNormalStyle, pressed: this.actionPressedStyle })
      .onClick((): void => router.back());
      Text('流量使用情况').fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
      Row() {
        if (this.refreshing) { LoadingProgress().width(18).height(18).color(COLOR_PRIMARY); }
        else { SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(20).fontColor([COLOR_PRIMARY]); }
      }.width(44).height(44).borderRadius(22).justifyContent(FlexAlign.Center)
      .enabled(!this.loading && !this.refreshing && !this.resetting)
      .stateStyles({ normal: this.actionNormalStyle, pressed: this.actionPressedStyle })
      .onClick((): void => this.load(false));
    }.width('100%').height(56).padding({ left: 8, right: 8 }).alignItems(VerticalAlign.Center);
  }

  @Builder
  summaryCard() {
    Column({ space: 14 }) {
      Text(this.sinceLabel()).fontSize(12).fontColor(COLOR_TEXT_SECONDARY).width('100%');
      Row({ space: 10 }) {
        Column({ space: 3 }) {
          Text('已接收').fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          Text(this.usage !== null ? formatBytes(this.usage.received) : '—')
            .fontSize(23).fontWeight(FontWeight.Bold).fontColor(COLOR_PRIMARY);
        }.layoutWeight(1).alignItems(HorizontalAlign.Start);
        Divider().vertical(true).height(44).strokeWidth(0.5).color(COLOR_DIVIDER);
        Column({ space: 3 }) {
          Text('已发送').fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          Text(this.usage !== null ? formatBytes(this.usage.sent) : '—')
            .fontSize(23).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
        }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      }.width('100%');
      if (this.usage !== null && this.usage.callDuration > 0) {
        Row() {
          Text('累计通话').fontSize(13).fontColor(COLOR_TEXT_SECONDARY).layoutWeight(1);
          Text(formatDuration(this.usage.callDuration)).fontSize(13).fontColor(COLOR_TEXT_PRIMARY);
        }.width('100%');
      }
    }.width('100%').padding(16).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  @Builder
  breakdownRow(item: NetworkBreakdown, max: number) {
    Column({ space: 7 }) {
      Row() {
        Text(item.label).fontSize(15).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
        Text(formatBytes(item.sent + item.received)).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
      }.width('100%');
      Stack({ alignContent: Alignment.Start }) {
        Row().width('100%').height(6).borderRadius(3).backgroundColor($r('app.color.surface_alt'));
        Row().width(`${Math.max(2, Math.round(((item.sent + item.received) / max) * 100))}%`)
          .height(6).borderRadius(3).backgroundColor(COLOR_PRIMARY);
      }.width('100%').height(6);
      Row() {
        Text(`↓ ${formatBytes(item.received)}`).fontSize(11).fontColor(COLOR_PRIMARY);
        Text(`↑ ${formatBytes(item.sent)}`).fontSize(11).fontColor(COLOR_TEXT_SECONDARY)
          .margin({ left: 12 });
        Blank();
        if (item.duration > 0) {
          Text(formatDuration(item.duration)).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
        }
      }.width('100%');
    }.width('100%').padding({ left: 14, right: 14, top: 11, bottom: 11 });
  }

  @Builder
  breakdownCard(title: string, items: NetworkBreakdown[]) {
    Column() {
      Text(title).fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
        .width('100%').padding({ left: 14, right: 14, top: 12, bottom: 6 });
      ForEach(items, (item: NetworkBreakdown, index: number) => {
        if (index > 0) { Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 }); }
        this.breakdownRow(item, this.maxTotal(items));
      }, (item: NetworkBreakdown): string => item.key);
    }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  @Builder
  loadingState() {
    Column({ space: 11 }) {
      LoadingProgress().width(34).height(34).color(COLOR_PRIMARY);
      Text('正在汇总流量统计…').fontSize(15).fontColor(COLOR_TEXT_PRIMARY);
    }.width('100%').padding({ top: 72, bottom: 72 }).backgroundColor(COLOR_SURFACE)
      .borderRadius(CARD_RADIUS);
  }

  @Builder
  errorState() {
    Column({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(34).fontColor([DANGER]);
      Text('流量统计加载失败').fontSize(18).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
      Text(this.errorText).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      Text('重新加载').fontSize(14).fontColor(Color.White).padding({ left: 17, right: 17, top: 10, bottom: 10 })
        .backgroundColor(COLOR_PRIMARY).borderRadius(20).onClick((): void => this.load(true));
    }.width('100%').padding({ top: 54, bottom: 54 }).backgroundColor(COLOR_SURFACE)
      .borderRadius(CARD_RADIUS);
  }

  @Builder
  emptyState() {
    Column({ space: 9 }) {
      SymbolGlyph($r('sys.symbol.data_proportion')).fontSize(36).fontColor([COLOR_PRIMARY]);
      Text('还没有流量记录').fontSize(18).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
      Text('发送或接收消息后，分类统计会显示在这里。')
        .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center);
    }.width('100%').padding({ top: 52, bottom: 52 }).backgroundColor(COLOR_SURFACE)
      .borderRadius(CARD_RADIUS);
  }

  build() {
    Column() {
      this.header();
      Scroll() {
        Column({ space: 12 }) {
          if (this.warning !== '') {
            Text(this.warning).fontSize(12).fontColor('#FF9500').width('100%')
              .padding(10).backgroundColor('#12FF9500').borderRadius(10);
          }
          if (this.loading && this.usage === null) { this.loadingState(); }
          else if (this.errorText !== '' && this.usage === null) { this.errorState(); }
          else if (this.usage !== null && this.usage.sent + this.usage.received <= 0) {
            this.emptyState();
          } else if (this.usage !== null) {
            this.summaryCard();
            if (this.usage.byNetwork.length > 0) { this.breakdownCard('按网络', this.usage.byNetwork); }
            if (this.usage.byCategory.length > 0) { this.breakdownCard('按类型', this.usage.byCategory); }
          }
          Row({ space: 8 }) {
            if (this.resetting) { LoadingProgress().width(17).height(17).color(DANGER); }
            Text(this.resetting ? '正在重置…' : '重置流量统计')
              .fontSize(15).fontColor(DANGER).fontWeight(FontWeight.Medium);
          }.width('100%').height(46).justifyContent(FlexAlign.Center)
            .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
            .enabled(!this.resetting && !this.loading).onClick((): void => this.reset());
        }.width('100%').padding({ left: 12, right: 12, top: 6, bottom: this.bottomSafe + 24 });
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring);
    }.width('100%').height('100%').backgroundColor(COLOR_PAGE_BG)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .padding({ top: this.topSafe });
  }
}
