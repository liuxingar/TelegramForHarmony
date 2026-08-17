import { describe, it, expect } from '@ohos/hypium';
import { PlaySlotRegistry, PLAY_SLOT_SETTLE_MS } from '../main/ets/pages/chat/PlaySlotRegistry';
import { slotKey } from '../main/ets/pages/chat/playSlot';

export default function playSlotRegistryTest() {
  describe('PlaySlotRegistry', () => {
    it('滚动期间不产生播放位', 0, () => {
      const r = new PlaySlotRegistry();
      r.setViewportCenter(500);
      r.setScrolling(true, 0);
      r.report(1, -1, 0.95, 500);
      r.tick(10_000);
      expect(r.current()).assertEqual('');
    });

    it('停下后不足防抖时间也不判定', 0, () => {
      const r = new PlaySlotRegistry();
      r.setViewportCenter(500);
      r.setScrolling(true, 0);
      r.report(1, -1, 0.95, 500);
      r.setScrolling(false, 1000);
      r.tick(1000 + PLAY_SLOT_SETTLE_MS - 1);
      expect(r.current()).assertEqual('');
    });

    it('停满防抖时间才选出播放位', 0, () => {
      const r = new PlaySlotRegistry();
      r.setViewportCenter(500);
      r.setScrolling(true, 0);
      r.report(1, -1, 0.95, 500);
      r.setScrolling(false, 1000);
      r.tick(1000 + PLAY_SLOT_SETTLE_MS);
      expect(r.current()).assertEqual(slotKey(1, -1));
    });

    it('重新滚动会把计时清零', 0, () => {
      const r = new PlaySlotRegistry();
      r.setViewportCenter(500);
      r.report(1, -1, 0.95, 500);
      r.setScrolling(false, 1000);
      r.setScrolling(true, 1000 + PLAY_SLOT_SETTLE_MS - 10);
      r.tick(1000 + PLAY_SLOT_SETTLE_MS + 100);
      expect(r.current()).assertEqual('');
    });

    it('已在播的那条滚动中跌破保持线要立即释放', 0, () => {
      const r = new PlaySlotRegistry();
      r.setViewportCenter(500);
      r.setScrolling(false, 0);
      r.report(1, -1, 0.95, 500);
      r.tick(PLAY_SLOT_SETTLE_MS);
      expect(r.current()).assertEqual(slotKey(1, -1));
      r.setScrolling(true, 200);
      r.report(1, -1, 0.1, 100);
      expect(r.current()).assertEqual('');
    });

    it('已在播的那条滚动中仍然可见就不打断', 0, () => {
      const r = new PlaySlotRegistry();
      r.setViewportCenter(500);
      r.setScrolling(false, 0);
      r.report(1, -1, 0.95, 500);
      r.tick(PLAY_SLOT_SETTLE_MS);
      r.setScrolling(true, 200);
      r.report(1, -1, 0.55, 400);
      expect(r.current()).assertEqual(slotKey(1, -1));
    });

    it('drop 掉在播的那条等同于失去播放位', 0, () => {
      const r = new PlaySlotRegistry();
      r.setViewportCenter(500);
      r.setScrolling(false, 0);
      r.report(1, -1, 0.95, 500);
      r.tick(PLAY_SLOT_SETTLE_MS);
      r.drop(1, -1);
      expect(r.current()).assertEqual('');
    });

    it('换届只通知一次订阅者', 0, () => {
      const r = new PlaySlotRegistry();
      const seen: string[] = [];
      r.subscribe((key: string): void => { seen.push(key); });
      r.setViewportCenter(500);
      r.setScrolling(false, 0);
      r.report(1, -1, 0.95, 500);
      r.tick(PLAY_SLOT_SETTLE_MS);
      r.tick(PLAY_SLOT_SETTLE_MS + 500);
      expect(seen.length).assertEqual(1);
      expect(seen[0]).assertEqual(slotKey(1, -1));
    });

    it('pin 之后即使比例较低也当选', 0, () => {
      const r = new PlaySlotRegistry();
      r.setViewportCenter(500);
      r.setScrolling(false, 0);
      r.report(1, -1, 0.45, 200);
      r.report(2, -1, 0.99, 520);
      r.pin(1, -1);
      r.tick(PLAY_SLOT_SETTLE_MS);
      expect(r.current()).assertEqual(slotKey(1, -1));
    });

    it('reset 清空一切', 0, () => {
      const r = new PlaySlotRegistry();
      r.setViewportCenter(500);
      r.setScrolling(false, 0);
      r.report(1, -1, 0.95, 500);
      r.tick(PLAY_SLOT_SETTLE_MS);
      r.reset();
      expect(r.current()).assertEqual('');
    });
  });
}
