import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

@Component
export struct GiveawayBubble {
  @Prop messageId: number = 0;
  @Prop state: string = '';
  @Prop winnerCount: number = 0;
  @Prop prize: string = '';
  @Prop description: string = '';
  @Prop selectionDate: number = 0;
  @Prop unclaimedCount: number = 0;
  @Prop originalMessageId: number = 0;
  @Prop boostedChatId: number = 0;
  @Prop refunded: boolean = false;
  @Prop onlyNewMembers: boolean = false;
  @Prop photoPath: string = '';
  @Prop maxWidth: number = 260;
  onOpenOriginal: (chatId: number, messageId: number) => void =
    (_chatId: number, _messageId: number): void => {};

  @Styles
  private normalStyle(): void {
    .scale({ x: 1, y: 1 })
    .opacity(1)
  }

  @Styles
  private pressedStyle(): void {
    .scale({ x: 0.98, y: 0.98 })
    .opacity(0.76)
  }

  private title(): string {
    if (this.refunded) {
      return '抽奖已取消';
    }
    if (this.state === 'active') {
      return '频道抽奖';
    }
    if (this.state === 'prize') {
      return '你获得了抽奖奖品';
    }
    return this.state === 'winners' ? '抽奖结果' : '抽奖已结束';
  }

  private statusText(): string {
    if (this.refunded) {
      return '奖品已全额退回';
    }
    if (this.state === 'active') {
      return this.selectionDate > 0 ? `${this.dateText()} 开奖` : '等待开奖';
    }
    if (this.state === 'prize') {
      return this.description.trim() !== '' ? this.description : '奖品已到账';
    }
    return `${Math.max(0, this.winnerCount)} 位获奖者`;
  }

  private dateText(): string {
    if (this.selectionDate <= 0) {
      return '';
    }
    const date = new Date(this.selectionDate * 1000);
    const month = date.getMonth() + 1;
    const day = date.getDate();
    const hour = date.getHours().toString().padStart(2, '0');
    const minute = date.getMinutes().toString().padStart(2, '0');
    return `${month}月${day}日 ${hour}:${minute}`;
  }

  build() {
    Column({ space: 9 }) {
      Stack() {
        Column()
          .width('100%').height('100%')
          .linearGradient({
            angle: 135,
            colors: [[this.refunded ? '#E2E5E9' : '#DDEBFF', 0],
              [this.refunded ? '#F5F6F7' : '#F3E7FF', 1]]
          });
        if (this.photoPath !== '') {
          Image(this.photoPath.startsWith('/') ? `file://${this.photoPath}` : this.photoPath)
            .width(104).height(104).objectFit(ImageFit.Contain);
        } else {
          Text(this.state === 'prize' ? '🏆' : (this.refunded ? '↩️' : '🎉'))
            .fontSize(52);
        }
        Row({ space: 5 }) {
          SymbolGlyph($r(this.state === 'active'
            ? 'sys.symbol.clock_fill' : 'sys.symbol.checkmark_seal_fill'))
            .fontSize(11).fontColor([this.refunded ? '#8C96A1' : COLOR_PRIMARY]);
          Text(this.statusText()).fontSize(10.5)
            .fontColor(this.refunded ? '#8C96A1' : COLOR_PRIMARY);
        }
        .padding({ left: 7, right: 7, top: 4, bottom: 4 })
        .backgroundColor('#DFFFFFFF').borderRadius(9)
        .position({ x: 9, y: 94 });
      }
      .width('100%').height(126)
      .borderRadius(12).clip(true);
      Text(this.title())
        .fontSize(15).fontWeight(FontWeight.Medium)
        .fontColor(this.refunded ? COLOR_TEXT_SECONDARY : COLOR_TEXT_PRIMARY);
      Text(this.prize.trim() !== '' ? this.prize : '奖品信息暂不可用')
        .fontSize(13).fontWeight(FontWeight.Medium)
        .fontColor(this.refunded ? COLOR_TEXT_SECONDARY : '#7B57C7')
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis });
      if (this.description.trim() !== '' && this.state !== 'prize') {
        Text(this.description).fontSize(11.5).lineHeight(16).fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      Row({ space: 10 }) {
        if (this.winnerCount > 0) {
          Text(`${this.winnerCount} 位获奖者`)
            .fontSize(10.5).fontColor(COLOR_TEXT_SECONDARY);
        }
        if (this.onlyNewMembers) {
          Text('仅限新成员').fontSize(10.5).fontColor(COLOR_TEXT_SECONDARY);
        }
        if (this.unclaimedCount > 0) {
          Text(`${this.unclaimedCount} 份未领取`)
            .fontSize(10.5).fontColor('#B06A32');
        }
      }.width('100%');
      if (this.originalMessageId > 0) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.arrow_up_right')).fontSize(13).fontColor([COLOR_PRIMARY]);
          Text('查看原抽奖').fontSize(12).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY);
        }
        .width('100%').height(34)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#123390EC').borderRadius(9)
        .stateStyles({
          normal: this.normalStyle,
          pressed: this.pressedStyle
        })
        .animation({ duration: 110, curve: Curve.EaseOut })
        .onClick((): void => {
          this.onOpenOriginal(this.boostedChatId, this.originalMessageId);
        });
      }
      Row().height(9).width('100%');
    }
    .width(Math.max(220, Math.min(278, this.maxWidth)))
    .alignItems(HorizontalAlign.Start)
    .accessibilityText(`${this.title()}，${this.prize}，${this.statusText()}`);
  }
}
