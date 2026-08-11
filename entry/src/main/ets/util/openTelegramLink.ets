import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { getTdClient } from '../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import {
  normalizeTelegramLink, bareUsernameOf, inviteLinkOf, chatLinkActionOf, chatFolderInviteLinkOf,
  stickerSetLinkOf, ChatLinkAction, StickerSetLink
} from './linkNav';
import { openWebUrl } from './webBrowserNav';
import { getMainMiniApp, getMiniAppLinkUrl } from '../store/BotApi';

function openChatPage(chatId: number, showJoinedNotice: boolean = false,
    joinedNoticeIsChannel: boolean = false): void {
  const params: Record<string, Object> = { 'chatId': chatId };
  if (showJoinedNotice) {
    params['showJoinedNotice'] = true;
    params['joinedNoticeIsChannel'] = joinedNoticeIsChannel;
  }
  router.pushUrl({ url: 'pages/chat/ChatPage', params: params });
}

function isTelegramInternalUrl(url: string): boolean {
  const raw = url.trim();
  return raw.startsWith('tg://') || raw.startsWith('@') || normalizeTelegramLink(raw) !== '';
}

// A link that couldn't be resolved in-app. For a tapped in-message link we hand
// off to the system browser; for a deep-link ENTRY point we must not — opening
// the browser there bounces browser → app → browser, so just tell the user.
function onLinkUnresolved(context: common.UIAbilityContext, url: string, allowBrowser: boolean): void {
  // A Telegram resource must never bounce to its web landing page. Besides
  // being jarring for an in-message tap, a cold-start deep link can otherwise
  // loop browser -> app -> browser. Only genuinely external URLs use openUrl.
  if (allowBrowser && !isTelegramInternalUrl(url)) {
    openWebUrl(context, url);
  } else {
    promptAction.showToast({ message: '无法识别该 Telegram 链接', duration: 1700 });
  }
}

function openProfileForChat(chat: TdObject, draftText: string = '', openProfile: boolean = false): void {
  const chatId = (chat['id'] as number | undefined) ?? 0;
  if (chatId === 0) {
    return;
  }
  const type = chat['type'] as TdObject | undefined;
  const typeName = type !== undefined ? ((type['@type'] as string | undefined) ?? '') : '';
  if (typeName === 'chatTypePrivate') {
    const userId = type !== undefined ? ((type['user_id'] as number | undefined) ?? 0) : 0;
    if (userId > 0) {
      const params: Record<string, Object> = { 'userId': userId };
      if (draftText !== '') {
        params['draftText'] = draftText;
      }
      router.pushUrl({ url: 'pages/profile/ProfilePage', params: params });
      return;
    }
  }
  const params: Record<string, Object> = { 'chatId': chatId };
  if (draftText !== '') {
    params['draftText'] = draftText;
  }
  router.pushUrl({
    url: openProfile ? 'pages/profile/ChatProfilePage' : 'pages/chat/ChatPage',
    params: params
  });
}

function resolvePublicChat(context: common.UIAbilityContext, username: string, draftText: string,
    openProfile: boolean, original: string, allowBrowser: boolean): void {
  if (username === '') {
    onLinkUnresolved(context, original, allowBrowser);
    return;
  }
  const req: TdRequest = { '@type': 'searchPublicChat' };
  req['username'] = username;
  getTdClient().send(req).then((chat: TdObject): void => {
    if (((chat['id'] as number | undefined) ?? 0) === 0) {
      onLinkUnresolved(context, original, allowBrowser);
      return;
    }
    openProfileForChat(chat, draftText, openProfile);
  }).catch((error: TdError): void => {
    console.error(`openTelegramLink.searchPublicChat(${username}) failed: ${error.message}`);
    onLinkUnresolved(context, original, allowBrowser);
  });
}

function openMessageLink(context: common.UIAbilityContext, link: string, original: string,
    allowBrowser: boolean): void {
  const req: TdRequest = { '@type': 'getMessageLinkInfo' };
  req['url'] = link;
  getTdClient().send(req).then((info: TdObject): void => {
    const chatId = (info['chat_id'] as number | undefined) ?? 0;
    if (chatId === 0) {
      onLinkUnresolved(context, original, allowBrowser);
      return;
    }
    const msg = info['message'] as TdObject | undefined;
    const msgId = msg !== undefined ? ((msg['id'] as number | undefined) ?? 0) : 0;
    const params: Record<string, Object> = { 'chatId': chatId };
    if (msgId > 0) {
      params['jumpTo'] = msgId;
    }
    router.pushUrl({ url: 'pages/chat/ChatPage', params: params });
  }).catch((error: TdError): void => {
    console.error(`openTelegramLink.getMessageLinkInfo failed: ${error.message}`);
    onLinkUnresolved(context, original, allowBrowser);
  });
}

