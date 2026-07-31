import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { UserStore } from './UserStore';
import { MessageEntry, cloneMessage, buildMessageEntry, commentInfoFromInteraction, CommentInfo, reactionsFromInteraction, ReactionInfo, parseInlineKeyboard, refreshSystemUserLabel } from './MessageEntry';
import { ReplyKeyboard, parseReplyKeyboard } from './ReplyKeyboard';
import { formatUserStatus } from '../util/formatUserStatus';
import { formatPreview } from '../util/formatPreview';
import { formatMemberCount } from '../util/formatMemberCount';
import { KEY_POWER_AUTOPLAY_GIF, powerFeatureEnabled, reduceAnimations } from './AppSettings';
import { PollOptionInfo } from '../util/formatMsgContent';

const PAGE: number = 30;
// Visible bubble/header thumbnails should outrank silent video prefetch. The
// bubble still requests the compact inline size; this only changes scheduling,
// not image quality or transferred bytes.
const THUMBNAIL_PRIORITY: number = 16;
const MEDIA_PREFETCH_PRIORITY: number = 8;
const MEDIA_USER_PRIORITY: number = 24;
const REPLY_KB_PROBE_PAGE: number = 100;
const REPLY_KB_PROBE_LIMIT: number = 500;
// Re-request a still-missing thumbnail at most this often (stalled downloads
// whose bounded retries were exhausted by a transient network failure).
const THUMB_REKICK_MS: number = 8000;

type MsgListener = (msgs: MessageEntry[]) => void;
type SubtitleListener = (s: string) => void;
type ReplyKeyboardListener = (kb: ReplyKeyboard | null) => void;

interface KeyboardMarkupHit {
  messageId: number;
  keyboard: ReplyKeyboard | null;
}

export interface MediaSendItem {
  path: string;
  isVideo: boolean;
}

export class MessageStore {
  private client: TdClient;
  private users: UserStore;
  private chatId: number;
  private messages: MessageEntry[] = [];
  private oldestId: number = 0;
  private subtitle: string = '';
  private pinnedPreview: string = '';
  private pinnedIds: number[] = [];
  private pinnedPreviews: string[] = [];
  private pinnedLoadState: string = 'loading';
  private pinnedResolveSeq: number = 0;
  private msgSubs: MsgListener[] = [];
  private subSubs: SubtitleListener[] = [];
  private pinnedSubs: SubtitleListener[] = [];
  private unsubs: Array<() => void> = [];
  private fileToMsg: Map<number, number> = new Map();
  private linkFileToMsg: Map<number, number> = new Map();
  private fullPhotoFileToMsg: Map<number, number> = new Map();
  private videoFileToMsg: Map<number, number> = new Map();
  private voiceListenPending: Set<number> = new Set();
  private stickerFileToMsg: Map<number, number> = new Map();
  private inlineCustomEmojiFileToId: Map<number, string> = new Map();
  private inlineCustomEmojiPathById: Map<string, string> = new Map();
  // Telegram reuses the same thumbnail/source file ids whenever the same
  // sticker is sent again. Keep completed paths independently from a message
  // id so a newly-created outgoing bubble can render immediately.
  private completedFilePaths: Map<number, string> = new Map();
  private thumbLastKick: Map<number, number> = new Map();
  private peerUserId: number = 0;
  private peerUserStatus: TdObject | undefined = undefined;
  private statusRefreshTimer: number = -1;
  private groupId: number = 0;
  private lastReadInboxId: number = 0;
  private lastReadOutboxId: number = 0;
  private unreadCount: number = 0;
  private viewedUpTo: number = 0;
  private chatResolved: boolean = false;
  private historyPending: boolean = false;
  private historyPendingKind: string = 'history';
  private isGroupFlag: boolean = false;
  private isChannel: boolean = false;
  private chatPhotoFileId: number = 0;
  private chatPhotoPath: string = '';
  private headerAvatarSubs: SubtitleListener[] = [];
  private chatTitle: string = '';
  private headerTitleSubs: SubtitleListener[] = [];
  private senderAvatarPaths: Map<string, string> = new Map();
  private senderRequested: Set<string> = new Set();
  private avatarFileToSender: Map<number, string> = new Map();
  private forwardTitleCache: Map<number, string> = new Map();
  private forwardTitleRequested: Set<number> = new Set();
  private thumbAttempts: Map<number, number> = new Map();
  private replierAvatarPaths: Map<number, string> = new Map();
  private replierAvatarRequested: Set<number> = new Set();
  private avatarFileToReplier: Map<number, number> = new Map();
  private contactAvatarPaths: Map<number, string> = new Map();
  private contactAvatarRequested: Set<number> = new Set();
  private avatarFileToContact: Map<number, number> = new Map();
  private requestedAroundMessageId: number = 0;
  private initialLoadStarted: boolean = false;
  private initialHistoryState: string = 'loading'; // loading | ready | error
  private initialHistoryError: string = '';
  private olderPending: boolean = false;
  private newerPending: boolean = false;
  private latestPending: boolean = false;
  private hasMoreOlder: boolean = true;
  private hasMoreNewer: boolean = false;
  // Pagination errors never replace an already-readable timeline. The page
  // renders them as compact edge pills with an explicit retry action.
  private olderLoadState: string = 'idle'; // idle | loading | error | end
  private newerLoadState: string = 'idle'; // idle | loading | error | end
  // Exposed only while listeners are being notified. The page uses this to
  // distinguish a real-time arrival from a newer-history page whose maximum
  // id also increases, but must not animate or auto-follow like a new message.
  private currentNotifyKind: string = 'update';
  private memberCount: number = 0;
  private onlineCount: number = 0;
  // Bot custom reply keyboard. Chat-level: replyMarkupMessageId names the
  // message carrying the active markup (0 = none, per chat.reply_markup_message_id).
  private replyMarkupMessageId: number = 0;
  private replyKeyboard: ReplyKeyboard | null = null;
  private replyKbSubs: ReplyKeyboardListener[] = [];
  // Fallback for when TDLib reports chat.reply_markup_message_id as 0 even though
  // a keyboard is live (seen in supergroups, and after a one_time keyboard is
  // used — other clients keep showing it). Tracks the NEWEST loaded message
  // carrying a keyboard-affecting markup, and the keyboard it implies
  // (null when that newest markup is replyMarkupRemoveKeyboard).
  private kbMarkupMsgId: number = 0;
  private kbFromHistory: ReplyKeyboard | null = null;
  private kbHistoryProbeSeq: number = 0;
  private kbHistoryProbeRunning: boolean = false;
  private chatOpened: boolean = false;

  // >0: this store is scoped to one message thread (channel-post comments) —
  // history comes from getMessageThreadHistory and sends target the thread.
  private threadRootId: number = 0;
  private historyPageSize: number = PAGE;

  constructor(client: TdClient, users: UserStore, chatId: number,
    threadRootId: number = 0, historyPageSize: number = PAGE) {
    this.client = client;
    this.users = users;
    this.chatId = chatId;
    this.threadRootId = threadRootId;
    this.historyPageSize = Math.max(1, Math.min(100, historyPageSize));
  }

  // getChatHistory, or getMessageThreadHistory when scoped to a comment thread
  // (same paging contract: from_message_id + offset + limit).
  private historyRequest(fromId: number, offset: number): TdRequest {
    const req: TdRequest = { '@type': this.threadRootId > 0 ? 'getMessageThreadHistory' : 'getChatHistory' };
    req['chat_id'] = this.chatId;
    req['from_message_id'] = fromId;
    req['offset'] = offset;
    req['limit'] = this.historyPageSize;
    if (this.threadRootId > 0) {
      req['message_id'] = this.threadRootId;
    } else {
      req['only_local'] = false;
    }
    return req;
  }

  open(aroundMessageId?: number, passive: boolean = false): void {
    // Embedded consumers such as the livestream interaction panel need chat
    // history and updates without changing TDLib's open-chat lifecycle for the
    // full ChatPage underneath them.
    if (!passive) {
      this.sendSimple('openChat');
      this.chatOpened = true;
    }
    this.unsubs.push(this.client.onUpdate('updateNewMessage', (u: TdObject) => this.onNewMessage(u)));
    this.unsubs.push(this.client.onUpdate('updateMessageSendSucceeded', (u: TdObject) => this.onSendSucceeded(u)));
    this.unsubs.push(this.client.onUpdate('updateMessageSendFailed', (u: TdObject) => this.onSendFailed(u)));
    this.unsubs.push(this.client.onUpdate('updateMessageContent', (u: TdObject) => this.onContent(u)));
    this.unsubs.push(this.client.onUpdate('updatePoll', (u: TdObject) => this.onPoll(u)));
    this.unsubs.push(this.client.onUpdate('updateDeleteMessages', (u: TdObject) => this.onDelete(u)));
    this.unsubs.push(this.client.onUpdate('updateChatReadOutbox', (u: TdObject) => this.onReadOutbox(u)));
    this.unsubs.push(this.client.onUpdate('updateFile', (u: TdObject) => this.onFile(u)));
    this.unsubs.push(this.client.onUpdate('updateUserStatus', (u: TdObject) => this.onUserStatus(u)));
    this.unsubs.push(this.client.onUpdate('updateBasicGroup', (u: TdObject) => this.onGroup(u)));
    this.unsubs.push(this.client.onUpdate('updateSupergroup', (u: TdObject) => this.onGroup(u)));
    this.unsubs.push(this.client.onUpdate('updateUser', () => {
      this.resolveSenderAvatars();
      this.resolveSystemUserLabels();
      this.resolveCommentAvatars();
      this.resolveContactAvatars();
    }));
    this.unsubs.push(this.client.onUpdate('updateMessageInteractionInfo', (u: TdObject) => this.onInteractionInfo(u)));
    this.unsubs.push(this.client.onUpdate('updateChatOnlineMemberCount', (u: TdObject) => this.onOnlineCount(u)));
    // A message got (un)pinned while the chat is open — re-resolve the pinned
    // list so the banner reflects the new pin without re-entering the chat.
    this.unsubs.push(this.client.onUpdate('updateMessageIsPinned', (u: TdObject) => {
      if ((u['chat_id'] as number | undefined) === this.chatId) {
        this.onPinnedUpdate(u);
      }
    }));
    this.unsubs.push(this.client.onUpdate('updateMessageEdited', (u: TdObject) => this.onEdited(u)));
    // Bot showed/removed its custom reply keyboard.
    this.unsubs.push(this.client.onUpdate('updateChatReplyMarkup', (u: TdObject) => this.onChatReplyMarkup(u)));
    this.requestedAroundMessageId = aroundMessageId !== undefined ? aroundMessageId : 0;
    this.resolveChat();
    this.resolvePinned();
    if (this.threadRootId > 0) {
      this.fetchThreadRoot();
    }
  }

  // Comment thread: the root (the channel post as forwarded into the discussion
  // group) heads the view — thread history alone may not include it.
  private fetchThreadRoot(): void {
    const req: TdRequest = { '@type': 'getMessage' };
    req['chat_id'] = this.chatId;
    req['message_id'] = this.threadRootId;
    this.client.send(req).then((m: TdObject) => {
      this.upsert(buildMessageEntry(m, this.users));
      this.requestPhotos();
      this.resolveSenderAvatars();
      this.notify();
    }).catch((e: TdError) => {
      console.error(`MessageStore.fetchThreadRoot failed: ${e.message}`);
    });
  }

  close(): void {
    this.pinnedResolveSeq++;
    this.kbHistoryProbeSeq++;
    this.kbHistoryProbeRunning = false;
    if (this.chatOpened) {
      this.sendSimple('closeChat');
      this.chatOpened = false;
    }
    for (const un of this.unsubs) {
      un();
    }
    this.unsubs = [];
    if (this.statusRefreshTimer !== -1) {
      clearInterval(this.statusRefreshTimer);
      this.statusRefreshTimer = -1;
    }
  }

  getMessages(): MessageEntry[] {
    return this.messages;
  }

  getSubtitle(): string {
    return this.subtitle;
  }

  // Chat unread count snapshot captured at open time (for the scroll-to-bottom badge).
  getUnreadCount(): number {
    return this.unreadCount;
  }

  // True for basic groups / supergroups / channels — drives per-message avatars + sender names.
  getIsGroup(): boolean {
    return this.isGroupFlag;
  }

  // True only for broadcast channels — reply_info.reply_count is a generic
  // Peer user id for private chats (0 for groups/channels) — used to open the
  // user profile page from the chat header.
  getPeerUserId(): number {
    return this.peerUserId;
  }

  // "times replied" counter shared with ordinary in-chat reply threads, so the
  // "N Comments" chip must only render for real channel posts.
  getIsChannel(): boolean {
    return this.isChannel;
  }

  // Id of the first unread message captured at open time (0 = none / all read).
  // Used by the page to position the initial scroll at the unread boundary.
  getFirstUnreadId(): number {
    if (this.unreadCount <= 0 || this.lastReadInboxId <= 0) {
      return 0;
    }
    for (const m of this.messages) {
      if (m.id > this.lastReadInboxId) {
        return m.id;
      }
    }
    return 0;
  }

  getReplyKeyboard(): ReplyKeyboard | null {
    return this.replyKeyboard;
  }

  subscribeReplyKeyboard(l: ReplyKeyboardListener): () => void {
    this.replyKbSubs = [...this.replyKbSubs, l];
    l(this.replyKeyboard);
    return (): void => { this.replyKbSubs = this.replyKbSubs.filter((x: ReplyKeyboardListener) => x !== l); };
  }

  private setReplyKeyboard(kb: ReplyKeyboard | null): void {
    this.replyKeyboard = kb;
    for (const l of this.replyKbSubs) {
      l(kb);
    }
  }

  // Resolve replyMarkupMessageId into an actual keyboard. The message is usually
  // already in the loaded window; otherwise fetch it (the markup often comes from
  // a message far above the current view, so we can't rely on history alone).
  private resolveReplyKeyboard(): void {
    const id = this.replyMarkupMessageId;
    if (id === 0) {
      // TDLib reports 0 here even when a keyboard is live (supergroups; a
      // one_time keyboard that's already been used) while other clients keep
      // showing it — so trust the newest keyboard markup seen in history.
      this.setReplyKeyboard(this.kbFromHistory);
      return;
    }
    const req: TdRequest = { '@type': 'getMessage' };
    req['chat_id'] = this.chatId;
    req['message_id'] = id;
    this.client.send(req).then((m: TdObject) => {
      if (this.replyMarkupMessageId !== id) {
        return; // superseded while in flight
      }
      this.setReplyKeyboard(parseReplyKeyboard(m));
    }).catch((e: TdError) => {
      console.error(`MessageStore.resolveReplyKeyboard(${id}) failed: ${e.message}`);
      this.setReplyKeyboard(this.kbFromHistory);
      this.startKeyboardHistoryProbe();
    });
  }

