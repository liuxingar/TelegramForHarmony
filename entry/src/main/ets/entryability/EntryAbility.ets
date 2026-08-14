import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, KeyboardAvoidMode } from '@kit.ArkUI';
import { initTdKit, setTdOnlineState, setUiAbilityContext } from '../tdkit/Globals';
import { backgroundGraceTask } from '../services/BackgroundGraceTask';
import { initSettings, refreshPowerSavingState } from '../store/AppSettings';
import { beginNetworkMonitoring, refreshNetworkState } from '../services/NetworkStateService';
import { updateChecker } from '../services/UpdateChecker';
import { liveLocation } from '../services/LiveLocationService';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // Loads persisted settings into AppStorage and applies the stored night
    // mode (which subsumes the old unconditional COLOR_MODE_NOT_SET).
    initSettings(this.context);
    initTdKit(this.context);
    // 实时位置共享要跨会话、跨前后台存活，服务需要 Ability 上下文申请长时任务。
    liveLocation.init(this.context);
    // 版本号与上次的检查结果先读出来，红点在网络请求回来之前就是对的。
    updateChecker.init(this.context).catch((): void => {});
    setUiAbilityContext(this.context);
    beginNetworkMonitoring();
    // Cold start via a tg:// deep link — stash it; Index routes it once auth
    // reaches Ready (the UI/router aren't up yet here).
    this.stashDeepLink(want);
    AppStorage.setOrCreate('appIsForeground', false);
    AppStorage.setOrCreate('appForegroundEpoch', 0);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  // Warm start: the app is already running (foreground or background) when a
  // tg:// link arrives. Index's @Watch picks up the new value and routes it.
  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.stashDeepLink(want);
  }

  // Publish the launch URI for the UI layer. Cleared to '' first so re-opening
  // the SAME link still registers as a change and re-triggers routing.
  private stashDeepLink(want: Want): void {
    this.stashNotifyTarget(want);
    const uri = want.uri ?? '';
    if (uri === '') {
      return;
    }
    AppStorage.setOrCreate('pendingDeepLink', '');
    AppStorage.setOrCreate('pendingDeepLink', uri);
  }

  // 点击本地通知拉起时携带的目标会话。与 pendingDeepLink 相同的
  // 清零-再置位模式，保证重复点击同一会话的通知也触发路由。
  private stashNotifyTarget(want: Want): void {
    const chatId = want.parameters !== undefined
      ? (want.parameters['notifyChatId'] as number | undefined) ?? 0 : 0;
    if (chatId === 0) {
      return;
    }
    AppStorage.setOrCreate('pendingNotifyChatId', 0);
    AppStorage.setOrCreate('pendingNotifyChatId', chatId);
  }

  onDestroy(): void {
    setTdOnlineState(false);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');
    // 本地通知授权：先查是否已启用，未启用才弹授权框（重复调用/系统开关
    // 关闭时 requestEnableNotification 会报 Internal error，故先判断）。
    notificationManager.isNotificationEnabled().then((enabled: boolean): void => {
      if (enabled) {
        return;
      }
      notificationManager.requestEnableNotification(this.context).catch((e: Error): void => {
        console.error(`requestEnableNotification failed: ${e.message}`);
      });
    }).catch((e: Error): void => {
      console.error(`isNotificationEnabled failed: ${e.message}`);
    });

    try {
      const win = windowStage.getMainWindowSync();
      win.setWindowLayoutFullScreen(true);
      const avoid = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      AppStorage.setOrCreate('topSafeHeight', px2vp(avoid.topRect.height));
      // Bottom inset (gesture navigation bar) — pages pad their bottom bars by this.
      const navAvoid = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      AppStorage.setOrCreate('bottomSafeHeight', px2vp(navAvoid.bottomRect.height));
      const cutoutAvoid = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
      AppStorage.setOrCreate('cutoutTopSafeHeight', px2vp(cutoutAvoid.topRect.height));
      AppStorage.setOrCreate('cutoutLeftSafeWidth', px2vp(cutoutAvoid.leftRect.width));
      AppStorage.setOrCreate('cutoutRightSafeWidth', px2vp(cutoutAvoid.rightRect.width));
      AppStorage.setOrCreate('screenWidthVp', px2vp(win.getWindowProperties().windowRect.width));
      win.on('avoidAreaChange', (data) => {
        if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
          AppStorage.setOrCreate('topSafeHeight', px2vp(data.area.topRect.height));
        } else if (data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
          AppStorage.setOrCreate('bottomSafeHeight', px2vp(data.area.bottomRect.height));
        } else if (data.type === window.AvoidAreaType.TYPE_CUTOUT) {
          AppStorage.setOrCreate('cutoutTopSafeHeight', px2vp(data.area.topRect.height));
          AppStorage.setOrCreate('cutoutLeftSafeWidth', px2vp(data.area.leftRect.width));
          AppStorage.setOrCreate('cutoutRightSafeWidth', px2vp(data.area.rightRect.width));
        }
      });
      // Keyboard height: when the IME is up the window is already resized
      // above it, so pages must drop their gesture-bar bottom padding.
      win.on('keyboardHeightChange', (h: number) => {
        AppStorage.setOrCreate('keyboardHeightVp', px2vp(h));
      });
      win.on('windowSizeChange', (size) => {
        AppStorage.setOrCreate('screenWidthVp', px2vp(size.width));
      });
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set full-screen layout. Cause: %{public}s', JSON.stringify(err));
    }

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      // IME avoidance: RESIZE shrinks the page above the keyboard, so fixed
      // headers (chat title bar) stay put and only the scrolling content and
      // input bar move. The default OFFSET translates the WHOLE page up.
      try {
        windowStage.getMainWindowSync().getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
      } catch (e) {
        hilog.error(DOMAIN, 'testTag', 'setKeyboardAvoidMode failed: %{public}s', JSON.stringify(e));
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    refreshPowerSavingState();
    refreshNetworkState(true);
    AppStorage.setOrCreate('appIsForeground', true);
    // 回前台：释放短时任务配额（下次切后台再申请）。
    backgroundGraceTask.end();
    AppStorage.setOrCreate('appForegroundEpoch', Date.now());
    setTdOnlineState(true);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    AppStorage.setOrCreate('appIsForeground', false);
    setTdOnlineState(false);
    // 申请短时任务：切后台后多存活几分钟，这段时间内新消息仍能实时收到并通知。
    backgroundGraceTask.begin();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