function openProxyLink(type: TdObject): void {
  const proxy = type['proxy'] as TdObject | undefined;
  if (proxy === undefined) {
    promptAction.showToast({ message: '该代理类型暂不受支持', duration: 1800 });
    return;
  }
  const proxyType = proxy['type'] as TdObject | undefined;
  const server = (proxy['server'] as string | undefined) ?? '';
  const port = (proxy['port'] as number | undefined) ?? 0;
  if (server === '' || port <= 0 || proxyType === undefined) {
    promptAction.showToast({ message: '代理链接参数不完整', duration: 1800 });
    return;
  }
  const params: Record<string, Object> = {
    'proxyServer': server,
    'proxyPort': port,
    'proxyType': (proxyType['@type'] as string | undefined) ?? 'proxyTypeSocks5',
    'proxyUsername': (proxyType['username'] as string | undefined) ?? '',
    'proxyPassword': (proxyType['password'] as string | undefined) ?? '',
    'proxySecret': (proxyType['secret'] as string | undefined) ?? '',
    'proxyHttpOnly': (proxyType['http_only'] as boolean | undefined) ?? false
  };
  router.pushUrl({ url: 'pages/main/ProxyPage', params: params });
}

function openSelfProfile(): void {
  getTdClient().send({ '@type': 'getMe' } as TdRequest).then((me: TdObject): void => {
    const userId = (me['id'] as number | undefined) ?? 0;
    if (userId > 0) {
      const params: Record<string, Object> = { 'userId': userId };
      router.pushUrl({ url: 'pages/profile/ProfilePage', params: params });
    }
  }).catch((error: TdError): void => {
    console.error(`openTelegramLink.getMe failed: ${error.message}`);
    promptAction.showToast({ message: '无法打开个人资料', duration: 1600 });
  });
}

function openSavedMessages(): void {
  getTdClient().send({ '@type': 'getMe' } as TdRequest).then((me: TdObject): void => {
    const userId = (me['id'] as number | undefined) ?? 0;
    if (userId <= 0) {
      promptAction.showToast({ message: '无法打开收藏夹', duration: 1600 });
      return;
    }
    const req: TdRequest = { '@type': 'createPrivateChat' };
    req['user_id'] = userId;
    req['force'] = false;
    getTdClient().send(req).then((chat: TdObject): void => {
      const chatId = (chat['id'] as number | undefined) ?? 0;
      if (chatId > 0) {
        openChatPage(chatId);
      }
    }).catch((error: TdError): void => {
      console.error(`openTelegramLink.createSavedMessages failed: ${error.message}`);
      promptAction.showToast({ message: '无法打开收藏夹', duration: 1600 });
    });
  }).catch((error: TdError): void => {
    console.error(`openTelegramLink.getMeForSaved failed: ${error.message}`);
    promptAction.showToast({ message: '无法打开收藏夹', duration: 1600 });
  });
}

function openStoryOwner(context: common.UIAbilityContext, username: string, original: string,
    allowBrowser: boolean, live: boolean): void {
  if (username === '') {
    onLinkUnresolved(context, original, allowBrowser);
    return;
  }
  const req: TdRequest = { '@type': 'searchPublicChat' };
  req['username'] = username;
  getTdClient().send(req).then((chat: TdObject): void => {
    openProfileForChat(chat, '', true);
    promptAction.showToast({
      message: live ? '已打开发布者资料，直播动态查看暂未支持' : '已打开发布者动态',
      duration: live ? 2200 : 1400
    });
  }).catch((error: TdError): void => {
    console.error(`openTelegramLink.storyOwner(${username}) failed: ${error.message}`);
    onLinkUnresolved(context, original, allowBrowser);
  });
}

