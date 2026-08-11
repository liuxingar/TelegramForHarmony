export interface LiveViewerHeaderInput {
  valid: boolean;
  resolved: boolean;
  queryFailed: boolean;
  active: boolean;
  joined: boolean;
  joinedOnce: boolean;
  recovering: boolean;
  ending: boolean;
  terminalError: boolean;
  reconnectAttempt: number;
  retrySeconds: number;
  canMinimize: boolean;
  participantCount: number;
  mediaStatus: string;
}

export interface LiveViewerHeaderPresentation {
  kind: string;
  statusText: string;
  fullscreenText: string;
  pulse: boolean;
  retryable: boolean;
  actionsEnabled: boolean;
}

function containsAny(value: string, parts: string[]): boolean {
  for (const part of parts) {
    if (value.includes(part)) { return true; }
  }
  return false;
}

export function liveViewerHeaderPresentation(
  input: LiveViewerHeaderInput
): LiveViewerHeaderPresentation {
  if (!input.valid) {
    return {
      kind: 'invalid', statusText: '无法打开直播', fullscreenText: '无法打开',
      pulse: false, retryable: false, actionsEnabled: false
    };
  }
  if (input.ending) {
    return {
      kind: 'ending', statusText: '正在结束直播…', fullscreenText: '结束中',
      pulse: false, retryable: false, actionsEnabled: false
    };
  }
  if (input.resolved && !input.active) {
    return {
      kind: 'ended', statusText: '直播已结束', fullscreenText: '已结束',
      pulse: false, retryable: false, actionsEnabled: false
    };
  }
  if (input.terminalError) {
    return {
      kind: 'error', statusText: '直播模式已变化', fullscreenText: '需要返回',
      pulse: false, retryable: false, actionsEnabled: false
    };
  }
  if (input.queryFailed && !input.joinedOnce && !input.joined) {
    return {
      kind: 'error', statusText: '连接失败 · 轻触重试', fullscreenText: '连接失败',
      pulse: false, retryable: true, actionsEnabled: input.canMinimize
    };
  }
  if (input.recovering || containsAny(input.mediaStatus, ['恢复', '重试', '中断', '续播', '重新同步'])) {
    const retryText = input.retrySeconds > 0
      ? `${input.retrySeconds} 秒后重试 · 轻触立即重试`
      : (input.reconnectAttempt > 0 ? '正在重新连接直播…' : '正在恢复直播…');
    return {
      kind: 'recovering', statusText: retryText, fullscreenText: '重连中',
      pulse: true, retryable: true, actionsEnabled: input.canMinimize
    };
  }
  if (!input.resolved && !input.joinedOnce && !input.joined) {
    return {
      kind: 'connecting', statusText: '正在连接直播…', fullscreenText: '连接中',
      pulse: true, retryable: false, actionsEnabled: input.canMinimize
    };
  }
  if (containsAny(input.mediaStatus, ['等待主播', '等待开播', '等待推流'])) {
    return {
      kind: 'waiting', statusText: '等待主播开始推流', fullscreenText: '等待开播',
      pulse: false, retryable: false, actionsEnabled: input.canMinimize
    };
  }
  if (input.mediaStatus.includes('音频')) {
    return {
      kind: 'audio', statusText: '直播音频播放中', fullscreenText: '音频直播',
      pulse: true, retryable: false, actionsEnabled: input.canMinimize
    };
  }
  if (!input.joined && !input.joinedOnce) {
    return {
      kind: 'joining', statusText: '正在加入直播…', fullscreenText: '加入中',
      pulse: true, retryable: false, actionsEnabled: input.canMinimize
    };
  }
  return {
    kind: 'live',
    statusText: input.participantCount > 0
      ? `${input.participantCount} 人正在观看` : '直播中',
    fullscreenText: 'LIVE', pulse: true, retryable: false, actionsEnabled: input.canMinimize
  };
}
