import { describe, it, expect } from '@ohos/hypium';
import { PlaySlotRegistry, PLAY_SLOT_DWELL_MS } from '../main/ets/pages/chat/PlaySlotRegistry';
import { slotKey } from '../main/ets/pages/chat/playSlot';

export default function playSlotRegistryTest() {
  describe('PlaySlotRegistry', () => {
    it('达到入选线但驻留不足不当选', 0, () => {
      const r = new PlaySlotRegistry();
      r.setViewportCenter(500);
      r.report(1, -1, 0.95, 500, 0);
      r.report(1, -1, 0.95, 500, PLAY_SLOT_DWELL_MS - 1);
      expect(r.current()).assertEqual('');
    });

    it('连续满足入选线满驻留时长才当选', 0, () => {
      const r = new PlaySlotRegistry();
      r.setViewportCenter(500);
      r.report(1, -1, 0.95, 500, 0);
      r.report(1, -1, 0.95, 500, PLAY_SLOT_DWELL_MS);
      expect(r.current()).assertEqual(slotKey(1, -1));
    });

    it('tick 也能在驻留满时补一次判定，不必等下一次 report', 0, () => {
      const r = new PlaySlotRegistry();
      r.setViewportCenter(500);
      r.report(1, -1, 0.95, 500, 0);
      expect(r.current()).assertEqual('');
      r.tick(PLAY_SLOT_DWELL_MS);
      expect(r.current()).assertEqual(slotKey(1, -1));
    });

    it('中途跌破入选线再回升，驻留重新计时', 0, () => {
      const r = new PlaySlotRegistry();
      r.setViewportCenter(500);
      r.report(1, -1, 0.95, 500, 0);
      // 驻留攒到一半时跌破入选线：作废。
      r.report(1, -1, 0.5, 500, 200);
      // 立刻回升：从这一刻重新计时，不是接着 0 时刻算。
      r.report(1, -1, 0.95, 500, 210);
      r.tick(210 + PLAY_SLOT_DWELL_MS - 1);
      expect(r.current()).assertEqual('');
      r.tick(210 + PLAY_SLOT_DWELL_MS);
      expect(r.current()).assertEqual(slotKey(1, -1));
    });

    it('在播的那条 ratio 抖动但仍不低于保持线，继续连任不用重新攒驻留', 0, () => {
      const r = new PlaySlotRegistry();
      r.setViewportCenter(500);
      r.report(1, -1, 0.95, 500, 0);
      r.report(1, -1, 0.95, 500, PLAY_SLOT_DWELL_MS);
      expect(r.current()).assertEqual(slotKey(1, -1));
      // 抖到入选线以下、保持线以上：不当新增候选处理，现任直接连任。
      r.report(1, -1, 0.5, 500, PLAY_SLOT_DWELL_MS + 10);
      expect(r.current()).assertEqual(slotKey(1, -1));
    });

    it('在播的那条跌破保持线立即释放，不等任何计时', 0, () => {
      const r = new PlaySlotRegistry();
      r.setViewportCenter(500);
      r.report(1, -1, 0.95, 500, 0);
      r.report(1, -1, 0.95, 500, PLAY_SLOT_DWELL_MS);
      expect(r.current()).assertEqual(slotKey(1, -1));
      r.report(1, -1, 0.1, 500, PLAY_SLOT_DWELL_MS + 5);
      expect(r.current()).assertEqual('');
    });

    it('drop 掉在播的那条等同于失去播放位', 0, () => {
      const r = new PlaySlotRegistry();
      r.setViewportCenter(500);
      r.report(1, -1, 0.95, 500, 0);
      r.report(1, -1, 0.95, 500, PLAY_SLOT_DWELL_MS);
      expect(r.current()).assertEqual(slotKey(1, -1));
      r.drop(1, -1);
      expect(r.current()).assertEqual('');
    });

    it('换届只通知一次订阅者', 0, () => {
      const r = new PlaySlotRegistry();
      const seen: string[] = [];
      r.subscribe((key: string): void => { seen.push(key); });
      r.setViewportCenter(500);
      r.report(1, -1, 0.95, 500, 0);
      r.report(1, -1, 0.95, 500, PLAY_SLOT_DWELL_MS);
      r.tick(PLAY_SLOT_DWELL_MS + 500);
      expect(seen.length).assertEqual(1);
      expect(seen[0]).assertEqual(slotKey(1, -1));
    });

    it('pin 之后即使比例较低、驻留不足也当选', 0, () => {
      const r = new PlaySlotRegistry();
      r.setViewportCenter(500);
      r.report(1, -1, 0.45, 200, 0);
      r.report(2, -1, 0.99, 520, 0);
      r.pin(1, -1);
      r.tick(0);
      expect(r.current()).assertEqual(slotKey(1, -1));
    });

    it('reset 清空一切，包括驻留计时', 0, () => {
      const r = new PlaySlotRegistry();
      r.setViewportCenter(500);
      r.report(1, -1, 0.95, 500, 0);
      r.report(1, -1, 0.95, 500, PLAY_SLOT_DWELL_MS);
      expect(r.current()).assertEqual(slotKey(1, -1));
      r.reset();
      expect(r.current()).assertEqual('');
      // reset 之后重新达标要重新攒够 PLAY_SLOT_DWELL_MS，不能借用之前的计时。
      r.report(1, -1, 0.95, 500, PLAY_SLOT_DWELL_MS + 1);
      expect(r.current()).assertEqual('');
      r.tick(PLAY_SLOT_DWELL_MS + 1 + PLAY_SLOT_DWELL_MS);
      expect(r.current()).assertEqual(slotKey(1, -1));
    });

    it('nextCheckDelay 在有候选攒驻留时返回剩余时长', 0, () => {
      const r = new PlaySlotRegistry();
      r.setViewportCenter(500);
      r.report(1, -1, 0.95, 500, 0);
      expect(r.nextCheckDelay(100)).assertEqual(PLAY_SLOT_DWELL_MS - 100);
    });

    it('nextCheckDelay 在无候选待观察时返回 -1', 0, () => {
      const r = new PlaySlotRegistry();
      r.setViewportCenter(500);
      // 空表：没有任何候选。
      expect(r.nextCheckDelay(0)).assertEqual(-1);
      // 已经攒满驻留、已当选：不再需要观察。
      r.report(1, -1, 0.95, 500, 0);
      r.report(1, -1, 0.95, 500, PLAY_SLOT_DWELL_MS);
      expect(r.current()).assertEqual(slotKey(1, -1));
      expect(r.nextCheckDelay(PLAY_SLOT_DWELL_MS)).assertEqual(-1);
    });

    it('两个候选同屏，比例更高者当选（驻留都攒满后按 pickPlaySlot 规则竞选）', 0, () => {
      const r = new PlaySlotRegistry();
      r.setViewportCenter(500);
      r.report(1, -1, 0.7, 200, 0);
      r.report(2, -1, 0.99, 520, 0);
      r.tick(PLAY_SLOT_DWELL_MS);
      expect(r.current()).assertEqual(slotKey(2, -1));
    });
  });
}