function openPhoneNumberUser(context: common.UIAbilityContext, type: TdObject, original: string,
    allowBrowser: boolean): void {
  const phone = (type['phone_number'] as string | undefined) ?? '';
  if (phone === '') {
    onLinkUnresolved(context, original, allowBrowser);
    return;
  }
  const req: TdRequest = { '@type': 'searchUserByPhoneNumber' };
  req['phone_number'] = phone;
  req['only_local'] = false;
  getTdClient().send(req).then((user: TdObject): void => {
    const userId = (user['id'] as number | undefined) ?? 0;
    if (userId <= 0) {
      onLinkUnresolved(context, original, allowBrowser);
      return;
    }
    const draftText = (type['draft_text'] as string | undefined) ?? '';
    if ((type['open_profile'] as boolean | undefined) ?? false) {
      const params: Record<string, Object> = { 'userId': userId };
      if (draftText !== '') {
        params['draftText'] = draftText;
      }
      router.pushUrl({ url: 'pages/profile/ProfilePage', params: params });
      return;
    }
    const create: TdRequest = { '@type': 'createPrivateChat' };
    create['user_id'] = userId;
    create['force'] = false;
    getTdClient().send(create).then((chat: TdObject): void => {
      const chatId = (chat['id'] as number | undefined) ?? 0;
      if (chatId > 0) {
        const params: Record<string, Object> = { 'chatId': chatId };
        if (draftText !== '') {
          params['draftText'] = draftText;
        }
        router.pushUrl({ url: 'pages/chat/ChatPage', params: params });
      }
    }).catch((error: TdError): void => {
      console.error(`openTelegramLink.createPhoneChat failed: ${error.message}`);
      onLinkUnresolved(context, original, allowBrowser);
    });
  }).catch((error: TdError): void => {
    console.error(`openTelegramLink.searchUserByPhoneNumber failed: ${error.message}`);
    promptAction.showToast({ message: '未找到该手机号对应的用户', duration: 1800 });
  });
}

function openSettingsSection(type: TdObject): void {
  const section = type['section'] as TdObject | undefined;
  if (section === undefined) {
    promptAction.showToast({ message: '请从底部栏进入设置', duration: 1700 });
    return;
  }
  const sectionName = (section['@type'] as string | undefined) ?? '';
  let page = '';
  if (sectionName === 'settingsSectionEditProfile') {
    page = 'pages/main/AccountEditPage';
  } else if (sectionName === 'settingsSectionAppearance') {
    page = 'pages/main/ChatSettingsPage';
  } else if (sectionName === 'settingsSectionChatFolders') {
    page = 'pages/main/ChatFoldersPage';
  } else if (sectionName === 'settingsSectionPrivacyAndSecurity') {
    const subsection = (section['subsection'] as string | undefined) ?? '';
    page = subsection.startsWith('blocked')
      ? 'pages/main/BlockedUsersPage' : 'pages/main/PrivacySecurityPage';
  } else if (sectionName === 'settingsSectionDevices') {
    page = 'pages/main/ActiveSessionsPage';
  } else if (sectionName === 'settingsSectionDataAndStorage') {
    page = 'pages/main/DataStoragePage';
  } else if (sectionName === 'settingsSectionPowerSaving') {
    page = 'pages/main/PowerUsagePage';
  }
  if (page !== '') {
    router.pushUrl({ url: page });
  } else {
    promptAction.showToast({ message: '该设置分项暂未实现', duration: 1800 });
  }
}

function unsupportedLinkLabel(typeName: string): string {
  if (typeName === 'internalLinkTypeBackground') { return '聊天背景'; }
  if (typeName === 'internalLinkTypeTheme') { return '主题'; }
  if (typeName === 'internalLinkTypeLanguagePack') { return '语言包'; }
  if (typeName === 'internalLinkTypeGroupCall') { return '独立群组通话'; }
  if (typeName === 'internalLinkTypeInvoice') { return '付款'; }
  if (typeName === 'internalLinkTypePremiumGiftCode') { return 'Premium 礼品码'; }
  if (typeName === 'internalLinkTypeAuthenticationCode') { return '登录验证码'; }
  if (typeName === 'internalLinkTypeWebApp' || typeName === 'internalLinkTypeMainWebApp') {
    return 'Mini App';
  }
  if (typeName === 'internalLinkTypeBotStartInGroup') { return '将 Bot 添加到群组'; }
  if (typeName === 'internalLinkTypeBotAddToChannel') { return '将 Bot 添加到频道'; }
  if (typeName === 'internalLinkTypeUnknownDeepLink') { return '该类型'; }
  return '该类型';
}

