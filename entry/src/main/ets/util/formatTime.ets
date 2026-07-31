const WEEKDAYS: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

// Message bubbles always show the message's local clock time. Relative labels
// such as "周二" belong to conversation/search previews, not the timestamp in
// the lower-right corner of an individual message.
export function formatClockTime(unixSec: number): string {
  if (unixSec <= 0) {
    return '';
  }
  const d = new Date(unixSec * 1000);
  return `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
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
    return `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
  }
  const deltaDays = (nowSec - unixSec) / 86400;
  if (deltaDays >= 0 && deltaDays < 7) {
    return WEEKDAYS[d.getDay()];
  }
  if (d.getFullYear() === now.getFullYear()) {
    return `${d.getMonth() + 1}月${d.getDate()}日`;
  }
  return `${d.getFullYear()}/${d.getMonth() + 1}/${d.getDate()}`;
}
