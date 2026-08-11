import { router } from '@kit.ArkUI';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { getCallSession } from '../../tdkit/Globals';
import { CallSession, CallSnapshot } from '../../services/CallSession';
import { AvatarView } from '../chatlist/AvatarView';
import {
  callPhaseLabel, callDurationLabel, callEndLabel
} from '../../util/callPresentation';
import { CALL_VIDEO_OFF, CALL_VIDEO_FRONT } from '../../services/CallMediaBridge';

const BG_COLOR: string = '#FF17212B';
const CONTROL_BG: string = '#33FFFFFF';
const DANGER: string = '#FFE5484D';
const ACCEPT: string = '#FF31C48D';

// 1对1 通话页：单页覆盖 拨出/来电/通话中/已结束 四态，状态由 CallSession 驱动。
@Entry
@Component
struct CallPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State snap: CallSnapshot | null = null;
  @State nowMs: number = 0;
  private unsub: (() => void) | null = null;
  private tickTimer: number = -1;
  private closeTimer: number = -1;
  private remoteController: XComponentController = new XComponentController();
  private localController: XComponentController = new XComponentController();

  aboutToAppear(): void {
    const session: CallSession = getCallSession();
    this.unsub = session.subscribe((s: CallSnapshot): void => {
      this.snap = s;
      if (s.phase === 'ended' && this.closeTimer === -1) {
        this.closeTimer = setTimeout((): void => {
          router.back();
        }, 1500);
      }
    });
    this.tickTimer = setInterval((): void => {
      this.nowMs = Date.now();
    }, 1000);
    this.requestCallPermissions();
  }

  // 首次通话前申请麦克风（视频通话再加摄像头）。拒绝不阻断页面 ——
  // 无权限时对端听不到本端，由用户自行退出；后续可加显式提示。
  private requestCallPermissions(): void {
    const permissions: Permissions[] = ['ohos.permission.MICROPHONE'];
    if (this.snap !== null && this.snap.isVideo) {
      permissions.push('ohos.permission.CAMERA');
    }
    try {
      const context = getContext(this) as common.UIAbilityContext;
      abilityAccessCtrl.createAtManager()
        .requestPermissionsFromUser(context, permissions)
        .catch((error: Error): void => {
          console.error(`CallPage permission request failed: ${error.message}`);
        });
    } catch (e) {
      console.error(`CallPage permission request threw: ${(e as Error).message}`);
    }
  }

  aboutToDisappear(): void {
    if (this.unsub !== null) {
      this.unsub();
      this.unsub = null;
    }
    if (this.tickTimer !== -1) {
      clearInterval(this.tickTimer);
      this.tickTimer = -1;
    }
    if (this.closeTimer !== -1) {
      clearTimeout(this.closeTimer);
      this.closeTimer = -1;
    }
  }

  // 尚无悬浮窗/最小化形态：返回即结束通话，避免离开页面后通话变成
  // 无法找回的"孤儿"。响铃中返回视为拒接。
  onBackPress(): boolean {
    const s = this.snap;
    if (s === null || s.phase === 'ended' || s.phase === 'idle') {
      return false;
    }
    if (s.phase === 'ringing') {
      getCallSession().decline();
    } else {
      getCallSession().hangup();
    }
    return false; // 挂断后仍允许返回
  }

  private statusLine(): string {
    const s = this.snap;
    if (s === null) {
      return '';
    }
    if (s.phase === 'ended') {
      return callEndLabel(s.endReason, s.errorText);
    }
    if (s.phase === 'active') {
      return callDurationLabel(s.startedAtMs, this.nowMs === 0 ? Date.now() : this.nowMs);
    }
    return callPhaseLabel(s.phase, s.isVideo);
  }

  private videoActive(): boolean {
    const s = this.snap;
    return s !== null && s.phase === 'active' &&
      (s.remoteVideoActive || s.localVideoMode !== CALL_VIDEO_OFF);
  }

  // 图标一律用仓库其它页面验证过的符号名（无效符号名会静默画成空白）。
  @Builder
  roundControl(symbol: string, label: string, bg: string, rotateDeg: number, onTap: () => void) {
    Column({ space: 6 }) {
      Column() {
        SymbolGlyph($r(symbol)).fontSize(24).fontColor([Color.White])
          .rotate({ angle: rotateDeg });
      }
      .width(52).height(52).borderRadius(26)
      .backgroundColor(bg)
      .justifyContent(FlexAlign.Center)
      .onClick((): void => { onTap(); });
      if (label !== '') {
        Text(label).fontSize(11).fontColor('#B8C4CF');
      }
    }
    .alignItems(HorizontalAlign.Center);
  }

  @Builder
  identityHeader() {
    Column({ space: 12 }) {
      AvatarView({
        avatarPath: '', initials: this.snap !== null && this.snap.peerName !== ''
          ? this.snap.peerName.substring(0, 1).toUpperCase() : '?',
        colorSeed: this.snap !== null ? this.snap.peerUserId : 0,
        avatarSize: 96
      });
      Text(this.snap !== null && this.snap.peerName !== '' ? this.snap.peerName : '通话')
        .fontSize(24).fontWeight(FontWeight.Bold).fontColor(Color.White)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '86%' });
      Text(this.statusLine())
        .fontSize(15).fontColor('#B8C4CF');
      if (this.snap !== null && this.snap.phase === 'active' && this.snap.emojis.length > 0) {
        // 端到端加密校验 emoji：双方一致即链路未被中间人替换。
        Text(this.snap.emojis.join(' ')).fontSize(18).margin({ top: 2 });
      }
    }
    .alignItems(HorizontalAlign.Center);
  }

  @Builder
  activeControls() {
    Row({ space: 14 }) {
      this.roundControl('sys.symbol.mic',
        this.snap !== null && this.snap.muted ? '静音中' : '静音',
        this.snap !== null && this.snap.muted ? '#66FFFFFF' : CONTROL_BG, 0,
        (): void => { getCallSession().toggleMute(); });
      this.roundControl('sys.symbol.speaker', '扬声器',
        this.snap !== null && this.snap.speakerOn ? '#66FFFFFF' : CONTROL_BG, 0,
        (): void => { getCallSession().toggleSpeaker(); });
      this.roundControl('sys.symbol.video',
        this.snap !== null && this.snap.localVideoMode !== CALL_VIDEO_OFF ? '关视频' : '视频',
        this.snap !== null && this.snap.localVideoMode !== CALL_VIDEO_OFF
          ? '#66FFFFFF' : CONTROL_BG, 0,
        (): void => {
          const s = this.snap;
          if (s !== null) {
            getCallSession().setVideoMode(
              s.localVideoMode === CALL_VIDEO_OFF ? CALL_VIDEO_FRONT : CALL_VIDEO_OFF);
          }
        });
      if (this.snap !== null && this.snap.localVideoMode !== CALL_VIDEO_OFF) {
        this.roundControl('sys.symbol.arrow_clockwise', '切换', CONTROL_BG, 0,
          (): void => { getCallSession().switchCamera(); });
      }
      // phone_fill 旋转 135° 作挂断（repo 无验证过的 phone_down 符号）。
      this.roundControl('sys.symbol.phone_fill', '挂断', DANGER, 135,
        (): void => { getCallSession().hangup(); });
    }
    .justifyContent(FlexAlign.Center);
  }

  @Builder
  ringingControls() {
    Row() {
      this.roundControl('sys.symbol.phone_fill', '拒绝', DANGER, 135,
        (): void => { getCallSession().decline(); });
      Blank().layoutWeight(1);
      this.roundControl(
        this.snap !== null && this.snap.isVideo ? 'sys.symbol.video' : 'sys.symbol.phone_fill',
        '接听', ACCEPT, 0,
        (): void => { getCallSession().accept(); });
    }
    .width('62%');
  }

  @Builder
  dialingControls() {
    this.roundControl('sys.symbol.phone_fill', '挂断', DANGER, 135,
      (): void => { getCallSession().hangup(); });
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column().width('100%').height('100%').backgroundColor(BG_COLOR);
      // 远端视频全屏（TEXTURE 参与 ArkUI 合成，覆盖层才能正常显示）。
      if (this.videoActive()) {
        XComponent({
          id: 'call_remote_video',
          type: XComponentType.TEXTURE,
          controller: this.remoteController
        })
          .onLoad((): void => {
            getCallSession().setRemoteSurface(this.remoteController.getXComponentSurfaceId());
          })
          .onDestroy((): void => {
            getCallSession().setRemoteSurface('0');
          })
          .width('100%').height('100%');
      }
      Column() {
        this.identityHeader();
        Blank().layoutWeight(1);
        if (this.snap !== null && this.snap.phase === 'ringing') {
          this.ringingControls();
        } else if (this.snap !== null &&
          (this.snap.phase === 'dialing' || this.snap.phase === 'connecting')) {
          this.dialingControls();
        } else if (this.snap !== null && this.snap.phase === 'active') {
          this.activeControls();
        }
      }
      .width('100%').height('100%')
      .padding({ top: this.topSafe + 46, bottom: this.bottomSafe + 42 })
      .alignItems(HorizontalAlign.Center);
      // 本地预览小窗（右上角）。
      if (this.snap !== null && this.snap.localVideoMode !== CALL_VIDEO_OFF &&
        this.snap.phase === 'active') {
        XComponent({
          id: 'call_local_preview',
          type: XComponentType.TEXTURE,
          controller: this.localController
        })
          .onLoad((): void => {
            getCallSession().setLocalSurface(this.localController.getXComponentSurfaceId());
          })
          .onDestroy((): void => {
            getCallSession().setLocalSurface('0');
          })
          .width(104).height(150)
          .borderRadius(10)
          .clip(true)
          .position({ x: '68%', y: this.topSafe + 12 });
      }
    }
    .width('100%').height('100%');
  }
}
