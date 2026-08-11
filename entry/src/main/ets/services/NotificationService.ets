import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { ChatStore } from '../store/ChatStore';
import { CallSession, CallSnapshot } from './CallSession';
import { formatPreview } from '../util/formatPreview';

// 来电通知固定 id（TDLib notification id 为正整数，取远离区间的常量）。
export const CALL_NOTIFICATION_ID: number = 999001;

export interface LocalNotice {
  id: number;      // TDLib notification id（来电为 CALL_NOTIFICATION_ID）
  groupId: number; // TDLib notification group id（来电为 0）
  chatId: number;
  title: string;
  text: string;
  isCall: boolean;
}

export interface NotificationPublisher {
  publish(notice: LocalNotice): void;
  cancel(id: number): void;
  cancelAll(): void;
}

// 本地通知渲染层：消费 TDLib 内置通知管理器的事件（静音/例外/预览隐藏等
// 规则均由 TDLib 处理），把结果翻译成系统通知。前台时不打扰。
export class NotificationService {
  private client: TdClient;
  private chats: ChatStore;
  private publisher: NotificationPublisher;
  private isForeground: () => boolean;
  private unsubs: Array<() => void> = [];
  private unsubCall: (() => void) | null = null;
  private callNoticeShown: boolean = false;

  constructor(client: TdClient, chats: ChatStore, publisher: NotificationPublisher,
    isForeground: () => boolean) {
    this.client = client;
    this.chats = chats;
    this.publisher = publisher;
    this.isForeground = isForeground;
    this.unsubs.push(client.onUpdate('updateNotificationGroup',
      (u: TdObject) => this.onNotificationGroup(u)));
    // 临时诊断：区分"消息没到"与"到了但 TDLib 未生成通知组"。
    this.unsubs.push(client.onUpdate('updateNewMessage', (u: TdObject): void => {
      const message = u['message'] as TdObject | undefined;
      const chatId: number = message !== undefined
        ? ((message['chat_id'] as number | undefined) ?? 0) : 0;
      const outgoing: boolean = message !== undefined
        ? ((message['is_outgoing'] as boolean | undefined) ?? false) : false;
      console.info(`[NotifDiag] updateNewMessage chat=${chatId} outgoing=${outgoing} ` +
        `foreground=${this.isForeground()}`);
    }));
  }

  // 启用 TDLib 通知管理器。必须在 td_init 完成（Auth Ready）后调用 ——
  // 构造时 td 还没初始化，setOption 会 "tdSend before tdInit" 失败，
  // 之后 TDLib 就不推 updateNotificationGroup。
  enable(): void {
    this.enableTdNotifications();
  }

  attachCallSession(session: CallSession): void {
    this.unsubCall = session.subscribe((s: CallSnapshot): void => this.onCallSnapshot(s));
  }

  close(): void {
    for (const un of this.unsubs) {
      un();
    }
    this.unsubs = [];
    if (this.unsubCall !== null) {
      this.unsubCall();
      this.unsubCall = null;
    }
  }

  // TDLib 只有在这两个 option 非 0 时才会推 updateNotificationGroup。
  private enableTdNotifications(): void {
    this.setOption('notification_group_count_max', 5);
    this.setOption('notification_group_size_max', 10);
  }

  private setOption(name: string, value: number): void {
    const optionValue: TdObject = { '@type': 'optionValueInteger' };
    optionValue['value'] = `${value}`;
    const req: TdRequest = { '@type': 'setOption' };
    req['name'] = name;
    req['value'] = optionValue;
    this.client.send(req).then((): void => {
      console.info(`[NotifDiag] setOption(${name}=${value}) ok`);
    }).catch((e: TdError): void => {
      console.error(`NotificationService.setOption(${name}) failed: ${e.message}`);
    });
  }

  private onNotificationGroup(u: TdObject): void {
    const groupId: number = (u['notification_group_id'] as number | undefined) ?? 0;
    const chatId: number = (u['chat_id'] as number | undefined) ?? 0;
    const addedCount: number = ((u['added_notifications'] as TdObject[] | undefined) ?? []).length;
    console.info(`[NotifDiag] updateNotificationGroup chat=${chatId} added=${addedCount} ` +
      `foreground=${this.isForeground()}`);
    const removed: number[] = (u['removed_notification_ids'] as number[] | undefined) ?? [];
    for (const id of removed) {
      this.publisher.cancel(id);
    }
    if (this.isForeground()) {
      return; // 前台应用内可见，不发系统通知（撤销仍需处理，保持已发通知同步）
    }
    const added: TdObject[] = (u['added_notifications'] as TdObject[] | undefined) ?? [];
    for (const notification of added) {
      const notice = this.buildNotice(notification, groupId, chatId);
      if (notice !== null) {
        this.publisher.publish(notice);
      }
    }
  }

  private buildNotice(notification: TdObject, groupId: number,
    chatId: number): LocalNotice | null {
    const id: number = (notification['id'] as number | undefined) ?? 0;
    if (id <= 0) {
      return null;
    }
    const type = notification['type'] as TdObject | undefined;
    const typeName: string = type !== undefined
      ? ((type['@type'] as string | undefined) ?? '') : '';
    const entry = this.chats.entryOf(chatId);
    const title: string = entry !== undefined && entry.title !== '' ? entry.title : '新消息';
    if (typeName === 'notificationTypeNewMessage') {
      const message = type!['message'] as TdObject | undefined;
      const text: string = formatPreview(message ?? null);
      return {
        id: id, groupId: groupId, chatId: chatId,
        title: title, text: text !== '' ? text : '你收到一条新消息', isCall: false
      };
    }
    if (typeName === 'notificationTypeNewCall') {
      return {
        id: id, groupId: groupId, chatId: chatId,
        title: title, text: '来电', isCall: true
      };
    }
    if (typeName === 'notificationTypeNewSecretChat') {
      return {
        id: id, groupId: groupId, chatId: chatId,
        title: title, text: '新的秘密聊天', isCall: false
      };
    }
    // notificationTypeNewPushMessage 仅在推送场景出现，本方案不会收到。
    return null;
  }

  private onCallSnapshot(s: CallSnapshot): void {
    const ringing: boolean = s.phase === 'ringing' && !s.isOutgoing;
    if (ringing && !this.isForeground()) {
      this.callNoticeShown = true;
      this.publisher.publish({
        id: CALL_NOTIFICATION_ID, groupId: 0, chatId: s.peerUserId,
        title: s.peerName !== '' ? s.peerName : '来电',
        text: s.isVideo ? '视频来电' : '语音来电', isCall: true
      });
      return;
    }
    if (!ringing && this.callNoticeShown) {
      this.callNoticeShown = false;
      this.publisher.cancel(CALL_NOTIFICATION_ID);
    }
  }
}
