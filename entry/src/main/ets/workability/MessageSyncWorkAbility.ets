import { WorkSchedulerExtensionAbility, workScheduler } from '@kit.BackgroundTasksKit';
import { runHeadlessSync } from '../services/HeadlessSync';

// 系统延迟任务回调（独立扩展进程）：主进程死亡期间定时补收消息并发通知。
export default class MessageSyncWorkAbility extends WorkSchedulerExtensionAbility {
  onWorkStart(work: workScheduler.WorkInfo): void {
    console.info(`[MessageSyncWork] start workId=${work.workId}`);
    runHeadlessSync(this.context).then((): void => {
      console.info('[MessageSyncWork] done');
    }).catch((e: Error): void => {
      console.error(`[MessageSyncWork] failed: ${e.message}`);
    });
  }

  onWorkStop(work: workScheduler.WorkInfo): void {
    console.info(`[MessageSyncWork] stop workId=${work.workId}`);
  }
}
