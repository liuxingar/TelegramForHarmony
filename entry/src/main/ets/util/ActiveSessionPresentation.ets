import { TdObject } from '../tdkit/TdTypes';

export const FRESH_SESSION_PROTECTION_SECONDS: number = 24 * 60 * 60;

export type SessionErrorKind =
  'fresh' | 'missing' | 'rate_limit' | 'network' | 'qr' | 'password' | 'generic';

export interface SessionErrorPresentation {
  kind: SessionErrorKind;
  text: string;
  shouldRefresh: boolean;
}

export function sessionDeviceType(session: TdObject): string {
  const device = session['device_type'] as TdObject | undefined;
  if (device !== undefined) {
    return (device['@type'] as string | undefined) ?? '';
  }
  // Compatibility with cached objects produced by early app builds.
  const legacy = session['type'] as TdObject | undefined;
  return (legacy?.['@type'] as string | undefined) ?? '';
}

export function freshSessionSeconds(
  loginDate: number, nowSeconds: number = Math.floor(Date.now() / 1000)
): number {
  if (loginDate <= 0) { return 0; }
  return Math.max(0, loginDate + FRESH_SESSION_PROTECTION_SECONDS - nowSeconds);
}

export function sessionWaitText(seconds: number): string {
  if (seconds <= 0) { return '稍后'; }
  const totalMinutes = Math.max(1, Math.ceil(seconds / 60));
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  if (hours <= 0) { return `${minutes} 分钟后`; }
  if (minutes === 0) { return `${hours} 小时后`; }
  return `${hours} 小时 ${minutes} 分钟后`;
}

export function inactiveSessionTtlLabel(days: number): string {
  if (days === 7) { return '1 周'; }
  if (days === 30) { return '1 个月'; }
  if (days === 90) { return '3 个月'; }
  if (days === 180) { return '6 个月'; }
  if (days === 365 || days === 366) { return '1 年'; }
  return `${Math.max(1, Math.min(366, Math.round(days)))} 天`;
}

function floodWaitSeconds(message: string): number {
  const marker = 'FLOOD_WAIT_';
  const start = message.toUpperCase().indexOf(marker);
  if (start < 0) { return 0; }
  const tail = message.substring(start + marker.length);
  let digits = '';
  for (let index = 0; index < tail.length; index += 1) {
    const code = tail.charCodeAt(index);
    if (code < 48 || code > 57) { break; }
    digits += tail.charAt(index);
  }
  const parsed = Number(digits);
  return Number.isFinite(parsed) ? parsed : 0;
}

function rateLimitText(seconds: number): string {
  if (seconds <= 0) { return '操作过于频繁，请稍后再试'; }
  if (seconds < 60) { return `操作过于频繁，请在 ${seconds} 秒后重试`; }
  const minutes = Math.max(1, Math.ceil(seconds / 60));
  return `操作过于频繁，请在 ${minutes} 分钟后重试`;
}

export function activeSessionError(
  rawMessage: string, fallback: string = '操作失败，请重试'
): SessionErrorPresentation {
  const upper = rawMessage.toUpperCase();
  if (upper.indexOf('FRESH_RESET_AUTHORISATION_FORBIDDEN') >= 0 ||
    upper.indexOf('FRESH_RESET_AUTHORIZATION_FORBIDDEN') >= 0 ||
    upper.indexOf('SESSION_TOO_FRESH') >= 0) {
    return {
      kind: 'fresh',
      text: '出于安全保护，新登录设备暂时不能终止其他会话，请使用较早登录的设备或稍后重试',
      shouldRefresh: false
    };
  }
  if (upper.indexOf('SESSION_NOT_FOUND') >= 0 || upper.indexOf('HASH_INVALID') >= 0) {
    return { kind: 'missing', text: '该设备会话已失效，正在刷新列表', shouldRefresh: true };
  }
  if (upper.indexOf('FLOOD_WAIT') >= 0 || upper.indexOf('TOO_MANY_REQUESTS') >= 0) {
    return {
      kind: 'rate_limit', text: rateLimitText(floodWaitSeconds(upper)), shouldRefresh: false
    };
  }
  if (upper.indexOf('AUTH_TOKEN_INVALID') >= 0 || upper.indexOf('AUTH_TOKEN_EXPIRED') >= 0 ||
    upper.indexOf('AUTH_TOKEN_ALREADY_ACCEPTED') >= 0 || upper.indexOf('QR') >= 0) {
    return { kind: 'qr', text: '此二维码无效或已过期，请刷新二维码后重试', shouldRefresh: false };
  }
  if (upper.indexOf('PASSWORD_HASH_INVALID') >= 0 || upper.indexOf('PASSWORD') >= 0) {
    return { kind: 'password', text: '此设备仍需完成两步验证', shouldRefresh: true };
  }
  if (upper.indexOf('TIMEOUT') >= 0 || upper.indexOf('NETWORK') >= 0 ||
    upper.indexOf('CONNECTION') >= 0 || upper.indexOf('OFFLINE') >= 0) {
    return { kind: 'network', text: '网络连接不稳定，请检查网络后重试', shouldRefresh: false };
  }
  return { kind: 'generic', text: fallback, shouldRefresh: false };
}
