import { workScheduler } from '@kit.BackgroundTasksKit';

const WORK_ID: number = 8298;
// 系统按应用活跃分组管控实际触发间隔（活跃分组最小 2 小时）。
const CYCLE_MS: number = 2 * 3600 * 1000;

// 登录就绪后注册周期补收任务；重复注册（应用每次启动）无害——
// 相同 workId 直接覆盖或抛已存在错误，均忽略。
export function registerMessageSyncWork(bundleName: string): void {
  const info: workScheduler.WorkInfo = {
    workId: WORK_ID,
    bundleName: bundleName,
    abilityName: 'MessageSyncWorkAbility',
    networkType: workScheduler.NetworkType.NETWORK_TYPE_ANY,
    isRepeat: true,
    repeatCycleTime: CYCLE_MS
  };
  try {
    workScheduler.startWork(info);
    console.info('[MessageSyncWork] registered');
  } catch (e) {
    console.error(`[MessageSyncWork] register failed: ${(e as Error).message}`);
  }
}

export function unregisterMessageSyncWork(bundleName: string): void {
  const info: workScheduler.WorkInfo = {
    workId: WORK_ID,
    bundleName: bundleName,
    abilityName: 'MessageSyncWorkAbility'
  };
  try {
    workScheduler.stopWork(info, true);
    console.info('[MessageSyncWork] unregistered');
  } catch (e) {
    console.error(`[MessageSyncWork] unregister failed: ${(e as Error).message}`);
  }
}
