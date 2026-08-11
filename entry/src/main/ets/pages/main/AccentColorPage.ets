import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { getAccentColorStore, getTdClient } from '../../tdkit/Globals';
import { AccentPalettes } from '../../store/AccentColorStore';
import { TdError, TdObject, TdRequest } from '../../tdkit/TdTypes';
import {
  AccentPreview, accentPreviewOf, profileAccentPreviewOf
} from '../../util/accentPresentation';
import { syncAccentPrimary } from '../../util/accentTheme';
import {
  COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';

const CARD_RADIUS: number = 14;
const SWATCH: number = 44;

@Entry
@Component
struct AccentColorPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State namePreviews: AccentPreview[] = [];
  @State profilePreviews: AccentPreview[] = [];
  @State currentNameId: number = -1;
  @State currentProfileId: number = -1;
  @State busy: boolean = false;
  @State myName: string = '';
  private off: (() => void) | null = null;
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    const dark = this.darkMode();
    this.off = getAccentColorStore().subscribe((palettes: AccentPalettes): void => {
      this.namePreviews = this.orderPreviews(
        palettes.nameColors.map((c: TdObject): AccentPreview | null => accentPreviewOf(c, dark)),
        palettes.nameIds
      );
      this.profilePreviews = this.orderPreviews(
        palettes.profileColors.map(
          (c: TdObject): AccentPreview | null => profileAccentPreviewOf(c, dark)),
        palettes.profileIds
      );
    });
    this.refreshSelection();
  }

  aboutToDisappear(): void {
    this.active = false;
    if (this.off !== null) {
      this.off();
      this.off = null;
    }
  }

  // available_accent_color_ids defines the server's display order and may
  // reference built-in ids that have no palette entry of their own.
  private orderPreviews(
    mapped: (AccentPreview | null)[], availableIds: number[]
  ): AccentPreview[] {
    const byId = new Map<number, AccentPreview>();
    for (const preview of mapped) {
      if (preview !== null) { byId.set(preview.id, preview); }
    }
    const rows: AccentPreview[] = [];
    for (const id of availableIds) {
      const known = byId.get(id);
      if (known !== undefined) {
        rows.push(known);
      } else {
        const builtin = accentPreviewOf(
          { '@type': 'accentColor', 'id': id, 'built_in_accent_color_id': id } as TdObject, false
        );
        if (builtin !== null) { rows.push(builtin); }
      }
    }
    return rows;
  }

  private darkMode(): boolean {
    try {
      const color = (getContext(this) as common.UIAbilityContext)
        .resourceManager.getColorSync($r('app.color.chat_bg'));
      const red = (color >>> 16) & 0xFF;
      const green = (color >>> 8) & 0xFF;
      const blue = color & 0xFF;
      return red * 0.299 + green * 0.587 + blue * 0.114 < 128;
    } catch (_error) {
      return false;
    }
  }

  private refreshSelection(): void {
    getAccentColorStore().currentSelection().then((ids: [number, number]): void => {
      if (!this.active) { return; }
      this.currentNameId = ids[0];
      this.currentProfileId = ids[1];
    }).catch((error: TdError): void => {
      console.error(`AccentColorPage.selection failed: ${error.message}`);
    });
    getTdClient().send({ '@type': 'getMe' } as TdRequest).then((me: TdObject): void => {
      if (!this.active) { return; }
      const first = (me['first_name'] as string | undefined) ?? '';
      const last = (me['last_name'] as string | undefined) ?? '';
      this.myName = `${first} ${last}`.trim();
    }).catch((): void => {});
  }

  // Live preview: your own message color is what OTHERS see in groups — your
  // outgoing bubbles never carry a name, so the page shows it here instead.
  private previewNameColor(): string {
    const hex = getAccentColorStore().nameColorHex(this.currentNameId, this.darkMode());
    return hex !== '' ? hex : '#3390EC';
  }

  private errorText(error: TdError): string {
    return error.message.indexOf('PREMIUM') >= 0 || error.message.indexOf('premium') >= 0
      ? '该颜色需要 Telegram Premium' : '设置失败，请稍后重试';
  }

  private applyName(id: number): void {
    if (this.busy) { return; }
    this.busy = true;
    getAccentColorStore().setNameAccentColor(id).then((): void => {
      if (!this.active) { return; }
      this.busy = false;
      this.currentNameId = id;
      promptAction.showToast({ message: '名字颜色已更新', duration: 1500 });
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.busy = false;
      promptAction.showToast({ message: this.errorText(error), duration: 1800 });
    });
  }

  private applyProfile(id: number): void {
    if (this.busy) { return; }
    this.busy = true;
    getAccentColorStore().setProfileAccentColor(id).then((): void => {
      if (!this.active) { return; }
      this.busy = false;
      this.currentProfileId = id;
      syncAccentPrimary(getContext(this) as common.UIAbilityContext);
      promptAction.showToast({
        message: '资料页颜色已更新，App 主色已联动（已打开的页面重进后生效）', duration: 2200
      });
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.busy = false;
      promptAction.showToast({ message: this.errorText(error), duration: 1800 });
    });
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([COLOR_TEXT_PRIMARY]);
      }.width(40).height(40).borderRadius(20).backgroundColor(Color.Transparent)
      .onClick((): void => { router.back(); });
      Text('强调色').fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
      if (this.busy) { LoadingProgress().width(20).height(20).color(COLOR_PRIMARY); }
    }.width('100%').height(52).padding({ left: 8, right: 16 }).alignItems(VerticalAlign.Center);
  }

  private isSelected(preview: AccentPreview, forProfile: boolean): boolean {
    return (forProfile ? this.currentProfileId : this.currentNameId) === preview.id;
  }

  // Selection is read from @State INSIDE the builder: @Builder value params
  // are frozen at call time and would never show the asynchronously fetched
  // current color.
  @Builder
  swatch(preview: AccentPreview, forProfile: boolean, onTap: () => void) {
    Stack({ alignContent: Alignment.Center }) {
      if (preview.colors.length > 1) {
        Column().width(SWATCH).height(SWATCH).borderRadius(SWATCH / 2)
          .linearGradient({
            angle: 135,
            colors: preview.colors.map((color: string, index: number): [string, number] =>
              [color, index / (preview.colors.length - 1)])
          });
      } else {
        Column().width(SWATCH).height(SWATCH).borderRadius(SWATCH / 2)
          .backgroundColor(preview.colors.length === 1 ? preview.colors[0] : COLOR_SURFACE);
      }
      if (this.isSelected(preview, forProfile)) {
        SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([Color.White]);
      }
    }
    .width(SWATCH + 8).height(SWATCH + 8)
    .borderRadius((SWATCH + 8) / 2)
    .border({
      width: this.isSelected(preview, forProfile) ? 2 : 0,
      color: COLOR_PRIMARY
    })
    .onClick(onTap);
  }

  @Builder
  section(title: string, subtitle: string) {
    Column({ space: 3 }) {
      Text(title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
        .width('100%');
      Text(subtitle).fontSize(11).fontColor(COLOR_TEXT_SECONDARY).width('100%');
    }
  }

  build() {
    Column() {
      this.header();
      if (this.namePreviews.length === 0 && this.profilePreviews.length === 0) {
        Column({ space: 9 }) {
          LoadingProgress().width(34).height(34).color(COLOR_PRIMARY);
          Text('正在等待色板…').fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          Text('色板由 Telegram 服务器在登录后下发').fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else {
        Scroll() {
          Column({ space: 14 }) {
            Column({ space: 12 }) {
              this.section('名字颜色', '影响他人看到的你的名字、回复条与链接预览颜色');
              Column({ space: 4 }) {
                Text(this.myName !== '' ? this.myName : '你的名字')
                  .fontSize(14).fontWeight(FontWeight.Medium)
                  .fontColor(this.previewNameColor());
                Text('群聊中你的消息在他人设备上的名字效果')
                  .fontSize(12).fontColor(COLOR_TEXT_PRIMARY);
              }
              .width('100%').alignItems(HorizontalAlign.Start)
              .padding(10).borderRadius(10).backgroundColor(COLOR_PAGE_BG);
              Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                ForEach(this.namePreviews, (preview: AccentPreview) => {
                  Column() {
                    this.swatch(preview, false, (): void => this.applyName(preview.id));
                  }.padding(4);
                }, (preview: AccentPreview): string => `name_${preview.id}`);
              }
            }
            .width('100%').padding(14).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);

            Column({ space: 12 }) {
              this.section('资料页颜色', '影响你个人资料页顶部的配色');
              Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                ForEach(this.profilePreviews, (preview: AccentPreview) => {
                  Column() {
                    this.swatch(preview, true, (): void => this.applyProfile(preview.id));
                  }.padding(4);
                }, (preview: AccentPreview): string => `profile_${preview.id}`);
              }
            }
            .width('100%').padding(14).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);

            Text('多彩渐变色为 Telegram Premium 专属，非会员选择时服务器会拒绝。设置会同步到你的所有设备。')
              .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(18).width('100%');
          }.width('100%').padding({ left: 12, right: 12, bottom: this.bottomSafe + 24 });
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
      }
    }
    .width('100%').height('100%').backgroundColor(COLOR_PAGE_BG)
    .padding({ top: this.topSafe });
  }
}
