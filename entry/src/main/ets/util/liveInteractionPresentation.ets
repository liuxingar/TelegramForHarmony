export interface LiveInteractionEntry {
  key: string;
  revision: string;
  source: string;
  id: number;
  senderKey: string;
  senderName: string;
  senderInitials: string;
  senderAvatarPath: string;
  colorSeed: number;
  date: number;
  text: string;
  photoPath: string;
  emojiOnly: boolean;
  isFromOwner: boolean;
  sendState: string;
  arrivalOrder: number;
}

export interface LiveInteractionPresentationInput {
  valid: boolean;
  resolved: boolean;
  active: boolean;
  joined: boolean;
  joinedOnce: boolean;
  recovering: boolean;
  messagesAllowed: boolean;
  canSendMessages: boolean;
  messageCount: number;
  channelAttached: boolean;
  channelHistoryState: string;
  channelHistoryError: string;
}

export interface LiveInteractionPresentation {
  kind: string;
  statusText: string;
  statusTone: string;
  subtitle: string;
  emptyTitle: string;
  emptyDetail: string;
  composerEnabled: boolean;
  composerHint: string;
  showProgress: boolean;
  showHistoryRetry: boolean;
}

function normalizedMessageText(value: string): string {
  return value.trim().toLocaleLowerCase();
}

export function sameLiveInteraction(left: LiveInteractionEntry, right: LiveInteractionEntry): boolean {
  if (left.key === right.key) { return true; }
  if (left.source === right.source || left.senderKey === '' || left.senderKey !== right.senderKey) {
    return false;
  }
  if (Math.abs(left.date - right.date) > 1) { return false; }
  const leftText = normalizedMessageText(left.text);
  return leftText !== '' && leftText === normalizedMessageText(right.text);
}

// The live overlay and channel history are separate TDLib namespaces. Merge by
// server date, then keep a page-local arrival order as the deterministic tie
// breaker. Cross-source dedupe is intentionally conservative so repeated emoji
// sent by a real user are never collapsed merely because they look alike.
export function mergeLiveInteractions(
  candidates: LiveInteractionEntry[], limit: number
): LiveInteractionEntry[] {
  const ordered = candidates.slice();
  ordered.sort((left: LiveInteractionEntry, right: LiveInteractionEntry): number => {
    if (left.date !== right.date) { return left.date - right.date; }
    if (left.arrivalOrder !== right.arrivalOrder) { return left.arrivalOrder - right.arrivalOrder; }
    return left.key < right.key ? -1 : (left.key > right.key ? 1 : 0);
  });
  const deduped: LiveInteractionEntry[] = [];
  for (const candidate of ordered) {
    const duplicateIndex = deduped.findIndex(
      (entry: LiveInteractionEntry): boolean => sameLiveInteraction(entry, candidate)
    );
    if (duplicateIndex < 0) {
      deduped.push(candidate);
    } else if (candidate.source === 'call' && deduped[duplicateIndex].source !== 'call') {
      // Group-call messages carry Telegram's authoritative owner flag.
      deduped[duplicateIndex] = candidate;
    }
  }
  const boundedLimit = Math.max(1, limit);
  return deduped.length > boundedLimit
    ? deduped.slice(deduped.length - boundedLimit) : deduped;
}

export function isSupportedLiveChannelMessage(contentType: string, isAnimation: boolean): boolean {
  if (contentType === 'text' || contentType === 'photo' || contentType === 'emoji' ||
    contentType === 'customEmoji' || contentType === 'sticker') {
    return true;
  }
  return contentType === 'video' && isAnimation;
}

export function liveInteractionLooksLikeEmojiOnly(raw: string): boolean {
  const value = raw.trim();
  if (value === '') { return false; }
  let hasEmoji = false;
  for (let i = 0; i < value.length;) {
    const first = value.charCodeAt(i);
    let codePoint = first;
    let width = 1;
    if (first >= 0xD800 && first <= 0xDBFF && i + 1 < value.length) {
      const second = value.charCodeAt(i + 1);
      if (second >= 0xDC00 && second <= 0xDFFF) {
        codePoint = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00);
        width = 2;
      }
    }
    i += width;
    if (codePoint === 0x200D || codePoint === 0xFE0E || codePoint === 0xFE0F ||
      codePoint === 0x20E3 || codePoint === 0x0020) {
      continue;
    }
    const emoji = (codePoint >= 0x1F000 && codePoint <= 0x1FAFF) ||
      (codePoint >= 0x2600 && codePoint <= 0x27BF) ||
      (codePoint >= 0x2300 && codePoint <= 0x23FF) ||
      (codePoint >= 0x2B00 && codePoint <= 0x2BFF) ||
      codePoint === 0x00A9 || codePoint === 0x00AE || codePoint === 0x2122 ||
      codePoint === 0x3030 || codePoint === 0x303D || codePoint === 0x3297 || codePoint === 0x3299;
    if (!emoji) { return false; }
    hasEmoji = true;
  }
  return hasEmoji;
}

