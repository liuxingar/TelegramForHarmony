import {
  IjkMediaPlayer,
  OnBufferingUpdateListener,
  OnCompletionListener,
  OnErrorListener,
  OnInfoListener,
  OnPreparedListener,
  OnVideoSizeChangedListener
} from '@ohos/ijkplayer';
import { audio } from '@kit.AudioKit';
import { getTdClient } from '../../tdkit/Globals';
import { VideoRangeServer } from '../../services/VideoRangeServer';
import { VideoStreamSession } from '../../services/VideoStreamSession';

const CONTROL_BAR_BG: string = '#6e3e3e40';
const CONTROL_ACCENT: string = '#FFFFFF';
const CONTROL_TEXT_SOFT: string = '#EAEEF2'; // over dark video chrome — mode-independent
// Seek bar, back to front: unbuffered track → downloaded span → played span.
const CONTROL_TRACK_SOFT: string = '#4C5259';       // unbuffered remainder
const CONTROL_TRACK_SOFT_FILL: string = '#8E969E';  // downloaded but not played
const CONTROL_TRACK: string = '#FFFFFF';            // played, matches the knob

// Output device types that count as "headphones": unplugging/disconnecting one
// of these pauses playback instead of blasting the speaker.
const HEADSET_DEVICE_TYPES: audio.DeviceType[] = [
  audio.DeviceType.WIRED_HEADSET,
  audio.DeviceType.WIRED_HEADPHONES,
  audio.DeviceType.BLUETOOTH_SCO,
  audio.DeviceType.BLUETOOTH_A2DP
];

const SPEEDS: string[] = ['0.5', '1.0', '1.5', '2.0'];
const SPEED_LABELS: string[] = ['0.5x', '1.0x', '1.5x', '2.0x'];
const DEFAULT_SPEED_IDX: number = 1;
const QUICK_SEEK_MS: number = 15_000;
let nextPlayerInstanceId: number = 1;

// mm:ss (or h:mm:ss for videos over an hour) for the time labels.
function formatMs(ms: number): string {
  const totalSeconds = Math.max(0, Math.floor(ms / 1000));
  const h = Math.floor(totalSeconds / 3600);
  const m = Math.floor((totalSeconds % 3600) / 60);
  const s = totalSeconds % 60;
  const mm = h > 0 ? `${m}`.padStart(2, '0') : `${m}`;
  const ss = `${s}`.padStart(2, '0');
  return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
}

// Download throughput label (bytes/sec → "1.2 MB/s" / "340 KB/s").
function formatSpeed(bytesPerSec: number): string {
  if (bytesPerSec >= 1024 * 1024) {
    return `${(bytesPerSec / (1024 * 1024)).toFixed(1)} MB/s`;
  }
  if (bytesPerSec >= 1024) {
    return `${Math.round(bytesPerSec / 1024)} KB/s`;
  }
  return `${Math.round(bytesPerSec)} B/s`;
}

@Component
export struct StreamingVideoPlayer {
  @Prop fileId: number;
  @Prop fileSize: number;
  @Prop mimeType: string = '';
  @Prop videoWidth: number = 0;
  @Prop videoHeight: number = 0;
  @Prop localPath: string = '';
  @Prop posterPath: string = '';
  @Prop showControls: boolean = true;
  @Prop landscape: boolean = false;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  onBackgroundTap: () => void = (): void => {};
  onSwipeNext: () => void = (): void => {};
  onSwipePrev: () => void = (): void => {};
  onOrientationChange: (landscape: boolean) => void =
    (_landscape: boolean): void => {};
  private player: IjkMediaPlayer | null = null;
  private session: VideoStreamSession | null = null;
  private rangeServer: VideoRangeServer | null = null;
  private progressUnsub: (() => void) | null = null;
  private routingManager: audio.AudioRoutingManager | null = null;
  private deviceChangeCb: ((change: audio.DeviceChangeAction) => void) | null = null;
  private progressTimer: number = -1;
  private seekFeedbackTimer: number = -1;
  private speedFeedbackTimer: number = -1;
  private retryTimer: number = -1;
  private firstFrameTimer: number = -1;
  private surfaceContext: object | null = null;
  private active: boolean = true;
  private readonly playerInstanceId: number = nextPlayerInstanceId++;
  @State status: string = '正在缓冲...';
  @State hasError: boolean = false;
  @State errorDetail: string = '';
  @State isPrepared: boolean = false;
  @State videoVisible: boolean = false;
  @State bufferedPercent: number = 0;
  // Live download throughput (bytes/sec) shown in the control bar; 0 hides it
  // (fully downloaded or stalled). Sampled from the buffered-byte deltas.
  @State downloadSpeed: number = 0;
  private lastBufferedBytes: number = 0;
  private lastSpeedSampleMs: number = 0;
  @State isPlaying: boolean = false;
  @State currentTimeMs: number = 0;
  @State durationMs: number = 0;
  @State dragging: boolean = false;
  @State dragValueMs: number = 0;
  @State speedIdx: number = DEFAULT_SPEED_IDX;
  @State isCompleted: boolean = false;
  @State decodedAspectRatio: number = 0;
  @State viewportWidth: number = 1;
  @State viewportHeight: number = 1;
  @State seekFeedbackSide: number = 0; // -1 = rewind, 1 = forward
  @State seekFeedbackVisible: boolean = false;
  @State speedFeedbackVisible: boolean = false;
  @State speedFeedbackText: string = '';

