import { describe, expect, it } from '@ohos/hypium';
import {
  LiveViewerHeaderInput, liveViewerHeaderPresentation
} from '../main/ets/util/liveViewerHeaderPresentation';

function input(): LiveViewerHeaderInput {
  return {
    valid: true, resolved: false, queryFailed: false, active: false,
    joined: false, joinedOnce: false, recovering: false, ending: false,
    terminalError: false, reconnectAttempt: 0, retrySeconds: 0, canMinimize: false,
    participantCount: 0, mediaStatus: '正在加入直播…'
  };
}

export default function liveViewerHeaderPresentationTest() {
  describe('LiveViewerHeaderPresentation', (): void => {
    it('does_not_render_initial_state_as_ended', 0, (): void => {
      const result = liveViewerHeaderPresentation(input());
      expect(result.kind).assertEqual('connecting');
      expect(result.statusText).assertEqual('正在连接直播…');
    });
    it('renders_ended_only_after_state_resolves', 0, (): void => {
      const value = input();
      value.resolved = true;
      const result = liveViewerHeaderPresentation(value);
      expect(result.kind).assertEqual('ended');
      expect(result.actionsEnabled).assertFalse();
    });
    it('keeps_recovery_and_live_counts_distinct', 0, (): void => {
      const value = input();
      value.resolved = true;
      value.active = true;
      value.joinedOnce = true;
      value.recovering = true;
      value.canMinimize = true;
      expect(liveViewerHeaderPresentation(value).fullscreenText).assertEqual('重连中');
      value.recovering = false;
      value.mediaStatus = '直播播放中';
      value.participantCount = 23;
      expect(liveViewerHeaderPresentation(value).statusText).assertEqual('23 人正在观看');
    });
    it('offers_query_retry_without_enabling_invalid_room_actions', 0, (): void => {
      const failed = input();
      failed.queryFailed = true;
      expect(liveViewerHeaderPresentation(failed).retryable).assertTrue();
      expect(liveViewerHeaderPresentation(failed).actionsEnabled).assertFalse();
      failed.valid = false;
      const invalid = liveViewerHeaderPresentation(failed);
      expect(invalid.retryable).assertFalse();
      expect(invalid.actionsEnabled).assertFalse();
    });
    it('shows_retry_countdown_and_keeps_terminal_errors_non_retryable', 0, (): void => {
      const value = input();
      value.resolved = true;
      value.active = true;
      value.joinedOnce = true;
      value.recovering = true;
      value.reconnectAttempt = 2;
      value.retrySeconds = 4;
      value.canMinimize = true;
      const recovering = liveViewerHeaderPresentation(value);
      expect(recovering.statusText).assertEqual('4 秒后重试 · 轻触立即重试');
      expect(recovering.retryable).assertTrue();
      value.terminalError = true;
      const terminal = liveViewerHeaderPresentation(value);
      expect(terminal.kind).assertEqual('error');
      expect(terminal.retryable).assertFalse();
      expect(terminal.actionsEnabled).assertFalse();
    });
  });
}