function handleInternalLinkType(context: common.UIAbilityContext, type: TdObject, original: string,
    allowBrowser: boolean): void {
  const typeName = (type['@type'] as string | undefined) ?? '';
  if (typeName === 'internalLinkTypePublicChat') {
    resolvePublicChat(context,
      (type['chat_username'] as string | undefined) ?? '',
      (type['draft_text'] as string | undefined) ?? '',
      (type['open_profile'] as boolean | undefined) ?? false,
      original, allowBrowser);
    return;
  }
  if (typeName === 'internalLinkTypeBotStart') {
    const action: ChatLinkAction = {
      username: (type['bot_username'] as string | undefined) ?? '',
      startParam: (type['start_parameter'] as string | undefined) ?? '',
      draftText: ''
    };
    openChatLinkAction(context, action, original, allowBrowser);
    return;
  }
  if (typeName === 'internalLinkTypeChatInvite') {
    openInviteLink(context, (type['invite_link'] as string | undefined) ?? original,
      original, allowBrowser);
    return;
  }
  if (typeName === 'internalLinkTypeMessage') {
    openMessageLink(context, (type['url'] as string | undefined) ?? original,
      original, allowBrowser);
    return;
  }
  if (typeName === 'internalLinkTypeChatFolderInvite') {
    openChatFolderInviteLink((type['invite_link'] as string | undefined) ?? original);
    return;
  }
  if (typeName === 'internalLinkTypeStickerSet') {
    const sticker: StickerSetLink = {
      name: (type['sticker_set_name'] as string | undefined) ?? '',
      expectCustomEmoji: (type['expect_custom_emoji'] as boolean | undefined) ?? false
    };
    if (sticker.name !== '') {
      openStickerSetLink(sticker);
    } else {
      onLinkUnresolved(context, original, allowBrowser);
    }
    return;
  }
  if (typeName === 'internalLinkTypeProxy') {
    openProxyLink(type);
    return;
  }
  if (typeName === 'internalLinkTypeUserPhoneNumber') {
    openPhoneNumberUser(context, type, original, allowBrowser);
    return;
  }
  if (typeName === 'internalLinkTypeSearch') {
    router.pushUrl({ url: 'pages/search/GlobalSearchPage' });
    return;
  }
  if (typeName === 'internalLinkTypeCallsPage') {
    router.pushUrl({ url: 'pages/main/CallsPage' });
    return;
  }
  if (typeName === 'internalLinkTypeNewGroupChat') {
    router.pushUrl({ url: 'pages/main/NewGroupPage' });
    return;
  }
  if (typeName === 'internalLinkTypeSettings') {
    openSettingsSection(type);
    return;
  }
  if (typeName === 'internalLinkTypeMyProfilePage') {
    openSelfProfile();
    return;
  }
  if (typeName === 'internalLinkTypeSavedMessages') {
    openSavedMessages();
    return;
  }
  if (typeName === 'internalLinkTypeStory' || typeName === 'internalLinkTypeLiveStory') {
    openStoryOwner(context,
      (type['story_poster_username'] as string | undefined) ?? '', original, allowBrowser,
      typeName === 'internalLinkTypeLiveStory');
    return;
  }
  if (typeName === 'internalLinkTypeStoryAlbum') {
    openStoryOwner(context,
      (type['story_album_owner_username'] as string | undefined) ?? '', original, allowBrowser, false);
    return;
  }
  if (typeName === 'internalLinkTypeWebApp' || typeName === 'internalLinkTypeMainWebApp') {
    openMiniAppLink(context, type, typeName === 'internalLinkTypeMainWebApp', original,
      allowBrowser);
    return;
  }
  if (typeName === 'internalLinkTypeVideoChat') {
    // The chat page owns live-state resolution and presents its existing entry
    // banner once TDLib has refreshed the chat's current group call.
    resolvePublicChat(context, (type['chat_username'] as string | undefined) ?? '', '', false,
      original, allowBrowser);
    return;
  }
  promptAction.showToast({
    message: `当前版本暂不支持${unsupportedLinkLabel(typeName)} Telegram 链接`,
    duration: 2100
  });
}