  aboutToAppear(): void {
    this.active = true;
    if (this.surfaceContext !== null && this.player === null) {
      this.retryTimer = setTimeout((): void => {
        this.retryTimer = -1;
        if (this.active && this.surfaceContext !== null) {
          this.initPlayer(this.surfaceContext);
        }
      }, 0);
    }
  }

  aboutToDisappear(): void {
    this.active = false;
    this.release();
  }

  // Pause when a headset (wired or Bluetooth) disconnects, per platform convention.
  private setupAudioDeviceListener(): void {
    try {
      const routingManager = audio.getAudioManager().getRoutingManager();
      this.routingManager = routingManager;
      this.deviceChangeCb = (change: audio.DeviceChangeAction): void => {
        if (change.type !== audio.DeviceChangeType.DISCONNECT) {
          return;
        }
        const unpluggedHeadset = change.deviceDescriptors.some(
          (d: audio.AudioDeviceDescriptor) => HEADSET_DEVICE_TYPES.includes(d.deviceType));
        if (unpluggedHeadset && this.isPlaying && this.player !== null) {
          this.player.pause();
          this.isPlaying = false;
        }
      };
      routingManager.on('deviceChange', audio.DeviceFlag.OUTPUT_DEVICES_FLAG, this.deviceChangeCb);
    } catch (e) {
      console.error(`StreamingVideoPlayer.setupAudioDeviceListener failed: ${e}`);
    }
  }

  private cleanupAudioDeviceListener(): void {
    if (this.routingManager !== null && this.deviceChangeCb !== null) {
      try {
        this.routingManager.off('deviceChange', this.deviceChangeCb);
      } catch (e) {
        console.error(`StreamingVideoPlayer.cleanupAudioDeviceListener failed: ${e}`);
      }
    }
    this.routingManager = null;
    this.deviceChangeCb = null;
  }

  private release(): void {
    this.cleanupAudioDeviceListener();
    this.stopProgressPolling();
    if (this.seekFeedbackTimer !== -1) {
      clearTimeout(this.seekFeedbackTimer);
      this.seekFeedbackTimer = -1;
    }
    if (this.speedFeedbackTimer !== -1) {
      clearTimeout(this.speedFeedbackTimer);
      this.speedFeedbackTimer = -1;
    }
    if (this.retryTimer !== -1) {
      clearTimeout(this.retryTimer);
      this.retryTimer = -1;
    }
    if (this.firstFrameTimer !== -1) {
      clearTimeout(this.firstFrameTimer);
      this.firstFrameTimer = -1;
    }
    if (this.progressUnsub !== null) {
      this.progressUnsub();
      this.progressUnsub = null;
    }
    if (this.player !== null) {
      const p = this.player;
      this.player = null;
      try {
        // Native release must finish before its HTTP source is closed.
        p.release();
      } catch (e) {
        console.error(`StreamingVideoPlayer.release failed: ${e}`);
      }
    }
    if (this.rangeServer !== null) {
      this.rangeServer.close();
      this.rangeServer = null;
    }
    if (this.session !== null) {
      this.session.close();
      this.session = null;
    }
    this.isPlaying = false;
  }