  private onChatReplyMarkup(u: TdObject): void {
    if ((u['chat_id'] as number | undefined) !== this.chatId) {
      return;
    }
    this.replyMarkupMessageId = (u['reply_markup_message_id'] as number | undefined) ?? 0;
    this.resolveReplyKeyboard();
    if (this.replyMarkupMessageId === 0) {
      // Restart from the live tail: this update can mean a removal, but some
      // supergroups also publish 0 while a persistent keyboard remains active.
      this.startKeyboardHistoryProbe(true);
    }
  }

  private newestKeyboardMarkup(arr: TdObject[]): KeyboardMarkupHit | null {
    let hit: KeyboardMarkupHit | null = null;
    for (const m of arr) {
      const mk = m['reply_markup'] as TdObject | undefined;
      if (mk === undefined) {
        continue;
      }
      const t = (mk['@type'] as string | undefined) ?? '';
      if (t !== 'replyMarkupShowKeyboard' && t !== 'replyMarkupRemoveKeyboard') {
        continue;
      }
      const id = (m['id'] as number | undefined) ?? 0;
      if (id <= 0 || (hit !== null && id <= hit.messageId)) {
        continue;
      }
      hit = {
        messageId: id,
        keyboard: t === 'replyMarkupShowKeyboard' ? parseReplyKeyboard(m) : null
      };
    }
    return hit;
  }

  private applyKeyboardMarkupHit(hit: KeyboardMarkupHit): void {
    if (hit.messageId < this.kbMarkupMsgId) {
      return;
    }
    this.kbMarkupMsgId = hit.messageId;
    this.kbFromHistory = hit.keyboard;
    if (this.replyMarkupMessageId === 0 ||
      this.replyMarkupMessageId === hit.messageId) {
      this.setReplyKeyboard(hit.keyboard);
    }
  }

  // Track a real-time message that shows or removes a reply keyboard.
  // (replyMarkupInlineKeyboard is NOT one of these — those buttons live in the
  // bubble and are rendered separately.)
  private scanKeyboardMarkup(arr: TdObject[]): void {
    const hit: KeyboardMarkupHit | null = this.newestKeyboardMarkup(arr);
    if (hit === null) {
      return;
    }
    this.kbHistoryProbeSeq++;
    this.kbHistoryProbeRunning = false;
    this.applyKeyboardMarkupHit(hit);
  }

  // In busy groups the active keyboard message can be far above the currently
  // rendered 30-message window, and TDLib can publish reply_markup_message_id
  // as 0. Probe from the LIVE tail independently of the user's history anchor;
  // the first show/remove marker encountered is the authoritative newest one.
  private startKeyboardHistoryProbe(force: boolean = false): void {
    if (this.kbHistoryProbeRunning && !force) {
      return;
    }
    const seq: number = ++this.kbHistoryProbeSeq;
    this.kbHistoryProbeRunning = true;
    this.probeKeyboardHistoryPage(seq, 0, 0);
  }

  private finishKeyboardHistoryProbe(seq: number): void {
    if (seq === this.kbHistoryProbeSeq) {
      this.kbHistoryProbeRunning = false;
    }
  }

  private probeKeyboardHistoryPage(seq: number, fromMessageId: number,
    scanned: number): void {
    if (seq !== this.kbHistoryProbeSeq) {
      return;
    }
    const req: TdRequest = { '@type': 'getChatHistory' };
    req['chat_id'] = this.chatId;
    req['from_message_id'] = fromMessageId;
    req['offset'] = 0;
    req['limit'] = REPLY_KB_PROBE_PAGE;
    req['only_local'] = false;
    this.client.send(req).then((res: TdObject): void => {
      if (seq !== this.kbHistoryProbeSeq) {
        return;
      }
      const arr: TdObject[] = (res['messages'] as TdObject[] | undefined) ?? [];
      const hit: KeyboardMarkupHit | null = this.newestKeyboardMarkup(arr);
      if (hit !== null) {
        this.applyKeyboardMarkupHit(hit);
        this.finishKeyboardHistoryProbe(seq);
        return;
      }
      const nextScanned: number = scanned + arr.length;
      if (arr.length === 0 || nextScanned >= REPLY_KB_PROBE_LIMIT) {
        this.finishKeyboardHistoryProbe(seq);
        return;
      }
      let oldestId: number = 0;
      for (const m of arr) {
        const id: number = (m['id'] as number | undefined) ?? 0;
        if (id > 0 && (oldestId === 0 || id < oldestId)) {
          oldestId = id;
        }
      }
      if (oldestId === 0 || oldestId === fromMessageId) {
        this.finishKeyboardHistoryProbe(seq);
        return;
      }
      this.probeKeyboardHistoryPage(seq, oldestId, nextScanned);
    }).catch((e: TdError): void => {
      this.finishKeyboardHistoryProbe(seq);
      if (e.code !== 404) {
        console.error(`MessageStore keyboard history probe failed: ${e.message}`);
      }
    });
  }

  private ensureKeyboardHistoryProbe(): void {
    if (this.isGroupFlag && this.replyMarkupMessageId === 0 &&
      this.kbMarkupMsgId === 0) {
      this.startKeyboardHistoryProbe();
    }
  }

  subscribe(l: MsgListener): () => void {
    this.msgSubs = [...this.msgSubs, l];
    l(this.messages);
    return (): void => { this.msgSubs = this.msgSubs.filter((x: MsgListener) => x !== l); };
  }

  subscribeSubtitle(l: SubtitleListener): () => void {
    this.subSubs = [...this.subSubs, l];
    l(this.subtitle);
    return (): void => { this.subSubs = this.subSubs.filter((x: SubtitleListener) => x !== l); };
  }

  subscribePinned(l: SubtitleListener): () => void {
    this.pinnedSubs = [...this.pinnedSubs, l];
    l(this.pinnedPreview);
    return (): void => { this.pinnedSubs = this.pinnedSubs.filter((x: SubtitleListener) => x !== l); };
  }

  getPinnedLoadState(): string {
    return this.pinnedLoadState;
  }

  refreshPinned(): void {
    this.resolvePinned();
  }

  // Header avatar path, resolved from the chat photo. Authoritative for the chat
  // page header (works even for channels/chats not present in the loaded lists).
  subscribeHeaderAvatar(l: SubtitleListener): () => void {
    this.headerAvatarSubs = [...this.headerAvatarSubs, l];
    l(this.chatPhotoPath);
    return (): void => { this.headerAvatarSubs = this.headerAvatarSubs.filter((x: SubtitleListener) => x !== l); };
  }

  // Chat title resolved from getChat — a fallback header title/initials for chats
  // opened by t.me link that aren't in ChatStore's cache yet.
  subscribeHeaderTitle(l: SubtitleListener): () => void {
    this.headerTitleSubs = [...this.headerTitleSubs, l];
    l(this.chatTitle);
    return (): void => { this.headerTitleSubs = this.headerTitleSubs.filter((x: SubtitleListener) => x !== l); };
  }

  private notifyHeaderTitle(): void {
    for (const l of this.headerTitleSubs) {
      l(this.chatTitle);
    }
  }

  private notifyHeaderAvatar(): void {
    for (const l of this.headerAvatarSubs) {
      l(this.chatPhotoPath);
    }
  }

  // Load the previous (older) page. Guarded so scroll-driven prefetch can call
  // this repeatedly without stacking duplicate in-flight requests.
  loadOlder(): boolean {
    if (this.olderPending || this.olderLoadState === 'error' ||
      !this.hasMoreOlder || this.oldestId === 0) {
      return false;
    }
    const anchorId = this.oldestId;
    this.olderPending = true;
    this.olderLoadState = 'loading';
    this.notify('paginationState');
    const req = this.historyRequest(anchorId, 0);
    this.client.send(req).then((res: TdObject) => {
      this.olderPending = false;
      const arr = (res['messages'] as TdObject[] | undefined) ?? [];
      let hasOlderEntry = false;
      for (const message of arr) {
        const id = (message['id'] as number | undefined) ?? 0;
        if (id > 0 && id < anchorId) {
          hasOlderEntry = true;
          break;
        }
      }
      if (!hasOlderEntry) {
        this.hasMoreOlder = false;
        this.olderLoadState = 'end';
      } else {
        this.olderLoadState = 'idle';
      }
      this.onHistory(res, 'older');
    }).catch((e: TdError) => {
      this.olderPending = false;
      if ((e as TdError).code === 404) {
        this.hasMoreOlder = false;
        this.olderLoadState = 'end';
      } else {
        this.olderLoadState = 'error';
        console.error(`MessageStore.loadOlder failed: ${e.message}`);
      }
      this.notify('paginationState');
    });
    return true;
  }

  // True while unloaded newer pages exist below the loaded window (i.e. we
  // jumped into the middle of history and haven't reached the live tail).
  getHasMoreNewer(): boolean {
    return this.hasMoreNewer;
  }

  getHasMoreOlder(): boolean {
    return this.hasMoreOlder;
  }

  getOlderLoadState(): string {
    return this.olderLoadState;
  }

  getNewerLoadState(): string {
    return this.newerLoadState;
  }

  getCurrentNotifyKind(): string {
    return this.currentNotifyKind;
  }

  getInitialHistoryState(): string {
    return this.initialHistoryState;
  }

  getInitialHistoryError(): string {
    return this.initialHistoryError;
  }

  retryInitialHistory(): void {
    if (this.initialHistoryState !== 'error') {
      return;
    }
    this.initialHistoryState = 'loading';
    this.initialHistoryError = '';
    this.notify('initialState');
    this.requestInitialPage();
  }

  retryOlder(): void {
    if (this.olderLoadState !== 'error') {
      return;
    }
    this.olderLoadState = 'idle';
    this.loadOlder();
  }

  retryNewer(): void {
    if (this.newerLoadState !== 'error') {
      return;
    }
    this.newerLoadState = 'idle';
    this.loadNewer();
  }

  // Jump straight to the newest messages: drop the loaded window and reload
  // latest page. The replacement is atomic: keep the current window visible
  // until the request succeeds, so a network failure never leaves a blank list.
  // Used by the scroll-to-bottom button when thousands of unloaded messages
  // separate the user from the tail.
  jumpToLatest(onComplete?: (success: boolean) => void): void {
    if (this.latestPending) {
      if (onComplete !== undefined) {
        onComplete(false);
      }
      return;
    }
    this.latestPending = true;
    const req = this.historyRequest(0, 0);
    this.client.send(req).then((res: TdObject): void => {
      this.latestPending = false;
      this.hasMoreNewer = false;
      this.hasMoreOlder = true;
      this.newerPending = false;
      this.olderPending = false;
      this.newerLoadState = 'end';
      this.olderLoadState = 'idle';
      this.messages = [];
      this.oldestId = 0;
      this.onHistory(res, 'latest');
      if (onComplete !== undefined) {
        onComplete(true);
      }
    }).catch((e: TdError): void => {
      this.latestPending = false;
      if ((e as TdError).code !== 404) {
        console.error(`MessageStore.jumpToLatest failed: ${e.message}`);
      }
      if (onComplete !== undefined) {
        onComplete(false);
      }
    });
  }

  // Load the next (newer) page — only meaningful after a loadAround jump into
  // the middle of history left unloaded messages below the window.
  loadNewer(): boolean {
    if (this.newerPending || this.newerLoadState === 'error' ||
      !this.hasMoreNewer || this.messages.length === 0) {
      return false;
    }
    const newestId = this.messages[this.messages.length - 1].id;
    this.newerPending = true;
    this.newerLoadState = 'loading';
    this.notify('paginationState');
    const req = this.historyRequest(newestId, -(this.historyPageSize - 1));
    this.client.send(req).then((res: TdObject) => {
      this.newerPending = false;
      const arr = (res['messages'] as TdObject[] | undefined) ?? [];
      let maxId = 0;
      for (const m of arr) {
        const id = (m['id'] as number | undefined) ?? 0;
        if (id > maxId) {
          maxId = id;
        }
      }
      if (maxId <= newestId) {
        this.hasMoreNewer = false; // nothing newer came back — we've reached the live tail
        this.newerLoadState = 'end';
      } else {
        this.newerLoadState = 'idle';
      }
      this.onHistory(res, 'newer');
    }).catch((e: TdError) => {
      this.newerPending = false;
      if ((e as TdError).code === 404) {
        this.hasMoreNewer = false;
        this.newerLoadState = 'end';
      } else {
        this.newerLoadState = 'error';
        console.error(`MessageStore.loadNewer failed: ${e.message}`);
      }
      this.notify('paginationState');
    });
    return true;
  }

  send(text: string, replyToId: number = 0): void {
    this.sendAsync(text, replyToId).catch((e: TdError) => {
      console.error(`MessageStore.send failed: ${e.message}`);
    });
  }

  sendAsync(text: string, replyToId: number = 0): Promise<void> {
    const ft: TdObject = { '@type': 'formattedText' };
    ft['text'] = text;
    const content: TdObject = { '@type': 'inputMessageText' };
    content['text'] = ft;
    const req: TdRequest = { '@type': 'sendMessage' };
    req['chat_id'] = this.chatId;
    if (replyToId !== 0) {
      const rt: TdObject = { '@type': 'inputMessageReplyToMessage' };
      rt['message_id'] = replyToId;
      req['reply_to'] = rt;
    }
    req['input_message_content'] = content;
    if (this.threadRootId > 0) {
      req['message_thread_id'] = this.threadRootId;
    }
    return this.client.send(req).then((m: TdObject): void => {
      this.upsert(buildMessageEntry(m, this.users));
      this.resolveReplies();
      this.notify();
    });
  }

  // Toggle an emoji reaction on a message. TDLib pushes the updated counts back
  // via updateMessageInteractionInfo, which onInteraction() already applies.
  setReaction(messageId: number, emoji: string, isChosen: boolean): Promise<void> {
    const rt: TdObject = { '@type': 'reactionTypeEmoji' };
    rt['emoji'] = emoji;
    if (isChosen) {
      const req: TdRequest = { '@type': 'removeMessageReaction' };
      req['chat_id'] = this.chatId;
      req['message_id'] = messageId;
      req['reaction_type'] = rt;
      return this.client.send(req).then((): void => {}).catch((e: TdError): Promise<void> => {
        console.error(`MessageStore.removeMessageReaction failed: ${e.message}`);
        return Promise.reject(e);
      });
    }
    const req: TdRequest = { '@type': 'addMessageReaction' };
    req['chat_id'] = this.chatId;
    req['message_id'] = messageId;
    req['reaction_type'] = rt;
    req['is_big'] = false;
    req['update_recent_reactions'] = true;
    return this.client.send(req).then((): void => {}).catch((e: TdError): Promise<void> => {
      console.error(`MessageStore.addMessageReaction failed: ${e.message}`);
      return Promise.reject(e);
    });
  }

