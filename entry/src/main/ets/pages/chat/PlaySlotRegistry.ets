import {
  PlaySlotCandidate, pickPlaySlot, slotKey, PLAY_SLOT_KEEP_RATIO
} from './playSlot';

// 候选表 + 「视觉停顿才判定」的闸门。
//
// 判定只在滚动停下后发生：惯性滑动期间画面在动，此时起播既看不清也白费流量，
// 停下来才是用户「要看这一条」的信号。滚动期间可见比例照常记录，只是不换届。
//
// 唯一的例外是释放：已在播的那条一旦滑出保持线，立刻停 —— 停播不需要等停顿，
// 拖着播才是错的。
//
// 时间由外部注入（tick(now) / setScrolling(scrolling, now)），不在内部读时钟，
// 这样整套时序都能单测。
export const PLAY_SLOT_SETTLE_MS: number = 150;

export type PlaySlotListener = (key: string) => void;

export class PlaySlotRegistry {
  private candidates: Map<string, PlaySlotCandidate> = new Map();
  private listeners: PlaySlotListener[] = [];
  private slot: string = '';
  private pinned: string = '';
  private viewportCenterY: number = 0;
  // 初始视为「未静止」：构造后收到的第一次 setScrolling(false, now) 必须真正
  // 触发一次状态切换（进而记录 stillSince），不能因为和默认值相同而被短路掉。
  private scrolling: boolean = true;
  private stillSince: number = -1;

  subscribe(listener: PlaySlotListener): () => void {
    this.listeners.push(listener);
    return (): void => {
      const at = this.listeners.indexOf(listener);
      if (at >= 0) {
        this.listeners.splice(at, 1);
      }
    };
  }

  current(): string {
    return this.slot;
  }

  setViewportCenter(centerY: number): void {
    this.viewportCenterY = centerY;
  }

  report(messageId: number, albumIndex: number, ratio: number, centerY: number): void {
    const key = slotKey(messageId, albumIndex);
    this.candidates.set(key, { key, messageId, albumIndex, ratio, centerY });
    this.releaseIfGone();
  }

  drop(messageId: number, albumIndex: number): void {
    this.candidates.delete(slotKey(messageId, albumIndex));
    this.releaseIfGone();
  }

  pin(messageId: number, albumIndex: number): void {
    this.pinned = slotKey(messageId, albumIndex);
  }

  setScrolling(scrolling: boolean, now: number): void {
    if (this.scrolling === scrolling) {
      return;
    }
    this.scrolling = scrolling;
    this.stillSince = scrolling ? -1 : now;
  }

  // 每次滚动事件/定时器都可以调；只有静止满 PLAY_SLOT_SETTLE_MS 才真正判定。
  tick(now: number): void {
    if (this.scrolling || this.stillSince < 0 || now - this.stillSince < PLAY_SLOT_SETTLE_MS) {
      return;
    }
    this.elect();
  }

  reset(): void {
    this.candidates.clear();
    this.pinned = '';
    this.stillSince = -1;
    // 与构造函数一致：视为「尚未静止」，避免下一次 setScrolling(false, now)
    // 因为和默认值相等被短路掉，导致 stillSince 永远停在 -1、播放位再也选不出来。
    this.scrolling = true;
    this.setSlot('');
  }

  private list(): PlaySlotCandidate[] {
    const out: PlaySlotCandidate[] = [];
    this.candidates.forEach((c: PlaySlotCandidate): void => { out.push(c); });
    return out;
  }

  private elect(): void {
    this.setSlot(pickPlaySlot(this.list(), this.viewportCenterY, this.slot, this.pinned));
  }

  // 停播不等停顿：在播的那条划出保持线（或整个消失）就立刻释放。
  private releaseIfGone(): void {
    if (this.slot === '') {
      return;
    }
    const playing = this.candidates.get(this.slot);
    if (playing === undefined || playing.ratio < PLAY_SLOT_KEEP_RATIO) {
      if (this.pinned === this.slot) {
        this.pinned = '';
      }
      this.setSlot('');
    }
  }

  private setSlot(key: string): void {
    if (this.slot === key) {
      return;
    }
    this.slot = key;
    for (const listener of this.listeners) {
      listener(key);
    }
  }
}