// Mini App links (t.me/<bot>/<app>): resolve the bot, ask TDLib for the real
// https app URL, then render it in the in-app browser.
function openMiniAppLink(context: common.UIAbilityContext, type: TdObject, isMain: boolean,
    original: string, allowBrowser: boolean): void {
  const username = (type['bot_username'] as string | undefined) ?? '';
  if (username === '') {
    onLinkUnresolved(context, original, allowBrowser);
    return;
  }
  const req: TdRequest = { '@type': 'searchPublicChat' };
  req['username'] = username;
  getTdClient().send(req).then((chat: TdObject): Promise<string> => {
    const chatType = chat['type'] as TdObject | undefined;
    const botId = chatType !== undefined ? ((chatType['user_id'] as number | undefined) ?? 0) : 0;
    const chatId = (chat['id'] as number | undefined) ?? 0;
    if (botId === 0) { return Promise.reject(new TdError(404, 'not a bot')); }
    return isMain
      ? getMainMiniApp(chatId, botId)
      : getMiniAppLinkUrl(chatId, botId,
        (type['web_app_short_name'] as string | undefined) ?? '',
        (type['start_parameter'] as string | undefined) ?? '');
  }).then((url: string): void => {
    if (url === '') {
      promptAction.showToast({ message: '无法打开该 Mini App', duration: 1700 });
      return;
    }
    openWebUrl(context, url);
  }).catch((error: TdError): void => {
    console.error(`openMiniAppLink failed: ${error.message}`);
    promptAction.showToast({ message: '无法打开该 Mini App', duration: 1700 });
  });
}

function classifyTelegramLink(context: common.UIAbilityContext, url: string,
    allowBrowser: boolean): void {
  const req: TdRequest = { '@type': 'getInternalLinkType' };
  req['link'] = url;
  getTdClient().send(req).then((type: TdObject): void => {
    handleInternalLinkType(context, type, url, allowBrowser);
  }).catch((error: TdError): void => {
    console.error(`openTelegramLink.getInternalLinkType failed: ${error.message}`);
    // Keep a compatibility fallback for older TDLib builds: the two oldest
    // public link shapes can still be resolved without opening a browser.
    const bareName = bareUsernameOf(url);
    if (bareName !== '') {
      resolvePublicChat(context, bareName, '', false, url, allowBrowser);
      return;
    }
    const normalized = normalizeTelegramLink(url);
    if (normalized !== '') {
      openMessageLink(context, normalized, url, allowBrowser);
      return;
    }
    onLinkUnresolved(context, url, allowBrowser);
  });
}

// Private invite link (t.me/+hash): preview the chat via checkChatInviteLink;
// already a member → straight into the chat, otherwise confirm and join.
export function openInviteLink(context: common.UIAbilityContext, invite: string, original: string,
    allowBrowser: boolean = true): void {
  const req: TdRequest = { '@type': 'checkChatInviteLink' };
  req['invite_link'] = invite;
  getTdClient().send(req).then((info: TdObject) => {
    const chatId = (info['chat_id'] as number | undefined) ?? 0;
    if (chatId !== 0) {
      openChatPage(chatId);
      return;
    }
    const title = (info['title'] as string | undefined) ?? '';
    const count = (info['member_count'] as number | undefined) ?? 0;
    const inviteType = (info['type'] as TdObject | undefined)
      ?? (info['chat_type'] as TdObject | undefined);
    const inviteTypeName = (inviteType?.['@type'] as string | undefined) ?? '';
    const isChannel: boolean = ((info['is_channel'] as boolean | undefined) ?? false) ||
      inviteTypeName.indexOf('Channel') >= 0 || inviteTypeName.indexOf('channel') >= 0;
    promptAction.showDialog({
      title: '加入群组',
      message: count > 0 ? `「${title}」· ${count} 位成员` : `「${title}」`,
      buttons: [
        { text: '取消', color: '#8E8E93' },
        { text: '加入', color: $r('app.color.primary') }
      ]
    }).then((r) => {
      if (r.index !== 1) {
        return;
      }
      const join: TdRequest = { '@type': 'joinChatByInviteLink' };
      join['invite_link'] = invite;
      getTdClient().send(join).then((chat: TdObject) => {
        const id = (chat['id'] as number | undefined) ?? 0;
        if (id !== 0) {
          openChatPage(id, true, isChannel);
        }
      }).catch((e: TdError) => {
        console.error(`openInviteLink.join failed: ${e.message}`);
        promptAction.showToast({ message: '加入失败,链接可能已失效' });
      });
    });
  }).catch((e: TdError) => {
    // Expired or invalid Telegram resources stay in-app and show a precise
    // failure instead of opening Telegram's web landing page.
    console.error(`openInviteLink.check failed: ${e.message}`);
    onLinkUnresolved(context, original, allowBrowser);
  });
}