  // Resolve a public/private t.me link for a message (used by 拷贝消息链接).
  messageLink(messageId: number, cb: (url: string) => void): void {
    const req: TdRequest = { '@type': 'getMessageLink' };
    req['chat_id'] = this.chatId;
    req['message_id'] = messageId;
    this.client.send(req).then((res: TdObject) => {
      cb((res['link'] as string | undefined) ?? '');
    }).catch((e: TdError) => {
      console.error(`MessageStore.getMessageLink failed: ${e.message}`);
      cb('');
    });
  }

  // Send a document from a local (sandbox) path. TDLib uploads it and the
  // pending message arrives via the normal update flow.
  sendDocument(path: string, caption: string): void {
    const inputFile: TdObject = { '@type': 'inputFileLocal' };
    inputFile['path'] = path;
    const content: TdObject = { '@type': 'inputMessageDocument' };
    content['document'] = inputFile;
    if (caption !== '') {
      const ft: TdObject = { '@type': 'formattedText' };
      ft['text'] = caption;
      content['caption'] = ft;
    }
    const req: TdRequest = { '@type': 'sendMessage' };
    req['chat_id'] = this.chatId;
    req['input_message_content'] = content;
    if (this.threadRootId > 0) {
      req['message_thread_id'] = this.threadRootId;
    }
    this.client.send(req).then((m: TdObject) => {
      this.upsert(buildMessageEntry(m, this.users));
      // Media returned by sendMessage still needs the same local-file
      // resolution as history/new-message entries. Omitting this left a newly
      // sent sticker on its loading ring until the chat was reopened.
      this.requestPhotos();
      this.notify();
    }).catch((e: TdError) => {
      console.error(`MessageStore.sendDocument failed: ${e.message}`);
    });
  }

  // Shared sendMessage plumbing for media content types.
  private sendContent(content: TdObject, tag: string, replyToId: number = 0): void {
    const req: TdRequest = { '@type': 'sendMessage' };
    req['chat_id'] = this.chatId;
    req['input_message_content'] = content;
    if (replyToId > 0) {
      const replyTo: TdObject = { '@type': 'inputMessageReplyToMessage' };
      replyTo['message_id'] = replyToId;
      req['reply_to'] = replyTo;
    }
    if (this.threadRootId > 0) {
      req['message_thread_id'] = this.threadRootId;
    }
    this.client.send(req).then((m: TdObject) => {
      this.upsert(buildMessageEntry(m, this.users));
      this.requestPhotos();
      this.notify();
    }).catch((e: TdError) => {
      console.error(`MessageStore.${tag} failed: ${e.message}`);
    });
  }

  sendPhoto(path: string, caption: string, replyToId: number = 0): void {
    const inputFile: TdObject = { '@type': 'inputFileLocal' };
    inputFile['path'] = path;
    const content: TdObject = { '@type': 'inputMessagePhoto' };
    content['photo'] = inputFile;
    if (caption !== '') {
      const ft: TdObject = { '@type': 'formattedText' };
      ft['text'] = caption;
      content['caption'] = ft;
    }
    this.sendContent(content, 'sendPhoto', replyToId);
  }

  sendVideo(path: string, caption: string, replyToId: number = 0): void {
    const inputFile: TdObject = { '@type': 'inputFileLocal' };
    inputFile['path'] = path;
    const content: TdObject = { '@type': 'inputMessageVideo' };
    content['video'] = inputFile;
    if (caption !== '') {
      const ft: TdObject = { '@type': 'formattedText' };
      ft['text'] = caption;
      content['caption'] = ft;
    }
    this.sendContent(content, 'sendVideo', replyToId);
  }

  private mediaInputContent(item: MediaSendItem, caption: string): TdObject {
    const inputFile: TdObject = { '@type': 'inputFileLocal' };
    inputFile['path'] = item.path;
    const content: TdObject = {
      '@type': item.isVideo ? 'inputMessageVideo' : 'inputMessagePhoto'
    };
    content[item.isVideo ? 'video' : 'photo'] = inputFile;
    if (caption !== '') {
      const ft: TdObject = { '@type': 'formattedText' };
      ft['text'] = caption;
      content['caption'] = ft;
    }
    return content;
  }

  private rememberLocalMedia(entry: MessageEntry, item: MediaSendItem): MessageEntry {
    const hydrated = cloneMessage(entry);
    if (item.isVideo) {
      hydrated.videoPath = item.path;
      hydrated.videoProgress = 100;
      hydrated.videoFailed = false;
      hydrated.mediaDownloadActive = false;
      if (hydrated.videoFileId > 0) {
        this.completedFilePaths.set(hydrated.videoFileId, item.path);
      }
    } else {
      hydrated.photoPath = item.path;
      hydrated.photoProgress = 100;
      hydrated.photoFailed = false;
      hydrated.photoFullPath = item.path;
      if (hydrated.photoFileId > 0) {
        this.completedFilePaths.set(hydrated.photoFileId, item.path);
      }
      if (hydrated.photoFullFileId > 0) {
        this.completedFilePaths.set(hydrated.photoFullFileId, item.path);
      }
    }
    return hydrated;
  }

  // The picker may return up to nine mixed photos/videos. Two or more items
  // must use sendMessageAlbum; sending them one-by-one loses media_album_id and
  // the receiver can never render a real Telegram album.
  sendMedia(items: MediaSendItem[], caption: string, replyToId: number = 0): Promise<void> {
    if (items.length === 0) {
      return Promise.resolve();
    }
    const contents: TdObject[] = [];
    for (let i = 0; i < items.length; i++) {
      contents.push(this.mediaInputContent(items[i], i === 0 ? caption : ''));
    }
    const req: TdRequest = {
      '@type': items.length > 1 ? 'sendMessageAlbum' : 'sendMessage'
    };
    req['chat_id'] = this.chatId;
    if (items.length > 1) {
      req['input_message_contents'] = contents;
    } else {
      req['input_message_content'] = contents[0];
    }
    if (replyToId > 0) {
      const replyTo: TdObject = { '@type': 'inputMessageReplyToMessage' };
      replyTo['message_id'] = replyToId;
      req['reply_to'] = replyTo;
    }
    if (this.threadRootId > 0) {
      req['message_thread_id'] = this.threadRootId;
    }
    return this.client.send(req).then((result: TdObject): void => {
      const sent: TdObject[] = items.length > 1
        ? ((result['messages'] as TdObject[] | undefined) ?? [])
        : [result];
      for (let i = 0; i < sent.length; i++) {
        const source = items[Math.min(i, items.length - 1)];
        const entry = this.rememberLocalMedia(buildMessageEntry(sent[i], this.users), source);
        this.upsert(entry);
      }
      this.resolveReplies();
      this.requestPhotos();
      this.notify();
    }).catch((e: TdError): Promise<void> => {
      console.error(`MessageStore.sendMedia failed: ${e.message}`);
      return Promise.reject(e);
    });
  }

  // Send a sticker the user picked from an installed set (already on Telegram
  // servers — reference it by TDLib file id).
  sendSticker(fileId: number, width: number, height: number): void {
    const inputFile: TdObject = { '@type': 'inputFileId' };
    inputFile['id'] = fileId;
    const content: TdObject = { '@type': 'inputMessageSticker' };
    content['sticker'] = inputFile;
    content['width'] = width;
    content['height'] = height;
    this.sendContent(content, 'sendSticker');
  }

  // Send a saved GIF (server-side file, referenced by id).
  sendAnimation(fileId: number, width: number, height: number, durationSec: number): void {
    const inputFile: TdObject = { '@type': 'inputFileId' };
    inputFile['id'] = fileId;
    const content: TdObject = { '@type': 'inputMessageAnimation' };
    content['animation'] = inputFile;
    content['width'] = width;
    content['height'] = height;
    content['duration'] = durationSec;
    this.sendContent(content, 'sendAnimation');
  }

  sendVoiceNote(path: string, durationSec: number): void {
    const inputFile: TdObject = { '@type': 'inputFileLocal' };
    inputFile['path'] = path;
    const content: TdObject = { '@type': 'inputMessageVoiceNote' };
    content['voice_note'] = inputFile;
    content['duration'] = durationSec;
    this.sendContent(content, 'sendVoiceNote');
  }

  private sendSimple(type: string): void {
    const req: TdRequest = { '@type': type };
    req['chat_id'] = this.chatId;
    this.client.send(req).catch((e: TdError) => {
      console.error(`MessageStore.${type} failed: ${e.message}`);
    });
  }

  private loadHistory(fromId: number): void {
    const req = this.historyRequest(fromId, 0);
    this.client.send(req).then((res: TdObject) => this.onHistory(res, fromId === 0 ? 'latest' : 'history'))
      .catch((e: TdError) => {
      const code = (e as TdError).code;
      if (code !== 404) {
        console.error(`MessageStore.getChatHistory failed: ${e.message}`);
      }
      if (this.initialHistoryState === 'loading') {
        // A 404 is TDLib's valid "this chat has no messages" result.
        this.initialHistoryState = code === 404 ? 'ready' : 'error';
        this.initialHistoryError = code === 404 ? '' : this.historyErrorHint(e);
        if (code === 404) {
          this.hasMoreOlder = false;
          this.olderLoadState = 'end';
        }
        this.notify('initialState');
      }
    });
  }

  private onHistory(res: TdObject, kind: string = 'history'): void {
    const arr = (res['messages'] as TdObject[] | undefined) ?? [];
    this.initialHistoryState = 'ready';
    this.initialHistoryError = '';
    if (kind === 'latest') {
      this.hasMoreOlder = arr.length >= this.historyPageSize;
      this.olderLoadState = this.hasMoreOlder ? 'idle' : 'end';
      this.hasMoreNewer = false;
      this.newerLoadState = 'end';
    }
    // Keyboard fallback is probed from the live tail separately. Scanning an
    // arbitrary around/older page here can resurrect a stale keyboard that a
    // newer remove marker already superseded.
    this.ensureKeyboardHistoryProbe();
    for (const m of arr) {
      this.upsert(buildMessageEntry(m, this.users));
    }
    if (this.messages.length > 0) {
      this.oldestId = this.messages[0].id;
    }
    this.resolveReplies();
    this.resolveForwardTitles();
    this.requestPhotos();
    this.resolveSenderAvatars();
    this.resolveCommentAvatars();
    // NOTE: do NOT mark messages read here. Read state is a high-water mark in
    // TDLib, so viewing the newest loaded message would mark ALL older ones read.
    // Read-marking is driven by the actually-visible range (see markViewed).
    // Hold the very first render until getChat supplies the unread anchor, so the
    // page can position at the first unread message without a race. Later loads
    // (loadOlder) notify normally.
    if (this.chatResolved) {
      this.notify(kind);
    } else {
      this.historyPending = true;
      this.historyPendingKind = kind;
    }
  }

  private flushInitial(): void {
    this.chatResolved = true;
    if (this.historyPending) {
      this.historyPending = false;
      this.notify(this.historyPendingKind);
      this.historyPendingKind = 'history';
    }
  }

  private onNewMessage(u: TdObject): void {
    const m = u['message'] as TdObject | undefined;
    if (m === undefined || (m['chat_id'] as number | undefined) !== this.chatId) {
      return;
    }
    // Thread mode: only messages of this thread belong in the view.
    if (this.threadRootId > 0 && (m['message_thread_id'] as number | undefined) !== this.threadRootId) {
      return;
    }
    // A bot that shows/removes its keyboard does it via a message's markup.
    this.scanKeyboardMarkup([m]);
    this.upsert(buildMessageEntry(m, this.users));
    this.resolveReplies();
    this.resolveForwardTitles();
    this.requestPhotos();
    this.resolveSenderAvatars();
    this.resolveCommentAvatars();
    // New incoming messages are marked read only when they become visible
    // (driven by markViewed from the page), not on arrival.
    this.notify();
  }

  private onSendSucceeded(u: TdObject): void {
    const oldId = u['old_message_id'] as number | undefined;
    const m = u['message'] as TdObject | undefined;
    if (oldId === undefined || m === undefined ||
      (m['chat_id'] as number | undefined) !== this.chatId) {
      return;
    }
    if (this.threadRootId > 0 &&
      (m['message_thread_id'] as number | undefined) !== this.threadRootId) {
      return;
    }
    this.messages = this.messages.filter((e: MessageEntry) => e.id !== oldId);
    this.upsert(buildMessageEntry(m, this.users));
    this.resolveReplies();
    this.requestPhotos();
    this.notify();
  }

  private onSendFailed(u: TdObject): void {
    const m = u['message'] as TdObject | undefined;
    if (m === undefined || (m['chat_id'] as number | undefined) !== this.chatId) {
      return;
    }
    if (this.threadRootId > 0 &&
      (m['message_thread_id'] as number | undefined) !== this.threadRootId) {
      return;
    }
    const id = m['id'] as number;
    this.patch(id, (c: MessageEntry) => { c.sendState = 'failed'; });
  }

