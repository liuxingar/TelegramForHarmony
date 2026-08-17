import {
  PlaySlotCandidate, pickPlaySlot, slotKey, PLAY_SLOT_ENTER_RATIO, PLAY_SLOT_KEEP_RATIO
} from './playSlot';

// 候选表 + 「视觉驻留才判定」的闸门。
//
// 判定主体是单个候选，不是整个列表：某条视频在视野里自己稳住了就该起播，
// 与列表是否仍在滚动无关——视觉停留不是滑动停留。每个候选各自维护一个
// stableSince：从它首次达到入选线（PLAY_SLOT_ENTER_RATIO）的那一刻起计时，
// 一旦某次上报的 ratio 掉到入选线以下，这个候选的 stableSince 清零重来。
// 只有连续达标满 PLAY_SLOT_DWELL_MS 的候选才有资格参与竞选新任——现任的
// 迟滞连任（见 pickPlaySlot）不受驻留门槛约束，否则在播的那条每次 ratio
// 抖动都要重新攒 400ms。
//
// 400ms 的由来：气泡用 onVisibleAreaApproximateChange({ expectedUpdateInterval:
// 200 }) 限频上报可见比例，两个上报周期才算「真的稳住了」，一次性的抖动
// 不算。慢速滑动时某条稳稳占了大半屏数百毫秒 → 起播；快速滑过时某条短暂
// 全屏可见 → 连续驻留凑不满 400ms → 不起播。「滑动中不乱播」是驻留判据的
// 自然结果，不需要额外的滚动闸门。
//
// 释放不等任何计时：已在播的那条一旦 ratio < PLAY_SLOT_KEEP_RATIO 或从候选
// 表消失，立刻释放，见 releaseIfGone()。
//
// 时间由外部注入（report(..., now) / tick(now)），不在内部读时钟，这样整套
// 时序都能单测。
export const PLAY_SLOT_DWELL_MS: number = 400;

export type PlaySlotListener = (key: string) => void;

export class PlaySlotRegistry {
  private candidates: Map<string, PlaySlotCandidate> = new Map();
  // 候选 key -> 它连续满足入选线的起始时刻；不在这个表里的候选要么从未达标，
  // 要么上一次上报已经跌破入选线（见 report()）。
  private stableSince: Map<string, number> = new Map();
  private listeners: PlaySlotListener[] = [];
  private slot: string = '';
  private pinned: string = '';
  private viewportCenterY: number = 0;

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

  report(messageId: number, albumIndex: number, ratio: number, centerY: number, now: number): void {
    const key = slotKey(messageId, albumIndex);
    this.candidates.set(key, { key, messageId, albumIndex, ratio, centerY });
    if (ratio >= PLAY_SLOT_ENTER_RATIO) {
      // 只在首次达标时落下计时起点；已经在计时的不重置，否则永远攒不满。
      if (!this.stableSince.has(key)) {
        this.stableSince.set(key, now);
      }
    } else {
      this.stableSince.delete(key);
    }
    this.releaseIfGone();
    this.elect(now);
  }

  drop(messageId: number, albumIndex: number): void {
    const key = slotKey(messageId, albumIndex);
    this.candidates.delete(key);
    this.stableSince.delete(key);
    this.releaseIfGone();
  }

  pin(messageId: number, albumIndex: number): void {
    this.pinned = slotKey(messageId, albumIndex);
  }

  // 外部定时器在「还有候选没攒满驻留」时调用；重新跑一次判定，不依赖任何
  // 新的可见区回调（onVisibleAreaApproximateChange 只在跨阈值时触发，一条
  // 视频稳稳停着反而不再有任何回调）。
  tick(now: number): void {
    this.elect(now);
  }

  // 下次值得再检查一次的延时（毫秒）；没有候选正在攒驻留时返回 -1。调用方
  // （ChatPage）据此安排一次性定时器，时间到了再调 tick(now)。
  nextCheckDelay(now: number): number {
    let earliest = -1;
    this.stableSince.forEach((since: number): void => {
      const remaining = PLAY_SLOT_DWELL_MS - (now - since);
      if (remaining > 0 && (earliest < 0 || remaining < earliest)) {
        earliest = remaining;
      }
    });
    return earliest;
  }

  reset(): void {
    this.candidates.clear();
    this.stableSince.clear();
    this.pinned = '';
    this.setSlot('');
  }

  // 喂给 pickPlaySlot 的候选表：现任与被 pin 的用真实 ratio（迟滞连任 / 手动
  // 点播都不需要重新攒驻留），其余没攒满 PLAY_SLOT_DWELL_MS 的候选把 ratio
  // 封顶在入选线以下——让它们在「挑新任」的那段循环里天然出局，但仍然留在
  // 候选表里（万一它们就是现任，不能凭空消失）。
  private list(now: number): PlaySlotCandidate[] {
    const out: PlaySlotCandidate[] = [];
    this.candidates.forEach((c: PlaySlotCandidate): void => {
      if (c.key === this.slot || c.key === this.pinned || this.hasDwelled(c.key, now)) {
        out.push(c);
        return;
      }
      const capped: PlaySlotCandidate = {
        key: c.key,
        messageId: c.messageId,
        albumIndex: c.albumIndex,
        ratio: Math.min(c.ratio, PLAY_SLOT_ENTER_RATIO - 0.0001),
        centerY: c.centerY
      };
      out.push(capped);
    });
    return out;
  }

  private hasDwelled(key: string, now: number): boolean {
    const since = this.stableSince.get(key);
    return since !== undefined && now - since >= PLAY_SLOT_DWELL_MS;
  }

  private elect(now: number): void {
    this.setSlot(pickPlaySlot(this.list(now), this.viewportCenterY, this.slot, this.pinned));
  }

  // 停播不等驻留：在播的那条划出保持线（或整个消失）就立刻释放。
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