function folderNameOf(info: TdObject): string {
  const folder = info['chat_folder_info'] as TdObject | undefined;
  const name = folder !== undefined ? (folder['name'] as TdObject | undefined) : undefined;
  const text = name !== undefined ? (name['text'] as TdObject | undefined) : undefined;
  return text !== undefined ? ((text['text'] as string | undefined) ?? '') : '';
}

// Shared folder links are Telegram resources, not web pages. Preview the
// folder and add all chats that aren't present yet after explicit confirmation.
export function openChatFolderInviteLink(invite: string): void {
  const req: TdRequest = { '@type': 'checkChatFolderInviteLink' };
  req['invite_link'] = invite;
  getTdClient().send(req).then((info: TdObject): void => {
    const missing = (info['missing_chat_ids'] as number[] | undefined) ?? [];
    const added = (info['added_chat_ids'] as number[] | undefined) ?? [];
    const name = folderNameOf(info);
    const displayName = name !== '' ? `「${name}」` : '这个聊天文件夹';
    if (missing.length === 0) {
      promptAction.showToast({
        message: added.length > 0 ? `${displayName}已添加` : '文件夹链接中没有可添加的聊天',
        duration: 1700
      });
      return;
    }
    const addedHint = added.length > 0 ? `，另有 ${added.length} 个已在文件夹中` : '';
    promptAction.showDialog({
      title: '添加聊天文件夹',
      message: `${displayName}包含 ${missing.length} 个可添加的聊天${addedHint}。添加后会自动加入尚未加入的群组或频道。`,
      buttons: [
        { text: '取消', color: '#8E8E93' },
        { text: '添加', color: $r('app.color.primary') }
      ]
    }).then((result): void => {
      if (result.index !== 1) {
        return;
      }
      const add: TdRequest = { '@type': 'addChatFolderByInviteLink' };
      add['invite_link'] = invite;
      add['chat_ids'] = missing;
      getTdClient().send(add).then((): void => {
        promptAction.showToast({ message: '聊天文件夹已添加', duration: 1600 });
      }).catch((error: TdError): void => {
        console.error(`openChatFolderInviteLink.add failed: ${error.message}`);
        promptAction.showToast({ message: '添加文件夹失败，请稍后重试', duration: 1800 });
      });
    }).catch((): void => {});
  }).catch((error: TdError): void => {
    console.error(`openChatFolderInviteLink.check failed: ${error.message}`);
    promptAction.showToast({ message: '文件夹链接无效或已失效', duration: 1800 });
  });
}

// Resolve a sticker-set short name, show its actual server-side metadata, then
// install/activate it in-place. Custom emoji links use the same TDLib object.
export function openStickerSetLink(link: StickerSetLink): void {
  const req: TdRequest = { '@type': 'searchStickerSet' };
  req['name'] = link.name;
  req['ignore_cache'] = false;
  getTdClient().send(req).then((set: TdObject): void => {
    const setId = (set['id'] as number | undefined) ?? 0;
    const title = (set['title'] as string | undefined) ?? link.name;
    const installed = (set['is_installed'] as boolean | undefined) ?? false;
    const stickers = (set['stickers'] as TdObject[] | undefined) ?? [];
    const type = set['sticker_type'] as TdObject | undefined;
    const isCustomEmoji = link.expectCustomEmoji ||
      (type !== undefined && type['@type'] === 'stickerTypeCustomEmoji');
    const resourceName = isCustomEmoji ? 'Emoji 包' : '贴纸包';
    const countHint = stickers.length > 0 ? `，共 ${stickers.length} 个` : '';
    promptAction.showDialog({
      title: installed ? `${resourceName}已添加` : `添加${resourceName}`,
      message: `「${title}」${countHint}`,
      buttons: [
        { text: '关闭', color: '#8E8E93' },
        { text: installed ? '已添加' : '添加', color: $r('app.color.primary') }
      ]
    }).then((result): void => {
      if (result.index !== 1 || installed || setId <= 0) {
        return;
      }
      const change: TdRequest = { '@type': 'changeStickerSet' };
      change['set_id'] = setId;
      change['is_installed'] = true;
      change['is_archived'] = false;
      getTdClient().send(change).then((): void => {
        promptAction.showToast({ message: `${resourceName}已添加`, duration: 1500 });
      }).catch((error: TdError): void => {
        console.error(`openStickerSetLink.change failed: ${error.message}`);
        promptAction.showToast({ message: `${resourceName}添加失败，请稍后重试`, duration: 1800 });
      });
    }).catch((): void => {});
  }).catch((error: TdError): void => {
    console.error(`openStickerSetLink.search(${link.name}) failed: ${error.message}`);
    promptAction.showToast({ message: '贴纸链接无效或已失效', duration: 1800 });
  });
}