  private onContent(u: TdObject): void {
    if ((u['chat_id'] as number | undefined) !== this.chatId) {
      return;
    }
    const id = u['message_id'] as number | undefined;
    if (id === undefined) {
      return;
    }
    const idx = this.indexOf(id);
    if (idx < 0) {
      return;
    }
    // rebuild content by wrapping the new content into a message-like object
    const fake: TdObject = { '@type': 'message' };
    fake['content'] = u['new_content'];
    const rebuilt = buildMessageEntry(fake, this.users);
    this.patch(id, (c: MessageEntry) => {
      const sameVideoFile: boolean = c.videoFileId !== 0 && c.videoFileId === rebuilt.videoFileId;
      const samePhotoFile: boolean = c.photoFileId !== 0 && c.photoFileId === rebuilt.photoFileId;
      const sameStickerFile: boolean = c.stickerFileId !== 0 &&
        c.stickerFileId === rebuilt.stickerFileId;
      const sameContactUser: boolean = c.contactUserId !== 0 &&
        c.contactUserId === rebuilt.contactUserId;
      const previousContactAvatarPath: string = c.contactAvatarPath;
      const previousPhotoPath: string = c.photoPath;
      const previousPhotoProgress: number = c.photoProgress;
      const previousPhotoFailed: boolean = c.photoFailed;
      const previousVideoPath: string = c.videoPath;
      const previousVideoProgress: number = c.videoProgress;
      const previousVideoFailed: boolean = c.videoFailed;
      const previousDownloadActive: boolean = c.mediaDownloadActive;
      c.contentType = rebuilt.contentType;
      c.text = rebuilt.text;
      c.textEntities = rebuilt.textEntities;
      c.inlineCustomEmojiIds = rebuilt.inlineCustomEmojiIds;
      c.inlineCustomEmojiPaths = rebuilt.inlineCustomEmojiPaths;
      c.photoFileId = rebuilt.photoFileId;
      c.photoWidth = rebuilt.photoWidth;
      c.photoHeight = rebuilt.photoHeight;
      c.placeholderLabel = rebuilt.placeholderLabel;
      c.photoPath = samePhotoFile ? previousPhotoPath : rebuilt.photoPath;
      c.photoProgress = samePhotoFile ? previousPhotoProgress : rebuilt.photoProgress;
      c.photoFailed = samePhotoFile ? previousPhotoFailed : rebuilt.photoFailed;
      c.linkSiteName = rebuilt.linkSiteName;
      c.linkTitle = rebuilt.linkTitle;
      c.linkDescription = rebuilt.linkDescription;
      c.linkDescriptionEntities = rebuilt.linkDescriptionEntities;
      c.linkPhotoFileId = rebuilt.linkPhotoFileId;
      c.linkPhotoPath = '';
      c.linkUrl = rebuilt.linkUrl;
      c.photoFullFileId = rebuilt.photoFullFileId;
      c.photoFullPath = '';
      c.photoFullProgress = 0;
      c.photoFullFailed = false;
      c.videoFileId = rebuilt.videoFileId;
      c.videoFileSize = rebuilt.videoFileSize;
      c.videoMimeType = rebuilt.videoMimeType;
      c.videoFileName = rebuilt.videoFileName;
      c.videoDuration = rebuilt.videoDuration;
      c.isAnimation = rebuilt.isAnimation;
      // Listening to a voice note arrives as updateMessageContent. Preserve
      // the already-downloaded file when only is_listened/waveform changed;
      // otherwise the bubble jumps back to "loading" while audio is playing.
      c.videoPath = sameVideoFile ? previousVideoPath : rebuilt.videoPath;
      c.videoProgress = sameVideoFile ? previousVideoProgress : rebuilt.videoProgress;
      c.videoFailed = sameVideoFile ? previousVideoFailed : false;
      c.mediaDownloadActive = sameVideoFile
        ? previousDownloadActive : rebuilt.mediaDownloadActive;
      c.voiceWaveform = rebuilt.voiceWaveform;
      c.voiceListened = rebuilt.voiceListened;
      c.audioTitle = rebuilt.audioTitle;
      c.audioPerformer = rebuilt.audioPerformer;
      c.stickerFileId = rebuilt.stickerFileId;
      c.stickerFormat = rebuilt.stickerFormat;
      c.isEmojiSticker = rebuilt.isEmojiSticker;
      c.stickerPath = sameStickerFile ? c.stickerPath : rebuilt.stickerPath;
      c.stickerProgress = sameStickerFile ? c.stickerProgress : rebuilt.stickerProgress;
      c.stickerFailed = sameStickerFile ? c.stickerFailed : rebuilt.stickerFailed;
      c.stickerDownloadActive = sameStickerFile
        ? c.stickerDownloadActive : rebuilt.stickerDownloadActive;
      c.customEmojiId = rebuilt.customEmojiId;
      c.contactPhone = rebuilt.contactPhone;
      c.contactFirstName = rebuilt.contactFirstName;
      c.contactLastName = rebuilt.contactLastName;
      c.contactVcard = rebuilt.contactVcard;
      c.contactUserId = rebuilt.contactUserId;
      c.contactAvatarPath = sameContactUser ? previousContactAvatarPath : rebuilt.contactAvatarPath;
      c.locationLatitude = rebuilt.locationLatitude;
      c.locationLongitude = rebuilt.locationLongitude;
      c.locationAccuracy = rebuilt.locationAccuracy;
      c.locationValid = rebuilt.locationValid;
      c.locationLivePeriod = rebuilt.locationLivePeriod;
      c.locationExpiresIn = rebuilt.locationExpiresIn;
      c.locationHeading = rebuilt.locationHeading;
      c.locationProximityRadius = rebuilt.locationProximityRadius;
      c.venueTitle = rebuilt.venueTitle;
      c.venueAddress = rebuilt.venueAddress;
      c.venueProvider = rebuilt.venueProvider;
      c.venueId = rebuilt.venueId;
      c.venueType = rebuilt.venueType;
      c.pollId = rebuilt.pollId;
      c.pollQuestion = rebuilt.pollQuestion;
      c.pollOptions = rebuilt.pollOptions;
      c.pollTotalVoterCount = rebuilt.pollTotalVoterCount;
      c.pollIsAnonymous = rebuilt.pollIsAnonymous;
      c.pollIsQuiz = rebuilt.pollIsQuiz;
      c.pollAllowMultiple = rebuilt.pollAllowMultiple;
      c.pollCorrectOptionId = rebuilt.pollCorrectOptionId;
      c.pollExplanation = rebuilt.pollExplanation;
      c.pollOpenPeriod = rebuilt.pollOpenPeriod;
      c.pollCloseDate = rebuilt.pollCloseDate;
      c.pollIsClosed = rebuilt.pollIsClosed;
      c.pollVotePending = false;
      c.pollVoteError = '';
      c.diceEmoji = rebuilt.diceEmoji;
      c.diceValue = rebuilt.diceValue;
      c.diceSuccessFrame = rebuilt.diceSuccessFrame;
      c.diceHasFinalState = rebuilt.diceHasFinalState;
      c.gameId = rebuilt.gameId;
      c.gameShortName = rebuilt.gameShortName;
      c.gameTitle = rebuilt.gameTitle;
      c.gameDescription = rebuilt.gameDescription;
      c.gameText = rebuilt.gameText;
      c.paidMediaLocked = rebuilt.paidMediaLocked;
      c.paidMediaStarCount = rebuilt.paidMediaStarCount;
      c.paidMediaCount = rebuilt.paidMediaCount;
      c.paidMediaKind = rebuilt.paidMediaKind;
      c.giftKind = rebuilt.giftKind;
      c.giftTitle = rebuilt.giftTitle;
      c.giftValue = rebuilt.giftValue;
      c.giftStatus = rebuilt.giftStatus;
      c.giftCode = rebuilt.giftCode;
      c.giftRefunded = rebuilt.giftRefunded;
      c.giveawayState = rebuilt.giveawayState;
      c.giveawayWinnerCount = rebuilt.giveawayWinnerCount;
      c.giveawayPrize = rebuilt.giveawayPrize;
      c.giveawayDescription = rebuilt.giveawayDescription;
      c.giveawaySelectionDate = rebuilt.giveawaySelectionDate;
      c.giveawayUnclaimedCount = rebuilt.giveawayUnclaimedCount;
      c.giveawayMessageId = rebuilt.giveawayMessageId;
      c.giveawayBoostedChatId = rebuilt.giveawayBoostedChatId;
      c.giveawayRefunded = rebuilt.giveawayRefunded;
      c.giveawayOnlyNewMembers = rebuilt.giveawayOnlyNewMembers;
    });
    this.requestPhotos();
    if (this.pinnedIds.includes(id)) {
      this.resolvePinned();
    }
  }

  // Poll result changes are delivered globally by poll id rather than by
  // chat/message id. Patch every loaded bubble carrying that poll and clear
  // any optimistic "submitting" state once the authoritative result arrives.
  private onPoll(u: TdObject): void {
    const poll = u['poll'] as TdObject | undefined;
    if (poll === undefined) {
      return;
    }
    const pollId = `${poll['id'] ?? ''}`;
    if (pollId === '') {
      return;
    }
    const content: TdObject = { '@type': 'messagePoll' };
    content['poll'] = poll;
    const fake: TdObject = { '@type': 'message' };
    fake['content'] = content;
    const rebuilt = buildMessageEntry(fake, this.users);
    let changed = false;
    this.messages = this.messages.map((message: MessageEntry): MessageEntry => {
      if (message.contentType !== 'poll' || message.pollId !== pollId) {
        return message;
      }
      changed = true;
      const next = cloneMessage(message);
      next.pollQuestion = rebuilt.pollQuestion;
      next.pollOptions = rebuilt.pollOptions;
      next.pollTotalVoterCount = rebuilt.pollTotalVoterCount;
      next.pollIsAnonymous = rebuilt.pollIsAnonymous;
      next.pollIsQuiz = rebuilt.pollIsQuiz;
      next.pollAllowMultiple = rebuilt.pollAllowMultiple;
      next.pollCorrectOptionId = rebuilt.pollCorrectOptionId;
      next.pollExplanation = rebuilt.pollExplanation;
      next.pollOpenPeriod = rebuilt.pollOpenPeriod;
      next.pollCloseDate = rebuilt.pollCloseDate;
      next.pollIsClosed = rebuilt.pollIsClosed;
      next.pollVotePending = false;
      next.pollVoteError = '';
      return next;
    });
    if (changed) {
      this.notify();
    }
  }

  private onDelete(u: TdObject): void {
    if ((u['chat_id'] as number | undefined) !== this.chatId) {
      return;
    }
    const removeIds = (u['message_ids'] as number[] | undefined) ?? [];
    const set = new Set<number>(removeIds);
    this.messages = this.messages.filter((e: MessageEntry) => !set.has(e.id));
    this.notify();
    if (this.pinnedIds.some((id: number): boolean => set.has(id))) {
      this.removePinnedIds(set);
      this.resolvePinned();
    }
  }

  // updateMessageEdited carries both the edit timestamp and the fresh inline
  // keyboard. Keep both in the render model so text edits and bot keyboard
  // changes invalidate the same bubble row.
  private onEdited(u: TdObject): void {
    if ((u['chat_id'] as number | undefined) !== this.chatId) {
      return;
    }
    const id = u['message_id'] as number | undefined;
    if (id === undefined) {
      return;
    }
    const buttons = parseInlineKeyboard(u['reply_markup'] as TdObject | undefined);
    const editDate = (u['edit_date'] as number | undefined) ?? 0;
    this.patch(id, (c: MessageEntry) => {
      c.inlineButtons = buttons;
      c.editDate = editDate;
    });
  }

  private onInteractionInfo(u: TdObject): void {
    if ((u['chat_id'] as number | undefined) !== this.chatId) {
      return;
    }
    const id = u['message_id'] as number | undefined;
    if (id === undefined) {
      return;
    }
    const ii = u['interaction_info'] as TdObject | undefined;
    const cmt: CommentInfo = commentInfoFromInteraction(ii);
    const rx: ReactionInfo[] = reactionsFromInteraction(ii);
    this.patch(id, (c: MessageEntry) => {
      c.commentCount = cmt.count;
      c.commentReplierIds = cmt.replierIds;
      c.commentReplierAvatarPaths = [];
      c.reactions = rx;
    });
    this.resolveCommentAvatars();
  }

  private onReadOutbox(u: TdObject): void {
    if ((u['chat_id'] as number | undefined) !== this.chatId) {
      return;
    }
    this.lastReadOutboxId = (u['last_read_outbox_message_id'] as number | undefined) ?? 0;
    this.notify(); // notify() applies the read marking centrally
  }

  // Outgoing messages at or below the outbox-read boundary become 'read'.
  // Applied on every notify so history pages (already read long ago) get
  // marked too, not only live updateChatReadOutbox events.
  private applyReadOutbox(): void {
    if (this.lastReadOutboxId <= 0) {
      return;
    }
    let changed = false;
    const mapped = this.messages.map((e: MessageEntry) => {
      if (e.isOutgoing && e.sendState === 'sent' && e.id <= this.lastReadOutboxId) {
        const c = cloneMessage(e);
        c.sendState = 'read';
        changed = true;
        return c;
      }
      return e;
    });
    if (changed) {
      this.messages = mapped;
    }
  }

  // --- photos ---
  private setThumbnailFailed(fileId: number, failed: boolean): void {
    let changed = false;
    this.messages = this.messages.map((m: MessageEntry): MessageEntry => {
      if (m.photoFileId !== fileId || m.photoFailed === failed || m.photoPath !== '') {
        return m;
      }
      const c = cloneMessage(m);
      c.photoFailed = failed;
      if (failed) {
        c.photoProgress = 0;
      }
      changed = true;
      return c;
    });
    if (changed) {
      this.notify();
    }
  }

  // Download an inline thumbnail with up to 2 automatic retries (backoff),
  // so a transient failure doesn't leave the bubble stuck at 0% forever.
  private downloadThumb(fileId: number): void {
    this.setThumbnailFailed(fileId, false);
    const attempt = (this.thumbAttempts.get(fileId) ?? 0) + 1;
    this.thumbAttempts.set(fileId, attempt);
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = fileId;
    req['priority'] = THUMBNAIL_PRIORITY;
    this.client.send(req).then((f: TdObject) => this.applyFile(f)).catch((err: TdError) => {
      console.error(`MessageStore photo ${fileId} (attempt ${attempt}): ${err.message}`);
      if (attempt <= 2) {
        setTimeout(() => this.downloadThumb(fileId), 1000 * attempt);
      } else {
        this.setThumbnailFailed(fileId, true);
      }
    });
  }

  // Resolve every custom-emoji id once. A message made of one custom emoji
  // morphs into the existing animated sticker pipeline; custom emoji embedded
  // in mixed text use a static WEBP/thumbnail through ArkUI ImageSpan.
  private customEmojiRequested: Set<string> = new Set();
  private customEmojiFailed: Set<string> = new Set();

  private resolveCustomEmojis(): void {
    this.hydrateInlineCustomEmojiPaths();
    for (const e of this.messages) {
      if (e.contentType === 'customEmoji' && e.customEmojiId !== '') {
        this.resolveCustomEmojiId(e.customEmojiId, e.id);
      }
      for (const id of e.inlineCustomEmojiIds) {
        this.resolveCustomEmojiId(id, e.id);
      }
    }
  }

