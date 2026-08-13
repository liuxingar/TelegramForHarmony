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

const CARD_RADIUS: number = 14;

// 自定义 Web Push 中转通道的配置页。
//
// 这个功能默认关闭，且必须先读完风险说明才能启用 —— 它会把消息预览的明文交给
// 用户自建的服务器，属于「知情后自愿」的取舍，不能默默生效。
@Entry
@Component
struct WebPushPage {
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

  aboutToAppear(): void {
    this.endpoint = this.storedEndpoint;
    this.p256dh = this.storedP256dh;
    this.auth = this.storedAuth;
    if (this.pushEnabled && this.storedEndpoint !== '') {
      this.statusOk = true;
      this.statusText = '已启用。注册状态见下方「保存并注册」结果。';
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
    this.statusText = '已停用，并已向 Telegram 注销该 endpoint。';
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
    this.statusText = '正在注册…';
    registerWebPush(getTdClient(), config).then((receiverId: string): void => {
      setString(KEY_WEBPUSH_ENDPOINT, config.endpoint.trim());
      setString(KEY_WEBPUSH_P256DH, config.p256dh.trim());
      setString(KEY_WEBPUSH_AUTH, config.auth.trim());
      setBoolean(KEY_WEBPUSH_ENABLED, true);
      this.statusOk = true;
      this.statusText = receiverId !== ''
        ? `已注册 · receiver id ${receiverId}`
        : '已注册（服务端未返回 receiver id）';
      this.busy = false;
    }).catch((e: TdError): void => {
      // 注册失败不打开开关 —— 否则用户会以为通知已经生效。
      setBoolean(KEY_WEBPUSH_ENABLED, false);
      this.statusOk = false;
      this.statusText = `注册失败：${e.message}`;
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
  fieldLabel(label: string) {
    Text(label).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
      .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 5 });
  }

  @Builder
  endpointField() {
    this.fieldLabel('Endpoint（必须 https + 域名）');
    // 宽度交给外层 padding：width('100%') 再叠 margin 会超出父容器，
    // 表现为输入框两侧顶到卡片边缘。
    Row() {
      TextArea({ text: $$this.endpoint, placeholder: 'https://push.example.com/webpush/<随机订阅ID>' })
        .fontSize(13).layoutWeight(1).maxLines(3).enabled(!this.busy)
        .backgroundColor(COLOR_PAGE_BG).borderRadius(10).padding(10);
    }.width('100%').padding({ left: 16, right: 16 });
  }

  @Builder
  p256dhField() {
    this.fieldLabel('p256dh（公钥，base64url）');
    // 宽度交给外层 padding：width('100%') 再叠 margin 会超出父容器，
    // 表现为输入框两侧顶到卡片边缘。
    Row() {
      TextArea({ text: $$this.p256dh, placeholder: '服务器生成的 P-256 公钥' })
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
      TextArea({ text: $$this.auth, placeholder: '服务器生成的 auth secret' })
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
    this.statusText = '已填入，检查无误后点「保存并注册」。';
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
      this.statusText = '已取消注册。Telegram 不会再向该地址投递，配置已保留。';
      this.busy = false;
    });
  }

  @Builder
  consentSheet() {
    Column({ space: 12 }) {
      Text('启用前请先了解')
        .fontSize(18).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
      Text('这个功能把通知投递交给你自己搭建的服务器。启用即表示你接受下列取舍：')
        .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).lineHeight(19);
      Text('1. 你的服务器能看到消息预览明文。解密必须在服务器上完成，这是这条链路的前提，无法规避。')
        .fontSize(13).fontColor(COLOR_TEXT_PRIMARY).lineHeight(19);
      Text('2. 预览可能不完整甚至没有。关闭了预览的会话、部分消息类型只会推送「你有一条新消息」。')
        .fontSize(13).fontColor(COLOR_TEXT_PRIMARY).lineHeight(19);
      Text('3. 送达完全依赖你的服务器。它停机、证书过期或地址变更时不会有任何通知，应用也无法感知。')
        .fontSize(13).fontColor(COLOR_TEXT_PRIMARY).lineHeight(19);
      Text('4. 只填你自己掌控的地址。填入他人提供的 endpoint 等于把消息预览交给对方。')
        .fontSize(13).fontColor(COLOR_TEXT_PRIMARY).lineHeight(19);
      Text('5. 这是附加通道，不替代现有通知。应用原有的后台同步和本地通知照常工作。')
        .fontSize(13).fontColor(COLOR_TEXT_PRIMARY).lineHeight(19);
      Row({ space: 10 }) {
        Button('取消').fontSize(15).layoutWeight(1)
          .backgroundColor(COLOR_PAGE_BG).fontColor(COLOR_TEXT_PRIMARY)
          .onClick((): void => { this.consentShown = false; });
        Button('我已了解并接受').fontSize(15).layoutWeight(1)
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
        Text('自定义推送通道').fontSize(18).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
      }
      .width('100%').height(52).padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center);

      Scroll() {
        Column({ space: 12 }) {
          Column() {
            Row() {
              Text('启用 Web Push 中转').fontSize(15).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
              Toggle({ type: ToggleType.Switch, isOn: this.pushEnabled })
                .selectedColor(COLOR_PRIMARY)
                .enabled(!this.busy)
                .onChange((next: boolean): void => this.onToggle(next));
            }.width('100%').height(48).padding({ left: 14, right: 12 });
            Text('由你自建的服务器接收 Telegram 的 Web Push、解密后转发到你选择的通道。')
              .fontSize(11).fontColor(COLOR_TEXT_SECONDARY).lineHeight(16)
              .width('100%').padding({ left: 14, right: 14, bottom: 10 });
          }
          .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);

          Column() {
            Row() {
              Text('订阅信息').fontSize(12).fontColor(COLOR_TEXT_SECONDARY).layoutWeight(1);
              Text(this.jsonExpanded ? '收起' : '粘贴 JSON')
                .fontSize(13).fontColor(COLOR_PRIMARY)
                .onClick((): void => { this.jsonExpanded = !this.jsonExpanded; });
            }.width('100%').padding({ left: 16, right: 16, top: 14 });
            Text('在你的服务器上生成一对 P-256 密钥和 auth secret，私钥留在服务器，把下面三项填进来。应用不持有私钥，也不参与解密。\n实测 Telegram 只向 https + 域名的地址投递，http 或 IP 形式收不到。')
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
                Button('填入下面三项')
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
              Button(this.busy ? '处理中…' : '保存并注册')
                .fontSize(15).width('100%').height(44)
                .backgroundColor(COLOR_PRIMARY).fontColor(Color.White)
                .enabled(!this.busy)
                .onClick((): void => this.saveAndRegister());
              // 注销入口独立出来：关开关也会注销，但换地址时用户想的是
              // "先退掉旧的"，没有这个按钮就只能去拨开关，很不直观。
              Button('取消注册')
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
            Text('服务器需要做什么').fontSize(12).fontColor(COLOR_TEXT_SECONDARY).width('100%');
            Text('1. 在 Endpoint 上接收 Telegram 的 POST 请求。\n' +
              '2. 用私钥按 RFC 8291 解密，得到含 loc_key / loc_args / custom 的 JSON。\n' +
              '3. 按 loc_key 组装标题和正文，转发到你的推送通道。\n' +
              '4. 推送里带上 tg://openmessage?channel_id=<custom.channel_id>&msg_id=<custom.msg_id>，' +
              '点击通知即可直接打开对应会话（私聊用 from_id，基础群用 chat_id）。')
              .fontSize(11).fontColor(COLOR_TEXT_SECONDARY).lineHeight(17).width('100%');
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
