import { generateBarcode, scanCore } from '@kit.ScanKit';
import { image } from '@kit.ImageKit';
import {
  canReturnToPreviousTdAccount, getAuthService, returnToPreviousTdAccount
} from '../../tdkit/Globals';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

interface QrLoginStep {
  index: string;
  text: string;
}

const QR_STEPS: QrLoginStep[] = [
  { index: '1', text: '在手机上打开 Telegram' },
  { index: '2', text: '进入 设置 → 设备 → 关联桌面设备' },
  { index: '3', text: '扫描此二维码并确认登录' }
];

const QR_PIXEL_SIZE: number = 400;

@Preview
@Component
export struct QrLoginPage {
  @State link: string = '';
  @State code: image.PixelMap | null = null;
  @State failed: boolean = false;
  @State busy: boolean = false;
  @State errorText: string = '';
  private unsubscribeLink: (() => void) | null = null;
  private disposed: boolean = false;
  // TDLib 周期性刷新 token，二维码生成是异步的；用序号丢弃过期链接的迟到结果，
  // 避免旧二维码覆盖新二维码。
  private renderSeq: number = 0;

  aboutToAppear(): void {
    this.disposed = false;
    this.unsubscribeLink = getAuthService().onQrLinkChange((link: string): void => {
      if (this.disposed || link === this.link) { return; }
      this.link = link;
      this.renderCode(link);
    });
  }

  aboutToDisappear(): void {
    this.disposed = true;
    if (this.unsubscribeLink !== null) {
      this.unsubscribeLink();
      this.unsubscribeLink = null;
    }
  }

  private renderCode(link: string): void {
    if (link === '') {
      this.code = null;
      return;
    }
    this.renderSeq += 1;
    const seq: number = this.renderSeq;
    const options: generateBarcode.CreateOptions = {
      scanType: scanCore.ScanType.QR_CODE,
      height: QR_PIXEL_SIZE,
      width: QR_PIXEL_SIZE
    };
    generateBarcode.createBarcode(link, options).then((pixels: image.PixelMap): void => {
      if (this.disposed || seq !== this.renderSeq) { return; }
      this.code = pixels;
      this.failed = false;
    }).catch((caught: Object): void => {
      console.error(`QrLoginPage.createBarcode failed: ${JSON.stringify(caught)}`);
      if (this.disposed || seq !== this.renderSeq) { return; }
      this.failed = true;
    });
  }

  private switchToPhoneLogin(): void {
    if (this.busy) { return; }
    getAuthService().switchToPhoneLogin();
  }

  private returnToOriginalAccount(): void {
    this.busy = true;
    returnToPreviousTdAccount().catch((caught: Error): void => {
      this.errorText = caught.message;
      this.busy = false;
    });
  }

  @Builder
  qrSurface() {
    // 白底保证深色模式下二维码依然可被扫描。
    Column() {
      if (this.code !== null) {
        Image(this.code).width(212).height(212).interpolation(ImageInterpolation.None);
      } else if (this.failed) {
        Text('二维码生成失败，请改用手机号登录')
          .fontSize(14).fontColor('#FF3B30')
          .width(212).height(212).textAlign(TextAlign.Center);
      } else {
        Column() {
          LoadingProgress().width(34).height(34).color(COLOR_TEXT_SECONDARY);
        }.width(212).height(212).justifyContent(FlexAlign.Center);
      }
    }
    .backgroundColor(Color.White)
    .padding(14)
    .borderRadius(18);
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Text('扫码登录')
          .fontSize(27).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
        Text('用另一台已登录 Telegram 的设备扫描下方二维码，即可直接登录本机。')
          .fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
          .textAlign(TextAlign.Center).lineHeight(21)
          .padding({ left: 18, right: 18 });

        this.qrSurface();

        Column({ space: 12 }) {
          ForEach(QR_STEPS, (step: QrLoginStep) => {
            Row({ space: 12 }) {
              Text(step.index)
                .fontSize(14).fontWeight(FontWeight.Medium).fontColor(Color.White)
                .width(24).height(24).textAlign(TextAlign.Center)
                .backgroundColor(COLOR_PRIMARY).borderRadius(12);
              Text(step.text)
                .fontSize(15).fontColor(COLOR_TEXT_PRIMARY)
                .layoutWeight(1);
            }
            .width('100%')
            .alignItems(VerticalAlign.Center);
          }, (step: QrLoginStep): string => step.index);
        }
        .width('100%')
        .padding(16)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(14)
        .alignItems(HorizontalAlign.Start);

        if (this.errorText !== '') {
          Text(this.errorText)
            .width('100%').fontSize(13).fontColor('#FF3B30')
            .padding({ left: 4, right: 4 });
        }

        Button('改用手机号登录')
          .width('100%').height(50)
          .fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor(COLOR_PRIMARY)
          .backgroundColor(Color.Transparent)
          .enabled(!this.busy)
          .onClick((): void => this.switchToPhoneLogin());

        if (canReturnToPreviousTdAccount()) {
          Button('返回原账号')
            .width('100%').height(45)
            .fontColor(COLOR_TEXT_SECONDARY)
            .backgroundColor(Color.Transparent)
            .enabled(!this.busy)
            .onClick((): void => this.returnToOriginalAccount());
        }
      }
      .width('100%')
      .constraintSize({ maxWidth: 430 })
      .padding({ left: 24, right: 24, top: 28, bottom: 28 });
    }
    .width('100%').height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .backgroundColor($r('app.color.page_bg'));
  }
}
