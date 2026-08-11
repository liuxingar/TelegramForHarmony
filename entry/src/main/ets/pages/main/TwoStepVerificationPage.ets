import { router, promptAction } from '@kit.ArkUI';
import { TdError, TdObject } from '../../tdkit/TdTypes';
import {
  cancelRecoveryEmailVerification, checkRecoveryEmailCode, getPasswordState,
  recoverPassword, requestPasswordRecovery, resendRecoveryEmailCode, setPassword, setRecoveryEmail
} from '../../store/PrivacyApi';
import {
  COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE,
  COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';

const CARD_RADIUS: number = 16;
const COLOR_DANGER: string = '#E5484D';

@Entry
@Component
struct TwoStepVerificationPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State loadState: string = 'loading';
  @State passwordState: TdObject | null = null;
  @State mode: string = 'password';
  @State oldPassword: string = '';
  @State newPassword: string = '';
  @State confirmPassword: string = '';
  @State hint: string = '';
  @State recoveryEmail: string = '';
  @State code: string = '';
  @State errorText: string = '';
  @State saving: boolean = false;
  @State revealPassword: boolean = false;
  @State recoveryPattern: string = '';
  private active: boolean = false;
  private sequence: number = 0;

  aboutToAppear(): void {
    this.active = true;
    this.load();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.sequence++;
    this.oldPassword = '';
    this.newPassword = '';
    this.confirmPassword = '';
  }

  private load(): void {
    const sequence = ++this.sequence;
    this.loadState = 'loading';
    getPasswordState().then((state: TdObject): void => {
      if (!this.active || sequence !== this.sequence) { return; }
      this.passwordState = state;
      this.hint = (state['password_hint'] as string | undefined) ?? '';
      this.loadState = 'ready';
      this.errorText = '';
    }).catch((error: TdError): void => {
      if (!this.active || sequence !== this.sequence) { return; }
      console.error(`TwoStepVerificationPage.load failed: ${error.message}`);
      this.loadState = 'error';
    });
  }

  private hasPassword(): boolean {
    return this.passwordState !== null &&
      ((this.passwordState['has_password'] as boolean | undefined) ?? false);
  }

  private pendingEmailInfo(): TdObject | null {
    if (this.passwordState === null) { return null; }
    return (this.passwordState['recovery_email_address_code_info'] as TdObject | undefined) ?? null;
  }

  private clearSensitive(): void {
    this.oldPassword = '';
    this.newPassword = '';
    this.confirmPassword = '';
    this.code = '';
  }

  private friendlyError(error: TdError): string {
    const message = error.message.toUpperCase();
    if (message.indexOf('PASSWORD_HASH_INVALID') >= 0) { return '当前密码不正确'; }
    if (message.indexOf('PASSWORD_TOO_FRESH') >= 0) { return '密码设置时间太短，请稍后再试'; }
    if (message.indexOf('NEW_PASSWORD_BAD') >= 0) { return '新密码不符合要求，请提高复杂度'; }
    if (message.indexOf('EMAIL_INVALID') >= 0) { return '恢复邮箱格式不正确'; }
    if (message.indexOf('CODE_INVALID') >= 0) { return '验证码不正确'; }
    if (message.indexOf('FLOOD_WAIT') >= 0) { return '操作过于频繁，请稍后再试'; }
    return '保存失败，请检查网络后重试';
  }

  private validatePasswordForm(): boolean {
    this.errorText = '';
    if (this.hasPassword() && this.oldPassword.length === 0) {
      this.errorText = '请输入当前密码'; return false;
    }
    if (this.newPassword.length < 4) {
      this.errorText = '新密码至少需要 4 个字符'; return false;
    }
    if (this.newPassword !== this.confirmPassword) {
      this.errorText = '两次输入的新密码不一致'; return false;
    }
    if (this.hint !== '' && this.hint === this.newPassword) {
      this.errorText = '密码提示不能与密码相同'; return false;
    }
    return true;
  }

  private savePassword(): void {
    if (this.saving || !this.validatePasswordForm()) { return; }
    const wasEnabled = this.hasPassword();
    this.saving = true;
    const setEmail = !wasEnabled && this.recoveryEmail.trim() !== '';
    setPassword(this.oldPassword, this.newPassword, this.hint.trim(), setEmail,
      this.recoveryEmail.trim()).then((state: TdObject): void => {
      if (!this.active) { return; }
      this.passwordState = state;
      this.saving = false;
      this.clearSensitive();
      promptAction.showToast({ message: wasEnabled ? '两步验证已更新' : '两步验证已开启', duration: 1600 });
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.saving = false;
      this.errorText = this.friendlyError(error);
    });
  }

  private beginRecovery(): void {
    if (this.saving) { return; }
    const hasEmail = this.passwordState !== null &&
      ((this.passwordState['has_recovery_email_address'] as boolean | undefined) ?? false);
    if (!hasEmail) {
      this.errorText = '当前账号没有设置恢复邮箱，无法通过邮箱重置密码';
      return;
    }
    this.saving = true;
    requestPasswordRecovery().then((info: TdObject): void => {
      if (!this.active) { return; }
      this.recoveryPattern = (info['email_address_pattern'] as string | undefined) ?? '恢复邮箱';
      this.mode = 'recover';
      this.code = '';
      this.newPassword = '';
      this.confirmPassword = '';
      this.errorText = '';
      this.saving = false;
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.saving = false;
      this.errorText = this.friendlyError(error);
    });
  }

  private finishRecovery(): void {
    if (this.saving) { return; }
    this.errorText = '';
    if (this.code.trim() === '') { this.errorText = '请输入邮箱验证码'; return; }
    if (this.newPassword.length < 4) { this.errorText = '新密码至少需要 4 个字符'; return; }
    if (this.newPassword !== this.confirmPassword) { this.errorText = '两次输入的新密码不一致'; return; }
    this.saving = true;
    recoverPassword(this.code.trim(), this.newPassword, this.hint.trim()).then((state: TdObject): void => {
      if (!this.active) { return; }
      this.passwordState = state;
      this.mode = 'password';
      this.recoveryPattern = '';
      this.saving = false;
      this.clearSensitive();
      promptAction.showToast({ message: '密码已通过恢复邮箱重置', duration: 1700 });
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.saving = false;
      this.errorText = this.friendlyError(error);
    });
  }

  private saveEmail(): void {
    if (this.saving) { return; }
    this.errorText = '';
    if (this.oldPassword === '') { this.errorText = '请输入当前密码'; return; }
    if (this.recoveryEmail.trim().indexOf('@') <= 0) { this.errorText = '请输入有效的恢复邮箱'; return; }
    this.saving = true;
    setRecoveryEmail(this.oldPassword, this.recoveryEmail.trim()).then((state: TdObject): void => {
      if (!this.active) { return; }
      this.passwordState = state;
      this.saving = false;
      this.oldPassword = '';
      this.recoveryEmail = '';
      this.errorText = '';
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.saving = false;
      this.errorText = this.friendlyError(error);
    });
  }

  private verifyEmail(): void {
    if (this.saving || this.code.trim() === '') { return; }
    this.saving = true;
    checkRecoveryEmailCode(this.code.trim()).then((state: TdObject): void => {
      if (!this.active) { return; }
      this.passwordState = state;
      this.saving = false;
      this.code = '';
      promptAction.showToast({ message: '恢复邮箱已确认', duration: 1500 });
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.saving = false;
      this.errorText = this.friendlyError(error);
    });
  }

  private resendCode(): void {
    if (this.saving) { return; }
    this.saving = true;
    resendRecoveryEmailCode().then((state: TdObject): void => {
      if (!this.active) { return; }
      this.passwordState = state;
      this.saving = false;
      promptAction.showToast({ message: '验证码已重新发送', duration: 1500 });
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.saving = false;
      this.errorText = this.friendlyError(error);
    });
  }

  private cancelEmail(): void {
    if (this.saving) { return; }
    this.saving = true;
    cancelRecoveryEmailVerification().then((state: TdObject): void => {
      if (!this.active) { return; }
      this.passwordState = state;
      this.saving = false;
      this.code = '';
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.saving = false;
      this.errorText = this.friendlyError(error);
    });
  }

  private confirmDisable(): void {
    if (this.saving) { return; }
    if (this.oldPassword === '') { this.errorText = '请输入当前密码后再关闭'; return; }
    promptAction.showDialog({
      title: '关闭两步验证',
      message: '关闭后，仅凭登录验证码即可登录你的账号，账号保护会明显减弱。',
      buttons: [
        { text: '取消', color: COLOR_TEXT_SECONDARY as string },
        { text: '关闭', color: COLOR_DANGER }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (!this.active || result.index !== 1 || this.saving) { return; }
      this.saving = true;
      setPassword(this.oldPassword, '', '', false, '').then((state: TdObject): void => {
        if (!this.active) { return; }
        this.passwordState = state;
        this.saving = false;
        this.clearSensitive();
        this.mode = 'password';
        promptAction.showToast({ message: '两步验证已关闭', duration: 1600 });
      }).catch((error: TdError): void => {
        if (!this.active) { return; }
        this.saving = false;
        this.errorText = this.friendlyError(error);
      });
    }).catch((): void => {});
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([COLOR_TEXT_PRIMARY]);
      }.width(40).height(40).borderRadius(20).backgroundColor(Color.Transparent)
      .onClick((): void => { router.back(); });
      Text('两步验证').fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
      if (this.saving) { LoadingProgress().width(21).height(21).color(COLOR_PRIMARY); }
    }.width('100%').height(52).padding({ left: 8, right: 16 }).alignItems(VerticalAlign.Center);
  }

  @Builder
  passwordInput(value: string, placeholder: string, onChange: (value: string) => void) {
    TextInput({ text: value, placeholder })
      .type(this.revealPassword ? InputType.Normal : InputType.Password)
      .height(48).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).placeholderColor(COLOR_TEXT_SECONDARY)
      .caretColor(COLOR_PRIMARY).backgroundColor($r('app.color.surface_alt')).borderRadius(12)
      .padding({ left: 14, right: 14 }).enabled(!this.saving)
      .onChange((text: string): void => { onChange(text); this.errorText = ''; });
  }

  @Builder
  pendingEmailCard(info: TdObject) {
    Column({ space: 12 }) {
      Text('确认恢复邮箱').fontSize(18).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
        .width('100%');
      Text(`验证码已发送至 ${(info['email_address_pattern'] as string | undefined) ?? '你的邮箱'}。完成确认前，密码修改不会全部生效。`)
        .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).lineHeight(19).width('100%');
      TextInput({ text: this.code, placeholder: '邮箱验证码' })
        .type(InputType.Number).height(48).fontSize(17).caretColor(COLOR_PRIMARY)
        .backgroundColor($r('app.color.surface_alt')).borderRadius(12).padding({ left: 14, right: 14 })
        .onChange((value: string): void => { this.code = value; this.errorText = ''; });
      Button(this.saving ? '验证中…' : '确认邮箱').width('100%').height(46).borderRadius(23)
        .fontColor(Color.White).backgroundColor(COLOR_PRIMARY).enabled(!this.saving && this.code.trim() !== '')
        .onClick((): void => { this.verifyEmail(); });
      Row() {
        Text('重新发送').fontSize(14).fontColor(COLOR_PRIMARY).onClick((): void => { this.resendCode(); });
        Blank();
        Text('取消更改').fontSize(14).fontColor(COLOR_DANGER).onClick((): void => { this.cancelEmail(); });
      }.width('100%');
    }
    .width('100%').padding(16).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  @Builder
  modePicker() {
    Row() {
      ForEach(['password', 'email', 'disable'], (mode: string) => {
        Text(mode === 'password' ? '更改密码' : (mode === 'email' ? '恢复邮箱' : '关闭'))
          .fontSize(14).fontWeight(this.mode === mode ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.mode === mode ? Color.White : COLOR_TEXT_SECONDARY)
          .textAlign(TextAlign.Center).layoutWeight(1).height(36)
          .backgroundColor(this.mode === mode ? COLOR_PRIMARY : Color.Transparent)
          .borderRadius(18).onClick((): void => { if (!this.saving) { this.mode = mode; this.errorText = ''; } });
      }, (mode: string): string => `password_mode_${mode}_${this.mode}`);
    }
    .width('100%').padding(3).backgroundColor($r('app.color.surface_alt')).borderRadius(21);
  }

  build() {
    Column() {
      this.header();
      if (this.loadState === 'loading') {
        Column() { LoadingProgress().width(34).height(34).color(COLOR_PRIMARY); }
          .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.loadState === 'error') {
        Column({ space: 10 }) {
          Text('两步验证状态加载失败').fontSize(17).fontColor(COLOR_TEXT_PRIMARY);
          Button('重新加载').onClick((): void => { this.load(); });
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else {
        Scroll() {
          Column({ space: 12 }) {
            if (this.pendingEmailInfo() !== null) {
              this.pendingEmailCard(this.pendingEmailInfo() as TdObject);
            }

            Column({ space: 8 }) {
              SymbolGlyph($r(this.hasPassword() ? 'sys.symbol.lock_fill' : 'sys.symbol.lock_open_fill'))
                .fontSize(48).fontColor([this.hasPassword() ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY]);
              Text(this.hasPassword() ? '两步验证已开启' : '保护你的登录安全')
                .fontSize(20).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
              Text(this.hasPassword()
                ? '新设备登录时，除了验证码还需要输入你的密码。'
                : '设置额外密码后，即使验证码泄露，其他人也无法直接登录。')
                .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).lineHeight(19).textAlign(TextAlign.Center);
            }
            .width('100%').padding({ left: 22, right: 22, top: 18, bottom: 18 })
            .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);

            if (this.hasPassword() && this.mode !== 'recover') { this.modePicker(); }

            Column({ space: 11 }) {
              if (this.hasPassword() && this.mode !== 'recover') {
                Text('当前密码').fontSize(13).fontColor(COLOR_TEXT_SECONDARY).width('100%');
                this.passwordInput(this.oldPassword, '输入当前密码', (value: string): void => { this.oldPassword = value; });
                if (this.mode !== 'disable') {
                  Text('忘记密码？使用恢复邮箱重置').fontSize(13).fontColor(COLOR_PRIMARY)
                    .width('100%').textAlign(TextAlign.End)
                    .onClick((): void => { this.beginRecovery(); });
                }
              }

              if (this.mode === 'recover') {
                Text(`验证码已发送至 ${this.recoveryPattern}`).fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY).width('100%');
                TextInput({ text: this.code, placeholder: '邮箱验证码' })
                  .type(InputType.Number).height(48).fontSize(17)
                  .backgroundColor($r('app.color.surface_alt')).borderRadius(12)
                  .padding({ left: 14, right: 14 }).enabled(!this.saving)
                  .onChange((value: string): void => { this.code = value; this.errorText = ''; });
                this.passwordInput(this.newPassword, '设置新密码', (value: string): void => { this.newPassword = value; });
                this.passwordInput(this.confirmPassword, '再次输入新密码',
                  (value: string): void => { this.confirmPassword = value; });
                TextInput({ text: this.hint, placeholder: '新密码提示（选填）' })
                  .height(48).fontSize(16).backgroundColor($r('app.color.surface_alt')).borderRadius(12)
                  .padding({ left: 14, right: 14 }).enabled(!this.saving)
                  .onChange((value: string): void => { this.hint = value; this.errorText = ''; });
              } else if (!this.hasPassword() || this.mode === 'password') {
                Text(this.hasPassword() ? '新密码' : '设置密码').fontSize(13).fontColor(COLOR_TEXT_SECONDARY).width('100%');
                this.passwordInput(this.newPassword, '至少 4 个字符', (value: string): void => { this.newPassword = value; });
                this.passwordInput(this.confirmPassword, '再次输入新密码',
                  (value: string): void => { this.confirmPassword = value; });
                TextInput({ text: this.hint, placeholder: '密码提示（选填）' })
                  .height(48).fontSize(16).backgroundColor($r('app.color.surface_alt')).borderRadius(12)
                  .padding({ left: 14, right: 14 }).enabled(!this.saving)
                  .onChange((value: string): void => { this.hint = value; this.errorText = ''; });
                if (!this.hasPassword()) {
                  TextInput({ text: this.recoveryEmail, placeholder: '恢复邮箱（推荐）' })
                    .type(InputType.Email).height(48).fontSize(16)
                    .backgroundColor($r('app.color.surface_alt')).borderRadius(12)
                    .padding({ left: 14, right: 14 }).enabled(!this.saving)
                    .onChange((value: string): void => { this.recoveryEmail = value; this.errorText = ''; });
                }
              } else if (this.mode === 'email') {
                Text('恢复邮箱').fontSize(13).fontColor(COLOR_TEXT_SECONDARY).width('100%');
                TextInput({ text: this.recoveryEmail, placeholder: 'name@example.com' })
                  .type(InputType.Email).height(48).fontSize(16)
                  .backgroundColor($r('app.color.surface_alt')).borderRadius(12)
                  .padding({ left: 14, right: 14 }).enabled(!this.saving)
                  .onChange((value: string): void => { this.recoveryEmail = value; this.errorText = ''; });
              } else {
                Text('输入当前密码后，可关闭两步验证。关闭后账号将只受登录验证码保护。')
                  .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).lineHeight(19).width('100%');
              }

              Row() {
                Text('显示密码').fontSize(14).fontColor(COLOR_TEXT_SECONDARY).layoutWeight(1);
                Toggle({ type: ToggleType.Switch, isOn: this.revealPassword }).selectedColor(COLOR_PRIMARY)
                  .onChange((value: boolean): void => { this.revealPassword = value; });
              }.width('100%').height(42);

              if (this.errorText !== '') {
                Text(this.errorText).fontSize(13).fontColor(COLOR_DANGER).width('100%');
              }

              Button(this.saving ? '正在保存…' :
                (this.mode === 'recover' ? '重置密码' : (!this.hasPassword() ? '开启两步验证' :
                  (this.mode === 'password' ? '保存新密码' : (this.mode === 'email' ? '更新恢复邮箱' : '关闭两步验证')))))
                .width('100%').height(48).borderRadius(24).fontSize(16).fontWeight(FontWeight.Medium)
                .fontColor(Color.White).backgroundColor(this.mode === 'disable' ? COLOR_DANGER : COLOR_PRIMARY)
                .enabled(!this.saving)
                .onClick((): void => {
                  if (this.mode === 'recover') { this.finishRecovery(); }
                  else if (!this.hasPassword() || this.mode === 'password') { this.savePassword(); }
                  else if (this.mode === 'email') { this.saveEmail(); }
                  else { this.confirmDisable(); }
                });
            }
            .width('100%').padding(16).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
            .alignItems(HorizontalAlign.Start);

            Text('密码只会发送给 Telegram 进行验证，页面离开后会立即清除输入内容。请务必设置可访问的恢复邮箱。')
              .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(18)
              .width('100%').padding({ left: 16, right: 16 });
          }
          .width('100%').padding({ left: 12, right: 12, top: 6, bottom: this.bottomSafe + 24 });
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
      }
    }
    .width('100%').height('100%').backgroundColor(COLOR_PAGE_BG)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.topSafe });
  }
}
