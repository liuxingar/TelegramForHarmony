import { describe, it, expect } from '@ohos/hypium';
import { formatClockTime, formatTime } from '../main/ets/util/formatTime';

function pad2(n: number): string { return n < 10 ? `0${n}` : `${n}`; }
const WD: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
const NOW = 1783512000;

export default function formatTimeTest() {
  describe('formatTime', () => {
    it('empty_for_zero', 0, () => {
      expect(formatTime(0, NOW)).assertEqual('');
    });
    it('same_day_hh_mm', 0, () => {
      const d = new Date(NOW * 1000);
      expect(formatTime(NOW, NOW)).assertEqual(`${pad2(d.getHours())}:${pad2(d.getMinutes())}`);
    });
    it('message_clock_is_hh_mm_even_for_old_messages', 0, () => {
      const old = NOW - 400 * 86400;
      const d = new Date(old * 1000);
      expect(formatClockTime(old)).assertEqual(`${pad2(d.getHours())}:${pad2(d.getMinutes())}`);
      expect(formatClockTime(0)).assertEqual('');
    });
    it('within_week_weekday', 0, () => {
      const t = NOW - 3 * 86400;
      const d = new Date(t * 1000);
      expect(formatTime(t, NOW)).assertEqual(WD[d.getDay()]);
    });
    it('same_year_month_day', 0, () => {
      const t = NOW - 100 * 86400;
      const d = new Date(t * 1000);
      const n = new Date(NOW * 1000);
      if (d.getFullYear() === n.getFullYear()) {
        expect(formatTime(t, NOW)).assertEqual(`${d.getMonth() + 1}月${d.getDate()}日`);
      } else {
        expect(formatTime(t, NOW)).assertEqual(`${d.getFullYear()}/${d.getMonth() + 1}/${d.getDate()}`);
      }
    });
    it('older_numeric', 0, () => {
      const t = NOW - 400 * 86400;
      const d = new Date(t * 1000);
      expect(formatTime(t, NOW)).assertEqual(`${d.getFullYear()}/${d.getMonth() + 1}/${d.getDate()}`);
    });
  });
}
