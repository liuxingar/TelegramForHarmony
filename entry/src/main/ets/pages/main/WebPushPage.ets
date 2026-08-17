import { router, promptAction } from '@kit.ArkUI';
import { TdError } from '../../tdkit/TdTypes';
import { getTdClient } from '../../tdkit/Globals';
import {
  COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import {
  KEY_WEBPUSH_ACCEPTED, KEY_WEBPUSH_AUTH, KEY_WEBPUSH_ENABLED, KEY_WEBPUSH_ENDPOINT,
  KEY_WEBPUSH_P256DH, setBoolean, setString
} from '../../store/AppSettings';
import {
  ParsedSubscription, SUBSCRIPTION_JSON_HINT, WebPushConfig, WebPushValidation,
  deregisterWebPush, parseSubscriptionJson, registerWebPush, validateWebPushConfig
} from '../../services/WebPushRegistration';
import { HuaweiPushResult, registerHuaweiPush } from '../../services/HuaweiPushRegistration';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';

const CARD_RADIUS: number = 14;

// 自定义 Web Push 中转通道的配置页。
//
// 这个功能默认关闭，且必须先读完风险说明才能启用 —— 它会把消息预览的明文交给
// 用户自建的服务器，属于「知情后自愿」的取舍，不能默默生效。
@Entry
@Component
struct WebPushPage {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageProp(KEY_WEBPUSH_ENABLED) pushEnabled: boolean = false;
  @StorageProp(KEY_WEBPUSH_ACCEPTED) accepted: boolean = false;
  @StorageProp(KEY_WEBPUSH_ENDPOINT) storedEndpoint: string = '';
  @StorageProp(KEY_WEBPUSH_P256DH) storedP256dh: string = '';
  @StorageProp(KEY_WEBPUSH_AUTH) storedAuth: string = '';
  // 草稿态：编辑中的值不立刻落盘，点「保存并注册」才写入并生效。
  @State endpoint: string = '';
  @State p256dh: string = '';
  @State auth: string = '';
  @State busy: boolean = false;
  @State statusText: string = '';
  @State statusOk: boolean = false;
  @State consentShown: boolean = false;
  @State jsonInput: string = '';
  @State jsonExpanded: boolean = false;
  // 华为 Push Kit 探针：验证 Telegram 服务器能否直接投递到 Push Kit 通道
  // （而不经过自建 Web Push 中转）。三行分别对应 token / registerDevice 结果 /
  // 失败时的错误码与文案，见 HuaweiPushRegistration.ets 顶部注释。
  @State hwBusy: boolean = false;
  @State hwTokenLine: string = '';
  @State hwResultLine: string = '';
  @State hwErrorLine: string = '';

  aboutToAppear(): void {
    this.endpoint = this.storedEndpoint;
    this.p256dh = this.storedP256dh;
    this.auth = this.storedAuth;
    if (this.pushEnabled && this.storedEndpoint !== '') {
      this.statusOk = true;
      this.statusText = str('wp_enabled');
    }
  }

  private currentConfig(): WebPushConfig {
    return { endpoint: this.endpoint, p256dh: this.p256dh, auth: this.auth };
  }

  private onToggle(next: boolean): void {
    if (!next) {
      this.disable();
      return;
    }
    if (!this.accepted) {
      // 未读过说明：先弹说明，开关保持关闭，接受后由 acceptConsent 打开。
      this.consentShown = true;
      return;
    }
    this.saveAndRegister();
  }

  private acceptConsent(): void {
    this.consentShown = false;
    setBoolean(KEY_WEBPUSH_ACCEPTED, true);
    this.saveAndRegister();
  }

  private disable(): void {
    setBoolean(KEY_WEBPUSH_ENABLED, false);
    this.statusOk = false;
    this.statusText = str('wp_disabled');
    deregisterWebPush(getTdClient());
  }

  private saveAndRegister(): void {
    if (this.busy) {
      return;
    }
    const config: WebPushConfig = this.currentConfig();
    const check: WebPushValidation = validateWebPushConfig(config);
    if (!check.valid) {
      this.statusOk = false;
      this.statusText = check.error;
      promptAction.showToast({ message: check.error, duration: 2000 });
      return;
    }
    this.busy = true;
    this.statusText = str('wp_registering');
    registerWebPush(getTdClient(), config).then((receiverId: string): void => {
      setString(KEY_WEBPUSH_ENDPOINT, config.endpoint.trim());
      setString(KEY_WEBPUSH_P256DH, config.p256dh.trim());
      setString(KEY_WEBPUSH_AUTH, config.auth.trim());
      setBoolean(KEY_WEBPUSH_ENABLED, true);
      this.statusOk = true;
      this.statusText = receiverId !== ''
        ? str('wp_registered_with_id', receiverId)
        : str('wp_registered_no_id');
      this.busy = false;
    }).catch((e: TdError): void => {
      // 注册失败不打开开关 —— 否则用户会以为通知已经生效。
      setBoolean(KEY_WEBPUSH_ENABLED, false);
      this.statusOk = false;
      this.statusText = str('wp_register_failed', e.message);
      this.busy = false;
    });
  }

  // 多行输入：endpoint 和两个 base64url 密钥都很长，单行框只能看到开头一小截，
  // 核对和排错都很难受。
  //
  // 三个字段各写一个无参 @Builder，且用 $$ 双向绑定。不能把值当参数传进
  // @Builder —— 值参数只在首次渲染时求值，之后任何一次重渲染（比如点「保存」
  // 时 busy 变化）都会把 TextArea 的 text 重置回捕获时的旧值，表现就是
  // "输入完保存后地址弹回上一个"。
  @Builder
  fieldLabel(label: ResourceStr) {
    Text(label).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
      .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 5 });
  }

  @Builder
  endpointField() {
    this.fieldLabel($r('app.string.wp_endpoint_label'));
    // 宽度交给外层 padding：width('100%') 再叠 margin 会超出父容器，
    // 表现为输入框两侧顶到卡片边缘。
    Row() {
      TextArea({ text: $$this.endpoint, placeholder: $r('app.string.wp_endpoint_hint') })
        .fontSize(13).layoutWeight(1).maxLines(3).enabled(!this.busy)
        .backgroundColor(COLOR_PAGE_BG).borderRadius(10).padding(10);
    }.width('100%').padding({ left: 16, right: 16 });
  }

  @Builder
  p256dhField() {
    this.fieldLabel($r('app.string.wp_p256dh_label'));
    // 宽度交给外层 padding：width('100%') 再叠 margin 会超出父容器，
    // 表现为输入框两侧顶到卡片边缘。
    Row() {
      TextArea({ text: $$this.p256dh, placeholder: $r('app.string.wp_p256dh_hint') })
        .fontSize(13).layoutWeight(1).maxLines(3).enabled(!this.busy)
        .backgroundColor(COLOR_PAGE_BG).borderRadius(10).padding(10);
    }.width('100%').padding({ left: 16, right: 16 });
  }

  @Builder
  authField() {
    this.fieldLabel('auth（base64url）');
    // 宽度交给外层 padding：width('100%') 再叠 margin 会超出父容器，
    // 表现为输入框两侧顶到卡片边缘。
    Row() {
      TextArea({ text: $$this.auth, placeholder: $r('app.string.wp_auth_hint') })
        .fontSize(13).layoutWeight(1).maxLines(3).enabled(!this.busy)
        .backgroundColor(COLOR_PAGE_BG).borderRadius(10).padding(10);
    }.width('100%').padding({ left: 16, right: 16 });
  }

  private fillFromJson(): void {
    const parsed: ParsedSubscription = parseSubscriptionJson(this.jsonInput);
    // 即使有缺字段也把已解析出来的回填，用户只需补齐缺的那项。
    if (parsed.config.endpoint !== '') { this.endpoint = parsed.config.endpoint; }
    if (parsed.config.p256dh !== '') { this.p256dh = parsed.config.p256dh; }
    if (parsed.config.auth !== '') { this.auth = parsed.config.auth; }
    if (parsed.error !== '') {
      this.statusOk = false;
      this.statusText = parsed.error;
      promptAction.showToast({ message: parsed.error, duration: 2000 });
      return;
    }
    this.jsonExpanded = false;
    this.statusOk = true;
    this.statusText = str('wp_filled');
  }

  private truncateToken(token: string): string {
    const EDGE_LEN: number = 12;
    if (token.length <= EDGE_LEN * 2) {
      return token;
    }
    return `${token.substring(0, EDGE_LEN)}...${token.substring(token.length - EDGE_LEN)}`;
  }

  private runHuaweiPushProbe(): void {
    if (this.hwBusy) {
      return;
    }
    this.hwBusy = true;
    this.hwTokenLine = str('wp_registering');
    this.hwResultLine = '';
    this.hwErrorLine = '';
    registerHuaweiPush(getTdClient()).then((result: HuaweiPushResult): void => {
      this.hwTokenLine = result.token !== ''
        ? this.truncateToken(result.token)
        : str('wp_register_failed', `${result.errorCode}`);
      this.hwResultLine = result.success
        ? (result.pushReceiverId !== '' ? str('wp_registered_with_id', result.pushReceiverId) : str('wp_registered_no_id'))
        : (result.token !== '' ? str('wp_register_failed', `${result.errorCode}`) : '');
      this.hwErrorLine = result.success ? '' : result.errorMessage;
      this.hwBusy = false;
    });
  }

  private deregister(): void {
    if (this.busy) {
      return;
    }
    this.busy = true;
    setBoolean(KEY_WEBPUSH_ENABLED, false);
    deregisterWebPush(getTdClient()).then((): void => {
      this.statusOk = false;
      // 只注销订阅，保留已填的三项 —— 用户多半是想换个地址再注册，
      // 清空会逼他重新粘一遍。
      this.statusText = str('wp_deregistered');
      this.busy = false;
    });
  }

  @Builder
  consentSheet() {
    Column({ space: 12 }) {
      Text($r('app.string.wp_before_you_enable'))
        .fontSize(18).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
      Text($r('app.string.wp_intro'))
        .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).lineHeight(19);
      Text($r('app.string.wp_warn_1'))
        .fontSize(13).fontColor(COLOR_TEXT_PRIMARY).lineHeight(19);
      Text($r('app.string.wp_warn_2'))
        .fontSize(13).fontColor(COLOR_TEXT_PRIMARY).lineHeight(19);
      Text($r('app.string.wp_warn_3'))
        .fontSize(13).fontColor(COLOR_TEXT_PRIMARY).lineHeight(19);
      Text($r('app.string.wp_warn_4'))
        .fontSize(13).fontColor(COLOR_TEXT_PRIMARY).lineHeight(19);
      Text($r('app.string.wp_warn_5'))
        .fontSize(13).fontColor(COLOR_TEXT_PRIMARY).lineHeight(19);
      Row({ space: 10 }) {
        Button($r('app.string.cancel')).fontSize(15).layoutWeight(1)
          .backgroundColor(COLOR_PAGE_BG).fontColor(COLOR_TEXT_PRIMARY)
          .onClick((): void => { this.consentShown = false; });
        Button($r('app.string.wp_accept')).fontSize(15).layoutWeight(1)
          .backgroundColor(COLOR_PRIMARY).fontColor(Color.White)
          .onClick((): void => this.acceptConsent());
      }.width('100%').margin({ top: 4 });
    }
    .width('100%').padding(20).alignItems(HorizontalAlign.Start);
  }

  build() {
    Column() {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(22).fontColor([COLOR_TEXT_PRIMARY])
          .onClick((): void => { router.back(); });
        Text($r('app.string.ns_custom_push')).fontSize(18).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
      }
      .width('100%').height(52).padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center);

      Scroll() {
        Column({ space: 12 }) {
          Column() {
            Row() {
              Text($r('app.string.wp_enable')).fontSize(15).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
              Toggle({ type: ToggleType.Switch, isOn: this.pushEnabled })
                .selectedColor(COLOR_PRIMARY)
                .enabled(!this.busy)
                .onChange((next: boolean): void => this.onToggle(next));
            }.width('100%').height(48).padding({ left: 14, right: 12 });
            Text($r('app.string.wp_enable_sub'))
              .fontSize(11).fontColor(COLOR_TEXT_SECONDARY).lineHeight(16)
              .width('100%').padding({ left: 14, right: 14, bottom: 10 });
          }
          .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);

          Column() {
            Row() {
              Text($r('app.string.wp_subscription')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY).layoutWeight(1);
              Text(this.jsonExpanded ? $r('app.string.collapse') : $r('app.string.wp_paste_json'))
                .fontSize(13).fontColor(COLOR_PRIMARY)
                .onClick((): void => { this.jsonExpanded = !this.jsonExpanded; });
            }.width('100%').padding({ left: 16, right: 16, top: 14 });
            Text($r('app.string.wp_keygen_note'))
              .fontSize(11).fontColor(COLOR_TEXT_SECONDARY).lineHeight(16)
              .width('100%').padding({ left: 16, right: 16, top: 6 });

            // 一键填充：多数服务端库直接输出这个结构，逐项复制既慢又容易串行。
            if (this.jsonExpanded) {
              Column({ space: 8 }) {
                Row() {
                  TextArea({ text: $$this.jsonInput, placeholder: SUBSCRIPTION_JSON_HINT })
                    .fontSize(12).layoutWeight(1).maxLines(8)
                    .enabled(!this.busy)
                    .backgroundColor(COLOR_PAGE_BG).borderRadius(10).padding(10);
                }.width('100%');
                Button($r('app.string.wp_fill_three'))
                  .fontSize(14).width('100%').height(40)
                  .backgroundColor(COLOR_PAGE_BG).fontColor(COLOR_PRIMARY)
                  .enabled(!this.busy)
                  .onClick((): void => this.fillFromJson());
              }
              .width('100%').padding({ left: 16, right: 16, top: 10 });
            }

            this.endpointField();
            this.p256dhField();
            this.authField();

            Column({ space: 8 }) {
              Button(this.busy ? $r('app.string.processing') : $r('app.string.wp_save_register'))
                .fontSize(15).width('100%').height(44)
                .backgroundColor(COLOR_PRIMARY).fontColor(Color.White)
                .enabled(!this.busy)
                .onClick((): void => this.saveAndRegister());
              // 注销入口独立出来：关开关也会注销，但换地址时用户想的是
              // "先退掉旧的"，没有这个按钮就只能去拨开关，很不直观。
              Button($r('app.string.wp_deregister'))
                .fontSize(15).width('100%').height(44)
                .backgroundColor(COLOR_PAGE_BG).fontColor('#FF3B30')
                .enabled(!this.busy)
                .onClick((): void => this.deregister());
              if (this.statusText !== '') {
                Text(this.statusText)
                  .fontSize(12).lineHeight(17)
                  .fontColor(this.statusOk ? COLOR_PRIMARY : '#FF3B30')
                  .width('100%');
              }
            }
            .width('100%').padding({ left: 16, right: 16, top: 12 });
          }
          .width('100%').padding({ bottom: 16 })
          .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);

          Column({ space: 6 }) {
            Text($r('app.string.wp_server_todo')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY).width('100%');
            // One key for the whole list rather than five joined fragments: the
            // numbering and line breaks belong to the copy, and a translator
            // needs to see the sentences whole.
            Text($r('app.string.wp_server_steps'))
              .fontSize(11).fontColor(COLOR_TEXT_SECONDARY).lineHeight(17).width('100%');
          }
          .width('100%').padding(14)
          .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);

          // 探针区块：与上面的自建 Web Push 并存，验证华为 Push Kit 通道是否
          // 可被 Telegram 服务器直接使用。验证通过前不接入 PushExtensionAbility。
          Column({ space: 8 }) {
            Button(this.hwBusy ? $r('app.string.processing') : $r('app.string.px_test'))
              .fontSize(15).width('100%').height(44)
              .backgroundColor(COLOR_PAGE_BG).fontColor(COLOR_PRIMARY)
              .enabled(!this.hwBusy)
              .onClick((): void => this.runHuaweiPushProbe());
            if (this.hwTokenLine !== '') {
              Text(this.hwTokenLine).fontSize(12).lineHeight(17).fontColor(COLOR_TEXT_PRIMARY).width('100%');
            }
            if (this.hwResultLine !== '') {
              Text(this.hwResultLine).fontSize(12).lineHeight(17).fontColor(COLOR_TEXT_SECONDARY).width('100%');
            }
            if (this.hwErrorLine !== '') {
              Text(this.hwErrorLine).fontSize(12).lineHeight(17).fontColor('#FF3B30').width('100%');
            }
          }
          .width('100%').padding(14)
          .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
        }
        .width('100%').padding({ left: 12, right: 12, bottom: this.bottomSafe + 16 });
      }
      .layoutWeight(1).width('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.Top);
    }
    .width('100%').height('100%')
    .padding({ top: this.topSafe })
    .backgroundColor(COLOR_PAGE_BG)
    .bindSheet($$this.consentShown, this.consentSheet(), {
      height: SheetSize.FIT_CONTENT,
      backgroundColor: COLOR_SURFACE
    });
  }
}