  private hydrateInlineCustomEmojiPaths(): void {
    let changed = false;
    this.messages = this.messages.map((m: MessageEntry): MessageEntry => {
      if (m.inlineCustomEmojiIds.length === 0) {
        return m;
      }
      const paths: string[] = [];
      let differs = m.inlineCustomEmojiPaths.length !== m.inlineCustomEmojiIds.length;
      for (let i = 0; i < m.inlineCustomEmojiIds.length; i++) {
        const path = this.inlineCustomEmojiPathById.get(m.inlineCustomEmojiIds[i]) ?? '';
        paths.push(path);
        if (!differs && path !== m.inlineCustomEmojiPaths[i]) {
          differs = true;
        }
      }
      if (!differs) {
        return m;
      }
      const c = cloneMessage(m);
      c.inlineCustomEmojiPaths = paths;
      changed = true;
      return c;
    });
    if (changed) {
      this.notify();
    }
  }

  private applyInlineCustomEmojiPath(customEmojiId: string, path: string): void {
    if (customEmojiId === '' || path === '' ||
      this.inlineCustomEmojiPathById.get(customEmojiId) === path) {
      return;
    }
    this.inlineCustomEmojiPathById.set(customEmojiId, path);
    this.hydrateInlineCustomEmojiPaths();
  }

  private markCustomEmojiResolveFailed(ceId: string): void {
    this.customEmojiRequested.delete(ceId);
    this.customEmojiFailed.add(ceId);
    let changed = false;
    this.messages = this.messages.map((m: MessageEntry): MessageEntry => {
      if (m.contentType !== 'customEmoji' || m.customEmojiId !== ceId || m.photoFailed) {
        return m;
      }
      const c = cloneMessage(m);
      c.photoFailed = true;
      changed = true;
      return c;
    });
    if (changed) {
      this.notify();
    }
  }

  private completedPathOf(file: TdObject | undefined): string {
    if (file === undefined) {
      return '';
    }
    const local = file['local'] as TdObject | undefined;
    if (local === undefined ||
      !((local['is_downloading_completed'] as boolean | undefined) ?? false)) {
      return '';
    }
    return (local['path'] as string | undefined) ?? '';
  }

  private resolveCustomEmojiId(ceId: string, messageId: number, forceRetry: boolean = false): void {
    if (ceId === '' || this.customEmojiRequested.has(ceId) ||
      (!forceRetry && this.customEmojiFailed.has(ceId))) {
      return;
    }
    if (forceRetry) {
      this.customEmojiFailed.delete(ceId);
    }
    this.customEmojiRequested.add(ceId);
    console.info(`MessageStore: resolving custom emoji ${ceId} for msg ${messageId}`);
    const req: TdRequest = { '@type': 'getCustomEmojiStickers' };
    req['custom_emoji_ids'] = [ceId];
    this.client.send(req).then((res: TdObject) => {
      const stickers = (res['stickers'] as TdObject[] | undefined) ?? [];
      if (stickers.length === 0) {
        this.markCustomEmojiResolveFailed(ceId);
        return; // Unicode alternative remains visible with a retry affordance.
      }
      const st = stickers[0];
      const fmt = st['format'] as TdObject | undefined;
      const fmtName = fmt !== undefined ? ((fmt['@type'] as string | undefined) ?? '') : '';
      const format = fmtName === 'stickerFormatWebp' ? 'webp'
        : (fmtName === 'stickerFormatTgs' ? 'tgs'
          : (fmtName === 'stickerFormatWebm' ? 'webm' : ''));
      const file = st['sticker'] as TdObject | undefined;
      const srcId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
      const thumb = st['thumbnail'] as TdObject | undefined;
      const thumbFile = thumb !== undefined ? (thumb['file'] as TdObject | undefined) : undefined;
      const thumbId = thumbFile !== undefined ? ((thumbFile['id'] as number | undefined) ?? 0) : 0;
      if (format === '' || (srcId === 0 && thumbId === 0)) {
        this.markCustomEmojiResolveFailed(ceId);
        return;
      }
      const sourceLocalPath = this.completedPathOf(file);
      const thumbLocalPath = this.completedPathOf(thumbFile);
      if (sourceLocalPath !== '' && srcId !== 0) {
        this.completedFilePaths.set(srcId, sourceLocalPath);
      }
      if (thumbLocalPath !== '' && thumbId !== 0) {
        this.completedFilePaths.set(thumbId, thumbLocalPath);
      }

      // Mixed text needs a raster source. Animated TGS/WEBM uses its thumbnail;
      // static WEBP can be inserted directly when no separate thumbnail exists.
      const inlineFileId = thumbId !== 0 ? thumbId : (format === 'webp' ? srcId : 0);
      if (inlineFileId !== 0) {
        this.inlineCustomEmojiFileToId.set(inlineFileId, ceId);
        const cachedPath = this.completedFilePaths.get(inlineFileId) ?? '';
        if (cachedPath !== '') {
          this.applyInlineCustomEmojiPath(ceId, cachedPath);
        } else {
          const download: TdRequest = { '@type': 'downloadFile' };
          download['file_id'] = inlineFileId;
          download['priority'] = THUMBNAIL_PRIORITY;
          this.client.send(download).then((f: TdObject) => this.applyFile(f)).catch((err: TdError) => {
            console.error(`MessageStore inline custom emoji ${inlineFileId}: ${err.message}`);
          });
        }
      }

      let changed = false;
      this.messages = this.messages.map((m: MessageEntry): MessageEntry => {
        if (m.contentType !== 'customEmoji' || m.customEmojiId !== ceId) {
          return m;
        }
        changed = true;
        const c = cloneMessage(m);
        c.contentType = 'sticker';
        c.stickerFormat = format;
        c.isEmojiSticker = true;
        c.photoWidth = 100;
        c.photoHeight = 100;
        c.photoFailed = false;
        c.stickerFailed = false;
        if (format === 'webp') {
          c.photoFileId = srcId;
          c.photoPath = sourceLocalPath !== '' ? sourceLocalPath
            : (this.completedFilePaths.get(srcId) ?? '');
          c.photoProgress = c.photoPath !== '' ? 100 : 0;
          c.stickerFileId = 0;
          c.stickerPath = '';
          c.stickerProgress = 0;
          c.stickerDownloadActive = false;
        } else {
          c.photoFileId = thumbId;
          c.photoPath = thumbLocalPath !== '' ? thumbLocalPath
            : (this.completedFilePaths.get(thumbId) ?? '');
          c.photoProgress = c.photoPath !== '' ? 100 : 0;
          c.stickerFileId = srcId;
          c.stickerPath = sourceLocalPath !== '' ? sourceLocalPath
            : (this.completedFilePaths.get(srcId) ?? '');
          c.stickerProgress = c.stickerPath !== '' ? 100 : 0;
          c.stickerDownloadActive = c.stickerPath === '' && srcId !== 0;
        }
        return c;
      });
      this.customEmojiFailed.delete(ceId);
      if (changed) {
        this.requestPhotos(); // kick thumbnail + animated source downloads
        this.notify();
      }
    }).catch((err: TdError) => {
      console.error(`MessageStore.getCustomEmojiStickers(${ceId}) failed: ${err.message}`);
      this.markCustomEmojiResolveFailed(ceId);
    });
  }

  // Send one custom emoji as its own message (formattedText + custom-emoji
  // entity — the receiver renders the animated emoji).
  sendCustomEmoji(emoji: string, customEmojiId: string): void {
    const ent: TdObject = { '@type': 'textEntity' };
    ent['offset'] = 0;
    ent['length'] = emoji.length; // UTF-16 units — matches TDLib's convention
    const entType: TdObject = { '@type': 'textEntityTypeCustomEmoji' };
    entType['custom_emoji_id'] = customEmojiId;
    ent['type'] = entType;
    const ft: TdObject = { '@type': 'formattedText' };
    ft['text'] = emoji;
    ft['entities'] = [ent];
    const content: TdObject = { '@type': 'inputMessageText' };
    content['text'] = ft;
    this.sendContent(content, 'sendCustomEmoji');
  }

  private requestPhotos(): void {
    this.resolveCustomEmojis();
    this.resolveContactAvatars();
    for (const e of this.messages) {
      if ((e.contentType === 'photo' || e.contentType === 'video' ||
        e.contentType === 'sticker' || e.contentType === 'audio' ||
        e.contentType === 'game' || e.contentType === 'paidMedia' ||
        e.contentType === 'gift' || e.contentType === 'giveaway')
        && e.photoFileId !== 0 && e.photoPath === '') {
        if (!this.fileToMsg.has(e.photoFileId)) {
          this.fileToMsg.set(e.photoFileId, e.id);
          this.downloadThumb(e.photoFileId);
        } else {
          // Already requested but still no local file: a download that burned
          // its retries (transient network failure at load time) would sit at
          // 0% forever — re-kick it, rate-limited. downloadFile is idempotent.
          const now = Date.now();
          const lastKick = this.thumbLastKick.get(e.photoFileId) ?? 0;
          if (now - lastKick > THUMB_REKICK_MS) {
            this.thumbLastKick.set(e.photoFileId, now);
            this.downloadThumb(e.photoFileId);
          }
        }
      }
      // Voice notes are small — download eagerly so tapping plays instantly.
      if (e.contentType === 'voice' && e.videoFileId !== 0 && e.videoPath === '') {
        this.requestVideoDownload(e.id); // deduped via videoFileToMsg
      }
      // Telegram GIFs are compact muted MP4 loops. Download them eagerly only
      // while inline autoplay is enabled; normal videos remain tap-to-play.
      if (e.isAnimation && e.videoFileId !== 0 && e.videoPath === '' &&
        powerFeatureEnabled(KEY_POWER_AUTOPLAY_GIF) && !reduceAnimations()) {
        this.requestVideoDownload(e.id);
      }
      // Animated (TGS) sticker source file — small (<64KB), download eagerly so
      // the Lottie animation starts as soon as the message is visible.
      if (e.contentType === 'sticker' && e.stickerFileId !== 0 && e.stickerPath === '') {
        this.requestStickerSource(e.id);
      }
      if (e.linkPhotoFileId !== 0 && e.linkPhotoPath === '') {
        if (!this.linkFileToMsg.has(e.linkPhotoFileId)) {
          this.linkFileToMsg.set(e.linkPhotoFileId, e.id);
          const req: TdRequest = { '@type': 'downloadFile' };
          req['file_id'] = e.linkPhotoFileId;
          req['priority'] = THUMBNAIL_PRIORITY;
          this.client.send(req).then((f: TdObject) => this.applyFile(f)).catch((err: TdError) => {
            console.error(`MessageStore link photo ${e.linkPhotoFileId}: ${err.message}`);
          });
        }
      }
    }
  }

  // On-demand full-resolution photo download (triggered by opening the fullscreen
  // viewer). The inline bubble only ever downloads photoFileId (a small size).
  requestFullPhoto(messageId: number, forceRetry: boolean = false): void {
    const idx = this.indexOf(messageId);
    if (idx < 0) {
      return;
    }
    const e = this.messages[idx];
    if (e.photoFullFileId === 0 || e.photoFullPath !== '') {
      return;
    }
    if (forceRetry) {
      this.fullPhotoFileToMsg.delete(e.photoFullFileId);
    } else if (this.fullPhotoFileToMsg.has(e.photoFullFileId)) {
      return;
    }
    this.patch(messageId, (c: MessageEntry): void => {
      c.photoFullFailed = false;
      c.photoFullProgress = 0;
    });
    this.fullPhotoFileToMsg.set(e.photoFullFileId, messageId);
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = e.photoFullFileId;
    req['priority'] = MEDIA_USER_PRIORITY;
    this.client.send(req).then((f: TdObject) => this.applyFile(f)).catch((err: TdError) => {
      this.fullPhotoFileToMsg.delete(e.photoFullFileId);
      this.patch(messageId, (c: MessageEntry): void => {
        c.photoFullFailed = true;
        c.photoFullProgress = 0;
      });
      console.error(`MessageStore full photo ${e.photoFullFileId}: ${err.message}`);
    });
  }

  retryPhoto(messageId: number): void {
    const idx = this.indexOf(messageId);
    if (idx < 0) {
      return;
    }
    const e: MessageEntry = this.messages[idx];
    if (e.photoPath === '' && e.photoFileId !== 0) {
      this.fileToMsg.delete(e.photoFileId);
      this.thumbLastKick.delete(e.photoFileId);
      this.thumbAttempts.delete(e.photoFileId);
      this.patch(messageId, (c: MessageEntry): void => {
        c.photoFailed = false;
        c.photoProgress = 0;
      });
      this.fileToMsg.set(e.photoFileId, messageId);
      this.downloadThumb(e.photoFileId);
    }
    if (e.photoFullPath === '' && e.photoFullFileId !== 0) {
      this.requestFullPhoto(messageId, true);
    }
  }

  private patchStickerEntries(fileId: number, fn: (c: MessageEntry) => void): void {
    let changed = false;
    this.messages = this.messages.map((m: MessageEntry): MessageEntry => {
      if (m.stickerFileId !== fileId) {
        return m;
      }
      const c = cloneMessage(m);
      fn(c);
      changed = true;
      return c;
    });
    if (changed) {
      this.notify();
    }
  }

  private requestStickerSource(messageId: number, forceRetry: boolean = false): void {
    const idx = this.indexOf(messageId);
    if (idx < 0) {
      return;
    }
    const entry = this.messages[idx];
    const fileId = entry.stickerFileId;
    if (fileId === 0 || entry.stickerPath !== '') {
      return;
    }
    const cachedPath = this.completedFilePaths.get(fileId) ?? '';
    if (cachedPath !== '') {
      this.patchStickerEntries(fileId, (c: MessageEntry): void => {
        c.stickerPath = cachedPath;
        c.stickerProgress = 100;
        c.stickerFailed = false;
        c.stickerDownloadActive = false;
      });
      return;
    }
    if (forceRetry) {
      this.stickerFileToMsg.delete(fileId);
    } else if (entry.stickerFailed || this.stickerFileToMsg.has(fileId)) {
      return;
    }
    this.stickerFileToMsg.set(fileId, messageId);
    this.patchStickerEntries(fileId, (c: MessageEntry): void => {
      c.stickerFailed = false;
      c.stickerDownloadActive = true;
      if (forceRetry) {
        c.stickerProgress = 0;
      }
    });
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = fileId;
    req['priority'] = THUMBNAIL_PRIORITY;
    this.client.send(req).then((f: TdObject) => this.applyFile(f)).catch((err: TdError) => {
      this.stickerFileToMsg.delete(fileId);
      this.patchStickerEntries(fileId, (c: MessageEntry): void => {
        c.stickerFailed = true;
        c.stickerProgress = 0;
        c.stickerDownloadActive = false;
      });
      console.error(`MessageStore sticker ${fileId}: ${err.message}`);
    });
  }

