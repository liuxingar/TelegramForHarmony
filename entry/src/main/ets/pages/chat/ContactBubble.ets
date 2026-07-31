import { AvatarView } from '../chatlist/AvatarView';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

@Component
export struct ContactBubble {
  @Prop firstName: string = '';
  @Prop lastName: string = '';
  @Prop phone: string = '';
  @Prop vcard: string = '';
  @Prop userId: number = 0;
  @Prop avatarPath: string = '';
  @Prop maxWidth: number = 250;
  onOpen: () => void = (): void => {};
  onCall: () => void = (): void => {};

  @Styles
  private cardNormalStyle(): void {
    .scale({ x: 1, y: 1 })
    .opacity(1)
  }

  @Styles
  private cardPressedStyle(): void {
    .scale({ x: 0.985, y: 0.985 })
    .opacity(0.82)
  }

  @Styles
  private actionNormalStyle(): void {
    .scale({ x: 1, y: 1 })
    .opacity(1)
  }

  @Styles
  private actionPressedStyle(): void {
    .scale({ x: 0.86, y: 0.86 })
    .opacity(0.62)
  }

  private name(): string {
    const value = `${this.firstName} ${this.lastName}`.trim();
    if (value !== '') {
      return value;
    }
    return this.userId > 0 ? 'Telegram 用户' : '未命名联系人';
  }

  private initials(): string {
    const first = this.firstName.trim();
    const last = this.lastName.trim();
    const value = `${first.length > 0 ? first.substring(0, 1) : ''}` +
      `${last.length > 0 ? last.substring(0, 1) : ''}`;
    return value !== '' ? value.toUpperCase() : '?';
  }

  private available(): boolean {
    return this.userId > 0 || this.phone.trim() !== '' ||
      this.firstName.trim() !== '' || this.lastName.trim() !== '' || this.vcard.trim() !== '';
  }

  private subtitle(): string {
    if (this.phone.trim() !== '') {
      return this.phone.trim();
    }
    if (this.userId > 0) {
      return '点击查看 Telegram 资料';
    }
    if (this.vcard.trim() !== '') {
      return '联系人名片';
    }
    return '联系人信息不可用';
  }

  build() {
    Row({ space: 10 }) {
      Row({ space: 10 }) {
        AvatarView({
          avatarPath: this.avatarPath,
          initials: this.initials(),
          colorSeed: this.userId !== 0 ? this.userId : this.name().length * 31,
          avatarSize: 48
        });
        Column({ space: 4 }) {
          Text(this.name())
            .fontSize(14.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%');
          Text(this.subtitle())
            .fontSize(11.5)
            .fontColor(this.available() ? COLOR_TEXT_SECONDARY : '#D95B57')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%');
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
      .stateStyles({
        normal: this.cardNormalStyle,
        pressed: this.cardPressedStyle
      })
      .animation({ duration: 110, curve: Curve.EaseOut })
      .accessibilityText(this.available() ? `联系人 ${this.name()}` : '联系人信息不可用')
      .onClick((): void => {
        if (this.available()) {
          this.onOpen();
        }
      });

      if (this.phone.trim() !== '') {
        Stack() {
          Circle({ width: 34, height: 34 }).fill('#123390EC');
          SymbolGlyph($r('sys.symbol.phone_fill'))
            .fontSize(17).fontColor([COLOR_PRIMARY]);
        }
        .width(34).height(34)
        .stateStyles({
          normal: this.actionNormalStyle,
          pressed: this.actionPressedStyle
        })
        .animation({ duration: 100, curve: Curve.EaseOut })
        .accessibilityText(`拨打 ${this.phone.trim()}`)
        .onClick((): void => { this.onCall(); });
      } else {
        SymbolGlyph($r(this.userId > 0 ? 'sys.symbol.chevron_right' : 'sys.symbol.person'))
          .fontSize(this.userId > 0 ? 14 : 19)
          .fontColor([this.userId > 0 ? COLOR_TEXT_SECONDARY : '#9EA6AF'])
          .opacity(this.available() ? 1 : 0.55);
      }
    }
    .width(Math.max(190, Math.min(264, this.maxWidth)))
    .alignItems(VerticalAlign.Center)
    .padding({ top: 2, bottom: 11, right: 30 });
  }
}
