import { router, promptAction } from '@kit.ArkUI';
import {
  StorageUsage, formatBytes, getStorageUsage, clearCache,
  prepareAutosaveSettings, syncAutosaveSettings, applyCacheLimit
} from '../../store/StorageApi';
import {
  CACHE_LIMIT_OPTIONS, CACHE_LIMIT_UNLIMITED, CACHE_LIMIT_DEFAULT
} from '../../store/CacheLimit';
import {
  setBoolean, setNumber,
  KEY_CACHE_LIMIT, KEY_POWER_AUTOPLAY_VIDEO, KEY_POWER_AUTOPLAY_GIF, KEY_AUTOPLAY_MUTED,
  KEY_AUTOSAVE_PRIVATE, KEY_AUTOSAVE_GROUP, KEY_AUTOSAVE_CHANNEL
} from '../../store/AppSettings';
import { TdError } from '../../tdkit/TdTypes';
import {
  COLOR_DIVIDER, COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE,
  COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';

const CARD_RADIUS: number = 14;
const DANGER: string = '#E64646';

@Entry
@Component
struct CacheSettingsPage {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageProp(KEY_CACHE_LIMIT) cacheLimit: number = CACHE_LIMIT_DEFAULT;
  @StorageProp(KEY_POWER_AUTOPLAY_VIDEO) autoplayVideo: boolean = true;
  @StorageProp(KEY_POWER_AUTOPLAY_GIF) autoplayGif: boolean = true;
  @StorageProp(KEY_AUTOPLAY_MUTED) autoplayMuted: boolean = true;
  @State usage: StorageUsage | null = null;
  @State loading: boolean = true;
  @State clearing: boolean = false;
  @State autosavePrivate: boolean = false;
  @State autosaveGroup: boolean = false;
  @State autosaveChannel: boolean = false;
  @State syncing: boolean = false;
  @State warning: string = '';
  private active: boolean = false;
  private syncSequence: number = 0;
  private autosavePrepared: boolean = false;

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
    this.autosavePrivate = AppStorage.get<boolean>(KEY_AUTOSAVE_PRIVATE) ?? false;
    this.autosaveGroup = AppStorage.get<boolean>(KEY_AUTOSAVE_GROUP) ?? false;
    this.autosaveChannel = AppStorage.get<boolean>(KEY_AUTOSAVE_CHANNEL) ?? false;
    this.loadUsage();
    prepareAutosaveSettings().then((): void => {
      this.autosavePrepared = true;
    }).catch((error: TdError): void => {
      console.warn(`CacheSettingsPage.prepareAutosave failed: ${error.message}`);
      if (this.active) { this.warning = str('ms_album_sync_failed'); }
    });
  }

  aboutToDisappear(): void {
    this.active = false;
    this.syncSequence++;
  }

  private loadUsage(): void {
    this.loading = true;
    getStorageUsage().then((value: StorageUsage): void => {
      if (!this.active) { return; }
      this.usage = value;
      this.loading = false;
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.loading = false;
      console.error(`CacheSettingsPage.loadUsage failed: ${error.message}`);
    });
  }

  private confirmClear(): void {
    if (this.clearing) { return; }
    const before = this.usage !== null ? this.usage.filesSize : 0;
    promptAction.showDialog({
      title: $r('app.string.ds_clear_cache'),
      message: str('ds_clear_confirm', formatBytes(before)),
      buttons: [
        { text: $r('app.string.cancel'), color: COLOR_TEXT_SECONDARY as string },
        { text: $r('app.string.clear'), color: COLOR_PRIMARY as string }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (result.index !== 1 || this.clearing) { return; }
      this.clearing = true;
      clearCache().then((): void => {
        this.clearing = false;
        promptAction.showToast({ message: $r('app.string.storage_clear_done'), duration: 1500 });
        this.loadUsage();
      }).catch((error: TdError): void => {
        this.clearing = false;
        console.error(`CacheSettingsPage.clearCache failed: ${error.message}`);
        promptAction.showToast({ message: $r('app.string.clear_failed_retry'), duration: 1700 });
      });
    });
  }

  private selectLimit(value: number): void {
    if (this.cacheLimit === value) { return; }
    setNumber(KEY_CACHE_LIMIT, value);
    applyCacheLimit(value).catch((error: TdError): void => {
      if (this.active) { this.warning = str('ms_download_sync_failed'); }
      console.error(`CacheSettingsPage.applyCacheLimit failed: ${error.message}`);
    });
  }

  private setAutosave(scope: string, value: boolean): void {
    const key = scope === 'channel' ? KEY_AUTOSAVE_CHANNEL
      : (scope === 'group' ? KEY_AUTOSAVE_GROUP : KEY_AUTOSAVE_PRIVATE);
    setBoolean(key, value);
    if (scope === 'channel') { this.autosaveChannel = value; }
    else if (scope === 'group') { this.autosaveGroup = value; }
    else { this.autosavePrivate = value; }
    if (!this.autosavePrepared) { return; }
    const current = ++this.syncSequence;
    this.syncing = true;
    syncAutosaveSettings(scope, value).then((): void => {
      if (this.active && current === this.syncSequence) { this.syncing = false; }
    }).catch((error: TdError): void => {
      if (!this.active || current !== this.syncSequence) { return; }
      this.syncing = false;
      this.warning = str('ms_album_cloud_sync_failed');
      console.error(`CacheSettingsPage.syncAutosave failed: ${error.message}`);
    });
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Row() { SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(25).fontColor([COLOR_TEXT_PRIMARY]); }
      .width(44).height(44).borderRadius(22).justifyContent(FlexAlign.Center)
      .stateStyles({ normal: this.actionNormalStyle, pressed: this.actionPressedStyle })
      .onClick((): void => router.back());
      Text($r('app.string.ms_cache_title')).fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
      if (this.syncing) { LoadingProgress().width(18).height(18).color(COLOR_PRIMARY).margin({ right: 13 }); }
    }.width('100%').height(56).padding({ left: 8, right: 8 }).alignItems(VerticalAlign.Center);
  }

  @Builder
  usageCard() {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Text($r('app.string.storage_clearable')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
        Text(this.loading && this.usage === null ? '—' : formatBytes(this.usage !== null ? this.usage.filesSize : 0))
          .fontSize(28).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      Row() {
        if (this.clearing) {
          LoadingProgress().width(18).height(18).color(DANGER);
        } else {
          Text($r('app.string.ds_clear_cache')).fontSize(14).fontColor(DANGER);
        }
      }
      .padding({ left: 16, right: 16, top: 9, bottom: 9 }).backgroundColor($r('app.color.surface_alt'))
      .borderRadius(18).enabled(!this.clearing)
      .stateStyles({ normal: this.actionNormalStyle, pressed: this.actionPressedStyle })
      .onClick((): void => this.confirmClear());
    }.width('100%').padding(16).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  @Builder
  limitRow(value: number) {
    Row({ space: 10 }) {
      Text(value === CACHE_LIMIT_UNLIMITED ? str('ms_cache_unlimited') : formatBytes(value))
        .fontSize(15).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
      if (this.cacheLimit === value) {
        SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([COLOR_PRIMARY]);
      }
    }
    .width('100%').padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
    .onClick((): void => this.selectLimit(value));
  }

  @Builder
  limitCard() {
    Column() {
      Text(str('ms_cache_limit')).fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
        .width('100%').padding({ left: 14, right: 14, top: 12, bottom: 2 });
      Text(str('ms_cache_limit_sub')).fontSize(11).fontColor(COLOR_TEXT_SECONDARY)
        .width('100%').padding({ left: 14, right: 14, bottom: 6 });
      ForEach(CACHE_LIMIT_OPTIONS, (value: number, index: number) => {
        if (index > 0) { Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 }); }
        this.limitRow(value);
      }, (value: number): string => `${value}`);
    }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).clip(true);
  }

  @Builder
  toggleRow(title: string, subtitle: string, value: boolean, change: (next: boolean) => void) {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(title).fontSize(15).fontColor(COLOR_TEXT_PRIMARY);
        Text(subtitle).fontSize(11).fontColor(COLOR_TEXT_SECONDARY).maxLines(2);
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      Toggle({ type: ToggleType.Switch, isOn: value }).selectedColor(COLOR_PRIMARY)
        .onChange((next: boolean): void => change(next));
    }.width('100%').padding({ left: 14, right: 14, top: 10, bottom: 10 });
  }

  @Builder
  playbackCard() {
    Column() {
      this.toggleRow(str('power_autoplay_video'), '', this.autoplayVideo,
        (next: boolean): void => setBoolean(KEY_POWER_AUTOPLAY_VIDEO, next));
      if (this.autoplayVideo) {
        Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 });
        this.toggleRow(str('ms_autoplay_muted'), '', this.autoplayMuted,
          (next: boolean): void => setBoolean(KEY_AUTOPLAY_MUTED, next));
      }
      Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 });
      this.toggleRow(str('power_autoplay_gif'), '', this.autoplayGif,
        (next: boolean): void => setBoolean(KEY_POWER_AUTOPLAY_GIF, next));
    }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).clip(true);
  }

  @Builder
  autosaveCard() {
    Column() {
      this.toggleRow(str('ns_private'), str('ms_save_private_sub'), this.autosavePrivate,
        (next: boolean): void => this.setAutosave('private', next));
      Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 });
      this.toggleRow(str('gn_group'), str('ms_save_group_sub'), this.autosaveGroup,
        (next: boolean): void => this.setAutosave('group', next));
      Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 });
      this.toggleRow(str('gn_channel'), str('ms_save_channel_sub'), this.autosaveChannel,
        (next: boolean): void => this.setAutosave('channel', next));
    }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).clip(true);
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
          this.usageCard();
          this.limitCard();
          this.playbackCard();
          Text($r('app.string.ms_save_to_gallery')).fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
            .width('100%').padding({ left: 4, top: 4 });
          this.autosaveCard();
        }.width('100%').padding({ left: 12, right: 12, top: 6, bottom: this.bottomSafe + 24 });
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring);
    }.width('100%').height('100%').backgroundColor(COLOR_PAGE_BG)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .padding({ top: this.topSafe });
  }
}
