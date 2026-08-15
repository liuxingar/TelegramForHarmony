import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { UserStore } from '../main/ets/store/UserStore';
import { ChatStore } from '../main/ets/store/ChatStore';
import { CallSession } from '../main/ets/services/CallSession';
import { NullCallMedia } from '../main/ets/services/CallMediaBridge';
import {
  NotificationService, NotificationPublisher, LocalNotice, CALL_NOTIFICATION_ID
} from '../main/ets/services/NotificationService';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}

class FakePublisher implements NotificationPublisher {
  published: LocalNotice[] = [];
  cancelled: number[] = [];
  publish(notice: LocalNotice): void { this.published.push(notice); }
  cancel(id: number): void { this.cancelled.push(id); }
  cancelAll(): void {}
}

interface Env {
  bridge: FakeBridge;
  publisher: FakePublisher;
  service: NotificationService;
  foreground: boolean;
}

function setup(): Env {
  const b = new FakeBridge();
  const c = new TdClient(b);
  const users = new UserStore(c);
  const chats = new ChatStore(c, users);
  const publisher = new FakePublisher();
  const env: Env = { bridge: b, publisher: publisher, service: null!, foreground: false };
  env.service = new NotificationService(c, chats, publisher, (): boolean => env.foreground);
  c.start();
  // 提供会话标题
  const chat: TdObject = { '@type': 'chat' };
  chat['id'] = 5;
  chat['title'] = '工作群';
  chat['positions'] = [];
  chat['unread_count'] = 0;
  const newChat: TdObject = { '@type': 'updateNewChat' };
  newChat['chat'] = chat;
  b.onReceive(JSON.stringify(newChat));
  return env;
}

function feedGroup(b: FakeBridge, groupId: number, chatId: number,
  added: TdObject[], removed: number[]): void {
  const u: TdObject = { '@type': 'updateNotificationGroup' };
  u['notification_group_id'] = groupId;
  u['chat_id'] = chatId;
  u['added_notifications'] = added;
  u['removed_notification_ids'] = removed;
  b.onReceive(JSON.stringify(u));
}

function messageNotification(id: number, text: string): TdObject {
  const ft: TdObject = { '@type': 'formattedText' };
  ft['text'] = text;
  const content: TdObject = { '@type': 'messageText' };
  content['text'] = ft;
  const message: TdObject = { '@type': 'message' };
  message['id'] = id * 100;
  message['chat_id'] = 5;
  message['date'] = 100;
  message['content'] = content;
  const type: TdObject = { '@type': 'notificationTypeNewMessage' };
  type['message'] = message;
  const notification: TdObject = { '@type': 'notification' };
  notification['id'] = id;
  notification['type'] = type;
  return notification;
}

function feedNewMessage(b: FakeBridge, chatId: number, messageId: number,
  text: string, outgoing: boolean): void {
  const ft: TdObject = { '@type': 'formattedText' };
  ft['text'] = text;
  const content: TdObject = { '@type': 'messageText' };
  content['text'] = ft;
  const message: TdObject = { '@type': 'message' };
  message['id'] = messageId;
  message['chat_id'] = chatId;
  message['date'] = 100;
  message['is_outgoing'] = outgoing;
  message['content'] = content;
  const u: TdObject = { '@type': 'updateNewMessage' };
  u['message'] = message;
  b.onReceive(JSON.stringify(u));
}

function sentOptions(b: FakeBridge): string[] {
  return b.sent.map((json: string): TdObject => JSON.parse(json) as TdObject)
    .filter((o: TdObject): boolean => o['@type'] === 'setOption')
    .map((o: TdObject): string => (o['name'] as string | undefined) ?? '');
}

export default function notificationServiceTest() {
  describe('NotificationService', () => {
    it('enables_td_notification_options', 0, () => {
      const env = setup();
      // 构造时 TDLib 可能尚未 init，故启用改由 enable() 在登录就绪后触发。
      expect(sentOptions(env.bridge).length).assertEqual(0);
      env.service.enable();
      const names = sentOptions(env.bridge);
      expect(names.indexOf('notification_group_count_max') >= 0).assertTrue();
      expect(names.indexOf('notification_group_size_max') >= 0).assertTrue();
    });
    it('new_message_publishes_when_background', 0, () => {
      const env = setup();
      env.foreground = false;
      feedNewMessage(env.bridge, 5, 4194304, '晚上开会', false);
      expect(env.publisher.published.length).assertEqual(1);
      const notice = env.publisher.published[0];
      expect(notice.chatId).assertEqual(5);
      expect(notice.title).assertEqual('工作群');
      expect(notice.text.indexOf('晚上开会') >= 0).assertTrue();
      expect(notice.isCall).assertFalse();
    });
    it('outgoing_message_does_not_publish', 0, () => {
      const env = setup();
      env.foreground = false;
      feedNewMessage(env.bridge, 5, 4194304, '我发的', true);
      expect(env.publisher.published.length).assertEqual(0);
    });
    it('foreground_suppresses_publish', 0, () => {
      const env = setup();
      env.foreground = true;
      feedNewMessage(env.bridge, 5, 8388608, 'hi', false);
      expect(env.publisher.published.length).assertEqual(0);
    });
    it('read_inbox_cancels_chat_notices', 0, () => {
      const env = setup();
      env.foreground = false;
      feedNewMessage(env.bridge, 5, 12582912, 'a', false);
      expect(env.publisher.published.length).assertEqual(1);
      const shownId: number = env.publisher.published[0].id;
      const read: TdObject = { '@type': 'updateChatReadInbox' };
      read['chat_id'] = 5;
      read['unread_count'] = 0;
      env.bridge.onReceive(JSON.stringify(read));
      expect(env.publisher.cancelled.join(',')).assertEqual(`${shownId}`);
    });
    it('call_ringing_publishes_and_clears', 0, () => {
      // CallSession 用独立 bridge，避免与通知服务的 TdClient 事件混淆。
      const b2 = new FakeBridge();
      const c2 = new TdClient(b2);
      const call2 = new CallSession(c2, new UserStore(c2), new NullCallMedia());
      c2.start();
      const env2 = setup();
      env2.foreground = false;
      env2.service.attachCallSession(call2);
      const sender: TdObject = { '@type': 'callStatePending' };
      const callObj: TdObject = { '@type': 'call' };
      callObj['id'] = 21;
      callObj['user_id'] = 9;
      callObj['is_outgoing'] = false;
      callObj['is_video'] = true;
      callObj['state'] = sender;
      const upd: TdObject = { '@type': 'updateCall' };
      upd['call'] = callObj;
      b2.onReceive(JSON.stringify(upd));
      const published = env2.publisher.published
        .filter((n: LocalNotice): boolean => n.isCall);
      expect(published.length).assertEqual(1);
      expect(published[0].id).assertEqual(CALL_NOTIFICATION_ID);
      expect(published[0].text).assertEqual('ns_incoming_video_call');
      // 响铃结束 → 撤销
      callObj['state'] = { '@type': 'callStateDiscarded' } as TdObject;
      b2.onReceive(JSON.stringify(upd));
      expect(env2.publisher.cancelled.indexOf(CALL_NOTIFICATION_ID) >= 0).assertTrue();
    });
  });
}
