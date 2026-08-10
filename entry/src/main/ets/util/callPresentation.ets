// 1对1 通话页的展示纯函数（可单测）。

// 通话中（active）与空闲不显示状态行，由计时/无内容代替。
export function callPhaseLabel(phase: string, isVideo: boolean): string {
  if (phase === 'dialing') {
    return '正在呼叫…';
  }
  if (phase === 'ringing') {
    return isVideo ? '视频来电' : '语音来电';
  }
  if (phase === 'connecting') {
    return '连接中…';
  }
  return '';
}

// 通话时长：m:ss，超过 1 小时 h:mm:ss；未接通返回空。
export function callDurationLabel(startedAtMs: number, nowMs: number): string {
  if (startedAtMs <= 0) {
    return '';
  }
  const totalSeconds: number = Math.max(0, Math.floor((nowMs - startedAtMs) / 1000));
  const hours: number = Math.floor(totalSeconds / 3600);
  const minutes: number = Math.floor((totalSeconds % 3600) / 60);
  const seconds: number = totalSeconds % 60;
  const two = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
  if (hours > 0) {
    return `${hours}:${two(minutes)}:${two(seconds)}`;
  }
  return `${minutes}:${two(seconds)}`;
}

export function callEndLabel(reason: string, errorText: string): string {
  if (reason === 'declined') {
    return '对方已拒绝';
  }
  if (reason === 'missed') {
    return '未接听';
  }
  if (reason === 'busy') {
    return '对方忙线中';
  }
  if (reason === 'error') {
    return errorText !== '' ? errorText : '通话失败';
  }
  return '通话已结束';
}
