import { describe, it, expect } from '@ohos/hypium';
import {
  callPhaseLabel, callDurationLabel, callEndLabel
} from '../main/ets/util/callPresentation';

export default function callPresentationTest() {
  describe('CallPresentation', () => {
    it('phase_labels', 0, () => {
      expect(callPhaseLabel('dialing', false)).assertEqual('正在呼叫…');
      expect(callPhaseLabel('ringing', false)).assertEqual('语音来电');
      expect(callPhaseLabel('ringing', true)).assertEqual('视频来电');
      expect(callPhaseLabel('connecting', false)).assertEqual('连接中…');
      expect(callPhaseLabel('active', false)).assertEqual('');
      expect(callPhaseLabel('idle', false)).assertEqual('');
    });
    it('duration_formats_h_m_s', 0, () => {
      expect(callDurationLabel(1000, 1000)).assertEqual('0:00');
      expect(callDurationLabel(1000, 62000)).assertEqual('1:01');
      expect(callDurationLabel(1000, 3662000)).assertEqual('1:01:01');
      // 未接通（startedAtMs=0）不显示计时。
      expect(callDurationLabel(0, 5000)).assertEqual('');
    });
    it('end_labels', 0, () => {
      expect(callEndLabel('hangup', '')).assertEqual('通话已结束');
      expect(callEndLabel('declined', '')).assertEqual('对方已拒绝');
      expect(callEndLabel('missed', '')).assertEqual('未接听');
      expect(callEndLabel('busy', '')).assertEqual('对方忙线中');
      expect(callEndLabel('error', '连接失败')).assertEqual('连接失败');
      expect(callEndLabel('error', '')).assertEqual('通话失败');
    });
  });
}
