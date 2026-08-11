export interface LiveViewerMediaInput {
  mode: string;
  valid: boolean;
  resolved: boolean;
  active: boolean;
  joined: boolean;
  joinedOnce: boolean;
  recovering: boolean;
  ending: boolean;
  terminalError: boolean;
  reconnectAttempt: number;
  retrySeconds: number;
  retryable: boolean;
  hasVideo: boolean;
  visualReady: boolean;
  participantCount: number;
  mediaStatus: string;
  error: string;
}

export interface LiveViewerMediaPresentation {
  kind: string;
  title: string;
  detail: string;
  badgeText: string;
  badgeTone: string;
  showProgress: boolean;
  pulse: boolean;
  retryable: boolean;
  actionText: string;
  keepVisual: boolean;
}

function countDetail(count: number): string {
  return count > 0 ? `${count} 人在直播间` : '声音会继续实时播放';
}

export function liveViewerMediaPresentation(
  input: LiveViewerMediaInput
): LiveViewerMediaPresentation {
  if (!input.valid) {
    return {
      kind: 'invalid', title: '无法打开直播', detail: '直播参数无效，请返回后重试',
      badgeText: '', badgeTone: 'muted', showProgress: false, pulse: false,
      retryable: false, actionText: '', keepVisual: false
    };
  }
  if (input.ending) {
    return {
      kind: 'ending', title: '正在结束直播', detail: '请稍候…',
      badgeText: '结束中', badgeTone: 'danger', showProgress: true, pulse: false,
      retryable: false, actionText: '', keepVisual: input.hasVideo
    };
  }
  if (input.resolved && !input.active) {
    return {
      kind: 'ended', title: '直播已结束', detail: '可以返回频道查看其他消息',
      badgeText: '已结束', badgeTone: 'muted', showProgress: false, pulse: false,
      retryable: false, actionText: '', keepVisual: input.hasVideo
    };
  }
  if (input.terminalError) {
    return {
      kind: 'error', title: '直播模式已经变化', detail: '请返回频道后重新进入直播',
      badgeText: '需要返回', badgeTone: 'danger', showProgress: false, pulse: false,
      retryable: false, actionText: '', keepVisual: input.hasVideo
    };
  }
  if (input.recovering) {
    let detail = '网络恢复后将自动继续播放';
    if (input.retrySeconds > 0) {
      const attempt = Math.max(1, input.reconnectAttempt);
      detail = `第 ${attempt} 次尝试 · ${input.retrySeconds} 秒后自动重试`;
    } else if (input.reconnectAttempt > 0) {
      detail = `正在进行第 ${input.reconnectAttempt} 次连接尝试`;
    }
    return {
      kind: 'recovering', title: input.retrySeconds > 0 ? '直播连接暂时中断' : '正在恢复直播',
      detail, badgeText: '重连中', badgeTone: 'accent', showProgress: true, pulse: true,
      retryable: input.retryable, actionText: input.retryable ? '立即重试' : '',
      keepVisual: input.hasVideo
    };
  }
  if (input.error !== '' && !input.joined) {
    return {
      kind: 'error', title: '暂时无法连接直播',
      detail: input.retrySeconds > 0 ? `${input.retrySeconds} 秒后自动重试` : '可以立即重新连接',
      badgeText: '连接失败', badgeTone: 'danger', showProgress: false, pulse: false,
      retryable: input.retryable, actionText: input.retryable ? '重新连接' : '',
      keepVisual: input.hasVideo
    };
  }
  if (!input.joined && !input.joinedOnce) {
    return {
      kind: 'connecting', title: '正在连接直播', detail: '正在准备音频和画面…',
      badgeText: '连接中', badgeTone: 'accent', showProgress: true, pulse: true,
      retryable: false, actionText: '', keepVisual: false
    };
  }
  if (input.hasVideo) {
    if (input.mode === 'rtmp' && !input.visualReady) {
      return {
        kind: 'videoLoading', title: '正在载入直播画面', detail: '音频与画面正在同步…',
        badgeText: '载入中', badgeTone: 'accent', showProgress: true, pulse: true,
        retryable: false, actionText: '', keepVisual: false
      };
    }
    return {
      kind: 'video', title: '', detail: '', badgeText: 'LIVE', badgeTone: 'live',
      showProgress: false, pulse: true, retryable: false, actionText: '', keepVisual: true
    };
  }
  if (input.mediaStatus.includes('音频') || input.mode === 'group') {
    return {
      kind: 'audio', title: '音频直播', detail: countDetail(input.participantCount),
      badgeText: 'AUDIO', badgeTone: 'audio', showProgress: false, pulse: true,
      retryable: false, actionText: '', keepVisual: false
    };
  }
  return {
    kind: 'waiting', title: '等待主播画面', detail: '直播已连接，画面开始后会自动播放',
    badgeText: '等待开播', badgeTone: 'waiting', showProgress: false, pulse: false,
    retryable: false, actionText: '', keepVisual: false
  };
}
