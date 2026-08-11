import { router } from '@kit.ArkUI';
import {
  KEY_BG_PLAY_MUSIC, KEY_BG_PLAY_VOICE, KEY_BG_PLAY_VIDEO, KEY_BG_PLAY_LIVE, setBoolean
} from '../../store/AppSettings';
import {
  COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';

const CARD_RADIUS: number = 14;

// 后台播放设置：各媒体类别切后台时是否继续播放（audioPlayback 长时任务）。
@Entry
@Component
struct BackgroundPlaybackPage {
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
        Text('后台播放').fontSize(19).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
      }
      .width('100%').padding({ left: 8, right: 12, top: this.topSafe + 6, bottom: 6 });
      Scroll() {
        Column({ space: 12 }) {
          Column() {
            this.switchRow('音乐', '聊天中的音乐文件切后台继续播放', this.bgMusic,
              (next: boolean): void => setBoolean(KEY_BG_PLAY_MUSIC, next));
            this.switchRow('语音消息', '语音消息切后台继续播放', this.bgVoice,
              (next: boolean): void => setBoolean(KEY_BG_PLAY_VOICE, next));
            this.switchRow('视频', '视频切后台继续播放声音', this.bgVideo,
              (next: boolean): void => setBoolean(KEY_BG_PLAY_VIDEO, next));
            this.switchRow('直播', '直播切后台继续播放', this.bgLive,
              (next: boolean): void => setBoolean(KEY_BG_PLAY_LIVE, next));
          }
          .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
          Text('开启后对应内容在后台继续播放，通知栏会显示"正在后台运行"。关闭则切后台自动暂停。')
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
