import { notificationManager } from '@kit.NotificationKit';
import { wantAgent } from '@kit.AbilityKit';
import { NotificationPublisher, LocalNotice } from './NotificationService';

// NotificationPublisher 的系统实现：Notification Kit 文本通知。
// 点击经 wantAgent 拉起 EntryAbility 并携带 notifyChatId（Index 消费路由）。
export class SystemNotificationPublisher implements NotificationPublisher {
  private bundleName: string;
  private abilityName: string;

  constructor(bundleName: string, abilityName: string) {
    this.bundleName = bundleName;
    this.abilityName = abilityName;
  }

  publish(notice: LocalNotice): void {
    this.buildAgent(notice.chatId).then((agent: object): Promise<void> => {
      const request: notificationManager.NotificationRequest = {
        id: notice.id,
        notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
        content: {
          notificationContentType:
            notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: notice.title,
            text: notice.text
          }
        },
        wantAgent: agent
      };
      return notificationManager.publish(request);
    }).catch((e: Error): void => {
      console.error(`SystemNotificationPublisher.publish(${notice.id}) failed: ${e.message}`);
    });
  }

  cancel(id: number): void {
    notificationManager.cancel(id).catch((e: Error): void => {
      console.error(`SystemNotificationPublisher.cancel(${id}) failed: ${e.message}`);
    });
  }

  cancelAll(): void {
    notificationManager.cancelAll().catch((e: Error): void => {
      console.error(`SystemNotificationPublisher.cancelAll failed: ${e.message}`);
    });
  }

  private buildAgent(chatId: number): Promise<object> {
    const params: Record<string, Object> = { 'notifyChatId': chatId };
    const info: wantAgent.WantAgentInfo = {
      wants: [{
        bundleName: this.bundleName,
        abilityName: this.abilityName,
        parameters: params
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 8297,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    return wantAgent.getWantAgent(info);
  }
}