export function liveInteractionPresentation(
  input: LiveInteractionPresentationInput
): LiveInteractionPresentation {
  const historyFailed = input.channelAttached && input.channelHistoryState === 'error';
  const historyLoading = input.channelAttached && input.channelHistoryState === 'loading' &&
    input.messageCount === 0;
  if (!input.valid) {
    return {
      kind: 'invalid', statusText: '不可用', statusTone: 'muted',
      subtitle: '互动通道不可用', emptyTitle: '无法载入互动',
      emptyDetail: '直播参数无效，请返回后重试', composerEnabled: false,
      composerHint: '当前没有可用的消息通道', showProgress: false,
      showHistoryRetry: false
    };
  }
  if (input.resolved && !input.active) {
    return {
      kind: 'ended', statusText: '已结束', statusTone: 'muted',
      subtitle: '直播已结束，已有互动仍可查看', emptyTitle: '直播已结束',
      emptyDetail: '本场直播没有互动消息', composerEnabled: false,
      composerHint: '直播已结束，互动已关闭', showProgress: false,
      showHistoryRetry: historyFailed
    };
  }
  if (input.recovering) {
    return {
      kind: 'recovering', statusText: '重连中', statusTone: 'accent',
      subtitle: '现有消息可继续查看，正在恢复实时互动', emptyTitle: '正在恢复互动',
      emptyDetail: '网络恢复后会自动继续', composerEnabled: false,
      composerHint: '正在恢复互动连接…', showProgress: input.messageCount === 0,
      showHistoryRetry: historyFailed
    };
  }
  if (!input.joined && !input.joinedOnce) {
    return {
      kind: 'connecting', statusText: '连接中', statusTone: 'accent',
      subtitle: '正在连接实时互动通道', emptyTitle: '正在载入互动',
      emptyDetail: '连接成功后会自动显示新消息', composerEnabled: false,
      composerHint: '正在连接互动…', showProgress: true, showHistoryRetry: historyFailed
    };
  }
  if (historyLoading) {
    return {
      kind: 'loading', statusText: '同步中', statusTone: 'accent',
      subtitle: '实时互动已连接，正在同步频道消息', emptyTitle: '正在同步消息',
      emptyDetail: '新互动仍会实时出现',
      composerEnabled: input.messagesAllowed && input.canSendMessages,
      composerHint: '说点什么…', showProgress: true, showHistoryRetry: false
    };
  }
  if (!input.messagesAllowed) {
    return {
      kind: 'disabled', statusText: '已关闭', statusTone: 'muted',
      subtitle: historyFailed ? '实时互动已关闭，频道历史加载失败' :
        (input.channelAttached ? '可以继续查看频道消息' : '主播没有开启互动消息'),
      emptyTitle: '主播暂未开启互动', emptyDetail: '开启后新消息会自动显示',
      composerEnabled: false, composerHint: '当前没有可用的消息通道',
      showProgress: false, showHistoryRetry: historyFailed
    };
  }
  if (!input.canSendMessages) {
    return {
      kind: 'readonly', statusText: '只读', statusTone: 'muted',
      subtitle: historyFailed ? '实时互动正常，频道历史加载失败' : '互动消息会实时更新',
      emptyTitle: '还没有互动消息', emptyDetail: '你可以观看，但当前账号暂时不能发送',
      composerEnabled: false, composerHint: '当前账号暂时不能发送互动消息',
      showProgress: false, showHistoryRetry: historyFailed
    };
  }
  return {
    kind: 'live', statusText: '实时', statusTone: 'live',
    subtitle: historyFailed ? '实时互动正常，频道历史加载失败' :
      (input.channelAttached ? '直播互动与频道消息实时汇总' : '互动消息仅在本次直播期间显示'),
    emptyTitle: '还没有互动消息', emptyDetail: '来说第一句吧', composerEnabled: true,
    composerHint: '说点什么…', showProgress: false, showHistoryRetry: historyFailed
  };
}
