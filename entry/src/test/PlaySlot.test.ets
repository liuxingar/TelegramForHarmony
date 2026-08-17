import { describe, it, expect } from '@ohos/hypium';
import {
  pickPlaySlot, slotKey, PlaySlotCandidate,
  PLAY_SLOT_ENTER_RATIO, PLAY_SLOT_KEEP_RATIO
} from '../main/ets/pages/chat/playSlot';

function cand(messageId: number, ratio: number, centerY: number,
  albumIndex: number = -1): PlaySlotCandidate {
  return {
    key: slotKey(messageId, albumIndex),
    messageId, albumIndex, ratio, centerY
  };
}

export default function playSlotTest() {
  describe('playSlot', () => {
    it('阈值本身是有序的', 0, () => {
      expect(PLAY_SLOT_ENTER_RATIO > PLAY_SLOT_KEEP_RATIO).assertTrue();
    });

    it('相册成员与整条消息的 key 不会相撞', 0, () => {
      expect(slotKey(7, -1) === slotKey(7, 0)).assertFalse();
      expect(slotKey(7, 0) === slotKey(7, 1)).assertFalse();
      expect(slotKey(7, -1)).assertEqual(slotKey(7, -1));
    });

    it('没有候选就没有播放位', 0, () => {
      const none: PlaySlotCandidate[] = [];
      expect(pickPlaySlot(none, 500, '', '')).assertEqual('');
    });

    it('可见比例不到入选线的一律落选', 0, () => {
      const list: PlaySlotCandidate[] = [cand(1, 0.5, 500)];
      expect(pickPlaySlot(list, 500, '', '')).assertEqual('');
    });

    it('可见比例最高者当选', 0, () => {
      const list: PlaySlotCandidate[] = [cand(1, 0.7, 300), cand(2, 0.95, 800)];
      expect(pickPlaySlot(list, 500, '', '')).assertEqual(slotKey(2, -1));
    });

    it('比例相同则取离视口中心更近的', 0, () => {
      const list: PlaySlotCandidate[] = [cand(1, 0.8, 200), cand(2, 0.8, 520)];
      expect(pickPlaySlot(list, 500, '', '')).assertEqual(slotKey(2, -1));
    });

    it('迟滞：现任只要还在保持线上就不换届，哪怕对手更高', 0, () => {
      const list: PlaySlotCandidate[] = [cand(1, 0.45, 200), cand(2, 0.9, 520)];
      expect(pickPlaySlot(list, 500, slotKey(1, -1), '')).assertEqual(slotKey(1, -1));
    });

    it('现任跌破保持线就换届', 0, () => {
      const list: PlaySlotCandidate[] = [cand(1, 0.3, 200), cand(2, 0.9, 520)];
      expect(pickPlaySlot(list, 500, slotKey(1, -1), '')).assertEqual(slotKey(2, -1));
    });

    it('现任已经不在候选表里也要换届', 0, () => {
      const list: PlaySlotCandidate[] = [cand(2, 0.9, 520)];
      expect(pickPlaySlot(list, 500, slotKey(1, -1), '')).assertEqual(slotKey(2, -1));
    });

    it('用户手动点播的锁定项优先于比例最高者', 0, () => {
      const list: PlaySlotCandidate[] = [cand(1, 0.45, 200), cand(2, 0.99, 520)];
      expect(pickPlaySlot(list, 500, '', slotKey(1, -1))).assertEqual(slotKey(1, -1));
    });

    it('锁定项跌破保持线即释放，让位给比例最高者', 0, () => {
      const list: PlaySlotCandidate[] = [cand(1, 0.2, 200), cand(2, 0.99, 520)];
      expect(pickPlaySlot(list, 500, '', slotKey(1, -1))).assertEqual(slotKey(2, -1));
    });

    it('锁定项不在候选表里就当没锁定', 0, () => {
      const list: PlaySlotCandidate[] = [cand(2, 0.99, 520)];
      expect(pickPlaySlot(list, 500, '', slotKey(9, -1))).assertEqual(slotKey(2, -1));
    });

    it('相册里最多只有一格当选', 0, () => {
      const list: PlaySlotCandidate[] = [cand(5, 0.8, 480, 0), cand(5, 0.9, 520, 1)];
      const got = pickPlaySlot(list, 500, '', '');
      expect(got).assertEqual(slotKey(5, 1));
    });

    it('入选线是包含边界的', 0, () => {
      const list: PlaySlotCandidate[] = [cand(1, PLAY_SLOT_ENTER_RATIO, 500)];
      expect(pickPlaySlot(list, 500, '', '')).assertEqual(slotKey(1, -1));
    });

    it('比例与离视口中心距离都相同时保留先出现者', 0, () => {
      const list: PlaySlotCandidate[] = [cand(1, 0.8, 400), cand(2, 0.8, 600)];
      expect(pickPlaySlot(list, 500, '', '')).assertEqual(slotKey(1, -1));
    });
  });
}
