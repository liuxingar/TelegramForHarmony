// 播放位竞选。
//
// 聊天流是异构变高列表（图片/视频/文字混排，相册九宫格里还能图视频混装，
// LazyForEach 还会回收组件），官方短视频列表那套「按 offset / itemHeight 反推
// 索引」不成立 —— 播放位只能选，不能算。
//
// 判定何时发生由调用方决定（见 PlaySlotRegistry：滚动停下后才跑）。这里只
// 负责：给定一组候选与现任，选出唯一的播放位。

// 入选线：新任必须可见到这个比例才有资格上位。
export const PLAY_SLOT_ENTER_RATIO: number = 0.6;
// 保持线：现任只要还在这条线上就不换届。两条线拉开差距形成迟滞 —— 同屏两个
// 视频时，没有迟滞就会因为几像素的滚动来回夺位，这是最伤体验的抖动。
export const PLAY_SLOT_KEEP_RATIO: number = 0.4;

export interface PlaySlotCandidate {
  key: string;
  messageId: number;
  albumIndex: number; // -1 表示整条消息（非相册）
  ratio: number;      // 可见面积 / 自身面积，[0,1]
  centerY: number;    // 自身中心在窗口坐标系的 y（vp）
}

export function slotKey(messageId: number, albumIndex: number): string {
  return `${messageId}:${albumIndex}`;
}

function find(candidates: PlaySlotCandidate[], key: string): PlaySlotCandidate | null {
  if (key === '') {
    return null;
  }
  for (const c of candidates) {
    if (c.key === key) {
      return c;
    }
  }
  return null;
}

// 比例高者胜；持平时取离视口中心更近的。
function better(a: PlaySlotCandidate, b: PlaySlotCandidate, viewportCenterY: number): boolean {
  if (a.ratio !== b.ratio) {
    return a.ratio > b.ratio;
  }
  return Math.abs(a.centerY - viewportCenterY) < Math.abs(b.centerY - viewportCenterY);
}

export function pickPlaySlot(candidates: PlaySlotCandidate[], viewportCenterY: number,
  current: string, pinned: string): string {
  // 用户手动点播的最优先，直到它自己跌破保持线。
  const locked = find(candidates, pinned);
  if (locked !== null && locked.ratio >= PLAY_SLOT_KEEP_RATIO) {
    return locked.key;
  }
  // 迟滞：现任还在保持线上就连任，哪怕别人可见比例更高。
  const incumbent = find(candidates, current);
  if (incumbent !== null && incumbent.ratio >= PLAY_SLOT_KEEP_RATIO) {
    return incumbent.key;
  }
  let winner: PlaySlotCandidate | null = null;
  for (const c of candidates) {
    if (c.ratio < PLAY_SLOT_ENTER_RATIO) {
      continue;
    }
    if (winner === null || better(c, winner, viewportCenterY)) {
      winner = c;
    }
  }
  return winner === null ? '' : winner.key;
}
