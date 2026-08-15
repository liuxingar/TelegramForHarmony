import { describe, it, expect } from '@ohos/hypium';
import { formatClockTime, formatTime } from '../main/ets/util/formatTime';
import { clockTime, fullDate, monthDay, weekdayShort } from '../main/ets/util/intlFormat';

const NOW = 1783512000;

// formatTime's own logic is branch selection — which of the four renderings a
// timestamp gets. The renderings themselves are Intl's job, so the assertions
// name the expected primitive rather than a hardcoded Chinese string; pinning
// "周二" here would only re-test ICU and would break the moment the app runs in
// another language.
export default function formatTimeTest() {
  describe('formatTime', () => {
    it('empty_for_zero', 0, () => {
      expect(formatTime(0, NOW)).assertEqual('');
    });
    it('same_day_hh_mm', 0, () => {
      expect(formatTime(NOW, NOW)).assertEqual(clockTime(new Date(NOW * 1000)));
    });
    it('message_clock_is_hh_mm_even_for_old_messages', 0, () => {
      const old = NOW - 400 * 86400;
      expect(formatClockTime(old)).assertEqual(clockTime(new Date(old * 1000)));
      expect(formatClockTime(0)).assertEqual('');
    });
    it('within_week_weekday', 0, () => {
      const t = NOW - 3 * 86400;
      expect(formatTime(t, NOW)).assertEqual(weekdayShort(new Date(t * 1000)));
    });
    it('same_year_month_day', 0, () => {
      const t = NOW - 100 * 86400;
      const d = new Date(t * 1000);
      const n = new Date(NOW * 1000);
      if (d.getFullYear() === n.getFullYear()) {
        expect(formatTime(t, NOW)).assertEqual(monthDay(d));
      } else {
        expect(formatTime(t, NOW)).assertEqual(fullDate(d));
      }
    });
    it('older_numeric', 0, () => {
      const t = NOW - 400 * 86400;
      expect(formatTime(t, NOW)).assertEqual(fullDate(new Date(t * 1000)));
    });
    // The four branches must actually differ; without this the test above would
    // still pass if every branch returned the same thing.
    it('four_branches_are_distinct', 0, () => {
      const sameDay = formatTime(NOW, NOW);
      const week = formatTime(NOW - 3 * 86400, NOW);
      const year = formatTime(NOW - 100 * 86400, NOW);
      const older = formatTime(NOW - 400 * 86400, NOW);
      expect(sameDay === week).assertFalse();
      expect(week === year).assertFalse();
      expect(year === older).assertFalse();
    });
  });
}
