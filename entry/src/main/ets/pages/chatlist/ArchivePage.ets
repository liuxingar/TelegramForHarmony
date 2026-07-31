import { router } from '@kit.ArkUI';
import { ChatListView } from './ChatListView';
import { CHAT_LIST_NOW } from './ChatListFreeze';
import { COLOR_TEXT_PRIMARY } from '../../util/theme';

@Entry
@Preview
@Component
struct ArchivePage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  private clockTimer: number = -1;

  @Styles
  backNormalStyle() {
    .backgroundColor(Color.Transparent)
  }

  @Styles
  backPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
  }

  aboutToAppear(): void {
    AppStorage.setOrCreate(CHAT_LIST_NOW, Math.floor(Date.now() / 1000));
    this.clockTimer = setInterval((): void => {
      AppStorage.setOrCreate(CHAT_LIST_NOW, Math.floor(Date.now() / 1000));
    }, 60000);
  }

  aboutToDisappear(): void {
    if (this.clockTimer !== -1) {
      clearInterval(this.clockTimer);
      this.clockTimer = -1;
    }
  }

  build() {
    Column() {
      Row() {
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([COLOR_TEXT_PRIMARY]);
        }
        .width(44).height(44).borderRadius(22)
        .justifyContent(FlexAlign.Center)
        .stateStyles({
          normal: this.backNormalStyle,
          pressed: this.backPressedStyle
        })
        .onClick(() => { router.back(); });
        Text('已归档的聊天')
          .fontSize(20).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
          .margin({ left: 4 });
      }
      .width('100%').height(this.topSafe + 56)
      .padding({ left: 6, right: 16, top: this.topSafe });
      ChatListView({ listKey: 'archive', reserveDockSpace: false });
    }
    .width('100%').height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}