  private async initPlayer(context: object): Promise<void> {
    if (!this.active || this.player !== null || this.session !== null) {
      return;
    }
    if (this.localPath === '' && this.fileId === 0) {
      this.showError('视频文件不可用');
      return;
    }
    if (this.localPath === '' && this.fileSize <= 0) {
      this.showError('无法获取视频大小');
      return;
    }
    this.surfaceContext = context;
    this.hasError = false;
    this.errorDetail = '';
    this.isPrepared = false;
    this.videoVisible = false;
    this.status = '正在准备视频';
    this.bufferedPercent = this.localPath !== '' ? 100 : 0;
    this.downloadSpeed = 0;
    this.lastBufferedBytes = 0;
    this.lastSpeedSampleMs = 0;
    this.setupAudioDeviceListener();
    let sourceUrl: string = this.localPath;
    let session: VideoStreamSession | null = null;
    try {
      if (sourceUrl === '') {
        session = new VideoStreamSession(getTdClient(), this.fileId, this.fileSize);
        this.session = session;
        this.progressUnsub = session.subscribeProgress((buffered: number, total: number): void => {
          this.bufferedPercent = total > 0 ? Math.min(100, Math.floor((buffered / total) * 100)) : 0;
          // Throughput from the buffered-byte delta between samples (>=400ms apart
          // to smooth out bursty TDLib updates). Fully-downloaded → 0 (hidden).
          const now = Date.now();
          if (total > 0 && buffered >= total) {
            this.downloadSpeed = 0;
          } else if (this.lastSpeedSampleMs === 0) {
            this.lastSpeedSampleMs = now;
            this.lastBufferedBytes = buffered;
          } else {
            const dtMs = now - this.lastSpeedSampleMs;
            if (dtMs >= 400) {
              const dBytes = buffered - this.lastBufferedBytes;
              this.downloadSpeed = dBytes > 0 ? (dBytes / dtMs) * 1000 : 0;
              this.lastSpeedSampleMs = now;
              this.lastBufferedBytes = buffered;
            }
          }
        });
        session.start();
        const rangeServer = new VideoRangeServer(session, this.fileId, this.fileSize, this.mimeType);
        this.rangeServer = rangeServer;
        sourceUrl = await rangeServer.start();
        if (!this.active || this.session !== session) {
          rangeServer.close();
          return;
        }
      }
      const componentId = this.componentId();
      const player = new IjkMediaPlayer(componentId);
      this.player = player;
      player.setContext(context, componentId);
      player.native_setup();
      const preparedListener: OnPreparedListener = {
        onPrepared: (): void => {
          if (this.player !== player) {
            return;
          }
          this.status = '';
          this.hasError = false;
          this.isPrepared = true;
          this.durationMs = Math.max(0, player.getDuration());
          player.setSpeed(SPEEDS[this.speedIdx]);
          player.start();
          this.isPlaying = true;
          this.isCompleted = false;
          this.startProgressPolling();
        }
      };
      const completionListener: OnCompletionListener = {
        onCompletion: (): void => {
          this.isPlaying = false;
          this.isCompleted = true;
          this.currentTimeMs = this.durationMs;
        }
      };
      // bufferedPercent tracks the actual TDLib download (subscribeProgress
      // above), not ijk's playback buffer — ijk reports 100% long before the
      // file is local, which used to make the indicator lie and finish early.
      const bufferingListener: OnBufferingUpdateListener = {
        onBufferingUpdate: (): void => {}
      };
      const infoListener: OnInfoListener = {
        onInfo: (what: number, extra: number): void => {
          if (what === 701) {
            this.status = '正在缓冲';
          } else if (what === 702 || what === 3) {
            this.status = '';
            if (what === 3 && this.firstFrameTimer === -1) {
              // IJK's rendering-start event can arrive one compositor frame
              // before the Surface contains the decoded image. Leave the
              // poster in place through that gap.
              this.firstFrameTimer = setTimeout((): void => {
                this.firstFrameTimer = -1;
                if (this.player === player) {
                  this.videoVisible = true;
                }
              }, 80);
            }
          }
        }
      };
      const errorListener: OnErrorListener = {
        onError: (what: number, extra: number): void => {
          this.isPlaying = false;
          this.showError('播放失败，请稍后重试');
          console.error(`StreamingVideoPlayer error: what=${what}, extra=${extra}`);
        }
      };
      const sizeListener: OnVideoSizeChangedListener = {
        onVideoSizeChanged: (width: number, height: number, sarNum: number, sarDen: number): void => {
          this.updateVideoAspect(width, height, sarNum, sarDen);
        }
      };
      player.setOnPreparedListener(preparedListener);
      player.setOnCompletionListener(completionListener);
      player.setOnBufferingUpdateListener(bufferingListener);
      player.setOnInfoListener(infoListener);
      player.setOnErrorListener(errorListener);
      player.setOnVideoSizeChangedListener(sizeListener);
      player.setMessageListener();
      player.setOptionLong(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'start-on-prepared', '0');
      player.setOptionLong(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'enable-accurate-seek', '1');
      player.setOptionLong(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'soundtouch', '1');
      player.setOptionLong(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'mediacodec-all-videos', '1');
      player.setOptionLong(IjkMediaPlayer.OPT_CATEGORY_FORMAT, 'timeout', '60000000');
      player.setDataSource(sourceUrl);
      player.prepareAsync();
    } catch (e) {
      console.error(`StreamingVideoPlayer.init failed: ${e}`);
      this.release();
      this.showError('视频加载失败，请检查网络后重试');
    }
  }

