import {
  canReturnToPreviousTdAccount, getAuthService, returnToPreviousTdAccount
} from '../../tdkit/Globals';
import { TdError } from '../../tdkit/TdTypes';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { LoginHero } from './LoginHero';

// 号码尚未注册 Telegram 时走到这里（authorizationStateWaitRegistration）。
// 此前没有这个页面，该状态映射不到任何 stage，界面会停在验证码页毫无反应 ——
// 用户只会觉得"验证码输对了但没下文"。
//
// 服务条款必须展示并显式同意：它是 Telegram 注册流程的一部分，不是可选的礼貌。
@Preview
@Component
export struct RegisterPage {
  @State firstName: string = '';
  @State lastName: string = '';
  @State termsText: string = '';
  @State minUserAge: number = 0;
  @State agreed: boolean = false;
  @State errorText: string = '';
  @State busy: boolean = false;

  aboutToAppear(): void {
    const auth = getAuthService();
    this.termsText = auth.getTermsOfServiceText();
    this.minUserAge = auth.getTermsMinUserAge();
  }

  private canSubmit(): boolean {
    return !this.busy && this.firstName.trim() !== '' && this.agreed;
  }

  private submit(): void {
    if (!this.canSubmit()) { return; }
    this.busy = true;
    this.errorText = '';
    getAuthService().registerUser(this.firstName.trim(), this.lastName.trim())
      .catch((caught: TdError): void => {
        this.errorText = caught.message;
      })
      .finally((): void => {
        this.busy = false;
      });
  }

  private agreementLabel(): string {
    return this.minUserAge > 0
      ? `我已阅读并同意服务条款，且已年满 ${this.minUserAge} 周岁`
      : '我已阅读并同意服务条款';
  }

  @Builder
  private nameField(placeholder: string, value: string, required: boolean,
    onInput: (v: string) => void) {
    TextInput({ text: value, placeholder: placeholder })
      .fontSize(17).fontColor(COLOR_TEXT_PRIMARY)
      .placeholderColor(COLOR_TEXT_SECONDARY)
      .caretColor(COLOR_PRIMARY)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(13)
      .border({
        width: 1,
        color: required && this.errorText !== '' ? '#FF3B30' : '#263390EC'
      })
      .width('100%').height(54)
      .padding({ left: 14, right: 12 })
      .enterKeyType(EnterKeyType.Next)
      .onChange((v: string): void => {
        onInput(v);
        this.errorText = '';
      });
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        LoginHero({ mode: 'phone', active: this.firstName !== '' });

        Text('创建账号')
          .fontSize(27).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
        Text('这个号码还没有 Telegram 账号。填写姓名即可创建。')
          .fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
          .textAlign(TextAlign.Center).lineHeight(21)
          .padding({ left: 18, right: 18 });

        this.nameField('名字（必填）', this.firstName, true,
          (v: string): void => { this.firstName = v; });
        this.nameField('姓氏（可选）', this.lastName, false,
          (v: string): void => { this.lastName = v; });

        if (this.termsText !== '') {
          Scroll() {
            Text(this.termsText)
              .fontSize(12.5).fontColor(COLOR_TEXT_SECONDARY).lineHeight(19)
              .width('100%');
          }
          .width('100%').height(160)
          .padding(12)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(13)
          .scrollBar(BarState.Auto)
          .align(Alignment.Top);
        }

        Row({ space: 10 }) {
          Checkbox()
            .select(this.agreed)
            .selectedColor(COLOR_PRIMARY)
            .onChange((checked: boolean): void => { this.agreed = checked; });
          Text(this.agreementLabel())
            .fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
            .layoutWeight(1);
        }
        .width('100%')
        .alignItems(VerticalAlign.Center);

        if (this.errorText !== '') {
          Text(this.errorText)
            .width('100%').fontSize(13).fontColor('#FF3B30')
            .padding({ left: 4, right: 4 });
        }

        Button(this.busy ? '正在创建…' : '创建账号')
          .width('100%').height(50)
          .fontSize(16).fontWeight(FontWeight.Medium)
          .backgroundColor(COLOR_PRIMARY).borderRadius(14)
          .enabled(this.canSubmit())
          .onClick((): void => this.submit());

        if (canReturnToPreviousTdAccount()) {
          Button('返回原账号')
            .width('100%').height(45)
            .fontColor(COLOR_TEXT_SECONDARY)
            .backgroundColor(Color.Transparent)
            .enabled(!this.busy)
            .onClick((): void => {
              this.busy = true;
              returnToPreviousTdAccount().catch((caught: Error): void => {
                this.errorText = caught.message;
                this.busy = false;
              });
            });
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
