import { router } from '@kit.ArkUI';
import {
  KEY_BG_PLAY_MUSIC, KEY_BG_PLAY_VOICE, KEY_BG_PLAY_VIDEO, KEY_BG_PLAY_LIVE, setBoolean
} from '../../store/AppSettings';
import {
  COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';

const CARD_RADIUS: number = 14;

// 后台播放设置：各媒体类别切后台时是否继续播放（audioPlayback 长时任务）。
@Entry
@Component
struct BackgroundPlaybackPage {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageProp(KEY_BG_PLAY_MUSIC) bgMusic: boolean = true;
  @StorageProp(KEY_BG_PLAY_VOICE) bgVoice: boolean = true;
  @StorageProp(KEY_BG_PLAY_VIDEO) bgVideo: boolean = false;
  @StorageProp(KEY_BG_PLAY_LIVE) bgLive: boolean = true;

  @Builder
  switchRow(label: string, subtitle: string, value: boolean, onChange: (next: boolean) => void) {
    Row({ space: 8 }) {
      Column({ space: 3 }) {
        Text(label).fontSize(15).fontColor(COLOR_TEXT_PRIMARY);
        Text(subtitle).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
      Toggle({ type: ToggleType.Switch, isOn: value }).selectedColor(COLOR_PRIMARY)
        .onChange(onChange);
    }
    .width('100%').constraintSize({ minHeight: 56 })
    .padding({ left: 14, right: 12, top: 8, bottom: 8 });
  }

  build() {
    Column() {
      Row({ space: 6 }) {
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(25).fontColor([COLOR_TEXT_PRIMARY]);
        }
        .width(44).height(44).borderRadius(22).justifyContent(FlexAlign.Center)
        .onClick((): void => router.back());
        Text($r('app.string.settings_background_playback')).fontSize(19).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
      }
      .width('100%').padding({ left: 8, right: 12, top: this.topSafe + 6, bottom: 6 });
      Scroll() {
        Column({ space: 12 }) {
          Column() {
            this.switchRow(str('bgplay_music'), str('bgplay_music_sub'), this.bgMusic,
              (next: boolean): void => setBoolean(KEY_BG_PLAY_MUSIC, next));
            this.switchRow(str('bgplay_voice'), str('bgplay_voice_sub'), this.bgVoice,
              (next: boolean): void => setBoolean(KEY_BG_PLAY_VOICE, next));
            this.switchRow(str('bgplay_video'), str('bgplay_video_sub'), this.bgVideo,
              (next: boolean): void => setBoolean(KEY_BG_PLAY_VIDEO, next));
            this.switchRow(str('bgplay_live'), str('bgplay_live_sub'), this.bgLive,
              (next: boolean): void => setBoolean(KEY_BG_PLAY_LIVE, next));
          }
          .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
          Text($r('app.string.bgplay_note'))
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
            .width('100%').padding({ left: 14, right: 14 });
        }
        .padding({ left: 12, right: 12, top: 4, bottom: this.bottomSafe + 16 });
      }
      .layoutWeight(1).align(Alignment.Top);
    }
    .width('100%').height('100%').backgroundColor(COLOR_PAGE_BG);
  }
}
