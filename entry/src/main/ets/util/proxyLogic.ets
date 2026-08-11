import {
  PROXY_HTTP, PROXY_MTPROTO, ProxyEntry
} from '../store/ProxyApi';

export function parseProxyPort(rawPort: string): number {
  const value = rawPort.trim();
  if (!/^\d+$/.test(value)) { return 0; }
  const port = Number(value);
  if (!Number.isInteger(port) || port < 1 || port > 65535) { return 0; }
  return port;
}

export function proxyFormError(
  server: string, rawPort: string, type: string, secret: string
): string {
  if (server.trim() === '') { return '请填写服务器地址'; }
  if (parseProxyPort(rawPort) === 0) { return '端口需为 1–65535 的整数'; }
  if (type === PROXY_MTPROTO && secret.trim() === '') {
    return 'MTProto 代理需要填写密钥';
  }
  return '';
}

export function sameProxyConfiguration(left: ProxyEntry, right: ProxyEntry): boolean {
  if (left.server.trim().toLowerCase() !== right.server.trim().toLowerCase() ||
    left.port !== right.port || left.type !== right.type) {
    return false;
  }
  if (left.type === PROXY_MTPROTO) { return left.secret === right.secret; }
  if (left.type === PROXY_HTTP && left.httpOnly !== right.httpOnly) { return false; }
  return left.username === right.username && left.password === right.password;
}

export function proxyActionErrorText(rawMessage: string, action: string): string {
  const message = rawMessage.toUpperCase();
  if (message.indexOf('TIMEOUT') >= 0) { return `${action}超时，请刷新状态后重试`; }
  if (message.indexOf('NETWORK') >= 0 || message.indexOf('CONNECTION') >= 0) {
    return `网络不可用，暂时无法${action}`;
  }
  if (message.indexOf('PROXY') >= 0 || message.indexOf('SERVER') >= 0 ||
    message.indexOf('PORT') >= 0 || message.indexOf('SECRET') >= 0) {
    return '代理参数无效，请检查地址、端口和凭据';
  }
  return `${action}失败，请稍后重试`;
}

export function proxyConnectionText(state: string, usingProxy: boolean): string {
  if (state === 'connectionStateReady') { return usingProxy ? '代理已连接' : '当前为直连'; }
  if (state === 'connectionStateConnectingToProxy') { return '正在连接代理'; }
  if (state === 'connectionStateConnecting') { return '正在连接'; }
  if (state === 'connectionStateWaitingForNetwork') { return '等待网络'; }
  if (state === 'connectionStateUpdating') { return '正在同步'; }
  return usingProxy ? '正在读取代理状态' : '正在读取连接状态';
}
