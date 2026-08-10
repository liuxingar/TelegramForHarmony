import { router } from '@kit.ArkUI';
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

  @Builder
  roundControl(symbol: string, bg: string, onTap: () => void) {
    Column() {
      SymbolGlyph($r(symbol)).fontSize(26).fontColor([Color.White]);
    }
    .width(58).height(58).borderRadius(29)
    .backgroundColor(bg)
    .justifyContent(FlexAlign.Center)
    .onClick((): void => { onTap(); });
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
    Row({ space: 22 }) {
      this.roundControl(
        this.snap !== null && this.snap.muted ? 'sys.symbol.microphone_slash' : 'sys.symbol.microphone',
        this.snap !== null && this.snap.muted ? '#66FFFFFF' : CONTROL_BG,
        (): void => { getCallSession().toggleMute(); });
      this.roundControl(
        'sys.symbol.speaker_wave_2',
        this.snap !== null && this.snap.speakerOn ? '#66FFFFFF' : CONTROL_BG,
        (): void => { getCallSession().toggleSpeaker(); });
      this.roundControl(
        this.snap !== null && this.snap.localVideoMode !== CALL_VIDEO_OFF
          ? 'sys.symbol.video' : 'sys.symbol.video_slash',
        CONTROL_BG,
        (): void => {
          const s = this.snap;
          if (s !== null) {
            getCallSession().setVideoMode(
              s.localVideoMode === CALL_VIDEO_OFF ? CALL_VIDEO_FRONT : CALL_VIDEO_OFF);
          }
        });
      if (this.snap !== null && this.snap.localVideoMode !== CALL_VIDEO_OFF) {
        this.roundControl('sys.symbol.camera_rotate', CONTROL_BG,
          (): void => { getCallSession().switchCamera(); });
      }
      this.roundControl('sys.symbol.phone_down_fill', DANGER,
        (): void => { getCallSession().hangup(); });
    }
    .justifyContent(FlexAlign.Center);
  }

  @Builder
  ringingControls() {
    Row() {
      Column({ space: 8 }) {
        this.roundControl('sys.symbol.phone_down_fill', DANGER,
          (): void => { getCallSession().decline(); });
        Text('拒绝').fontSize(13).fontColor('#B8C4CF');
      }
      Blank().layoutWeight(1);
      Column({ space: 8 }) {
        this.roundControl(
          this.snap !== null && this.snap.isVideo ? 'sys.symbol.video' : 'sys.symbol.phone_fill',
          ACCEPT,
          (): void => { getCallSession().accept(); });
        Text('接听').fontSize(13).fontColor('#B8C4CF');
      }
    }
    .width('62%');
  }

  @Builder
  dialingControls() {
    this.roundControl('sys.symbol.phone_down_fill', DANGER,
      (): void => {
        const s = this.snap;
        if (s !== null && s.phase === 'ringing') {
          getCallSession().decline();
        } else {
          getCallSession().hangup();
        }
      });
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