  private showError(detail: string): void {
    this.status = '';
    this.hasError = true;
    this.errorDetail = detail;
    this.isPrepared = false;
    this.videoVisible = false;
    this.isPlaying = false;
  }

  private retry(): void {
    if (this.surfaceContext === null || !this.active) {
      return;
    }
    const context = this.surfaceContext;
    this.release();
    this.hasError = false;
    this.errorDetail = '';
    this.status = '正在重新连接';
    this.isCompleted = false;
    this.currentTimeMs = 0;
    this.retryTimer = setTimeout((): void => {
      this.retryTimer = -1;
      if (this.active) {
        this.initPlayer(context);
      }
    }, 100);
  }

  private togglePlay(): void {
    if (this.player === null || this.hasError || !this.isPrepared) {
      return;
    }
    if (this.isCompleted) {
      this.replay();
      return;
    }
    if (this.isPlaying) {
      this.player.pause();
      this.isPlaying = false;
    } else {
      this.player.start();
      this.isPlaying = true;
    }
  }

  private replay(): void {
    if (this.player === null) {
      return;
    }
    this.isCompleted = false;
    this.currentTimeMs = 0;
    this.player.seekTo('0');
    this.player.start();
    this.isPlaying = true;
  }

  // Common media-viewer convention: double tap either half to jump exactly
  // 15 seconds. Clamp at the media boundaries and keep the existing
  // play/pause state, so an inspection seek never unexpectedly starts audio.
  private seekBy(deltaMs: number): void {
    if (this.player === null || !this.isPrepared || this.durationMs <= 0 || this.hasError) {
      return;
    }
    const base = this.dragging ? this.dragValueMs : this.currentTimeMs;
    const target = Math.max(0, Math.min(this.durationMs, base + deltaMs));
    this.dragging = false;
    this.currentTimeMs = target;
    this.player.seekTo(`${Math.floor(target)}`);
    if (target < this.durationMs) {
      this.isCompleted = false;
    }
    this.showSeekFeedback(deltaMs < 0 ? -1 : 1);
  }

