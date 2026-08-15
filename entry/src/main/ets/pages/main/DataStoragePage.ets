import { router, promptAction } from '@kit.ArkUI';
import { TdError } from '../../tdkit/TdTypes';
import {
  StorageUsage, NetworkUsage, formatBytes, getStorageUsage, clearCache,
  getNetworkUsage, resetNetworkUsage, clearAllDrafts
} from '../../store/StorageApi';
import {
  KEY_CURRENT_NETWORK_TYPE, KEY_AUTOSAVE_PRIVATE, KEY_AUTOSAVE_GROUP,
  KEY_AUTOSAVE_CHANNEL, autoDownloadPolicy, powerAnimationDuration,
  KEY_POWER_SMOOTH_TRANSITIONS
} from '../../store/AppSettings';
import {
  COLOR_DIVIDER, COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE,
  COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { plural, str } from '../../util/strings';
import { fullDate } from '../../util/intlFormat';

const CARD_RADIUS: number = 14;
const DANGER: string = '#E64646';
const SKELETON_ROWS: number[] = [0, 1, 2];

@Entry
@Component
struct DataStoragePage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageProp(KEY_CURRENT_NETWORK_TYPE) networkType: string = 'other';
  @StorageProp(KEY_AUTOSAVE_PRIVATE) autosavePrivate: boolean = false;
  @StorageProp(KEY_AUTOSAVE_GROUP) autosaveGroup: boolean = false;
  @StorageProp(KEY_AUTOSAVE_CHANNEL) autosaveChannel: boolean = false;
  @State storage: StorageUsage | null = null;
  @State network: NetworkUsage | null = null;
  @State storageLoading: boolean = true;
  @State networkLoading: boolean = true;
  @State storageError: string = '';
  @State networkError: string = '';
  @State syncWarning: string = '';
  @State actionKey: string = '';
  @State skeletonBright: boolean = false;
  private active: boolean = false;
  private loadSequence: number = 0;
  private lastLoadAt: number = 0;
  private skeletonTimer: number = -1;

  @Styles
  actionNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  actionPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.76)
    .scale({ x: 0.94, y: 0.94 })
  }

  @Styles
  rowNormalStyle() {
    .backgroundColor(COLOR_SURFACE)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  rowPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .scale({ x: 0.99, y: 0.99 })
  }

  aboutToAppear(): void {
    this.active = true;
    this.load(true);
  }

  onPageShow(): void {
    if (Date.now() - this.lastLoadAt > 1200) { this.load(false); }
  }

  aboutToDisappear(): void {
    this.active = false;
    this.loadSequence++;
    this.stopSkeleton();
  }

  private animationDuration(value: number): number {
    return powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, value);
  }

  private startSkeleton(): void {
    if (this.skeletonTimer !== -1 || this.animationDuration(1) === 0) { return; }
    this.skeletonTimer = setInterval((): void => {
      this.skeletonBright = !this.skeletonBright;
    }, 680);
  }

  private stopSkeleton(): void {
    if (this.skeletonTimer !== -1) {
      clearInterval(this.skeletonTimer);
      this.skeletonTimer = -1;
    }
    this.skeletonBright = false;
  }

  private load(initial: boolean): void {
    const sequence = ++this.loadSequence;
    this.lastLoadAt = Date.now();
    if (initial && this.storage === null && this.network === null) { this.startSkeleton(); }
    this.storageLoading = true;
    this.networkLoading = true;
    this.syncWarning = '';
    getStorageUsage().then((value: StorageUsage): void => {
      if (!this.active || sequence !== this.loadSequence) { return; }
      this.storage = value;
      this.storageLoading = false;
      this.storageError = '';
      if (!this.networkLoading) { this.stopSkeleton(); }
    }).catch((error: TdError): void => {
      if (!this.active || sequence !== this.loadSequence) { return; }
      this.storageLoading = false;
      this.storageError = this.storage === null ? str('ds_storage_load_failed') : '';
      if (this.storage !== null) { this.syncWarning = str('ds_partial_sync'); }
      if (!this.networkLoading) { this.stopSkeleton(); }
      console.error(`DataStoragePage.getStorageUsage failed: ${error.message}`);
    });
    getNetworkUsage().then((value: NetworkUsage): void => {
      if (!this.active || sequence !== this.loadSequence) { return; }
      this.network = value;
      this.networkLoading = false;
      this.networkError = '';
      if (!this.storageLoading) { this.stopSkeleton(); }
    }).catch((error: TdError): void => {
      if (!this.active || sequence !== this.loadSequence) { return; }
      this.networkLoading = false;
      this.networkError = this.network === null ? str('network_load_failed') : '';
      if (this.network !== null) { this.syncWarning = str('ds_partial_sync'); }
      if (!this.storageLoading) { this.stopSkeleton(); }
      console.error(`DataStoragePage.getNetworkUsage failed: ${error.message}`);
    });
  }

  private networkLabel(): string {
    if (this.networkType === 'wifi') { return 'Wi‑Fi'; }
    if (this.networkType === 'mobile') { return str('network_mobile'); }
    if (this.networkType === 'roaming') { return str('network_roaming'); }
    if (this.networkType === 'none') { return str('ds_no_network'); }
    return str('network_other');
  }

  private autoDownloadSummary(): string {
    const current = autoDownloadPolicy();
    const enabled: string[] = [];
    if (current.photos) { enabled.push(str('storage_photo')); }
    if (current.videos) { enabled.push(str('storage_video')); }
    if (current.files) { enabled.push(str('storage_file')); }
    return str('ds_network_and_kinds', this.networkLabel(), enabled.length > 0 ? enabled.join(str('list_separator')) : str('ds_off'));
  }

  private autosaveSummary(): string {
    const enabled: string[] = [];
    if (this.autosavePrivate) { enabled.push(str('ns_private')); }
    if (this.autosaveGroup) { enabled.push(str('gn_group')); }
    if (this.autosaveChannel) { enabled.push(str('gn_channel')); }
    return enabled.length > 0 ? enabled.join('、') : str('ds_off');
  }

  private sinceLabel(): string {
    if (this.network === null || this.network.sinceDate <= 0) { return str('ds_since_unknown'); }
    const date = new Date(this.network.sinceDate * 1000);
    return str('ds_since', fullDate(date));
  }

  private confirmAction(key: string, title: ResourceStr, message: ResourceStr, button: ResourceStr,
    color: string, operation: () => Promise<void>, success: ResourceStr): void {
    if (this.actionKey !== '') { return; }
    promptAction.showDialog({
      title, message,
      buttons: [
        { text: $r('app.string.cancel'), color: COLOR_TEXT_SECONDARY as string },
        { text: button, color }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (result.index !== 1 || this.actionKey !== '') { return; }
      this.actionKey = key;
      operation().then((): void => {
        this.actionKey = '';
        promptAction.showToast({ message: success, duration: 1800 });
        this.load(false);
      }).catch((error: TdError): void => {
        this.actionKey = '';
        console.error(`DataStoragePage.${key} failed: ${error.message}`);
        promptAction.showToast({ message: $r('app.string.action_failed_retry'), duration: 1800 });
        this.load(false);
      });
    });
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(25).fontColor([COLOR_TEXT_PRIMARY]);
      }
      .width(44).height(44).borderRadius(22).justifyContent(FlexAlign.Center)
      .stateStyles({ normal: this.actionNormalStyle, pressed: this.actionPressedStyle })
      .accessibilityText($r('app.string.back_to_settings')).onClick((): void => router.back());
      Column({ space: 1 }) {
        Text($r('app.string.settings_data')).fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
        if (this.storageLoading || this.networkLoading) {
          Text($r('app.string.ds_syncing')).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      Row() {
        if (this.storageLoading || this.networkLoading) {
          LoadingProgress().width(18).height(18).color(COLOR_PRIMARY);
        } else {
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(20).fontColor([COLOR_PRIMARY]);
        }
      }
      .width(44).height(44).borderRadius(22).justifyContent(FlexAlign.Center)
      .enabled(!this.storageLoading && !this.networkLoading)
      .stateStyles({ normal: this.actionNormalStyle, pressed: this.actionPressedStyle })
      .accessibilityText($r('app.string.ds_refresh')).onClick((): void => this.load(false));
    }
    .width('100%').height(56).padding({ left: 8, right: 8 }).alignItems(VerticalAlign.Center);
  }

  @Builder
  skeletonCard() {
    Column({ space: 13 }) {
      Row().width('42%').height(14).borderRadius(7).backgroundColor($r('app.color.surface_alt'));
      Row().width('68%').height(28).borderRadius(8).backgroundColor($r('app.color.surface_alt'));
      ForEach(SKELETON_ROWS, (index: number) => {
        Row({ space: 10 }) {
          Circle({ width: 34, height: 34 }).fill($r('app.color.surface_alt'));
          Column({ space: 5 }) {
            Row().width(index === 1 ? '48%' : '62%').height(11).borderRadius(6)
              .backgroundColor($r('app.color.surface_alt'));
            Row().width(index === 1 ? '70%' : '52%').height(9).borderRadius(5)
              .backgroundColor($r('app.color.surface_alt'));
          }.layoutWeight(1).alignItems(HorizontalAlign.Start);
        }.width('100%');
      }, (index: number): string => `${index}`);
    }
    .width('100%').padding(16).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
    .opacity(this.skeletonBright ? 0.55 : 0.94)
    .animation({ duration: this.animationDuration(640), curve: Curve.EaseInOut });
  }

  @Builder
  overviewCard() {
    Column({ space: 14 }) {
      Row() {
        Column({ space: 3 }) {
          Text($r('app.string.ds_local_usage')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          Text(this.storage !== null ? formatBytes(this.storage.totalSize) : '—')
            .fontSize(30).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
        }.layoutWeight(1).alignItems(HorizontalAlign.Start);
        Stack({ alignContent: Alignment.Center }) {
          Circle({ width: 58, height: 58 }).fill('#163478F6');
          SymbolGlyph($r('sys.symbol.folder_fill')).fontSize(27).fontColor([COLOR_PRIMARY]);
        }
      }.width('100%');
      if (this.storage !== null) {
        Row({ space: 4 }) {
          Row().height(6).layoutWeight(Math.max(1, this.storage.filesSize))
            .borderRadius(3).backgroundColor(COLOR_PRIMARY);
          Row().height(6).layoutWeight(Math.max(1, this.storage.databaseSize))
            .borderRadius(3).backgroundColor('#8E8E93');
          Row().height(6).layoutWeight(Math.max(1,
            this.storage.languagePackDatabaseSize + this.storage.logSize))
            .borderRadius(3).backgroundColor('#C7C7CC');
        }.width('100%');
        Row() {
          Text(str('ds_media_size', formatBytes(this.storage.filesSize))).fontSize(11).fontColor(COLOR_PRIMARY);
          Blank();
          Text(str('ds_database_size', formatBytes(this.storage.databaseSize))).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
        }.width('100%');
      }
    }
    .width('100%').padding(16).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
    .transition(TransitionEffect.OPACITY.animation({ duration: this.animationDuration(180) }));
  }

  @Builder
  navRow(icon: Resource, title: ResourceStr, subtitle: ResourceStr, value: ResourceStr, page: string) {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: 38, height: 38 }).fill('#163478F6');
        SymbolGlyph(icon).fontSize(20).fontColor([COLOR_PRIMARY]);
      }
      Column({ space: 2 }) {
        Text(title).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
        Text(subtitle).fontSize(12).fontColor(COLOR_TEXT_SECONDARY).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      if (value !== '') { Text(value).fontSize(13).fontColor(COLOR_TEXT_SECONDARY); }
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(15).fontColor([COLOR_TEXT_SECONDARY]);
    }
    .width('100%').height(64).padding({ left: 12, right: 12 })
    .stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
    .onClick((): void => { router.pushUrl({ url: page }); });
  }

  @Builder
  statsCard() {
    Column() {
      this.navRow($r('sys.symbol.folder_fill'), $r('app.string.storage_title'),
        this.storageError !== '' ? this.storageError :
          (this.storage !== null ? plural('ds_cached_files', this.storage.fileCount, this.storage.fileCount) : $r('app.string.ds_awaiting_stats')),
        this.storage !== null ? formatBytes(this.storage.filesSize) : '—',
        'pages/main/StorageUsagePage');
      Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 62 });
      this.navRow($r('sys.symbol.data_proportion'), $r('app.string.network_title'),
        this.networkError !== '' ? this.networkError : this.sinceLabel(),
        this.network !== null ? formatBytes(this.network.sent + this.network.received) : '—',
        'pages/main/NetworkUsagePage');
    }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).clip(true);
  }

  @Builder
  mediaCard() {
    Column() {
      this.navRow($r('sys.symbol.arrow_down_circle'), $r('app.string.ds_auto_download'), this.autoDownloadSummary(), '',
        'pages/main/MediaStorageSettingsPage');
      Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 62 });
      this.navRow($r('sys.symbol.camera'), $r('app.string.ms_save_to_gallery'), this.autosaveSummary(), '',
        'pages/main/MediaStorageSettingsPage');
    }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).clip(true);
  }

  @Builder
  actionRow(title: ResourceStr, subtitle: ResourceStr, key: string, danger: boolean,
    action: () => void) {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(title).fontSize(16).fontColor(danger ? DANGER : COLOR_TEXT_PRIMARY);
        Text(subtitle).fontSize(12).fontColor(COLOR_TEXT_SECONDARY).maxLines(2);
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      if (this.actionKey === key) {
        LoadingProgress().width(19).height(19).color(danger ? DANGER : COLOR_PRIMARY);
      }
    }
    .width('100%').padding({ left: 14, right: 14, top: 11, bottom: 11 })
    .enabled(this.actionKey === '')
    .stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
    .onClick(action);
  }

  @Builder
  actionsCard() {
    Column() {
      this.actionRow($r('app.string.ds_clear_cache'), $r('app.string.ds_clear_cache_sub'), 'cache', false, (): void => {
        const before = this.storage !== null ? this.storage.filesSize : 0;
        this.confirmAction('cache', $r('app.string.ds_clear_cache'),
          str('ds_clear_confirm', formatBytes(before)),
          $r('app.string.clear'), COLOR_PRIMARY as string,
          (): Promise<void> => clearCache().then((): void => {}), $r('app.string.storage_clear_done'));
      });
      Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 });
      this.actionRow($r('app.string.network_reset'), $r('app.string.ds_reset_sub'), 'network', false, (): void => {
        this.confirmAction('network', $r('app.string.network_reset'), $r('app.string.ds_reset_confirm'),
          $r('app.string.reset'), COLOR_PRIMARY as string, resetNetworkUsage, $r('app.string.network_reset_done'));
      });
      Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 });
      this.actionRow($r('app.string.ds_clear_drafts'), $r('app.string.ds_clear_drafts_sub'), 'drafts', true, (): void => {
        this.confirmAction('drafts', $r('app.string.ds_clear_drafts'),
          $r('app.string.ds_clear_drafts_confirm'),
          $r('app.string.clear_all'), DANGER, clearAllDrafts, $r('app.string.ds_drafts_cleared'));
      });
    }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).clip(true);
  }

  @Builder
  warningCard() {
    if (this.syncWarning !== '') {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(17).fontColor(['#FF9500']);
        Text(this.syncWarning).fontSize(12).fontColor(COLOR_TEXT_SECONDARY).layoutWeight(1);
        Text($r('app.string.settings_retry')).fontSize(12).fontColor(COLOR_PRIMARY).onClick((): void => this.load(false));
      }.width('100%').padding(11).backgroundColor('#12FF9500').borderRadius(11);
    }
  }

  build() {
    Column() {
      this.header();
      Scroll() {
        Column({ space: 12 }) {
          this.warningCard();
          if (this.storage === null && this.network === null &&
            (this.storageLoading || this.networkLoading)) {
            this.skeletonCard();
          } else {
            this.overviewCard();
            this.statsCard();
          }
          this.mediaCard();
          this.actionsCard();
          Text($r('app.string.ds_note'))
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).width('100%')
            .padding({ left: 14, right: 14, top: 1 });
        }.width('100%').padding({ left: 12, right: 12, top: 6, bottom: this.bottomSafe + 24 });
      }
      .layoutWeight(1).width('100%').align(Alignment.Top)
      .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring);
    }
    .width('100%').height('100%').backgroundColor(COLOR_PAGE_BG)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.topSafe });
  }
}
