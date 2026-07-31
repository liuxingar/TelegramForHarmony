import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

@Component
export struct DiceBubble {
  @Prop emoji: string = '🎲';
  @Prop value: number = 0;
  @Prop hasFinalState: boolean = false;
  @Prop successFrame: number = 0;
  @State turn: number = 0;
  @State pulse: number = 1;

  @Styles
  private normalStyle(): void {
    .scale({ x: 1, y: 1 })
    .opacity(1)
  }

  @Styles
  private pressedStyle(): void {
    .scale({ x: 0.96, y: 0.96 })
    .opacity(0.8)
  }

  private safeEmoji(): string {
    return this.emoji.trim() !== '' ? this.emoji : '🎲';
  }

  private replay(): void {
    animateTo({ duration: 150, curve: Curve.EaseOut }, (): void => {
      this.turn += 22;
      this.pulse = 0.84;
    });
    setTimeout((): void => {
      animateTo({ duration: 260, curve: Curve.Friction }, (): void => {
        this.turn += 338;
        this.pulse = 1;
      });
    }, 150);
  }

  private resultText(): string {
    if (!this.hasFinalState || this.value <= 0) {
      return '等待服务器生成结果';
    }
    return `结果 ${this.value}`;
  }

  build() {
    Row({ space: 11 }) {
      Stack() {
        Circle({ width: 66, height: 66 })
          .fill('#0F3390EC')
          .stroke('#183390EC')
          .strokeWidth(1);
        Text(this.safeEmoji())
          .fontSize(46)
          .rotate({ angle: this.turn })
          .scale({ x: this.pulse, y: this.pulse })
          .animation({ duration: 180, curve: Curve.EaseOut });
        if (!this.hasFinalState || this.value <= 0) {
          LoadingProgress().width(18).height(18).color(COLOR_PRIMARY)
            .backgroundColor('#EFFFFFFF').borderRadius(10).padding(2)
            .position({ x: 46, y: 46 });
        }
      }.width(68).height(68);

      Column({ space: 4 }) {
        Text(this.resultText())
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.hasFinalState && this.value > 0
            ? COLOR_TEXT_PRIMARY : COLOR_TEXT_SECONDARY)
          .maxLines(2);
        Text(this.hasFinalState && this.value > 0 ? '点击重播动效' : '结果会自动更新')
          .fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start);
    }
    .width(190)
    .padding({ right: 32, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .stateStyles({
      normal: this.normalStyle,
      pressed: this.pressedStyle
    })
    .animation({ duration: 105, curve: Curve.EaseOut })
    .accessibilityText(`${this.safeEmoji()}，${this.resultText()}`)
    .onClick((): void => { this.replay(); });
  }
}