  retrySticker(messageId: number): void {
    const idx = this.indexOf(messageId);
    if (idx < 0) {
      return;
    }
    const entry = this.messages[idx];
    if (entry.contentType === 'customEmoji' && entry.customEmojiId !== '') {
      this.patch(messageId, (c: MessageEntry): void => {
        c.photoFailed = false;
        c.photoProgress = 0;
      });
      this.resolveCustomEmojiId(entry.customEmojiId, messageId, true);
      return;
    }
    if (entry.contentType !== 'sticker') {
      return;
    }
    if (entry.photoPath === '' && entry.photoFileId !== 0) {
      this.retryPhoto(messageId);
    }
    if (entry.stickerPath === '' && entry.stickerFileId !== 0) {
      this.requestStickerSource(messageId, true);
    }
  }

  // Full video/file download used by inline autoplay and explicit save/open.
  // Fullscreen playback can stream independently, while this path provides a
  // stable local file and progress state for the bubble/download manager.
  // register=true (user-initiated file/video downloads) goes through TDLib's
  // download manager (addFileToDownloads) so the search page's 下载 tab can
  // list it with live progress; auto-downloads (voice prefetch) stay silent.
  requestVideoDownload(messageId: number, register: boolean = false, forceRetry: boolean = false): void {
    const idx = this.indexOf(messageId);
    if (idx < 0) {
      return;
    }
    const e = this.messages[idx];
    const cachedPath = e.videoFileId !== 0 ? (this.completedFilePaths.get(e.videoFileId) ?? '') : '';
    if (e.videoPath === '' && cachedPath !== '') {
      this.patchVideoEntries(e.videoFileId, (c: MessageEntry): void => {
        c.videoPath = cachedPath;
        c.videoProgress = 100;
        c.videoFailed = false;
        c.mediaDownloadActive = false;
      });
      return;
    }
    if (forceRetry && e.videoFileId !== 0) {
      this.videoFileToMsg.delete(e.videoFileId);
    }
    if (e.videoFileId === 0 || e.videoPath !== '' || this.videoFileToMsg.has(e.videoFileId)) {
      return;
    }
    this.videoFileToMsg.set(e.videoFileId, messageId);
    this.patchVideoEntries(e.videoFileId, (c: MessageEntry): void => {
      c.videoFailed = false;
      c.mediaDownloadActive = true;
      if (forceRetry) {
        c.videoProgress = 0;
      }
    });
    const req: TdRequest = { '@type': register ? 'addFileToDownloads' : 'downloadFile' };
    req['file_id'] = e.videoFileId;
    req['priority'] = register ? MEDIA_USER_PRIORITY : MEDIA_PREFETCH_PRIORITY;
    if (register) {
      req['chat_id'] = this.chatId;
      req['message_id'] = messageId;
    }
    this.client.send(req).then((f: TdObject) => this.applyFile(f)).catch((err: TdError) => {
      this.videoFileToMsg.delete(e.videoFileId);
      this.patchVideoEntries(e.videoFileId, (c: MessageEntry): void => {
        c.videoFailed = true;
        c.videoProgress = 0;
        c.mediaDownloadActive = false;
      });
      console.error(`MessageStore video ${e.videoFileId}: ${err.message}`);
    });
  }

  private onFile(u: TdObject): void {
    const f = u['file'] as TdObject | undefined;
    if (f !== undefined) {
      this.applyFile(f);
    }
  }

  private downloadPercent(file: TdObject, local: TdObject): number {
    const size = ((file['size'] as number | undefined) ?? 0) || ((file['expected_size'] as number | undefined) ?? 0);
    const downloaded = (local['downloaded_size'] as number | undefined) ?? 0;
    return size > 0 ? Math.min(100, Math.floor((downloaded / size) * 100)) : 0;
  }

  private applyFile(file: TdObject): void {
    const id = file['id'] as number | undefined;
    if (id === undefined) {
      return;
    }
    const local = file['local'] as TdObject | undefined;
    if (local === undefined) {
      return;
    }
    const done = (local['is_downloading_completed'] as boolean | undefined) ?? false;
    const path = (local['path'] as string | undefined) ?? '';
    if (done && path !== '') {
      this.completedFilePaths.set(id, path);
      const customEmojiId = this.inlineCustomEmojiFileToId.get(id);
      if (customEmojiId !== undefined) {
        this.applyInlineCustomEmojiPath(customEmojiId, path);
      }
      const contactUserId = this.avatarFileToContact.get(id);
      if (contactUserId !== undefined) {
        this.contactAvatarPaths.set(contactUserId, path);
        this.applyContactAvatarPath(contactUserId, path);
      }
    }

    // A sticker source id can belong to many messages. Keep source progress,
    // completion and paused state in sync for every matching bubble.
    if (this.messages.some((m: MessageEntry): boolean => m.stickerFileId === id)) {
      const percent = done && path !== '' ? 100 : this.downloadPercent(file, local);
      const active = !done &&
        ((local['is_downloading_active'] as boolean | undefined) ?? false);
      this.patchStickerEntries(id, (c: MessageEntry): void => {
        if (done && path !== '') {
          c.stickerPath = path;
          c.stickerFailed = false;
        }
        c.stickerProgress = percent;
        c.stickerDownloadActive = active;
      });
      if (done && path !== '') {
        this.stickerFileToMsg.delete(id);
      }
      return;
    }

    // Full-resolution photo / full video: progress while downloading, path on completion.
    const fullMsgId = this.fullPhotoFileToMsg.get(id);
    if (fullMsgId !== undefined) {
      const percent = this.downloadPercent(file, local);
      this.patch(fullMsgId, (c: MessageEntry) => {
        if (done && path !== '') {
          c.photoFullPath = path;
          c.photoFullFailed = false;
          // Backfill: if the inline thumbnail download failed/stalled, the
          // full-resolution image serves as the bubble thumbnail too.
          if (c.photoPath === '') {
            c.photoPath = path;
          }
        }
        c.photoFullProgress = percent;
      });
      return;
    }
    const videoTracked = this.videoFileToMsg.has(id);
    const hasVideoEntry = this.messages.some((m: MessageEntry): boolean => m.videoFileId === id);
    if (videoTracked || (done && path !== '' && hasVideoEntry)) {
      const percent = done && path !== '' ? 100 : this.downloadPercent(file, local);
      this.patchVideoEntries(id, (c: MessageEntry): void => {
        if (done && path !== '') {
          c.videoPath = path;
          c.videoFailed = false;
          c.mediaDownloadActive = false;
        } else {
          c.mediaDownloadActive = true;
        }
        c.videoProgress = percent;
      });
      if (done && path !== '') {
        this.videoFileToMsg.delete(id);
      }
      return;
    }
    // Inline thumbnail: progress while downloading, path on completion (drives
    // the in-bubble loading ring).
    if (this.messages.some((m: MessageEntry): boolean => m.photoFileId === id)) {
      const percent = this.downloadPercent(file, local);
      this.messages = this.messages.map((m: MessageEntry): MessageEntry => {
        if (m.photoFileId !== id) {
          return m;
        }
        const c = cloneMessage(m);
        if (done && path !== '') {
          c.photoPath = path;
          c.photoFailed = false;
        }
        c.photoProgress = percent;
        return c;
      });
      if (done && path !== '') {
        this.thumbAttempts.delete(id);
        this.thumbLastKick.delete(id);
      }
      this.notify();
      return;
    }

    if (!done || path === '') {
      return;
    }
    // The chat photo drives the header avatar (may also be a message sender's avatar
    // when the channel posts as itself — fall through so both get updated).
    if (id === this.chatPhotoFileId && this.chatPhotoPath !== path) {
      this.chatPhotoPath = path;
      this.notifyHeaderAvatar();
    }
    const senderKey = this.avatarFileToSender.get(id);
    if (senderKey !== undefined) {
      this.senderAvatarPaths.set(senderKey, path);
      this.applySenderPath(senderKey, path);
      return;
    }
    const replierUid = this.avatarFileToReplier.get(id);
    if (replierUid !== undefined) {
      this.replierAvatarPaths.set(replierUid, path);
      this.applyReplierAvatar(replierUid, path);
      return;
    }
    const linkMsgId = this.linkFileToMsg.get(id);
    if (linkMsgId !== undefined) {
      this.patch(linkMsgId, (c: MessageEntry) => { c.linkPhotoPath = path; });
    }
  }

  // Download the chat photo for the header avatar (independent of the chat lists,
  // so channels opened from a folder still get their header avatar).
  private downloadChatPhoto(): void {
    if (this.chatPhotoFileId <= 0) {
      return;
    }
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = this.chatPhotoFileId;
    req['priority'] = THUMBNAIL_PRIORITY;
    this.client.send(req).then((f: TdObject) => this.applyFile(f)).catch((err: TdError) => {
      console.error(`MessageStore chatPhoto ${this.chatPhotoFileId}: ${err.message}`);
    });
  }

  // --- sender avatars (group/channel per-message avatars) ---
  private senderKey(senderId: number, isUser: boolean): string {
    return `${isUser ? 'u' : 'c'}${senderId}`;
  }

  // Messages sent AS a chat (posting-as-channel / anonymous admins) carry a
  // messageSenderChat — their display name/avatar come from getChat, not the
  // user store (senderName() leaves them empty).
  private chatSenderNames: Map<number, string> = new Map();
  private chatSenderRequested: Set<number> = new Set();

  private resolveChatSenders(): void {
    for (const e of this.messages) {
      if (e.senderIsUser || e.senderId === 0 || e.senderId === this.chatId) {
        continue;
      }
      const cached = this.chatSenderNames.get(e.senderId);
      if (cached !== undefined && cached !== '') {
        this.applyChatSenderName(e.senderId, cached);
        continue;
      }
      if (this.chatSenderRequested.has(e.senderId)) {
        continue;
      }
      this.chatSenderRequested.add(e.senderId);
      const senderId = e.senderId;
      const req: TdRequest = { '@type': 'getChat' };
      req['chat_id'] = senderId;
      this.client.send(req).then((chat: TdObject) => {
        const title = (chat['title'] as string | undefined) ?? '';
        if (title !== '') {
          this.chatSenderNames.set(senderId, title);
          this.applyChatSenderName(senderId, title);
        }
        const photo = chat['photo'] as TdObject | undefined;
        const small = photo !== undefined ? (photo['small'] as TdObject | undefined) : undefined;
        const fileId = small !== undefined ? ((small['id'] as number | undefined) ?? 0) : 0;
        const key = this.senderKey(senderId, false);
        if (fileId > 0 && !this.senderRequested.has(key)) {
          this.senderRequested.add(key);
          this.avatarFileToSender.set(fileId, key);
          const dl: TdRequest = { '@type': 'downloadFile' };
          dl['file_id'] = fileId;
          dl['priority'] = THUMBNAIL_PRIORITY;
          this.client.send(dl).then((f: TdObject) => this.applyFile(f)).catch((err: TdError) => {
            console.error(`MessageStore chat-sender avatar ${fileId}: ${err.message}`);
          });
        }
      }).catch((err: TdError) => {
        console.error(`MessageStore.resolveChatSenders getChat(${senderId}) failed: ${err.message}`);
      });
    }
  }

  private applyChatSenderName(senderId: number, name: string): void {
    let changed = false;
    const next = this.messages.map((e: MessageEntry) => {
      if (!e.senderIsUser && e.senderId === senderId && e.senderName !== name) {
        changed = true;
        const c = cloneMessage(e);
        c.senderName = name;
        return c;
      }
      return e;
    });
    if (changed) {
      this.messages = next;
      this.notify();
    }
  }

  private resolveSenderAvatars(): void {
    this.resolveChatSenders();
    const seen = new Set<string>();
    for (const e of this.messages) {
      if (e.isOutgoing || e.senderId === 0) {
        continue;
      }
      const key = this.senderKey(e.senderId, e.senderIsUser);
      if (seen.has(key)) {
        continue;
      }
      seen.add(key);
      const known = this.senderAvatarPaths.get(key);
      if (known !== undefined && known !== '') {
        this.applySenderPath(key, known);
        continue;
      }
      if (this.senderRequested.has(key)) {
        continue;
      }
      let fileId = 0;
      if (e.senderIsUser) {
        // Users TDLib was never pushed (a chat opened from global search) have
        // no photo id and no updateUser is coming unless we ask.
        this.users.ensure(e.senderId);
        this.backfillSenderName(e.senderId);
        fileId = this.users.photoFileId(e.senderId);
      } else if (e.senderId === this.chatId) {
        fileId = this.chatPhotoFileId;
      }
      if (fileId <= 0) {
        continue; // not known yet — retried on updateUser / getChat
      }
      this.senderRequested.add(key);
      this.avatarFileToSender.set(fileId, key);
      const req: TdRequest = { '@type': 'downloadFile' };
      req['file_id'] = fileId;
      req['priority'] = THUMBNAIL_PRIORITY;
      this.client.send(req).then((f: TdObject) => this.applyFile(f)).catch((err: TdError) => {
        console.error(`MessageStore avatar ${fileId}: ${err.message}`);
      });
    }
  }

  // Message entries snapshot the sender's name AND initials when built. For a
  // user the cache didn't know yet both were empty, and many senders in a chat
  // we aren't a member of never get a profile photo at all (privacy) — their
  // initials ARE the avatar, so both fields must be backfilled once the user
  // arrives (the LazyForEach key includes senderName, so the row re-renders).
  private backfillSenderName(userId: number): void {
    const name = this.users.displayName(userId);
    if (name === '') {
      return;
    }
    const initials = name.substring(0, 1).toUpperCase();
    for (const e of this.messages) {
      if (e.senderIsUser && e.senderId === userId && e.senderName !== name) {
        this.patch(e.id, (c: MessageEntry) => {
          c.senderName = name;
          c.senderInitials = initials;
        });
      }
    }
  }

  private resolveSystemUserLabels(): void {
    let changed = false;
    const next = this.messages.map((entry: MessageEntry): MessageEntry => {
      const refreshed = refreshSystemUserLabel(entry, this.users);
      if (refreshed !== entry) {
        changed = true;
      }
      return refreshed;
    });
    if (changed) {
      this.messages = next;
      this.notify();
    }
  }

