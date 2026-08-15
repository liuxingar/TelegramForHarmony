import { str } from './strings';
import {
  normalizeTelegramLink, inviteLinkOf, bareUsernameOf,
  chatFolderInviteLinkOf, stickerSetLinkOf
} from './linkNav';

export interface LinkPreviewPresentation {
  kind: string; // web | telegramMessage | telegramChat | telegramInvite | telegramResource | unavailable
  actionLabel: string;
  siteLabel: string;
  isTelegram: boolean;
  actionable: boolean;
}

function withoutScheme(value: string): string {
  const scheme: number = value.indexOf('://');
  return scheme >= 0 ? value.substring(scheme + 3) : value;
}

export function linkPreviewDomain(url: string): string {
  const raw: string = url.trim();
  if (raw === '' || raw.startsWith('@')) {
    return raw.startsWith('@') ? 'Telegram' : '';
  }
  const rest: string = withoutScheme(raw);
  const endCandidates: number[] = [rest.indexOf('/'), rest.indexOf('?'), rest.indexOf('#')]
    .filter((index: number): boolean => index >= 0);
  let end: number = rest.length;
  for (const candidate of endCandidates) {
    end = Math.min(end, candidate);
  }
  let host: string = rest.substring(0, end).toLowerCase();
  if (host.startsWith('www.')) {
    host = host.substring(4);
  }
  return host;
}

function telegramPathParts(url: string): string[] {
  const rest: string = withoutScheme(url.trim());
  const slash: number = rest.indexOf('/');
  if (slash < 0) {
    return [];
  }
  const clean: string = rest.substring(slash + 1).split('?')[0].split('#')[0];
  return clean.split('/').filter((part: string): boolean => part !== '');
}

function isPositiveInteger(value: string): boolean {
  if (value === '') {
    return false;
  }
  for (let index: number = 0; index < value.length; index++) {
    const code: number = value.charCodeAt(index);
    if (code < 48 || code > 57) {
      return false;
    }
  }
  return true;
}

function isTelegramMessageLink(url: string, previewType: string): boolean {
  if (previewType.toLowerCase().indexOf('message') >= 0) {
    return true;
  }
  const parts: string[] = telegramPathParts(url);
  if (parts.length < 2) {
    return false;
  }
  // Public posts: t.me/<channel>/<messageId>; private posts:
  // t.me/c/<internalChatId>/<messageId>.
  return isPositiveInteger(parts[parts.length - 1]);
}

export function linkPreviewPresentation(url: string, previewType: string,
    siteName: string): LinkPreviewPresentation {
  const raw: string = url.trim();
  const explicitSite: string = siteName.trim();
  if (raw === '') {
    return {
      kind: 'unavailable', actionLabel: str('link_preview_unavailable'),
      siteLabel: explicitSite !== '' ? explicitSite : str('link_preview_title'),
      isTelegram: false, actionable: false
    };
  }
  const telegramUrl: string = normalizeTelegramLink(raw);
  const telegram: boolean = telegramUrl !== '' || raw.startsWith('tg://') || raw.startsWith('@');
  if (!telegram) {
    const domain: string = linkPreviewDomain(raw);
    return {
      kind: 'web', actionLabel: str('link_preview_open_web'),
      siteLabel: explicitSite !== '' ? explicitSite : (domain !== '' ? domain : str('link_preview_web_link')),
      isTelegram: false, actionable: true
    };
  }
  if (chatFolderInviteLinkOf(raw) !== '') {
    return {
      kind: 'telegramResource', actionLabel: str('link_preview_open_folder'),
      siteLabel: explicitSite !== '' ? explicitSite : 'Telegram',
      isTelegram: true, actionable: true
    };
  }
  if (stickerSetLinkOf(raw) !== null) {
    return {
      kind: 'telegramResource', actionLabel: str('link_preview_open_stickers'),
      siteLabel: explicitSite !== '' ? explicitSite : 'Telegram',
      isTelegram: true, actionable: true
    };
  }
  if (inviteLinkOf(raw) !== '') {
    return {
      kind: 'telegramInvite', actionLabel: str('link_preview_open_invite'),
      siteLabel: explicitSite !== '' ? explicitSite : 'Telegram',
      isTelegram: true, actionable: true
    };
  }
  if (isTelegramMessageLink(raw, previewType)) {
    return {
      kind: 'telegramMessage', actionLabel: str('link_preview_open_message'),
      siteLabel: explicitSite !== '' ? explicitSite : 'Telegram',
      isTelegram: true, actionable: true
    };
  }
  const directUsername: string = bareUsernameOf(raw);
  return {
    kind: directUsername !== '' ? 'telegramChat' : 'telegramResource',
    actionLabel: directUsername !== '' ? str('link_preview_open_profile') : str('link_preview_open_in_telegram'),
    siteLabel: explicitSite !== '' ? explicitSite : 'Telegram',
    isTelegram: true, actionable: true
  };
}
