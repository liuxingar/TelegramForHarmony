import { router } from '@kit.ArkUI';
import {
  KEY_TEXT_SIZE, KEY_BUBBLE_RADIUS, KEY_THREE_LINES, KEY_NIGHT_MODE, KEY_REDUCE_ANIM, KEY_SEND_BY_ENTER,
  KEY_POWER_SMOOTH_TRANSITIONS,
  TEXT_SIZE_MIN, TEXT_SIZE_MAX, RADIUS_MIN, RADIUS_MAX,
  NIGHT_SYSTEM, NIGHT_DARK, NIGHT_LIGHT,
  powerAnimationDuration, setNumber, setBoolean, setNightMode
} from '../../store/AppSettings';
import {
  COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY, COLOR_BUBBLE_IN, COLOR_BUBBLE_OUT
} from '../../util/theme';

const CARD_BG: ResourceColor = $r('app.color.surface');
const CARD_RADIUS: number = 14;

interface NightOption {
  label: string;
  value: string;
}

const NIGHT_OPTIONS: NightOption[] = [
  { label: '跟随系统', value: NIGHT_SYSTEM },
  { label: '始终开启', value: NIGHT_DARK },
  { label: '始终关闭', value: NIGHT_LIGHT }
];

// 聊天设置. Deliberately limited to settings the app actually honours — the
// official page also offers wallpapers, colour themes and app icons, which need
// capabilities we don't have yet, and a switch that changes nothing is worse
// than no switch at all.
@Entry
@Component
struct ChatSettingsPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageLink(KEY_TEXT_SIZE) textSize: number = 16;
  @StorageLink(KEY_BUBBLE_RADIUS) bubbleRadius: number = 17;
  @StorageLink(KEY_THREE_LINES) threeLines: boolean = false;
  @StorageLink(KEY_NIGHT_MODE) nightMode: string = NIGHT_SYSTEM;
  @StorageLink(KEY_REDUCE_ANIM) reduceAnim: boolean = false;
  @StorageLink(KEY_SEND_BY_ENTER) sendByEnter: boolean = false;
  @State leavingPage: boolean = false;
  private leaveTimer: number = -1;

  aboutToDisappear(): void {
    if (this.leaveTimer !== -1) {
      clearTimeout(this.leaveTimer);
      this.leaveTimer = -1;
    }
    this.leavingPage = false;
  }

  private leavePage(): void {
    if (this.leavingPage) {
      return;
    }
    this.leavingPage = true;
    this.leaveTimer = setTimeout((): void => {
      this.leaveTimer = -1;
      this.leavingPage = false;
    }, 500);
    router.back();
  }

  private numberValue(key: string): number {
    return key === KEY_TEXT_SIZE ? this.textSize : this.bubbleRadius;
  }

  private booleanValue(key: string): boolean {
    return key === KEY_REDUCE_ANIM ? this.reduceAnim : this.sendByEnter;
  }

  @Styles
  actionNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  actionPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.72)
    .scale({ x: 0.92, y: 0.92 })
  }

  @Styles
  optionNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  optionPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.75)
    .scale({ x: 0.98, y: 0.98 })
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(25).fontColor([COLOR_TEXT_PRIMARY]);
      }
      .width(44).height(44).borderRadius(22)
      .justifyContent(FlexAlign.Center)
      .stateStyles({
        normal: this.actionNormalStyle,
        pressed: this.actionPressedStyle
      })
      .enabled(!this.leavingPage)
      .accessibilityText('返回设置')
      .onClick((): void => { this.leavePage(); });
      Text('聊天设置').fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
    }
    .width('100%').height(56).padding({ left: 8, right: 16 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  cardTitle(text: string) {
    Text(text).fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 4 });
  }

  // Live sample of what the sliders above do — same colours, size and radius as
  // a real bubble.
  @Builder
  preview() {
    Column({ space: 8 }) {
      Row() {
        Text('早上好！现在几点了？')
          .fontSize(this.textSize).fontColor(COLOR_TEXT_PRIMARY)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(COLOR_BUBBLE_IN)
          .borderRadius(this.bubbleRadius);
      }.width('100%').justifyContent(FlexAlign.Start);
      Row() {
        Text('东京现在是早上 😄')
          .fontSize(this.textSize).fontColor(COLOR_TEXT_PRIMARY)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(COLOR_BUBBLE_OUT)
          .borderRadius(this.bubbleRadius);
      }.width('100%').justifyContent(FlexAlign.End);
    }
    .width('100%').padding(14);
  }

  @Builder
  sliderRow(title: string, key: string, min: number, max: number) {
    Column() {
      this.cardTitle(title);
      Row({ space: 12 }) {
        Slider({ value: this.numberValue(key), min: min, max: max, step: 1 })
          .layoutWeight(1)
          .trackColor($r('app.color.divider')).selectedColor(COLOR_PRIMARY).blockColor(COLOR_PRIMARY)
          .onChange((value: number): void => { setNumber(key, Math.round(value)); });
        Text(`${this.numberValue(key)}`)
          .fontSize(15).fontColor(COLOR_PRIMARY).width(28).textAlign(TextAlign.End);
      }.width('100%').padding({ left: 16, right: 16, bottom: 6 });
    }.width('100%');
  }

  @Builder
  toggleRow(title: string, subtitle: string, key: string) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(title).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
        if (subtitle !== '') {
          Text(subtitle).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
        }
      }
      .height(52)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .borderRadius(10)
      .stateStyles({
        normal: this.optionNormalStyle,
        pressed: this.optionPressedStyle
      })
      .accessibilityText(`${title}，${this.booleanValue(key) ? '已开启' : '已关闭'}`)
      .onClick((): void => { setBoolean(key, !this.booleanValue(key)); });
      Toggle({ type: ToggleType.Switch, isOn: this.booleanValue(key) })
        .selectedColor(COLOR_PRIMARY)
        .onChange((value: boolean): void => { setBoolean(key, value); });
    }
    .width('100%').height(64).padding({ left: 16, right: 13 })
    .alignItems(VerticalAlign.Center);
  }

  // Chat-list row density: two lines (name + preview) or three (adds a second
  // preview line).
  @Builder
  chatListView() {
    Column() {
      this.cardTitle('聊天列表视图');
      Row({ space: 12 }) {
        this.densityOption('两行', false);
        this.densityOption('三行', true);
      }.width('100%').padding({ left: 16, right: 16, top: 4, bottom: 12 });
    }.width('100%');
  }

  @Builder
  densityOption(label: string, isThree: boolean) {
    Column({ space: 8 }) {
      Column({ space: 5 }) {
        Row({ space: 8 }) {
          Circle({ width: 22, height: 22 }).fill($r('app.color.divider'));
          Column({ space: 3 }) {
            Row().width('70%').height(4).borderRadius(2).backgroundColor($r('app.color.divider'));
            Row().width('90%').height(4).borderRadius(2).backgroundColor($r('app.color.divider'));
            if (isThree) {
              Row().width('80%').height(4).borderRadius(2).backgroundColor($r('app.color.divider'));
            }
          }.alignItems(HorizontalAlign.Start).layoutWeight(1);
        }.width('100%').alignItems(VerticalAlign.Center);
      }
      .width('100%').padding(10)
      .borderRadius(10)
      .border({ width: this.threeLines === isThree ? 2 : 1,
        color: this.threeLines === isThree ? COLOR_PRIMARY : $r('app.color.divider') })
      .backgroundColor(this.threeLines === isThree ? $r('app.color.surface_alt') : Color.Transparent)
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160),
        curve: Curve.EaseOut
      });
      Text(label).fontSize(13)
        .fontColor(this.threeLines === isThree ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY);
    }
    .layoutWeight(1)
    .borderRadius(12)
    .stateStyles({
      normal: this.optionNormalStyle,
      pressed: this.optionPressedStyle
    })
    .accessibilityText(`${label}聊天列表视图${this.threeLines === isThree ? '，已选中' : ''}`)
    .onClick((): void => {
      if (this.threeLines !== isThree) {
        setBoolean(KEY_THREE_LINES, isThree);
      }
    });
  }

  @Builder
  nightModeCard() {
    Column() {
      this.cardTitle('夜间模式');
      ForEach(NIGHT_OPTIONS, (opt: NightOption, idx: number) => {
        if (idx > 0) {
          Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
        }
        Row() {
          Text(opt.label).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
          if (this.nightMode === opt.value) {
            SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([COLOR_PRIMARY]);
          }
        }
        .width('100%').height(48).padding({ left: 16, right: 16 })
        .stateStyles({
          normal: this.optionNormalStyle,
          pressed: this.optionPressedStyle
        })
        .accessibilityText(`${opt.label}${this.nightMode === opt.value ? '，已选中' : ''}`)
        .onClick((): void => {
          if (this.nightMode !== opt.value) {
            setNightMode(opt.value);
          }
        });
      }, (opt: NightOption) => opt.value);
    }.width('100%');
  }

  build() {
    Column() {
      this.header();
      Scroll() {
        Column({ space: 14 }) {
          // 字号 + 圆角, with the preview they drive.
          Column() {
            this.sliderRow('消息字号', KEY_TEXT_SIZE, TEXT_SIZE_MIN, TEXT_SIZE_MAX);
            this.preview();
            Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16, right: 16 });
            this.sliderRow('消息圆角', KEY_BUBBLE_RADIUS, RADIUS_MIN, RADIUS_MAX);
          }
          .width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS);

          Column() {
            this.chatListView();
          }.width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS);

          Column() {
            this.nightModeCard();
          }.width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS).padding({ bottom: 4 });

          Column() {
            this.toggleRow('减弱动态效果', '不再自动播放动画贴纸与表情，省电', KEY_REDUCE_ANIM);
            Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
            this.toggleRow('回车键发送', '开启后回车直接发送，换行用输入法的换行键', KEY_SEND_BY_ENTER);
          }
          .width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
          .padding({ top: 4, bottom: 4 });
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: this.bottomSafe + 24 });
      }
      .layoutWeight(1).width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off);
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.topSafe });
  }
}