  private applySenderPath(key: string, path: string): void {
    let changed = false;
    const next = this.messages.map((e: MessageEntry) => {
      if (!e.isOutgoing && this.senderKey(e.senderId, e.senderIsUser) === key && e.senderAvatarPath !== path) {
        changed = true;
        const c = cloneMessage(e);
        c.senderAvatarPath = path;
        return c;
      }
      return e;
    });
    if (changed) {
      this.messages = next;
      this.notify();
    }
  }

  // --- shared-contact avatars ---
  private resolveContactAvatars(): void {
    for (const e of this.messages) {
      const userId = e.contactUserId;
      if (e.contentType !== 'contact' || userId <= 0) {
        continue;
      }
      const known = this.contactAvatarPaths.get(userId);
      if (known !== undefined && known !== '') {
        this.applyContactAvatarPath(userId, known);
        continue;
      }
      this.users.ensure(userId);
      const fileId = this.users.photoFileId(userId);
      if (fileId <= 0 || this.contactAvatarRequested.has(userId)) {
        continue;
      }
      const cachedPath = this.completedFilePaths.get(fileId) ?? '';
      if (cachedPath !== '') {
        this.contactAvatarPaths.set(userId, cachedPath);
        this.applyContactAvatarPath(userId, cachedPath);
        continue;
      }
      this.contactAvatarRequested.add(userId);
      this.avatarFileToContact.set(fileId, userId);
      const req: TdRequest = { '@type': 'downloadFile' };
      req['file_id'] = fileId;
      req['priority'] = THUMBNAIL_PRIORITY;
      this.client.send(req).then((f: TdObject) => this.applyFile(f)).catch((err: TdError) => {
        this.contactAvatarRequested.delete(userId);
        this.avatarFileToContact.delete(fileId);
        console.error(`MessageStore contact avatar ${fileId}: ${err.message}`);
      });
    }
  }

  private applyContactAvatarPath(userId: number, path: string): void {
    let changed = false;
    this.messages = this.messages.map((e: MessageEntry): MessageEntry => {
      if (e.contentType !== 'contact' || e.contactUserId !== userId ||
        e.contactAvatarPath === path) {
        return e;
      }
      const c = cloneMessage(e);
      c.contactAvatarPath = path;
      changed = true;
      return c;
    });
    if (changed) {
      this.notify();
    }
  }

  // --- comment-row avatars (recent commenters shown on a channel post) ---
  private resolveCommentAvatars(): void {
    for (const e of this.messages) {
      for (const uid of e.commentReplierIds) {
        const known = this.replierAvatarPaths.get(uid);
        if (known !== undefined && known !== '') {
          this.applyReplierAvatar(uid, known);
          continue;
        }
        if (this.replierAvatarRequested.has(uid)) {
          continue;
        }
        const fileId = this.users.photoFileId(uid);
        if (fileId <= 0) {
          continue; // not known yet — retried on updateUser
        }
        this.replierAvatarRequested.add(uid);
        this.avatarFileToReplier.set(fileId, uid);
        const req: TdRequest = { '@type': 'downloadFile' };
        req['file_id'] = fileId;
        req['priority'] = THUMBNAIL_PRIORITY;
        this.client.send(req).then((f: TdObject) => this.applyFile(f)).catch((err: TdError) => {
          console.error(`MessageStore replier avatar ${fileId}: ${err.message}`);
        });
      }
    }
  }

  private applyReplierAvatar(userId: number, path: string): void {
    let changed = false;
    const next = this.messages.map((e: MessageEntry) => {
      const idx = e.commentReplierIds.indexOf(userId);
      if (idx < 0 || e.commentReplierAvatarPaths[idx] === path) {
        return e;
      }
      changed = true;
      const c = cloneMessage(e);
      const arr = c.commentReplierAvatarPaths.slice();
      while (arr.length <= idx) {
        arr.push('');
      }
      arr[idx] = path;
      c.commentReplierAvatarPaths = arr;
      return c;
    });
    if (changed) {
      this.messages = next;
      this.notify();
    }
  }

  // --- subtitle ---
  // Newest pinned message → one-line preview shown in the banner under the header.
  private resolvePinned(): void {
    const seq: number = ++this.pinnedResolveSeq;
    if (this.threadRootId > 0) {
      this.pinnedIds = [];
      this.pinnedPreviews = [];
      this.pinnedLoadState = 'ready';
      this.setPinned('');
      return; // comment thread view — the discussion group's pins don't apply
    }
    this.pinnedLoadState = 'loading';
    this.notifyPinned();
    const filter: TdObject = { '@type': 'searchMessagesFilterPinned' };
    const req: TdRequest = { '@type': 'searchChatMessages' };
    req['chat_id'] = this.chatId;
    req['query'] = '';
    req['from_message_id'] = 0;
    req['offset'] = 0;
    req['limit'] = 100;
    req['filter'] = filter;
    this.client.send(req).then((res: TdObject) => {
      if (seq !== this.pinnedResolveSeq) {
        return;
      }
      const arr = (res['messages'] as TdObject[] | undefined) ?? [];
      const ids: number[] = [];
      const previews: string[] = [];
      for (const m of arr) {
        const id = m['id'] as number | undefined;
        if (id !== undefined) {
          ids.push(id);
          previews.push(formatPreview(m));
        }
      }
      this.pinnedIds = ids; // newest → oldest, as returned
      this.pinnedPreviews = previews;
      this.pinnedLoadState = 'ready';
      this.setPinned(previews.length > 0 ? previews[0] : '');
    }).catch((e: TdError) => {
      if (seq !== this.pinnedResolveSeq) {
        return;
      }
      // TDLib uses 404 for "there is no pinned message" in some chat types.
      // That is a valid empty result, not a request failure: clear any stale
      // preview and let ChatPage omit the optional top card entirely.
      if (e.code === 404) {
        this.pinnedIds = [];
        this.pinnedPreviews = [];
        this.pinnedLoadState = 'ready';
        this.setPinned('');
        return;
      }
      this.pinnedLoadState = 'error';
      this.notifyPinned();
      console.error(`MessageStore.resolvePinned failed: ${e.message}`);
    });
  }

  private onPinnedUpdate(u: TdObject): void {
    const messageId = (u['message_id'] as number | undefined) ?? 0;
    const isPinned = (u['is_pinned'] as boolean | undefined) ?? false;
    if (!isPinned && messageId > 0) {
      this.removePinnedIds(new Set<number>([messageId]));
    }
    this.resolvePinned();
  }

  private removePinnedIds(removeIds: Set<number>): void {
    if (!this.pinnedIds.some((id: number): boolean => removeIds.has(id))) {
      return;
    }
    const ids: number[] = [];
    const previews: string[] = [];
    for (let i = 0; i < this.pinnedIds.length; i++) {
      if (!removeIds.has(this.pinnedIds[i])) {
        ids.push(this.pinnedIds[i]);
        previews.push(i < this.pinnedPreviews.length ? this.pinnedPreviews[i] : '');
      }
    }
    this.pinnedIds = ids;
    this.pinnedPreviews = previews;
    this.setPinned(previews.length > 0 ? previews[0] : '');
  }

  // Pinned message ids, newest → oldest (for the banner tap-cycle).
  getPinnedIds(): number[] {
    return this.pinnedIds;
  }

  // Pinned message previews, aligned with getPinnedIds().
  getPinnedPreviews(): string[] {
    return this.pinnedPreviews;
  }

  // Load a page centered on a message (for jumping to a pinned/quoted message
  // that isn't in the currently loaded window). Notifies when it arrives.
  loadAround(messageId: number, onComplete?: (found: boolean) => void): void {
    // Jumping into the middle of history: newer messages beyond this window
    // may exist — enable downward prefetch to discover/load them.
    const hadMoreNewer: boolean = this.hasMoreNewer;
    this.hasMoreNewer = true;
    this.newerLoadState = 'idle';
    const req = this.historyRequest(messageId, -15);
    req['limit'] = 30;
    this.client.send(req).then((res: TdObject): void => {
      this.onHistory(res, 'around');
      if (onComplete !== undefined) {
        onComplete(this.indexOf(messageId) >= 0);
      }
    }).catch((e: TdError) => {
      this.hasMoreNewer = hadMoreNewer;
      console.error(`MessageStore.loadAround failed: ${e.message}`);
      if (this.initialHistoryState === 'loading') {
        if ((e as TdError).code === 404) {
          // A stale unread/search anchor should not turn a healthy chat into
          // an empty/error page. Fall back to its live tail.
          this.loadHistory(0);
        } else {
          this.initialHistoryState = 'error';
          this.initialHistoryError = this.historyErrorHint(e);
          this.notify('initialState');
        }
      }
      if (onComplete !== undefined) {
        onComplete(false);
      }
    });
  }

  private setPinned(s: string): void {
    this.pinnedPreview = s;
    this.notifyPinned();
  }

  private historyErrorHint(error: TdError): string {
    if (error.code === -1 || error.message.toLowerCase().indexOf('timeout') >= 0) {
      return '连接超时，请检查网络后重试';
    }
    if (error.code === 401) {
      return '登录状态已失效，请重新登录';
    }
    return '暂时无法同步消息，请稍后重试';
  }

  private notifyPinned(): void {
    for (const l of this.pinnedSubs) {
      l(this.pinnedPreview);
    }
  }

  private resolveChat(): void {
    const req: TdRequest = { '@type': 'getChat' };
    req['chat_id'] = this.chatId;
    this.client.send(req).then((chat: TdObject) => this.onChat(chat)).catch((e: TdError) => {
      console.error(`MessageStore.getChat failed: ${e.message}`);
      this.startInitialLoad();
      this.flushInitial();
    });
  }

  private onChat(chat: TdObject): void {
    // Capture the unread boundary BEFORE loading history / marking read, so the
    // page can position at the first unread message even after we mark it read.
    this.lastReadInboxId = (chat['last_read_inbox_message_id'] as number | undefined) ?? 0;
    this.lastReadOutboxId = (chat['last_read_outbox_message_id'] as number | undefined) ?? 0;
    this.unreadCount = (chat['unread_count'] as number | undefined) ?? 0;
    const photo = chat['photo'] as TdObject | undefined;
    const small = photo !== undefined ? (photo['small'] as TdObject | undefined) : undefined;
    this.chatPhotoFileId = small !== undefined ? ((small['id'] as number | undefined) ?? 0) : 0;
    this.downloadChatPhoto();
    this.chatTitle = (chat['title'] as string | undefined) ?? '';
    this.notifyHeaderTitle();
    // Active bot reply keyboard for this chat (0 = none). updateChatReplyMarkup
    // keeps it current from here on.
    this.replyMarkupMessageId = (chat['reply_markup_message_id'] as number | undefined) ?? 0;
    this.resolveReplyKeyboard();
    const type = chat['type'] as TdObject | undefined;
    if (type !== undefined) {
      const t = type['@type'] as string | undefined;
      if (t === 'chatTypePrivate') {
        this.peerUserId = (type['user_id'] as number | undefined) ?? 0;
        this.fetchUserStatus();
      } else if (t === 'chatTypeBasicGroup') {
        this.groupId = (type['basic_group_id'] as number | undefined) ?? 0;
        this.isGroupFlag = true;
        this.resolveBasicGroup(this.groupId);
      } else if (t === 'chatTypeSupergroup') {
        this.groupId = (type['supergroup_id'] as number | undefined) ?? 0;
        this.isGroupFlag = true;
        this.resolveSupergroup(this.groupId);
      }
    }
    this.resolveSenderAvatars();
    this.startInitialLoad();
    this.flushInitial();
  }

  private startInitialLoad(): void {
    if (this.initialLoadStarted) {
      return;
    }
    this.initialLoadStarted = true;
    this.requestInitialPage();
  }

  private requestInitialPage(): void {
    if (this.requestedAroundMessageId > 0) {
      this.loadAround(this.requestedAroundMessageId);
      return;
    }
    // getFirstUnreadId() only scans the loaded window, so with a large unread
    // count the newest-30 page (loadHistory(0)) never actually contains the
    // true first-unread message — it silently returns the oldest of that page
    // instead, landing (and read-marking) far past the real boundary. Center
    // on lastReadInboxId to guarantee the boundary is in the loaded window —
    // but ONLY when there's actually something unread: last_read_inbox_message_id
    // only tracks incoming messages, so a fully-read chat whose newest messages
    // are outgoing (sent by us) can have it sitting well behind the true tail —
    // loadAround there would miss the real end of the chat. Fully-read chats
    // always just load the newest page instead.
    if (this.unreadCount > 0 && this.lastReadInboxId > 0) {
      this.loadAround(this.lastReadInboxId);
      return;
    }
    this.loadHistory(0);
  }

  private fetchUserStatus(): void {
    if (this.peerUserId === 0) {
      return;
    }
    const req: TdRequest = { '@type': 'getUser' };
    req['user_id'] = this.peerUserId;
    this.client.send(req).then((user: TdObject) => {
      this.applyPeerUserStatus(user['status'] as TdObject | undefined);
    }).catch((e: TdError) => {
      console.error(`MessageStore.getUser failed: ${e.message}`);
    });
  }

  private onUserStatus(u: TdObject): void {
    if ((u['user_id'] as number | undefined) !== this.peerUserId || this.peerUserId === 0) {
      return;
    }
    this.applyPeerUserStatus(u['status'] as TdObject | undefined);
  }

  private applyPeerUserStatus(status: TdObject | undefined): void {
    this.peerUserStatus = status;
    this.setSubtitle(formatUserStatus(status, Math.floor(Date.now() / 1000)));
    const type = status !== undefined ? ((status['@type'] as string | undefined) ?? '') : '';
    if (type !== 'userStatusOffline') {
      if (this.statusRefreshTimer !== -1) {
        clearInterval(this.statusRefreshTimer);
        this.statusRefreshTimer = -1;
      }
      return;
    }
    if (this.statusRefreshTimer !== -1) {
      return;
    }
    this.statusRefreshTimer = setInterval((): void => {
      const next = formatUserStatus(this.peerUserStatus, Math.floor(Date.now() / 1000));
      if (next !== this.subtitle) {
        this.setSubtitle(next);
      }
    }, 30 * 1000);
  }

  private onGroup(u: TdObject): void {
    const g = (u['basic_group'] as TdObject | undefined) ?? (u['supergroup'] as TdObject | undefined);
    if (g === undefined) {
      return;
    }
    if ((g['id'] as number | undefined) !== this.groupId || this.groupId === 0) {
      return;
    }
    const isCh = (g['is_channel'] as boolean | undefined);
    if (isCh !== undefined) {
      this.isChannel = isCh;
    }
    const count = (g['member_count'] as number | undefined) ?? 0;
    if (count > 0) {
      this.setMemberSubtitle(count);
    }
  }

