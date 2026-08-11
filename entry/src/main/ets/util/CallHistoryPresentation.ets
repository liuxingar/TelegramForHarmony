import { TdObject } from '../tdkit/TdTypes';

export type CallTone = 'normal' | 'missed' | 'warning' | 'active';

export interface ParsedCallContent {
  valid: boolean;
  isGroup: boolean;
  isVideo: boolean;
  missed: boolean;
  active: boolean;
  duration: number;
  reasonType: string;
  participantCount: number;
}

export interface CallStatusPresentation {
  text: string;
  tone: CallTone;
}

export function parseCallContent(content: TdObject | undefined, outgoing: boolean): ParsedCallContent {
  const type = (content?.['@type'] as string | undefined) ?? '';
  if (type === 'messageCall') {
    const reason = content?.['discard_reason'] as TdObject | undefined;
    const reasonType = (reason?.['@type'] as string | undefined) ?? 'callDiscardReasonEmpty';
    return {
      valid: true,
      isGroup: false,
      isVideo: (content?.['is_video'] as boolean | undefined) ?? false,
      missed: reasonType === 'callDiscardReasonMissed' || reasonType === 'callDiscardReasonDeclined',
      active: false,
      duration: Math.max(0, (content?.['duration'] as number | undefined) ?? 0),
      reasonType,
      participantCount: 0
    };
  }
  if (type === 'messageGroupCall') {
    const participants = (content?.['other_participant_ids'] as TdObject[] | undefined) ?? [];
    return {
      valid: true,
      isGroup: true,
      isVideo: (content?.['is_video'] as boolean | undefined) ?? false,
      missed: !outgoing && ((content?.['was_missed'] as boolean | undefined) ?? false),
      active: (content?.['is_active'] as boolean | undefined) ?? false,
      duration: Math.max(0, (content?.['duration'] as number | undefined) ?? 0),
      reasonType: '',
      participantCount: participants.length > 0 ? participants.length + 1 : 0
    };
  }
  return {
    valid: false, isGroup: false, isVideo: false, missed: false,
    active: false, duration: 0, reasonType: '', participantCount: 0
  };
}

export function compactCallDuration(seconds: number): string {
  const value = Math.max(0, Math.floor(seconds));
  if (value < 60) { return `${value}秒`; }
  const minutes = Math.floor(value / 60);
  const rest = value % 60;
  if (minutes < 60) { return rest > 0 ? `${minutes}分${rest}秒` : `${minutes}分钟`; }
  const hours = Math.floor(minutes / 60);
  const minuteRest = minutes % 60;
  return minuteRest > 0 ? `${hours}小时${minuteRest}分` : `${hours}小时`;
}

export function callStatus(parsed: ParsedCallContent, outgoing: boolean): CallStatusPresentation {
  const media = parsed.isVideo ? '视频' : '语音';
  if (parsed.isGroup) {
    if (parsed.missed) { return { text: `未接群组${media}通话`, tone: 'missed' }; }
    if (parsed.active) { return { text: `群组${media}通话进行中`, tone: 'active' }; }
    if (parsed.duration > 0) {
      return { text: `群组${media}通话 · ${compactCallDuration(parsed.duration)}`, tone: 'normal' };
    }
    return { text: `群组${media}通话`, tone: 'normal' };
  }
  if (parsed.duration > 0) {
    return {
      text: `${outgoing ? '呼出' : '呼入'}${media}通话 · ${compactCallDuration(parsed.duration)}`,
      tone: 'normal'
    };
  }
  if (parsed.reasonType === 'callDiscardReasonMissed') {
    return { text: outgoing ? `对方未接${media}通话` : `未接${media}来电`, tone: 'missed' };
  }
  if (parsed.reasonType === 'callDiscardReasonDeclined') {
    return { text: outgoing ? `对方已拒绝${media}通话` : `已拒接${media}来电`, tone: 'missed' };
  }
  if (parsed.reasonType === 'callDiscardReasonDisconnected') {
    return { text: `${media}通话连接中断`, tone: 'warning' };
  }
  if (parsed.reasonType === 'callDiscardReasonUpgradeToGroupCall') {
    return { text: `已转为群组${media}通话`, tone: 'normal' };
  }
  if (parsed.reasonType === 'callDiscardReasonHungUp') {
    return { text: outgoing ? `已取消${media}通话` : `${media}通话未接通`, tone: 'normal' };
  }
  return { text: outgoing ? `呼出${media}通话` : `呼入${media}通话`, tone: 'normal' };
}

function sameLocalDay(left: Date, right: Date): boolean {
  return left.getFullYear() === right.getFullYear() && left.getMonth() === right.getMonth()
    && left.getDate() === right.getDate();
}

export function callDayKey(timestamp: number): string {
  const date = new Date(Math.max(0, timestamp) * 1000);
  return `${date.getFullYear()}-${date.getMonth() + 1}-${date.getDate()}`;
}

export function callSectionLabel(timestamp: number, nowSeconds: number = Math.floor(Date.now() / 1000)): string {
  const date = new Date(Math.max(0, timestamp) * 1000);
  const now = new Date(nowSeconds * 1000);
  if (sameLocalDay(date, now)) { return '今天'; }
  const yesterday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
  if (sameLocalDay(date, yesterday)) { return '昨天'; }
  if (date.getFullYear() === now.getFullYear()) { return `${date.getMonth() + 1}月${date.getDate()}日`; }
  return `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日`;
}

export function callClockLabel(timestamp: number): string {
  const date = new Date(Math.max(0, timestamp) * 1000);
  const hour = `${date.getHours()}`.padStart(2, '0');
  const minute = `${date.getMinutes()}`.padStart(2, '0');
  return `${hour}:${minute}`;
}

export function formatCallTime(timestamp: number): string {
  const date = new Date(Math.max(0, timestamp) * 1000);
  return `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日 ${callClockLabel(timestamp)}`;
}