  private showSeekFeedback(side: number): void {
    if (this.seekFeedbackTimer !== -1) {
      clearTimeout(this.seekFeedbackTimer);
      this.seekFeedbackTimer = -1;
    }
    this.seekFeedbackSide = side;
    this.seekFeedbackVisible = false;
    animateTo({ duration: 120, curve: Curve.EaseOut }, () => {
      this.seekFeedbackVisible = true;
    });
    this.seekFeedbackTimer = setTimeout((): void => {
      this.seekFeedbackTimer = -1;
      animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
        this.seekFeedbackVisible = false;
      });
    }, 520);
  }

  // Drag the seek bar: track the dragged position live (without fighting the
  // player's own timeUpdate events); commit the seek only once the user
  // releases (End) or taps a new spot (Click).
  private onSeekChange(value: number, mode: SliderChangeMode): void {
    if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
      this.dragging = true;
      this.dragValueMs = value;
      return;
    }
    this.dragging = false;
    this.currentTimeMs = value;
    if (this.player !== null) {
      this.player.seekTo(`${Math.floor(value)}`);
    }
  }

  private cycleSpeed(): void {
    const nextIdx: number = (this.speedIdx + 1) % SPEEDS.length;
    let applied: boolean = true;
    if (this.player !== null && this.isPrepared) {
      try {
        this.player.setSpeed(SPEEDS[nextIdx]);
        const nativeSpeed: number = this.player.getSpeed();
        console.info(`StreamingVideoPlayer speed requested=${SPEEDS[nextIdx]}, native=${nativeSpeed}`);
        applied = nativeSpeed <= 0 || Math.abs(nativeSpeed - Number(SPEEDS[nextIdx])) < 0.08;
      } catch (caught) {
        applied = false;
        console.error(`StreamingVideoPlayer.setSpeed failed: ${caught}`);
      }
    }
    // Keep the chosen value even while preparing. onPrepared applies the
    // latest selection, so tapping during an initial buffer is never lost.
    this.speedIdx = nextIdx;
    this.showSpeedFeedback(applied
      ? `播放速度 ${SPEED_LABELS[nextIdx]}`
      : `倍速切换失败`);
  }

  private showSpeedFeedback(text: string): void {
    if (this.speedFeedbackTimer !== -1) {
      clearTimeout(this.speedFeedbackTimer);
      this.speedFeedbackTimer = -1;
    }
    this.speedFeedbackText = text;
    this.speedFeedbackVisible = false;
    animateTo({ duration: 120, curve: Curve.EaseOut }, () => {
      this.speedFeedbackVisible = true;
    });
    this.speedFeedbackTimer = setTimeout((): void => {
      this.speedFeedbackTimer = -1;
      animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
        this.speedFeedbackVisible = false;
      });
    }, 850);
  }

  private onSwipeSwitch(offsetX: number): void {
    if (Math.abs(offsetX) < 50) {
      return;
    }
    if (offsetX < 0) {
      this.onSwipeNext();
    } else {
      this.onSwipePrev();
    }
  }

  private componentId(): string {
    return `stream_video_${this.fileId}_${this.playerInstanceId}`;
  }

  private startProgressPolling(): void {
    this.stopProgressPolling();
    this.progressTimer = setInterval((): void => {
      if (this.player === null) {
        return;
      }
      if (!this.dragging) {
        this.currentTimeMs = Math.max(0, this.player.getCurrentPosition());
      }
      const duration = this.player.getDuration();
      if (duration > 0) {
        this.durationMs = duration;
      }
      this.updateVideoAspect(this.player.getVideoWidth(), this.player.getVideoHeight(),
        this.player.getVideoSarNum(), this.player.getVideoSarDen());
      this.isPlaying = this.player.isPlaying();
      // No buffered-byte update for a while → the download stalled or finished;
      // drop the speed readout instead of leaving a stale value on screen.
      if (this.downloadSpeed > 0 && this.lastSpeedSampleMs > 0
        && Date.now() - this.lastSpeedSampleMs > 1200) {
        this.downloadSpeed = 0;
      }
    }, 350);
  }

  private stopProgressPolling(): void {
    if (this.progressTimer >= 0) {
      clearInterval(this.progressTimer);
      this.progressTimer = -1;
    }
  }

  private updateVideoAspect(width: number, height: number, sarNum: number, sarDen: number): void {
    if (width <= 0 || height <= 0) {
      return;
    }
    const pixelAspect = sarNum > 0 && sarDen > 0 ? sarNum / sarDen : 1;
    const aspect = (width * pixelAspect) / height;
    if (Number.isFinite(aspect) && aspect > 0 && Math.abs(aspect - this.decodedAspectRatio) > 0.001) {
      this.decodedAspectRatio = aspect;
    }
  }

  private displayAspectRatio(): number {
    if (this.decodedAspectRatio > 0) {
      return this.decodedAspectRatio;
    }
    if (this.videoWidth > 0 && this.videoHeight > 0) {
      return this.videoWidth / this.videoHeight;
    }
    return 16 / 9;
  }

  private surfaceWidth(): number {
    const aspect = this.displayAspectRatio();
    const viewportAspect = this.viewportWidth / this.viewportHeight;
    return viewportAspect > aspect ? this.viewportHeight * aspect : this.viewportWidth;
  }

  private surfaceHeight(): number {
    const aspect = this.displayAspectRatio();
    const viewportAspect = this.viewportWidth / this.viewportHeight;
    return viewportAspect > aspect ? this.viewportHeight : this.viewportWidth / aspect;
  }

  private posterSrc(): string {
    return this.posterPath.startsWith('/') ? `file://${this.posterPath}` : this.posterPath;
  }

  @Styles
  controlNormalStyle() {
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  controlPressedStyle() {
    .opacity(0.68)
    .scale({ x: 0.9, y: 0.9 })
  }

  @Builder
  tapZone(forward: boolean) {
    Column()
      .width('50%')
      .height('100%')
      .backgroundColor(Color.Transparent)
      .accessibilityText(forward ? '双击快进15秒' : '双击快退15秒')
      .gesture(
        GestureGroup(GestureMode.Exclusive,
          TapGesture({ count: 2, fingers: 1 })
            .onAction((): void => { this.seekBy(forward ? QUICK_SEEK_MS : -QUICK_SEEK_MS); }),
          TapGesture({ count: 1, fingers: 1 })
            .onAction((): void => { this.onBackgroundTap(); })
        )
      );
  }

  @Builder
  seekFeedback() {
    Row() {
      Column({ space: 3 }) {
        if (this.seekFeedbackSide < 0) {
          SymbolGlyph($r('sys.symbol.gobackward_15'))
            .fontSize(36).fontColor([Color.White]);
        } else {
          SymbolGlyph($r('sys.symbol.goforward_15'))
            .fontSize(36).fontColor([Color.White]);
        }
        Text(this.seekFeedbackSide < 0 ? '后退 15 秒' : '快进 15 秒')
          .fontSize(12)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Medium);
      }
      .width(96)
      .height(96)
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#66000000')
      .borderRadius(48)
      .opacity(this.seekFeedbackVisible && this.seekFeedbackSide < 0 ? 1 : 0)
      .scale({
        x: this.seekFeedbackVisible && this.seekFeedbackSide < 0 ? 1 : 0.82,
        y: this.seekFeedbackVisible && this.seekFeedbackSide < 0 ? 1 : 0.82
      });
      Blank().layoutWeight(1);
      Column({ space: 3 }) {
        if (this.seekFeedbackSide < 0) {
          SymbolGlyph($r('sys.symbol.gobackward_15'))
            .fontSize(36).fontColor([Color.White]);
        } else {
          SymbolGlyph($r('sys.symbol.goforward_15'))
            .fontSize(36).fontColor([Color.White]);
        }
        Text(this.seekFeedbackSide < 0 ? '后退 15 秒' : '快进 15 秒')
          .fontSize(12)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Medium);
      }
      .width(96)
      .height(96)
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#66000000')
      .borderRadius(48)
      .opacity(this.seekFeedbackVisible && this.seekFeedbackSide > 0 ? 1 : 0)
      .scale({
        x: this.seekFeedbackVisible && this.seekFeedbackSide > 0 ? 1 : 0.82,
        y: this.seekFeedbackVisible && this.seekFeedbackSide > 0 ? 1 : 0.82
      });
    }
    .width('100%')
    .padding({ left: 24, right: 24 })
    .hitTestBehavior(HitTestMode.None);
  }

  @Builder
  symbolControl(symbol: string, width: number, symbolSize: number, onTap: () => void) {
    Row() {
      SymbolGlyph($r(symbol))
        .fontSize(symbolSize)
        .fontColor([CONTROL_ACCENT]);
    }
    .width(width)
    .height(34)
    .justifyContent(FlexAlign.Center)
    .borderRadius(17)
    .stateStyles({
      normal: this.controlNormalStyle,
      pressed: this.controlPressedStyle
    })
    .animation({ duration: 120, curve: Curve.EaseOut })
    .onClick(onTap);
  }

  @Builder
  speedControl() {
    Row() {
      Text(SPEED_LABELS[this.speedIdx])
        .fontSize(15)
        .fontColor(CONTROL_ACCENT)
        .fontWeight(FontWeight.Bold);
    }
    .width(48)
    .height(36)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.speedIdx === DEFAULT_SPEED_IDX ? Color.Transparent : '#24FFFFFF')
    .borderRadius(18)
    .stateStyles({
      normal: this.controlNormalStyle,
      pressed: this.controlPressedStyle
    })
    .animation({ duration: 120, curve: Curve.EaseOut })
    .accessibilityText(`当前${SPEED_LABELS[this.speedIdx]}倍速，点击切换`)
    .onClick((): void => { this.cycleSpeed(); });
  }

  @Builder
  playControl() {
    Stack() {
      Circle({ width: 42, height: 42 }).fill('#00000000');
      if (this.isPlaying) {
        Row({ space: 5 }) {
          Column().width(4).height(16).borderRadius(2).backgroundColor(CONTROL_ACCENT);
          Column().width(4).height(16).borderRadius(2).backgroundColor(CONTROL_ACCENT);
        }
        .width(18).height(18)
        .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center);
      } else {
        SymbolGlyph($r('sys.symbol.play_fill')).fontSize(22).fontColor([CONTROL_ACCENT]).margin({ left: 2 });
      }
    }
    .width(56).height(42)
    .borderRadius(21)
    .stateStyles({
      normal: this.controlNormalStyle,
      pressed: this.controlPressedStyle
    })
    .animation({ duration: 120, curve: Curve.EaseOut })
    .onClick(() => { this.togglePlay(); });
  }

  build() {
    Stack() {
      if (this.posterPath !== '') {
        Image(this.posterSrc())
          .width(this.surfaceWidth())
          .height(this.surfaceHeight())
          .objectFit(ImageFit.Contain)
          .opacity(this.hasError ? 0.54 : 0.88);
      }
      XComponent({ id: this.componentId(), type: XComponentType.SURFACE, libraryname: 'ijkplayer_napi' })
        .width(this.surfaceWidth()).height(this.surfaceHeight())
        .opacity(this.videoVisible ? 1 : 0)
        .animation({ duration: 180, curve: Curve.EaseOut })
        .onLoad((context: object) => {
          this.surfaceContext = context;
          this.initPlayer(context);
        })
        .onDestroy(() => {
          this.release();
          this.surfaceContext = null;
        });
      // Controls hidden → both halves remain interactive. Exclusive recognition
      // delays the single tap just enough to distinguish the double-tap seek.
      if (!this.showControls) {
        Row() {
          this.tapZone(false);
          this.tapZone(true);
        }
        .width('100%')
        .height('100%');
      }
      // Actual prepare/stall state: centered and explicit, while the poster
      // remains visible underneath instead of flashing a featureless black frame.
      if (this.status !== '' && !this.hasError) {
        Column({ space: 8 }) {
          if (this.bufferedPercent > 0 && this.bufferedPercent < 100) {
            Stack() {
              Progress({ value: this.bufferedPercent, total: 100, type: ProgressType.Ring })
                .width(44).height(44).color(Color.White);
              Text(`${this.bufferedPercent}%`).fontSize(10).fontColor(Color.White);
            }
          } else {
            LoadingProgress().width(38).height(38).color(Color.White);
          }
          Text(this.status)
            .fontSize(13)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Medium);
        }
        .alignItems(HorizontalAlign.Center)
        .padding({ left: 18, right: 18, top: 15, bottom: 15 })
        .backgroundColor('#70000000')
        .borderRadius(16)
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.9, y: 0.9 }))
          .animation({ duration: 180, curve: Curve.EaseOut }));
      }
      if (this.hasError) {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
            .fontSize(30)
            .fontColor([Color.White]);
          Text('视频播放失败')
            .fontSize(14)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Medium);
          Text(this.errorDetail)
            .fontSize(11)
            .fontColor(CONTROL_TEXT_SOFT)
            .maxLines(2)
            .textAlign(TextAlign.Center);
          Row({ space: 5 }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(13).fontColor([Color.White]);
            Text('重试').fontSize(13).fontColor(Color.White).fontWeight(FontWeight.Medium);
          }
          .height(34)
          .padding({ left: 15, right: 15 })
          .backgroundColor('#29FFFFFF')
          .borderRadius(17)
          .stateStyles({
            normal: this.controlNormalStyle,
            pressed: this.controlPressedStyle
          })
          .animation({ duration: 120, curve: Curve.EaseOut })
          .onClick((): void => { this.retry(); });
        }
        .constraintSize({ minWidth: 180, maxWidth: 248 })
        .padding({ left: 20, right: 20, top: 17, bottom: 16 })
        .backgroundColor('#78000000')
        .borderRadius(18)
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.9, y: 0.9 }))
          .animation({ duration: 180, curve: Curve.EaseOut }));
      }
      this.seekFeedback();
      if (this.speedFeedbackVisible) {
        Row() {
          Text(this.speedFeedbackText)
            .fontSize(14)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Medium);
        }
        .height(38)
        .padding({ left: 16, right: 16 })
        .backgroundColor('#78000000')
        .borderRadius(19)
        .opacity(this.speedFeedbackVisible ? 1 : 0)
        .scale({
          x: this.speedFeedbackVisible ? 1 : 0.88,
          y: this.speedFeedbackVisible ? 1 : 0.88
        })
        .hitTestBehavior(HitTestMode.None);
      }
      if (this.isCompleted) {
        Stack() {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(25).fontColor([Color.White]);
            Text('重播').fontSize(18).fontColor(Color.White).fontWeight(FontWeight.Medium);
          }
          .padding({ left: 20, right: 20, top: 14, bottom: 14 })
          .backgroundColor(CONTROL_BAR_BG)
          .borderRadius(20);
        }
        .constraintSize({ minWidth: 140, minHeight: 64 })
        .stateStyles({
          normal: this.controlNormalStyle,
          pressed: this.controlPressedStyle
        })
        .animation({ duration: 120, curve: Curve.EaseOut })
        .onClick(() => { this.replay(); });
      }
      if (this.showControls && !this.hasError) {
        Column() {
          Row() {
            this.tapZone(false);
            this.tapZone(true);
          }
          .width('100%')
          .layoutWeight(1);
          Column({ space: 10 }) {
            Row() {
              // Live download speed on the left (mirrors the play control on the
              // right), so the centered play button stays centered.
              Row({ space: 3 }) {
                if (this.downloadSpeed > 0) {
                  SymbolGlyph($r('sys.symbol.arrow_down')).fontSize(12).fontColor([CONTROL_TEXT_SOFT]);
                  Text(formatSpeed(this.downloadSpeed))
                    .fontSize(11).fontColor(CONTROL_TEXT_SOFT).fontWeight(FontWeight.Medium);
                }
              }
              .layoutWeight(1)
              .justifyContent(FlexAlign.Start)
              .alignItems(VerticalAlign.Center);
              this.playControl();
              Row({ space: 8 }) {
                this.symbolControl('sys.symbol.arrow_clockwise', 34, 19, () => { this.replay(); });
                this.speedControl();
                this.symbolControl(
                  this.landscape
                    ? 'sys.symbol.rectangle_portrait_rotate'
                    : 'sys.symbol.rectangle_rotate',
                  40,
                  25,
                  () => {
                    this.onOrientationChange(!this.landscape);
                  }
                );
              }
              .layoutWeight(1)
              .justifyContent(FlexAlign.End)
              .alignItems(VerticalAlign.Center);
            }.width('100%').alignItems(VerticalAlign.Center);
            Row({ space: 8 }) {
              Text(formatMs(this.dragging ? this.dragValueMs : this.currentTimeMs))
                .fontSize(11).fontColor(CONTROL_TEXT_SOFT).fontWeight(FontWeight.Medium);
              // Alignment.Start = left edge, vertically centered. With Center the
              // partial-width fill rows get centered in the track and appear to
              // grow outward from the middle instead of filling left-to-right.
              Stack() {
                Row()
                  .width('100%').height(4).borderRadius(2).backgroundColor(CONTROL_TRACK_SOFT);
                // Downloaded/buffered span — grey, behind the played fill.
                Row()
                  .width(`${Math.max(0, Math.min(100, this.bufferedPercent))}%`)
                  .height(4).borderRadius(2).backgroundColor(CONTROL_TRACK_SOFT_FILL);
                Row()
                  .width(this.durationMs > 0
                    ? `${Math.max(0, Math.min(100, ((this.dragging ? this.dragValueMs : this.currentTimeMs) / this.durationMs) * 100))}%`
                    : '0%')
                  .height(4).borderRadius(2).backgroundColor(CONTROL_TRACK);
                Slider({
                  value: this.dragging ? this.dragValueMs : this.currentTimeMs,
                  min: 0, max: this.durationMs > 0 ? this.durationMs : 1, step: 1
                })
                  .width('100%')
                  .trackColor('#00000000').selectedColor('#00000000').blockColor(CONTROL_ACCENT)
                  .blockSize({ width: 16, height: 16 })
                  .onChange((value: number, mode: SliderChangeMode) => { this.onSeekChange(value, mode); });
              }
              .layoutWeight(1)
              .height(20)
              .align(Alignment.Start);
              Text(formatMs(this.durationMs)).fontSize(11).fontColor(CONTROL_TEXT_SOFT).fontWeight(FontWeight.Medium);
            }.width('100%').alignItems(VerticalAlign.Center);
          }
          .margin({
            left: 12,
            right: 12,
            bottom: Math.max(14, this.bottomSafe + 8)
          })
          .padding({ left: 14, right: 14, top: 12, bottom: 12 })
          .backgroundColor(CONTROL_BAR_BG)
          .borderRadius(18)
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.translate({ y: 10 }))
            .animation({ duration: 180, curve: Curve.EaseOut }));
          // NOTE: no hitTestBehavior on this wrapper or the bar. Block suppresses
          // hit-testing of CHILDREN (killed every button), and Transparent leaks
          // gesture events through to the XComponent (buttons lose to its onClick).
        }
        .width('100%')
        .height('100%')
        .transition(TransitionEffect.OPACITY
          .animation({ duration: 160, curve: Curve.EaseOut }));
      }
    }
    .width('100%').height('100%').backgroundColor(Color.Black)
    .onAreaChange((_old: Area, area: Area): void => {
      const width = area.width as number;
      const height = area.height as number;
      if (width > 0 && height > 0) {
        this.viewportWidth = width;
        this.viewportHeight = height;
      }
    });
  }
}