  // Subscriber/member count subtitle, K-abbreviated like Telegram
  // ("33.1K 位订阅者" / "128 位成员, 12 人在线").
  private setMemberSubtitle(count: number): void {
    this.memberCount = count;
    this.composeMemberSubtitle();
  }

  private composeMemberSubtitle(): void {
    if (this.memberCount <= 0) {
      return;
    }
    let s = `${formatMemberCount(this.memberCount)} 位${this.isChannel ? '订阅者' : '成员'}`;
    // Channels don't surface member presence — online counts are a group thing.
    if (!this.isChannel && this.onlineCount > 0) {
      s += `, ${this.onlineCount} 人在线`;
    }
    this.setSubtitle(s);
  }

  private onOnlineCount(u: TdObject): void {
    if ((u['chat_id'] as number | undefined) !== this.chatId) {
      return;
    }
    this.onlineCount = (u['online_member_count'] as number | undefined) ?? 0;
    this.composeMemberSubtitle();
  }

  // Supergroup/channel: the pushed supergroup object often carries member_count 0,
  // so fetch the authoritative count from getSupergroupFullInfo (and is_channel
  // from getSupergroup) rather than waiting for an updateSupergroup that may not come.
  private resolveSupergroup(id: number): void {
    if (id === 0) {
      return;
    }
    const sg: TdRequest = { '@type': 'getSupergroup' };
    sg['supergroup_id'] = id;
    this.client.send(sg).then((s: TdObject) => {
      this.isChannel = (s['is_channel'] as boolean | undefined) ?? this.isChannel;
      const c = (s['member_count'] as number | undefined) ?? 0;
      if (c > 0) {
        this.setMemberSubtitle(c);
      }
    }).catch((e: TdError) => {
      console.error(`MessageStore.getSupergroup failed: ${e.message}`);
    });
    const full: TdRequest = { '@type': 'getSupergroupFullInfo' };
    full['supergroup_id'] = id;
    this.client.send(full).then((f: TdObject) => {
      const c = (f['member_count'] as number | undefined) ?? 0;
      if (c > 0) {
        this.setMemberSubtitle(c);
      }
    }).catch((e: TdError) => {
      console.error(`MessageStore.getSupergroupFullInfo failed: ${e.message}`);
    });
  }

  private resolveBasicGroup(id: number): void {
    if (id === 0) {
      return;
    }
    this.isChannel = false;
    const req: TdRequest = { '@type': 'getBasicGroup' };
    req['basic_group_id'] = id;
    this.client.send(req).then((bg: TdObject) => {
      const c = (bg['member_count'] as number | undefined) ?? 0;
      if (c > 0) {
        this.setMemberSubtitle(c);
      }
    }).catch((e: TdError) => {
      console.error(`MessageStore.getBasicGroup failed: ${e.message}`);
    });
  }

  private setSubtitle(s: string): void {
    this.subtitle = s;
    for (const l of this.subSubs) {
      l(this.subtitle);
    }
  }

  // --- read marking (driven by the visible range) ---
  // Mark messages read up to maxVisibleId. Because TDLib read state is a
  // high-water mark, we only ever send the highest id the user has actually
  // seen — so entering a chat without scrolling leaves the rest unread.
  markViewed(maxVisibleId: number): void {
    if (maxVisibleId <= this.viewedUpTo) {
      return;
    }
    this.viewedUpTo = maxVisibleId;
    const req: TdRequest = { '@type': 'viewMessages' };
    req['chat_id'] = this.chatId;
    req['message_ids'] = [maxVisibleId];
    req['force_read'] = true;
    this.client.send(req).catch((e: TdError) => {
      console.error(`MessageStore.viewMessages failed: ${e.message}`);
    });
  }

  // Submit or change a poll answer. The request is guarded per message so a
  // double tap can't race two different selections. TDLib's updatePoll is the
  // authoritative result; the small optimistic patch only bridges request →
  // update latency and is rolled back to the prior options on failure.
  votePoll(messageId: number, optionIds: number[],
    onFinished: (ok: boolean, error: string) => void): void {
    const idx = this.indexOf(messageId);
    if (idx < 0) {
      onFinished(false, '投票消息已不可用');
      return;
    }
    const entry = this.messages[idx];
    const expired = entry.pollCloseDate > 0 &&
      Math.floor(Date.now() / 1000) >= entry.pollCloseDate;
    if (entry.contentType !== 'poll' || entry.pollQuestion.trim() === '' ||
      entry.pollOptions.length < 2) {
      onFinished(false, '投票内容不可用');
      return;
    }
    if (entry.pollVotePending) {
      return;
    }
    if (entry.pollIsClosed || expired) {
      onFinished(false, '投票已经结束');
      return;
    }
    if (entry.pollIsQuiz &&
      entry.pollOptions.some((option): boolean => option.isChosen)) {
      onFinished(false, '答题投票只能提交一次');
      return;
    }
    const unique: number[] = [];
    for (const optionId of optionIds) {
      if (optionId >= 0 && optionId < entry.pollOptions.length &&
        unique.indexOf(optionId) < 0) {
        unique.push(optionId);
      }
    }
    if (!entry.pollAllowMultiple && unique.length > 1) {
      onFinished(false, '该投票只能选择一项');
      return;
    }
    const previousOptions: PollOptionInfo[] =
      entry.pollOptions.map((option: PollOptionInfo): PollOptionInfo => ({
      text: option.text,
      voterCount: option.voterCount,
      votePercentage: option.votePercentage,
      isChosen: option.isChosen,
      isBeingChosen: option.isBeingChosen
    }));
    this.patch(messageId, (message: MessageEntry): void => {
      message.pollVotePending = true;
      message.pollVoteError = '';
      message.pollOptions = message.pollOptions.map((
        option: PollOptionInfo,
        optionId: number
      ): PollOptionInfo => ({
        text: option.text,
        voterCount: option.voterCount,
        votePercentage: option.votePercentage,
        isChosen: option.isChosen,
        isBeingChosen: unique.indexOf(optionId) >= 0
      }));
    });
    const req: TdRequest = { '@type': 'setPollAnswer' };
    req['chat_id'] = this.chatId;
    req['message_id'] = messageId;
    req['option_ids'] = unique;
    this.client.send(req).then((): void => {
      this.patch(messageId, (message: MessageEntry): void => {
        message.pollVotePending = false;
        message.pollVoteError = '';
        message.pollOptions = message.pollOptions.map((
          option: PollOptionInfo,
          optionId: number
        ): PollOptionInfo => ({
          text: option.text,
          voterCount: option.voterCount,
          votePercentage: option.votePercentage,
          isChosen: unique.indexOf(optionId) >= 0,
          isBeingChosen: false
        }));
      });
      onFinished(true, '');
    }).catch((error: TdError): void => {
      const message = error.message.trim() !== '' ? error.message : '网络异常';
      this.patch(messageId, (current: MessageEntry): void => {
        current.pollVotePending = false;
        current.pollVoteError = message;
        current.pollOptions = previousOptions;
      });
      onFinished(false, message);
      console.error(`MessageStore.setPollAnswer failed: ${error.message}`);
    });
  }

  // Voice notes have a separate listened bit from the chat's ordinary read
  // high-water mark. Open the content only after playback has actually begun,
  // then optimistically remove the unread dot while TDLib propagates the
  // refreshed message content.
  markVoiceListened(messageId: number): void {
    const idx: number = this.indexOf(messageId);
    if (idx < 0) {
      return;
    }
    const entry: MessageEntry = this.messages[idx];
    if (entry.contentType !== 'voice' || entry.isOutgoing || entry.voiceListened ||
      this.voiceListenPending.has(messageId)) {
      return;
    }
    this.voiceListenPending.add(messageId);
    this.patch(messageId, (c: MessageEntry): void => {
      c.voiceListened = true;
    });
    const req: TdRequest = { '@type': 'openMessageContent' };
    req['chat_id'] = this.chatId;
    req['message_id'] = messageId;
    this.client.send(req).then((): void => {
      this.voiceListenPending.delete(messageId);
    }).catch((e: TdError): void => {
      this.voiceListenPending.delete(messageId);
      this.patch(messageId, (c: MessageEntry): void => {
        if (c.contentType === 'voice' && !c.isOutgoing) {
          c.voiceListened = false;
        }
      });
      console.error(`MessageStore.openMessageContent failed: ${e.message}`);
    });
  }

  // Forwards from a channel/chat only carry the origin chat id (forwardChatId);
  // resolve it to a display title via getChat, then patch matching messages.
  private resolveForwardTitles(): void {
    for (const e of this.messages) {
      if (e.forwardChatId === 0 || e.forwardFrom !== '') {
        continue;
      }
      const cached = this.forwardTitleCache.get(e.forwardChatId);
      if (cached !== undefined) {
        this.patch(e.id, (c: MessageEntry) => { c.forwardFrom = cached; c.forwardChatId = 0; });
        continue;
      }
      if (this.forwardTitleRequested.has(e.forwardChatId)) {
        continue;
      }
      this.forwardTitleRequested.add(e.forwardChatId);
      const id = e.forwardChatId;
      const req: TdRequest = { '@type': 'getChat' };
      req['chat_id'] = id;
      this.client.send(req).then((chat: TdObject) => {
        const title = (chat['title'] as string | undefined) ?? '';
        this.forwardTitleCache.set(id, title);
        this.resolveForwardTitles();
      }).catch((err: TdError) => {
        console.error(`MessageStore forward title ${id}: ${err.message}`);
      });
    }
  }

  private resolveReplies(): void {
    this.messages = this.messages.map((e: MessageEntry) => {
      if (e.replyToMessageId === 0 || e.replyText !== '') {
        return e;
      }
      const target = this.messages.find((x: MessageEntry) => x.id === e.replyToMessageId);
      if (target === undefined) {
        return e;
      }
      const c = cloneMessage(e);
      c.replySenderName = target.senderName;
      c.replyText = target.contentType === 'text' ? target.text : (target.placeholderLabel !== '' ? target.placeholderLabel : '[图片]');
      return c;
    });
  }

  private indexOf(id: number): number {
    for (let i = 0; i < this.messages.length; i++) {
      if (this.messages[i].id === id) {
        return i;
      }
    }
    return -1;
  }

  private upsert(entry: MessageEntry): void {
    // The picker commonly downloads the selected sticker before sendMessage
    // returns. Hydrate a new entry from that completed-file cache instead of
    // flashing an indefinite loading ring or downloading the same file again.
    if (entry.videoFileId !== 0 && entry.videoPath !== '') {
      this.completedFilePaths.set(entry.videoFileId, entry.videoPath);
    }
    if (entry.photoFileId !== 0 && entry.photoPath !== '') {
      this.completedFilePaths.set(entry.photoFileId, entry.photoPath);
    }
    if (entry.stickerFileId !== 0 && entry.stickerPath !== '') {
      this.completedFilePaths.set(entry.stickerFileId, entry.stickerPath);
    }
    const cachedPhotoPath = entry.photoFileId !== 0
      ? (this.completedFilePaths.get(entry.photoFileId) ?? '') : '';
    const cachedFullPhotoPath = entry.photoFullFileId !== 0
      ? (this.completedFilePaths.get(entry.photoFullFileId) ?? '') : '';
    const cachedVideoPath = entry.videoFileId !== 0
      ? (this.completedFilePaths.get(entry.videoFileId) ?? '') : '';
    const cachedStickerPath = entry.stickerFileId !== 0
      ? (this.completedFilePaths.get(entry.stickerFileId) ?? '') : '';
    let hydrated = entry;
    if ((entry.photoPath === '' && cachedPhotoPath !== '') ||
      (entry.photoFullPath === '' && cachedFullPhotoPath !== '') ||
      (entry.videoPath === '' && cachedVideoPath !== '') ||
      (entry.stickerPath === '' && cachedStickerPath !== '')) {
      hydrated = cloneMessage(entry);
      if (hydrated.photoPath === '' && cachedPhotoPath !== '') {
        hydrated.photoPath = cachedPhotoPath;
        hydrated.photoProgress = 100;
        hydrated.photoFailed = false;
      }
      if (hydrated.photoFullPath === '' && cachedFullPhotoPath !== '') {
        hydrated.photoFullPath = cachedFullPhotoPath;
        if (hydrated.photoPath === '') {
          hydrated.photoPath = cachedFullPhotoPath;
          hydrated.photoProgress = 100;
          hydrated.photoFailed = false;
        }
      }
      if (hydrated.videoPath === '' && cachedVideoPath !== '') {
        hydrated.videoPath = cachedVideoPath;
        hydrated.videoProgress = 100;
        hydrated.videoFailed = false;
        hydrated.mediaDownloadActive = false;
      }
      if (hydrated.stickerPath === '' && cachedStickerPath !== '') {
        hydrated.stickerPath = cachedStickerPath;
        hydrated.stickerProgress = 100;
        hydrated.stickerFailed = false;
        hydrated.stickerDownloadActive = false;
      }
    }
    const idx = this.indexOf(hydrated.id);
    if (idx >= 0) {
      const next = this.messages.slice();
      next[idx] = hydrated;
      this.messages = next;
      return;
    }
    const next = this.messages.slice();
    next.push(hydrated);
    next.sort((a: MessageEntry, b: MessageEntry) => a.id - b.id);
    this.messages = next;
  }

  private patch(id: number, fn: (c: MessageEntry) => void): void {
    const idx = this.indexOf(id);
    if (idx < 0) {
      return;
    }
    const c = cloneMessage(this.messages[idx]);
    fn(c);
    const next = this.messages.slice();
    next[idx] = c;
    this.messages = next;
    this.notify();
  }

  // Telegram may reuse one file id for forwards or repeated media. Keep every
  // visible consumer synchronized instead of updating only the message that
  // happened to start the download.
  private patchVideoEntries(fileId: number, fn: (c: MessageEntry) => void): void {
    if (fileId === 0) {
      return;
    }
    let changed = false;
    this.messages = this.messages.map((m: MessageEntry): MessageEntry => {
      if (m.videoFileId !== fileId) {
        return m;
      }
      const c = cloneMessage(m);
      fn(c);
      changed = true;
      return c;
    });
    if (changed) {
      this.notify();
    }
  }

  private notify(kind: string = 'update'): void {
    this.applyReadOutbox();
    this.currentNotifyKind = kind;
    try {
      for (const l of this.msgSubs) {
        l(this.messages);
      }
    } finally {
      this.currentNotifyKind = 'update';
    }
  }
}
