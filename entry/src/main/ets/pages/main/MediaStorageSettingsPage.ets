import { router } from '@kit.ArkUI';
import {
  AutoDownloadPolicy, autoDownloadPolicy, setBoolean, setNumber,
  KEY_AUTO_WIFI_PHOTO, KEY_AUTO_WIFI_VIDEO, KEY_AUTO_WIFI_FILE,
  KEY_AUTO_WIFI_VIDEO_LIMIT, KEY_AUTO_WIFI_FILE_LIMIT, KEY_AUTO_WIFI_PRELOAD_VIDEO,
  KEY_AUTO_WIFI_NEXT_AUDIO, KEY_AUTO_WIFI_STORIES,
  KEY_AUTO_MOBILE_PHOTO, KEY_AUTO_MOBILE_VIDEO, KEY_AUTO_MOBILE_FILE,
  KEY_AUTO_MOBILE_VIDEO_LIMIT, KEY_AUTO_MOBILE_FILE_LIMIT, KEY_AUTO_MOBILE_PRELOAD_VIDEO,
  KEY_AUTO_MOBILE_NEXT_AUDIO, KEY_AUTO_MOBILE_STORIES,
  KEY_AUTO_ROAMING_PHOTO, KEY_AUTO_ROAMING_VIDEO, KEY_AUTO_ROAMING_FILE,
  KEY_AUTO_ROAMING_VIDEO_LIMIT, KEY_AUTO_ROAMING_FILE_LIMIT, KEY_AUTO_ROAMING_PRELOAD_VIDEO,
  KEY_AUTO_ROAMING_NEXT_AUDIO, KEY_AUTO_ROAMING_STORIES,
  KEY_AUTO_LESS_DATA_CALLS, KEY_AUTOSAVE_PRIVATE, KEY_AUTOSAVE_GROUP, KEY_AUTOSAVE_CHANNEL
} from '../../store/AppSettings';
import {
  syncAutoDownloadSettings, prepareAutosaveSettings, syncAutosaveSettings, formatBytes
} from '../../store/StorageApi';
import { TdError } from '../../tdkit/TdTypes';
import {
  COLOR_DIVIDER, COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE,
  COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';

const CARD_RADIUS: number = 14;
const LIMITS: number[] = [512 * 1024, 2 * 1024 * 1024, 10 * 1024 * 1024,
  32 * 1024 * 1024, 64 * 1024 * 1024, 128 * 1024 * 1024, 512 * 1024 * 1024];

interface NetworkOption {
  key: string;
  label: string;
}

const NETWORKS: NetworkOption[] = [
  { key: 'wifi', label: 'Wi‑Fi' },
  { key: 'mobile', label: str('network_mobile') },
  { key: 'roaming', label: str('network_roaming') }
];

@Entry
@Component
struct MediaStorageSettingsPage {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State selectedNetwork: string = 'wifi';
  @State photos: boolean = true;
  @State videos: boolean = true;
  @State files: boolean = true;
  @State videoLimit: number = 64 * 1024 * 1024;
  @State fileLimit: number = 32 * 1024 * 1024;
  @State preloadVideo: boolean = true;
  @State nextAudio: boolean = true;
  @State stories: boolean = true;
  @State lessDataCalls: boolean = false;
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

  aboutToAppear(): void {
    this.active = true;
    this.loadSelected();
    this.lessDataCalls = AppStorage.get<boolean>(KEY_AUTO_LESS_DATA_CALLS) ?? false;
    this.autosavePrivate = AppStorage.get<boolean>(KEY_AUTOSAVE_PRIVATE) ?? false;
    this.autosaveGroup = AppStorage.get<boolean>(KEY_AUTOSAVE_GROUP) ?? false;
    this.autosaveChannel = AppStorage.get<boolean>(KEY_AUTOSAVE_CHANNEL) ?? false;
    prepareAutosaveSettings().then((): void => {
      this.autosavePrepared = true;
    }).catch((error: TdError): void => {
      console.warn(`MediaStorageSettingsPage.prepareAutosave failed: ${error.message}`);
      if (this.active) { this.warning = str('ms_album_sync_failed'); }
    });
  }

  aboutToDisappear(): void {
    this.active = false;
    this.syncSequence++;
  }

  private loadSelected(): void {
    const policy: AutoDownloadPolicy = autoDownloadPolicy(this.selectedNetwork);
    this.photos = policy.photos;
    this.videos = policy.videos;
    this.files = policy.files;
    this.videoLimit = policy.videoLimit;
    this.fileLimit = policy.fileLimit;
    this.preloadVideo = policy.preloadLargeVideos;
    this.nextAudio = policy.preloadNextAudio;
    this.stories = policy.preloadStories;
  }

  private boolKey(kind: string): string {
    if (this.selectedNetwork === 'wifi') {
      if (kind === 'photo') { return KEY_AUTO_WIFI_PHOTO; }
      if (kind === 'video') { return KEY_AUTO_WIFI_VIDEO; }
      if (kind === 'file') { return KEY_AUTO_WIFI_FILE; }
      if (kind === 'preload') { return KEY_AUTO_WIFI_PRELOAD_VIDEO; }
      if (kind === 'audio') { return KEY_AUTO_WIFI_NEXT_AUDIO; }
      return KEY_AUTO_WIFI_STORIES;
    }
    if (this.selectedNetwork === 'roaming') {
      if (kind === 'photo') { return KEY_AUTO_ROAMING_PHOTO; }
      if (kind === 'video') { return KEY_AUTO_ROAMING_VIDEO; }
      if (kind === 'file') { return KEY_AUTO_ROAMING_FILE; }
      if (kind === 'preload') { return KEY_AUTO_ROAMING_PRELOAD_VIDEO; }
      if (kind === 'audio') { return KEY_AUTO_ROAMING_NEXT_AUDIO; }
      return KEY_AUTO_ROAMING_STORIES;
    }
    if (kind === 'photo') { return KEY_AUTO_MOBILE_PHOTO; }
    if (kind === 'video') { return KEY_AUTO_MOBILE_VIDEO; }
    if (kind === 'file') { return KEY_AUTO_MOBILE_FILE; }
    if (kind === 'preload') { return KEY_AUTO_MOBILE_PRELOAD_VIDEO; }
    if (kind === 'audio') { return KEY_AUTO_MOBILE_NEXT_AUDIO; }
    return KEY_AUTO_MOBILE_STORIES;
  }

  private numberKey(kind: string): string {
    if (this.selectedNetwork === 'wifi') {
      return kind === 'video' ? KEY_AUTO_WIFI_VIDEO_LIMIT : KEY_AUTO_WIFI_FILE_LIMIT;
    }
    if (this.selectedNetwork === 'roaming') {
      return kind === 'video' ? KEY_AUTO_ROAMING_VIDEO_LIMIT : KEY_AUTO_ROAMING_FILE_LIMIT;
    }
    return kind === 'video' ? KEY_AUTO_MOBILE_VIDEO_LIMIT : KEY_AUTO_MOBILE_FILE_LIMIT;
  }

  private setMediaBoolean(kind: string, value: boolean): void {
    setBoolean(this.boolKey(kind), value);
    if (kind === 'photo') { this.photos = value; }
    else if (kind === 'video') { this.videos = value; }
    else if (kind === 'file') { this.files = value; }
    else if (kind === 'preload') { this.preloadVideo = value; }
    else if (kind === 'audio') { this.nextAudio = value; }
    else { this.stories = value; }
    this.syncCurrentPolicy();
  }

  private limitIndex(value: number): number {
    let best = 0;
    let distance = Number.MAX_SAFE_INTEGER;
    for (let index = 0; index < LIMITS.length; index++) {
      const next = Math.abs(LIMITS[index] - value);
      if (next < distance) { best = index; distance = next; }
    }
    return best;
  }

  private setLimit(kind: string, index: number): void {
    const safeIndex = Math.max(0, Math.min(LIMITS.length - 1, Math.round(index)));
    const value = LIMITS[safeIndex];
    setNumber(this.numberKey(kind), value);
    if (kind === 'video') { this.videoLimit = value; }
    else { this.fileLimit = value; }
    this.syncCurrentPolicy();
  }

  private syncCurrentPolicy(): void {
    this.runPolicySync(syncAutoDownloadSettings(autoDownloadPolicy(this.selectedNetwork)));
  }

  private syncAllPolicies(): void {
    const requests: Promise<void>[] = [
      syncAutoDownloadSettings(autoDownloadPolicy('wifi')),
      syncAutoDownloadSettings(autoDownloadPolicy('mobile')),
      syncAutoDownloadSettings(autoDownloadPolicy('roaming'))
    ];
    this.runPolicySync(Promise.all(requests).then((): void => {}));
  }

  private runPolicySync(request: Promise<void>): void {
    const current = ++this.syncSequence;
    this.syncing = true;
    this.warning = '';
    request.then((): void => {
      if (!this.active || current !== this.syncSequence) { return; }
      this.syncing = false;
    }).catch((error: TdError): void => {
      if (!this.active || current !== this.syncSequence) { return; }
      this.syncing = false;
      this.warning = str('ms_download_sync_failed');
      console.error(`MediaStorageSettingsPage.syncAutoDownload failed: ${error.message}`);
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
      console.error(`MediaStorageSettingsPage.syncAutosave failed: ${error.message}`);
    });
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Row() { SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(25).fontColor([COLOR_TEXT_PRIMARY]); }
      .width(44).height(44).borderRadius(22).justifyContent(FlexAlign.Center)
      .stateStyles({ normal: this.actionNormalStyle, pressed: this.actionPressedStyle })
      .onClick((): void => router.back());
      Column({ space: 1 }) {
        Text($r('app.string.ms_title')).fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
        Text($r('app.string.ms_subtitle')).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      if (this.syncing) { LoadingProgress().width(18).height(18).color(COLOR_PRIMARY).margin({ right: 13 }); }
    }.width('100%').height(56).padding({ left: 8, right: 8 }).alignItems(VerticalAlign.Center);
  }

  @Builder
  tabs() {
    Row({ space: 4 }) {
      ForEach(NETWORKS, (option: NetworkOption) => {
        Text(option.label).fontSize(13).fontWeight(FontWeight.Medium)
          .fontColor(this.selectedNetwork === option.key ? Color.White : COLOR_TEXT_SECONDARY)
          .layoutWeight(1).height(36).textAlign(TextAlign.Center).padding({ top: 8 })
          .backgroundColor(this.selectedNetwork === option.key ? COLOR_PRIMARY : Color.Transparent)
          .borderRadius(18).animation({ duration: 160, curve: Curve.EaseOut })
          .onClick((): void => {
            if (this.selectedNetwork !== option.key) {
              this.selectedNetwork = option.key;
              this.loadSelected();
            }
          });
      }, (option: NetworkOption): string => option.key);
    }.width('100%').padding(3).backgroundColor($r('app.color.surface_alt')).borderRadius(21);
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
  limitRow(title: string, value: number, kind: string) {
    Column({ space: 5 }) {
      Row() {
        Text(title).fontSize(14).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
        Text(formatBytes(value)).fontSize(13).fontColor(COLOR_PRIMARY);
      }.width('100%');
      Slider({ value: this.limitIndex(value), min: 0, max: LIMITS.length - 1, step: 1 })
        .width('100%').selectedColor(COLOR_PRIMARY).blockColor(COLOR_PRIMARY)
        .onChange((next: number, mode: SliderChangeMode): void => {
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            this.setLimit(kind, next);
          }
        });
      Row() {
        Text('512 KB').fontSize(10).fontColor(COLOR_TEXT_SECONDARY);
        Blank();
        Text('512 MB').fontSize(10).fontColor(COLOR_TEXT_SECONDARY);
      }.width('100%');
    }.width('100%').padding({ left: 14, right: 14, top: 8, bottom: 10 });
  }

  @Builder
  autoDownloadCard() {
    Column() {
      this.toggleRow(str('storage_photo'), str('ms_photo_sub'), this.photos,
        (next: boolean): void => this.setMediaBoolean('photo', next));
      Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 });
      this.toggleRow(str('ms_video_gif'), str('ms_up_to', formatBytes(this.videoLimit)), this.videos,
        (next: boolean): void => this.setMediaBoolean('video', next));
      if (this.videos) { this.limitRow(str('ms_video_limit'), this.videoLimit, 'video'); }
      Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 });
      this.toggleRow(str('ms_file_music'), str('ms_up_to', formatBytes(this.fileLimit)), this.files,
        (next: boolean): void => this.setMediaBoolean('file', next));
      if (this.files) { this.limitRow(str('ms_file_limit'), this.fileLimit, 'file'); }
    }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).clip(true);
  }

  @Builder
  preloadCard() {
    Column() {
      this.toggleRow(str('ms_preload_video'), str('ms_preload_video_sub'), this.preloadVideo,
        (next: boolean): void => this.setMediaBoolean('preload', next));
      Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 });
      this.toggleRow(str('ms_preload_music'), str('ms_preload_music_sub'), this.nextAudio,
        (next: boolean): void => this.setMediaBoolean('audio', next));
      Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 });
      this.toggleRow(str('ms_preload_stories'), str('ms_preload_stories_sub'), this.stories,
        (next: boolean): void => this.setMediaBoolean('stories', next));
      Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 });
      this.toggleRow(str('ms_call_data_saving'), str('ms_call_data_saving_sub'), this.lessDataCalls,
        (next: boolean): void => {
          this.lessDataCalls = next;
          setBoolean(KEY_AUTO_LESS_DATA_CALLS, next);
          this.syncAllPolicies();
        });
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
          Text($r('app.string.ms_auto_download')).fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
            .width('100%').padding({ left: 4 });
          this.tabs();
          this.autoDownloadCard();
          this.preloadCard();
          Text($r('app.string.ms_save_to_gallery')).fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
            .width('100%').padding({ left: 4, top: 4 });
          this.autosaveCard();
          Text($r('app.string.ms_note'))
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).width('100%')
            .padding({ left: 4, right: 4 });
        }.width('100%').padding({ left: 12, right: 12, top: 6, bottom: this.bottomSafe + 24 });
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring);
    }.width('100%').height('100%').backgroundColor(COLOR_PAGE_BG)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .padding({ top: this.topSafe });
  }
}
