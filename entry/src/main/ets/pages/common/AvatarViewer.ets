const MIN_SCALE: number = 1;
const MAX_SCALE: number = 4;

// 头像点击放大：全屏黑底查看器，支持双指缩放、拖动、双击切换、下滑关闭。
// 独立于聊天页的媒体查看器 —— 那个和消息列表/相册强耦合，头像只需要
// 单张静态图，复用它会把整套消息态一起拖进资料页。
@Component
export struct AvatarViewer {
  @Prop imagePath: string;
  onClose: () => void = (): void => {};
  @State private zoom: number = MIN_SCALE;
  @State private offsetX: number = 0;
  @State private offsetY: number = 0;
  @State private closing: boolean = false;
  // 手势起始基准：pinch/pan 的增量都相对手势开始时的值，避免累积漂移。
  private baseScale: number = MIN_SCALE;
  private baseOffsetX: number = 0;
  private baseOffsetY: number = 0;

  private clampScale(value: number): number {
    return Math.min(MAX_SCALE, Math.max(MIN_SCALE, value));
  }

  private resetTransform(): void {
    this.zoom = MIN_SCALE;
    this.offsetX = 0;
    this.offsetY = 0;
  }

  private imageSource(): string {
    return this.imagePath.startsWith('/') ? `file://${this.imagePath}` : this.imagePath;
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column()
        .width('100%').height('100%')
        .backgroundColor(Color.Black)
        // 未放大时下滑关闭；放大后该手势让位给拖动。
        .opacity(this.closing ? 0 : 1);
      Image(this.imageSource())
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Contain)
        .scale({ x: this.zoom, y: this.zoom })
        .translate({ x: this.offsetX, y: this.offsetY })
        .animation({ duration: 160, curve: Curve.EaseOut })
        .gesture(
          GestureGroup(GestureMode.Parallel,
            PinchGesture({ fingers: 2 })
              .onActionStart((): void => {
                this.baseScale = this.zoom;
              })
              .onActionUpdate((event: GestureEvent): void => {
                this.zoom = this.clampScale(this.baseScale * event.scale);
              })
              .onActionEnd((): void => {
                if (this.zoom <= MIN_SCALE + 0.01) {
                  this.resetTransform();
                }
              }),
            PanGesture({ fingers: 1 })
              .onActionStart((): void => {
                this.baseOffsetX = this.offsetX;
                this.baseOffsetY = this.offsetY;
              })
              .onActionUpdate((event: GestureEvent): void => {
                if (this.zoom > MIN_SCALE + 0.01) {
                  this.offsetX = this.baseOffsetX + event.offsetX;
                  this.offsetY = this.baseOffsetY + event.offsetY;
                  return;
                }
                // 原始比例下只跟随竖直位移，作为下滑关闭的视觉反馈。
                this.offsetY = this.baseOffsetY + Math.max(0, event.offsetY);
              })
              .onActionEnd((): void => {
                if (this.zoom <= MIN_SCALE + 0.01 && this.offsetY > 120) {
                  this.closing = true;
                  this.onClose();
                  return;
                }
                if (this.zoom <= MIN_SCALE + 0.01) {
                  this.resetTransform();
                }
              })
          )
        );
      // 双击缩放：与单击关闭互斥，单击需等双击判定窗口过去。
      Column()
        .width('100%').height('100%')
        .backgroundColor(Color.Transparent)
        .hitTestBehavior(HitTestMode.Transparent)
        .gesture(
          GestureGroup(GestureMode.Exclusive,
            TapGesture({ count: 2 })
              .onAction((): void => {
                if (this.zoom > MIN_SCALE + 0.01) {
                  this.resetTransform();
                } else {
                  this.zoom = 2.5;
                }
              }),
            TapGesture({ count: 1 })
              .onAction((): void => {
                if (this.zoom > MIN_SCALE + 0.01) {
                  this.resetTransform();
                  return;
                }
                this.onClose();
              })
          )
        );
      Row() {
        SymbolGlyph($r('sys.symbol.xmark')).fontSize(22).fontColor([Color.White]);
      }
      .width(40).height(40).borderRadius(20)
      .backgroundColor('#4D000000')
      .justifyContent(FlexAlign.Center)
      .margin({ top: 12, right: 12 })
      .onClick((): void => this.onClose());
    }
    .width('100%').height('100%');
  }
}