// Chat link carrying an action payload: resolve the username, enter the chat,
// then auto-send /start (bot ?start= links) or prefill the draft (?text=).
export function openChatLinkAction(context: common.UIAbilityContext, action: ChatLinkAction,
    original: string, allowBrowser: boolean): void {
  const req: TdRequest = { '@type': 'searchPublicChat' };
  req['username'] = action.username;
  getTdClient().send(req).then((chat: TdObject) => {
    const chatId = (chat['id'] as number | undefined) ?? 0;
    if (chatId === 0) {
      onLinkUnresolved(context, original, allowBrowser);
      return;
    }
    const params: Record<string, Object> = { 'chatId': chatId };
    if (action.draftText !== '') {
      params['draftText'] = action.draftText;
    }
    router.pushUrl({ url: 'pages/chat/ChatPage', params: params });
    if (action.startParam === '') {
      return;
    }
    const type = chat['type'] as TdObject | undefined;
    const uid = type !== undefined ? ((type['user_id'] as number | undefined) ?? 0) : 0;
    if (uid <= 0) {
      return; // ?start= is only meaningful on a private bot chat
    }
    const start: TdRequest = { '@type': 'sendBotStartMessage' };
    start['bot_user_id'] = uid;
    start['chat_id'] = chatId;
    start['parameter'] = action.startParam;
    getTdClient().send(start).catch((e: TdError) => {
      console.error(`openTelegramLink.sendBotStartMessage failed: ${e.message}`);
      promptAction.showToast({ message: '发送 /start 失败', duration: 1500 });
    });
  }).catch((e: TdError) => {
    console.error(`openTelegramLink.searchPublicChat(${action.username}) failed: ${e.message}`);
    onLinkUnresolved(context, original, allowBrowser);
  });
}

// Full in-app routing for a tapped link outside the chat page (profile bios,
// channel descriptions, ...): text mentions open the profile card, usernames
// resolve to a profile/chat, message links open the chat at the message, and
// external web URLs still go to the system browser.
export function openTelegramLink(context: common.UIAbilityContext, url: string,
    allowBrowser: boolean = true): void {
  const raw = url.trim();
  if (raw === '') {
    return;
  }
  if (raw.startsWith('tg://user?id=')) {
    const uid = Number(raw.substring('tg://user?id='.length));
    if (uid > 0) {
      const params: Record<string, Object> = { 'userId': uid };
      router.pushUrl({ url: 'pages/profile/ProfilePage', params: params });
    }
    return;
  }
  const folderInvite = chatFolderInviteLinkOf(raw);
  if (folderInvite !== '') {
    openChatFolderInviteLink(folderInvite);
    return;
  }
  const stickerSet = stickerSetLinkOf(raw);
  if (stickerSet !== null) {
    openStickerSetLink(stickerSet);
    return;
  }
  const invite = inviteLinkOf(raw);
  if (invite !== '') {
    openInviteLink(context, invite, raw, allowBrowser);
    return;
  }
  // ?start= / ?text= actions take priority over plain username routing —
  // bareUsernameOf drops the query string, which would lose the payload.
  const action = chatLinkActionOf(raw);
  if (action !== null) {
    openChatLinkAction(context, action, raw, allowBrowser);
    return;
  }
  // Plain @mentions aren't accepted by getInternalLinkType; resolve those
  // directly. Every real t.me/telegram.me/telegram.dog/tg:// URL goes through
  // TDLib so reserved routes such as /proxy aren't mistaken for usernames.
  if (raw.startsWith('@')) {
    const bareName = bareUsernameOf(raw);
    if (bareName !== '') {
      resolvePublicChat(context, bareName, '', false, raw, allowBrowser);
    } else {
      onLinkUnresolved(context, raw, allowBrowser);
    }
    return;
  }
  if (isTelegramInternalUrl(raw)) {
    classifyTelegramLink(context, raw, allowBrowser);
    return;
  }
  onLinkUnresolved(context, raw, allowBrowser);
}
