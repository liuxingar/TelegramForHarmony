import { describe, it, expect } from '@ohos/hypium';
import { TdObject } from '../main/ets/tdkit/TdTypes';
import {
  callClockLabel, callSectionLabel, callStatus, compactCallDuration, parseCallContent
} from '../main/ets/util/CallHistoryPresentation';

function standardCall(reasonType: string, isVideo: boolean = false, duration: number = 0): TdObject {
  const reason: TdObject = { '@type': reasonType };
  const content: TdObject = { '@type': 'messageCall' };
  content['discard_reason'] = reason;
  content['is_video'] = isVideo;
  content['duration'] = duration;
  return content;
}

export default function callHistoryPresentationTest() {
  describe('CallHistoryPresentation', () => {
    it('parses_incoming_missed_video_call', 0, () => {
      const parsed = parseCallContent(standardCall('callDiscardReasonMissed', true), false);
      const status = callStatus(parsed, false);
      expect(parsed.valid).assertTrue();
      expect(parsed.missed).assertTrue();
      expect(parsed.isVideo).assertTrue();
      expect(status.text).assertEqual('未接视频来电');
      expect(status.tone).assertEqual('missed');
    });

    it('describes_answered_and_declined_outgoing_calls', 0, () => {
      const answered = parseCallContent(standardCall('callDiscardReasonHungUp', false, 125), true);
      expect(callStatus(answered, true).text).assertEqual('呼出语音通话 · 2分5秒');
      const declined = parseCallContent(standardCall('callDiscardReasonDeclined', false), true);
      expect(callStatus(declined, true).text).assertEqual('对方已拒绝语音通话');
    });

    it('parses_active_and_missed_group_calls', 0, () => {
      const participant: TdObject = { '@type': 'messageSenderUser' };
      participant['user_id'] = 7;
      const active: TdObject = { '@type': 'messageGroupCall' };
      active['is_active'] = true;
      active['is_video'] = false;
      active['other_participant_ids'] = [participant];
      const parsedActive = parseCallContent(active, false);
      expect(parsedActive.participantCount).assertEqual(2);
      expect(callStatus(parsedActive, false).text).assertEqual('群组语音通话进行中');

      const missed: TdObject = { '@type': 'messageGroupCall' };
      missed['was_missed'] = true;
      missed['is_video'] = true;
      const parsedMissed = parseCallContent(missed, false);
      expect(parsedMissed.missed).assertTrue();
      expect(callStatus(parsedMissed, false).text).assertEqual('未接群组视频通话');
    });

    it('formats_duration_and_day_boundaries', 0, () => {
      expect(compactCallDuration(59)).assertEqual('59秒');
      expect(compactCallDuration(3600)).assertEqual('1小时');
      const now = new Date(2026, 7, 6, 17, 5, 0);
      const yesterday = new Date(2026, 7, 5, 9, 7, 0);
      expect(callSectionLabel(Math.floor(now.getTime() / 1000), Math.floor(now.getTime() / 1000)))
        .assertEqual('今天');
      expect(callSectionLabel(Math.floor(yesterday.getTime() / 1000), Math.floor(now.getTime() / 1000)))
        .assertEqual('昨天');
      expect(callClockLabel(Math.floor(yesterday.getTime() / 1000))).assertEqual('09:07');
    });
  });
}
