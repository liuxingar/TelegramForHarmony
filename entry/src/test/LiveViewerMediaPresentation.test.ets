import { describe, expect, it } from '@ohos/hypium';
import {
  LiveViewerMediaInput, liveViewerMediaPresentation
} from '../main/ets/util/liveViewerMediaPresentation';

function input(mode: string): LiveViewerMediaInput {
  return {
    mode, valid: true, resolved: false, active: false, joined: false,
    joinedOnce: false, recovering: false, ending: false, hasVideo: false, visualReady: false,
    terminalError: false, reconnectAttempt: 0, retrySeconds: 0, retryable: false,
    participantCount: 0, mediaStatus: '正在加入直播…', error: ''
  };
}

export default function liveViewerMediaPresentationTest() {
  describe('LiveViewerMediaPresentation', (): void => {
    it('keeps_initial_state_as_connecting', 0, (): void => {
      expect(liveViewerMediaPresentation(input('group')).kind).assertEqual('connecting');
    });
    it('renders_group_call_without_video_as_audio', 0, (): void => {
      const value = input('group');
      value.joined = true;
      value.joinedOnce = true;
      value.participantCount = 8;
      const result = liveViewerMediaPresentation(value);
      expect(result.kind).assertEqual('audio');
      expect(result.detail).assertEqual('8 人在直播间');
    });
    it('waits_for_rtmp_visual_activity_before_revealing_video', 0, (): void => {
      const value = input('rtmp');
      value.joined = true;
      value.joinedOnce = true;
      value.hasVideo = true;
      expect(liveViewerMediaPresentation(value).kind).assertEqual('videoLoading');
      value.visualReady = true;
      expect(liveViewerMediaPresentation(value).kind).assertEqual('video');
    });
    it('distinguishes_rtmp_audio_and_waiting_states', 0, (): void => {
      const value = input('rtmp');
      value.joined = true;
      value.joinedOnce = true;
      expect(liveViewerMediaPresentation(value).kind).assertEqual('waiting');
      value.mediaStatus = '直播音频播放中';
      expect(liveViewerMediaPresentation(value).kind).assertEqual('audio');
    });
    it('renders_ended_only_after_resolution', 0, (): void => {
      const value = input('rtmp');
      value.resolved = true;
      expect(liveViewerMediaPresentation(value).kind).assertEqual('ended');
    });
    it('describes_scheduled_recovery_and_offers_immediate_retry', 0, (): void => {
      const value = input('rtmp');
      value.resolved = true;
      value.active = true;
      value.joinedOnce = true;
      value.recovering = true;
      value.hasVideo = true;
      value.reconnectAttempt = 3;
      value.retrySeconds = 8;
      value.retryable = true;
      const result = liveViewerMediaPresentation(value);
      expect(result.kind).assertEqual('recovering');
      expect(result.detail).assertEqual('第 3 次尝试 · 8 秒后自动重试');
      expect(result.actionText).assertEqual('立即重试');
      expect(result.keepVisual).assertTrue();
    });
    it('treats_mode_change_as_terminal_error', 0, (): void => {
      const value = input('rtmp');
      value.resolved = true;
      value.active = true;
      value.terminalError = true;
      value.retryable = true;
      const result = liveViewerMediaPresentation(value);
      expect(result.kind).assertEqual('error');
      expect(result.retryable).assertFalse();
      expect(result.title).assertEqual('直播模式已经变化');
    });
  });
}
