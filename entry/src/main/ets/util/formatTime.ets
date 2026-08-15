import { clockTime, fullDate, monthDay, weekdayShort } from './intlFormat';

// Message bubbles always show the message's local clock time. Relative labels
// such as "周二" belong to conversation/search previews, not the timestamp in
// the lower-right corner of an individual message.
export function formatClockTime(unixSec: number): string {
  if (unixSec <= 0) {
    return '';
  }
  return clockTime(new Date(unixSec * 1000));
}

export function formatTime(unixSec: number, nowSec: number): string {
  if (unixSec <= 0) {
    return '';
  }
  const d = new Date(unixSec * 1000);
  const now = new Date(nowSec * 1000);
  const sameDay = d.getFullYear() === now.getFullYear()
    && d.getMonth() === now.getMonth()
    && d.getDate() === now.getDate();
  if (sameDay) {
    return clockTime(d);
  }
  const deltaDays = (nowSec - unixSec) / 86400;
  if (deltaDays >= 0 && deltaDays < 7) {
    return weekdayShort(d);
  }
  if (d.getFullYear() === now.getFullYear()) {
    return monthDay(d);
  }
  return fullDate(d);
}
