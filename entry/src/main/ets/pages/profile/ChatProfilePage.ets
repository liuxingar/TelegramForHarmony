import { router, promptAction } from '@kit.ArkUI';
import { getTdClient } from '../../tdkit/Globals';
import {
  ChatProfileStore, MemberItem, ProfileContentItem,
  PROFILE_TAB_MEMBERS, PROFILE_TAB_MEDIA, PROFILE_TAB_FILES, PROFILE_TAB_LINKS,
  PROFILE_TAB_MUSIC, PROFILE_TAB_POLLS, PROFILE_TAB_VOICE,
  PROFILE_TAB_VIDEO_NOTES, PROFILE_TAB_GIFS, PROFILE_TAB_GIFTS
} from '../../store/ChatProfileStore';
import { AvatarView } from '../chatlist/AvatarView';
import { QrDialog } from '../common/QrDialog';
import { AvatarViewer } from '../common/AvatarViewer';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import {
  COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY,
  COLOR_TAB_SELECTED, COLOR_TAB_UNSELECTED, COLOR_TAB_PILL_BG
} from '../../util/theme';
import { ExpandableText } from './ExpandableText';
import { publicLink } from '../../util/telegramLink';
import {
  createVideoChat, endGroupCall, getGroupCall, startScheduledVideoChat
} from '../../tdkit/GroupCallApi';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { MUTE_LONG, setMute } from '../../store/ChatActions';

const CARD_BG: ResourceColor = $r('app.color.surface');
const CARD_RADIUS: number = 14;
const DETAIL_TAB_BAR_HEIGHT: number = 44;
const DETAIL_TAB_INDICATOR_HEIGHT: number = 32;

interface ProfileTabItem {
  key: string;
  label: string;
}

const PROFILE_TABS: ProfileTabItem[] = [
  { key: PROFILE_TAB_MEMBERS, label: '成员' },
  { key: PROFILE_TAB_MEDIA, label: '媒体' },
  { key: PROFILE_TAB_FILES, label: '文件' },
  { key: PROFILE_TAB_LINKS, label: '链接' },
  { key: PROFILE_TAB_MUSIC, label: '音乐' },
  { key: PROFILE_TAB_POLLS, label: '投票' },
  { key: PROFILE_TAB_VOICE, label: '语音' },
  { key: PROFILE_TAB_VIDEO_NOTES, label: '圆形视频' },
  { key: PROFILE_TAB_GIFS, label: 'GIF' },
  { key: PROFILE_TAB_GIFTS, label: '礼物' }
];

// Group / channel detail page — visually mirrors ProfilePage (header, action
// row, info card) with a member list instead of the personal tabs.
@Entry
@Component
struct ChatProfilePage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('screenWidthVp') screenW: number = 360;
  @State title: string = '';
  @State initials: string = '?';
  @State avatarPath: string = '';
  // 头像点击放大（'' = 未打开）。
  @State viewerAvatarPath: string = '';
  @State avatarTapX: number = 0;
  @State avatarTapY: number = 0;
  @State avatarAnimPath: string = '';
  @State subtitle: string = '';
  @State description: string = '';
  @State chatUsername: string = '';
  @State isChannel: boolean = false;
  @State isMuted: boolean = false;
  @State canManageVideoChats: boolean = false;
  @State canManageChat: boolean = false;
  @State liveGroupCallId: number = 0;
  @State creatingLive: boolean = false;
  @State members: MemberItem[] = [];
  @State membersState: string = 'loading';
  @State selectedTab: number = 0;
  @State contentItems: ProfileContentItem[] = [];
  @State contentState: string = 'idle';
  @State contentErrorText: string = '';
  @State contentHasMore: boolean = false;
  @State contentPaging: boolean = false;
  @State contentPagingError: boolean = false;
  @State contentTotalCount: number = 0;
  @State availableTabKeys: string[] = [];
  @State tabsState: string = 'loading';
  @State detailIndicatorX: number = 8;
  @State detailIndicatorW: number = 0;
  @State pageState: string = 'loading'; // loading | ready | error
  @State errorText: string = '';
  @State membershipState: string = 'checking';
  @State joinByRequest: boolean = false;
  @State joining: boolean = false;
  @State joinRequestSent: boolean = false;
  private chatId: number = 0;
  private inviteLink: string = '';
  private pendingDraftText: string = '';
  private pendingJumpTo: number = 0;
  private justJoined: boolean = false;
  private store: ChatProfileStore | null = null;
  private unsub: (() => void) | null = null;
  private tabScroller: Scroller = new Scroller();
  private detailTabXs: number[] = [];
  private detailTabWs: number[] = [];
  private detailTabViewW: number = 0;

  @Styles
  tabNormalStyle() {
    .opacity(1)
  }

  @Styles
  tabPressedStyle() {
    .opacity(0.58)
  }

  @Styles
  contentRowNormalStyle() {
    .backgroundColor(CARD_BG)
  }

  @Styles
  contentRowPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
  }

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object> | undefined;
    this.chatId = params !== undefined
      ? ((params['chatId'] as number | undefined) ?? 0) : 0;
    this.inviteLink = params !== undefined
      ? ((params['inviteLink'] as string | undefined) ?? '') : '';
    this.pendingDraftText = params !== undefined
      ? ((params['draftText'] as string | undefined) ?? '') : '';
    this.pendingJumpTo = params !== undefined
      ? ((params['jumpTo'] as number | undefined) ?? 0) : 0;
    if (this.chatId !== 0) {
      this.startStore();
    } else if (this.inviteLink !== '') {
      this.loadInvitePreview();
    } else {
      this.pageState = 'error';
      this.errorText = '链接中没有可识别的频道或群组';
    }
  }

  private startStore(): void {
    if (this.chatId === 0) {
      return;
    }
    if (this.unsub !== null) {
      this.unsub();
      this.unsub = null;
    }
    if (this.store !== null) {
      this.store.close();
    }
    this.pageState = 'loading';
    const store = new ChatProfileStore(getTdClient(), this.chatId);
    this.store = store;
    this.unsub = store.subscribe(() => { this.refresh(); });
    store.open();
  }

  aboutToDisappear(): void {
    if (this.unsub !== null) { this.unsub(); this.unsub = null; }
    if (this.store !== null) { this.store.close(); this.store = null; }
  }

  @State qrLink: string = '';
  private qrCtrl: CustomDialogController = new CustomDialogController({
    builder: QrDialog({ link: this.qrLink, title: this.title }),
    alignment: DialogAlignment.Center,
    autoCancel: true
  });

  private openQr(): void {
    if (this.chatUsername === '') {
      return;
    }
    this.qrLink = publicLink(this.chatUsername);
    this.qrCtrl.open();
  }

  // Mirror the store snapshot into @State (plain-field reads don't re-render).
  private refresh(): void {
    const s = this.store;
    if (s === null) {
      return;
    }
    const beforeTabs = this.visibleTabs();
    const beforeKey = beforeTabs.length > 0 && this.selectedTab < beforeTabs.length
      ? beforeTabs[this.selectedTab].key : '';
    this.pageState = s.loadState;
    this.errorText = s.errorText;
    this.membershipState = s.membershipState;
    this.joinByRequest = s.joinByRequest;
    this.membersState = s.membersState;
    this.contentItems = s.contentItems;
    this.contentState = s.contentState;
    this.contentErrorText = s.contentErrorText;
    this.contentHasMore = s.contentHasMore;
    this.contentPaging = s.contentPaging;
    this.contentPagingError = s.contentPagingError;
    this.contentTotalCount = s.contentTotalCount;
    this.availableTabKeys = s.availableTabs;
    this.tabsState = s.tabsState;
    const nextTabs = this.visibleTabs();
    if (nextTabs.length > 0) {
      const nextIndex = beforeKey !== ''
        ? nextTabs.findIndex((tab: ProfileTabItem): boolean => tab.key === beforeKey) : -1;
      this.selectedTab = nextIndex >= 0 ? nextIndex : 0;
      const selectedKey = nextTabs[this.selectedTab].key;
      if (s.contentTab !== selectedKey) {
        s.selectContentTab(selectedKey);
      }
      this.moveDetailIndicator(this.selectedTab);
    } else {
      this.selectedTab = 0;
    }
    if (s.loadState !== 'ready') {
      return;
    }
    this.title = s.title;
    this.initials = s.initials;
    this.avatarPath = s.avatarPath;
    this.avatarAnimPath = s.avatarAnimPath;
    this.subtitle = s.subtitle;
    this.description = s.description;
    this.chatUsername = s.username;
    this.isChannel = s.isChannel;
    this.isMuted = s.isMuted;
    this.canManageVideoChats = s.canManageVideoChats;
    this.canManageChat = s.canManageChat;
    this.liveGroupCallId = s.liveGroupCallId;
    this.members = s.members;
  }

  private openChat(): void {
    if (this.chatId === 0 || this.membershipState !== 'writable') {
      return;
    }
    const params: Record<string, Object> = { 'chatId': this.chatId };
    if (this.pendingDraftText !== '') {
      params['draftText'] = this.pendingDraftText;
    }
    if (this.pendingJumpTo > 0) {
      params['jumpTo'] = this.pendingJumpTo;
    }
    if (this.justJoined) {
      params['showJoinedNotice'] = true;
      params['joinedNoticeIsChannel'] = this.isChannel;
      this.justJoined = false;
    }
    router.pushUrl({ url: 'pages/chat/ChatPage', params: params });
  }

  private openSearchInChat(): void {
    if (this.chatId === 0) { return; }
    const params: Record<string, Object> = { 'chatId': this.chatId, 'startSearch': true };
    router.pushUrl({ url: 'pages/chat/ChatPage', params });
  }


  private leaveCurrentChat(): void {
    promptAction.showDialog({
      title: this.isChannel ? '退出频道' : '退出群组',
      message: `确定退出「${this.title}」吗？`,
      buttons: [
        { text: '取消', color: '#8E8E93' },
        { text: '退出', color: '#E5484D' }
      ]
    }).then((result): void => {
      if (result.index !== 1) { return; }
      const req: TdRequest = { '@type': 'leaveChat' };
      req['chat_id'] = this.chatId;
      getTdClient().send(req).then((): void => {
        promptAction.showToast({ message: '已退出', duration: 1500 });
        router.back();
      }).catch((error: TdError): void => {
        console.error(`ChatProfilePage.leave failed: ${error.message}`);
        promptAction.showToast({ message: '退出失败，请稍后重试', duration: 1800 });
      });
    }).catch((): void => {});
  }

  private boostChat(): void {
    const req: TdRequest = { '@type': 'getChatBoostStatus' };
    req['chat_id'] = this.chatId;
    getTdClient().send(req).then((status: TdObject): void => {
      const level = (status['level'] as number | undefined) ?? 0;
      const count = (status['boost_count'] as number | undefined) ?? 0;
      const next = (status['next_level_boost_count'] as number | undefined) ?? 0;
      promptAction.showDialog({
        title: '助力频道',
        message: `当前等级 Lv.${level} · ${count} 次助力` +
          (next > 0 ? `，升级还需 ${Math.max(0, next - count)} 次` : ''),
        buttons: [
          { text: '取消', color: '#8E8E93' },
          { text: '助力', color: $r('app.color.primary') }
        ]
      }).then((result): void => {
        if (result.index !== 1) { return; }
        this.performBoost();
      }).catch((): void => {});
    }).catch((error: TdError): void => {
      console.error(`ChatProfilePage.boostStatus failed: ${error.message}`);
      promptAction.showToast({ message: '获取助力信息失败', duration: 1700 });
    });
  }

  private performBoost(): void {
    getTdClient().send({ '@type': 'getAvailableChatBoostSlots' } as TdRequest)
      .then((slots: TdObject): void => {
        const list = (slots['slots'] as TdObject[] | undefined) ?? [];
        const usable = list.find((slot: TdObject): boolean =>
          ((slot['currently_boosted_chat_id'] as number | undefined) ?? 0) !== this.chatId);
        if (usable === undefined) {
          promptAction.showToast({
            message: '没有可用的助力名额（助力需要 Telegram Premium）', duration: 2200
          });
          return;
        }
        const req: TdRequest = { '@type': 'boostChat' };
        req['chat_id'] = this.chatId;
        req['slot_ids'] = [(usable['slot_id'] as number | undefined) ?? 0];
        getTdClient().send(req).then((): void => {
          promptAction.showToast({ message: '助力成功', duration: 1600 });
        }).catch((error: TdError): void => {
          console.error(`ChatProfilePage.boost failed: ${error.message}`);
          promptAction.showToast({ message: '助力失败，请稍后重试', duration: 1800 });
        });
      }).catch((error: TdError): void => {
        console.error(`ChatProfilePage.boostSlots failed: ${error.message}`);
        promptAction.showToast({ message: '获取助力名额失败', duration: 1700 });
      });
  }

  // TDLib's report flow is iterative: an empty option first, then the server
  // returns the reason list; picking one either finishes or asks for text.
  private reportChat(optionId: string): void {
    const req: TdRequest = { '@type': 'reportChat' };
    req['chat_id'] = this.chatId;
    req['option_id'] = optionId;
    req['message_ids'] = [];
    req['text'] = '';
    getTdClient().send(req, 15000).then((result: TdObject): void => {
      const typeName = (result['@type'] as string | undefined) ?? '';
      if (typeName === 'reportChatResultOk') {
        promptAction.showToast({ message: '举报已提交', duration: 1700 });
        return;
      }
      if (typeName === 'reportChatResultTextRequired') {
        // Optional-comment step: submit without extra text.
        const nextId = (result['option_id'] as string | undefined) ?? '';
        if (((result['is_optional'] as boolean | undefined) ?? false) && nextId !== optionId) {
          this.reportChat(nextId);
        } else {
          promptAction.showToast({ message: '该举报类型需要补充说明，暂不支持', duration: 2000 });
        }
        return;
      }
      if (typeName === 'reportChatResultOptionRequired') {
        const options = (result['options'] as TdObject[] | undefined) ?? [];
        if (options.length === 0) {
          promptAction.showToast({ message: '当前不支持举报该会话', duration: 1800 });
          return;
        }
        const shown = options.slice(0, 6);
        promptAction.showActionMenu({
          title: (result['title'] as string | undefined) ?? '选择举报原因',
          buttons: shown.map((option: TdObject): promptAction.Button =>
            ({ text: (option['text'] as string | undefined) ?? '', color: '#E5484D' } as promptAction.Button)) as
            [promptAction.Button, promptAction.Button?, promptAction.Button?,
              promptAction.Button?, promptAction.Button?, promptAction.Button?]
        }).then((chosen): void => {
          const option = shown[chosen.index];
          if (option !== undefined) {
            this.reportChat((option['id'] as string | undefined) ?? '');
          }
        }).catch((): void => {});
        return;
      }
      promptAction.showToast({ message: '举报流程暂不支持该步骤', duration: 1800 });
    }).catch((error: TdError): void => {
      console.error(`ChatProfilePage.report failed: ${error.message}`);
      promptAction.showToast({ message: '举报失败，请稍后重试', duration: 1800 });
    });
  }

  private loadInvitePreview(): void {
    if (this.inviteLink === '') {
      return;
    }
    this.pageState = 'loading';
    this.errorText = '';
    this.membershipState = 'checking';
    const req: TdRequest = { '@type': 'checkChatInviteLink' };
    req['invite_link'] = this.inviteLink;
    getTdClient().send(req).then((info: TdObject): void => {
      const resolvedChatId = (info['chat_id'] as number | undefined) ?? 0;
      if (resolvedChatId !== 0) {
        this.chatId = resolvedChatId;
        this.startStore();
        return;
      }
      this.title = (info['title'] as string | undefined) ?? 'Telegram 群组';
      this.initials = this.title !== '' ? this.title.substring(0, 1).toUpperCase() : '?';
      this.description = (info['description'] as string | undefined) ?? '';
      const count = (info['member_count'] as number | undefined) ?? 0;
      const inviteType = (info['type'] as TdObject | undefined)
        ?? (info['chat_type'] as TdObject | undefined);
      const inviteTypeName = (inviteType?.['@type'] as string | undefined) ?? '';
      this.isChannel = ((info['is_channel'] as boolean | undefined) ?? false)
        || inviteTypeName.indexOf('Channel') >= 0
        || inviteTypeName.indexOf('channel') >= 0;
      this.subtitle = count > 0
        ? `${count} 位${this.isChannel ? '订阅者' : '成员'}`
        : (this.isChannel ? '频道' : '群组');
      this.joinByRequest =
        (info['creates_join_request'] as boolean | undefined) ?? false;
      this.membershipState = 'joinable';
      this.membersState = 'restricted';
      this.availableTabKeys = [];
      this.tabsState = 'ready';
      this.pageState = 'ready';
    }).catch((e: TdError): void => {
      console.error(`ChatProfilePage.checkChatInviteLink failed: ${e.message}`);
      this.pageState = 'error';
      this.errorText = '邀请链接无效、已过期或无法访问';
      this.membershipState = 'blocked';
    });
  }

  private joinChat(): void {
    if (this.joining || this.membershipState !== 'joinable' || this.joinRequestSent) {
      return;
    }
    this.joining = true;
    const req: TdRequest = {
      '@type': this.inviteLink !== '' ? 'joinChatByInviteLink' : 'joinChat'
    };
    if (this.inviteLink !== '') {
      req['invite_link'] = this.inviteLink;
    } else {
      req['chat_id'] = this.chatId;
    }
    getTdClient().send(req).then((chat: TdObject): void => {
      this.joining = false;
      const joinedChatId = (chat['id'] as number | undefined) ?? this.chatId;
      if (joinedChatId !== 0 && this.chatId === 0) {
        this.chatId = joinedChatId;
      }
      if (this.joinByRequest) {
        this.joinRequestSent = true;
        promptAction.showToast({ message: '加入申请已发送', duration: 1800 });
        return;
      }
      this.membershipState = 'writable';
      this.justJoined = true;
      promptAction.showToast({
        message: this.isChannel ? '已加入频道' : '已加入群组',
        duration: 1500
      });
      if (this.chatId !== 0 && this.store === null) {
        this.startStore();
      }
    }).catch((e: TdError): void => {
      this.joining = false;
      console.error(`ChatProfilePage.join failed: ${e.message}`);
      promptAction.showToast({ message: '加入失败，链接可能已失效', duration: 1800 });
    });
  }

  private primaryActionLabel(): string {
    if (this.joinRequestSent) {
      return '已申请';
    }
    if (this.membershipState === 'checking') {
      return '加载中';
    }
    if (this.membershipState === 'blocked') {
      return '无法加入';
    }
    if (this.membershipState === 'joinable') {
      if (this.joining) {
        return '正在加入';
      }
      if (this.joinByRequest) {
        return '申请加入';
      }
      return this.isChannel ? '加入频道' : '加入群组';
    }
    return '消息';
  }

  private toggleMute(): void {
    const willMute = !this.isMuted;
    // 统一走 ChatActions：那里用的是服务端会接受的静音时长，并且带
    // "会话未加载则先 getChat 再重试"的兜底。
    const pending = setMute(this.chatId, willMute ? MUTE_LONG : 0);
    // updateChatNotificationSettings 也会确认，但先本地翻转，按钮不必等往返。
    this.isMuted = willMute;
    pending.then((success: boolean): void => {
      if (success) {
        promptAction.showToast({ message: willMute ? '已静音' : '已取消静音', duration: 1500 });
      } else {
        this.isMuted = !willMute;
      }
    });
  }

  private openMemberProfile(userId: number): void {
    const params: Record<string, Object> = { 'userId': userId };
    router.pushUrl({ url: 'pages/profile/ProfilePage', params: params });
  }

  private moveDetailIndicator(index: number): void {
    const tabs = this.visibleTabs();
    if (index < 0 || index >= tabs.length) {
      return;
    }
    const width = this.detailTabWs[index] ?? 0;
    if (width <= 0) {
      return;
    }
    this.detailIndicatorX = this.detailTabXs[index] ?? 8;
    this.detailIndicatorW = width;
  }

  private ensureDetailTabVisible(index: number): void {
    const x = this.detailTabXs[index] ?? 0;
    const width = this.detailTabWs[index] ?? 0;
    if (width <= 0 || this.detailTabViewW <= 0) {
      return;
    }
    const offset = this.tabScroller.currentOffset().xOffset;
    let target = -1;
    if (x < offset + 8) {
      target = Math.max(0, x - 8);
    } else if (x + width > offset + this.detailTabViewW - 8) {
      target = x + width - this.detailTabViewW + 8;
    }
    if (target >= 0) {
      this.tabScroller.scrollTo({
        xOffset: target,
        yOffset: 0,
        animation: {
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 200),
          curve: Curve.EaseOut
        }
      });
    }
  }

  private detailTabLabelWidth(label: string): number {
    let width = 0;
    for (let i = 0; i < label.length; i++) {
      width += label.charCodeAt(i) > 127 ? 14 : 8;
    }
    return Math.max(14, width);
  }

  private detailTabBarWidth(): number {
    let width = 16; // inner Row's left/right padding
    for (const tab of this.visibleTabs()) {
      width += this.detailTabLabelWidth(tab.label) + 26; // pill padding + 2vp gap
    }
    return Math.min(Math.max(58, width), Math.max(58, this.screenW - 16));
  }

  private selectTab(index: number): void {
    const tabs = this.visibleTabs();
    if (index < 0 || index >= tabs.length || index === this.selectedTab) {
      return;
    }
    animateTo({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
      curve: Curve.EaseOut
    }, (): void => {
      this.selectedTab = index;
      this.moveDetailIndicator(index);
    });
    this.ensureDetailTabVisible(index);
    if (this.store !== null) {
      this.store.selectContentTab(tabs[index].key);
    } else if (index > 0) {
      this.contentItems = [];
      this.contentState = 'ready';
      this.contentHasMore = false;
    }
  }

  private handleDetailTabPan(offsetX: number): void {
    if (Math.abs(offsetX) < 42) {
      return;
    }
    if (offsetX < 0) {
      this.selectTab(this.selectedTab + 1);
    } else {
      this.selectTab(this.selectedTab - 1);
    }
  }

  private openContentMessage(messageId: number): void {
    if (this.chatId === 0 || messageId <= 0) {
      return;
    }
    const params: Record<string, Object> = {
      'chatId': this.chatId,
      'jumpTo': messageId
    };
    router.pushUrl({ url: 'pages/chat/ChatPage', params: params });
  }

  private currentTabLabel(): string {
    const tabs = this.visibleTabs();
    return tabs.length > 0 && this.selectedTab < tabs.length
      ? tabs[this.selectedTab].label : '';
  }

  private emptyStateText(): string {
    if (this.store === null && this.membershipState !== 'writable') {
      return `加入后可查看${this.currentTabLabel()}`;
    }
    const label = this.currentTabLabel();
    if (this.currentTabKey() === PROFILE_TAB_GIFTS && this.contentHasMore) {
      return '最近的消息中没有礼物';
    }
    return `暂无${label}内容`;
  }

  private visibleTabs(): ProfileTabItem[] {
    if (this.tabsState !== 'ready') {
      return [];
    }
    return PROFILE_TABS.filter((tab: ProfileTabItem): boolean =>
      this.availableTabKeys.indexOf(tab.key) >= 0);
  }

  private currentTabKey(): string {
    const tabs = this.visibleTabs();
    return tabs.length > 0 && this.selectedTab < tabs.length
      ? tabs[this.selectedTab].key : '';
  }

  private openLiveViewer(groupCallId: number, isRtmpStream: boolean): void {
    const params: Record<string, Object> = {
      'groupCallId': groupCallId,
      'chatId': this.chatId
    };
    router.pushUrl({
      url: isRtmpStream
        ? 'pages/chat/RtmpLiveStreamViewerPage'
        : 'pages/chat/LiveStreamViewerPage',
      params: params
    });
  }

  private async openExistingLive(): Promise<void> {
    if (this.liveGroupCallId <= 0 || this.creatingLive) { return; }
    this.creatingLive = true;
    const groupCallId = this.liveGroupCallId;
    try {
      let groupCall = await getGroupCall(getTdClient(), groupCallId);
      let active = (groupCall['is_active'] as boolean | undefined) ?? false;
      const scheduledStartDate =
        (groupCall['scheduled_start_date'] as number | undefined) ?? 0;
      if (!active && scheduledStartDate > 0 && this.canManageVideoChats) {
        await startScheduledVideoChat(getTdClient(), groupCallId);
        groupCall = await getGroupCall(getTdClient(), groupCallId);
        active = (groupCall['is_active'] as boolean | undefined) ?? false;
      }
      if (!active) {
        promptAction.showToast({ message: '直播尚未开始或已经结束', duration: 1600 });
        return;
      }
      const isRtmp = (groupCall['is_rtmp_stream'] as boolean | undefined) ?? false;
      this.openLiveViewer(groupCallId, isRtmp);
    } catch (caught) {
      const error = caught as TdError;
      promptAction.showToast({ message: `进入直播失败：${error.message}`, duration: 1800 });
    } finally {
      this.creatingLive = false;
    }
  }

  private createLiveMenu(): void {
    if (!this.canManageVideoChats || this.creatingLive) { return; }
    // A live call already exists: admins can either join it or end it for
    // everyone (endGroupCall), which plain "leave" never does.
    if (this.liveGroupCallId > 0) {
      promptAction.showActionMenu({
        title: '直播进行中',
        buttons: [
          { text: '进入直播', color: '#3390EC' },
          { text: '结束直播（所有人）', color: '#E5484D' }
        ]
      }).then((result): void => {
        if (result.index === 0) {
          this.openExistingLive();
        } else if (result.index === 1) {
          this.confirmEndLive();
        }
      }).catch((): void => {});
      return;
    }
    promptAction.showActionMenu({
      title: '发起直播',
      buttons: [
        { text: '多人语音/视频直播', color: '#3390EC' },
        { text: '单向频道直播（RTMP）', color: '#3390EC' }
      ]
    }).then((result): void => {
      if (result.index === 0) {
        this.createAndOpenLive(false);
      } else if (result.index === 1) {
        this.createAndOpenLive(true);
      }
    }).catch((): void => {});
  }

  private confirmEndLive(): void {
    const groupCallId = this.liveGroupCallId;
    if (groupCallId <= 0) { return; }
    promptAction.showDialog({
      title: '结束直播',
      message: '直播将对所有参与者结束，无法恢复。',
      buttons: [
        { text: '取消', color: '#8E8E93' },
        { text: '结束', color: '#E5484D' }
      ]
    }).then((result): void => {
      if (result.index !== 1) { return; }
      endGroupCall(getTdClient(), groupCallId).then((): void => {
        this.liveGroupCallId = 0;
        promptAction.showToast({ message: '直播已结束', duration: 1500 });
      }).catch((error: TdError): void => {
        console.error(`ChatProfilePage.endLive failed: ${error.message}`);
        promptAction.showToast({ message: '结束直播失败，请重试', duration: 1700 });
      });
    }).catch((): void => {});
  }

  private async createAndOpenLive(isRtmpStream: boolean): Promise<void> {
    if (this.creatingLive || !this.canManageVideoChats) { return; }
    this.creatingLive = true;
    try {
      const groupCallId = await createVideoChat(getTdClient(), this.chatId, isRtmpStream);
      if (groupCallId <= 0) {
        throw new Error('Telegram 未返回直播间标识');
      }
      this.liveGroupCallId = groupCallId;
      this.openLiveViewer(groupCallId, isRtmpStream);
    } catch (caught) {
      const error = caught as Error;
      promptAction.showToast({ message: `发起直播失败：${error.message}`, duration: 2000 });
    } finally {
      this.creatingLive = false;
    }
  }

  @Builder
  circleButton(symbol: string, onTap: () => void) {
    Row() {
      SymbolGlyph($r(symbol)).fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
    }
    .width(40).height(40).borderRadius(20).backgroundColor($r('app.color.surface'))
    .justifyContent(FlexAlign.Center)
    .shadow({ radius: 4, color: '#12000000', offsetX: 0, offsetY: 1 })
    .onClick(onTap);
  }

  @Builder
  actionButton(symbol: string, label: string, onTap: () => void) {
    Column({ space: 5 }) {
      SymbolGlyph($r(symbol)).fontSize(22).fontColor([COLOR_PRIMARY]);
      Text(label).fontSize(12).fontColor(COLOR_PRIMARY);
    }
    .layoutWeight(1).height(62)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
    .onClick(onTap);
  }

  @Builder
  primaryActionButton() {
    Column({ space: 5 }) {
      if (this.joinRequestSent) {
        SymbolGlyph($r('sys.symbol.checkmark_circle')).fontSize(22).fontColor([COLOR_PRIMARY]);
      } else if (this.membershipState === 'joinable') {
        SymbolGlyph($r('sys.symbol.person_badge_plus')).fontSize(22).fontColor([COLOR_PRIMARY]);
      } else {
        SymbolGlyph($r('sys.symbol.message')).fontSize(22).fontColor([COLOR_PRIMARY]);
      }
      Text(this.primaryActionLabel()).fontSize(12).fontColor(COLOR_PRIMARY);
    }
    .layoutWeight(1).height(62)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
    .opacity(this.membershipState === 'blocked' || this.membershipState === 'checking' ? 0.55 : 1)
    .enabled(this.membershipState === 'writable' ||
      (this.membershipState === 'joinable' && !this.joining && !this.joinRequestSent))
    .onClick((): void => {
      if (this.membershipState === 'writable') {
        this.openChat();
      } else {
        this.joinChat();
      }
    });
  }

  // Dedicated builder (not the param-based actionButton): @Builder value
  // params don't re-evaluate on @State change, so the icon/label would stick.
  @Builder
  muteButton() {
    Column({ space: 5 }) {
      Stack() {
        if (this.isMuted) {
          SymbolGlyph($r('sys.symbol.bell')).fontSize(22).fontColor([COLOR_PRIMARY])
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.scale({ x: 0.4, y: 0.4 }))
              .animation({
                duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 220), curve: Curve.EaseOut
              }));
        } else {
          SymbolGlyph($r('sys.symbol.bell_slash')).fontSize(22).fontColor([COLOR_PRIMARY])
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.scale({ x: 0.4, y: 0.4 }))
              .animation({
                duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 220), curve: Curve.EaseOut
              }));
        }
      }.height(24);
      Text(this.isMuted ? '取消静音' : '静音').fontSize(12).fontColor(COLOR_PRIMARY);
    }
    .layoutWeight(1).height(62)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
    .onClick(() => { this.toggleMute(); });
  }

  @Builder
  liveButton() {
    Column({ space: 5 }) {
      SymbolGlyph($r('sys.symbol.camera')).fontSize(22).fontColor([COLOR_PRIMARY]);
      Text(this.creatingLive ? '处理中' : '直播')
        .fontSize(12).fontColor(COLOR_PRIMARY);
    }
    .layoutWeight(1).height(62)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
    .enabled(!this.creatingLive)
    .opacity(this.creatingLive ? 0.62 : 1)
    .onClick((): void => { this.createLiveMenu(); });
  }

  @Builder
  sectionDivider() {
    Divider().color($r('app.color.divider')).strokeWidth(0.7);
  }

  @Builder
  header() {
    Column({ space: 8 }) {
      Row() {
        this.circleButton('sys.symbol.chevron_left', () => { router.back(); });
        Blank().layoutWeight(1);
        // Top-right is the leave action; everything else lives in the
        // actions-row 更多 menu.
        this.circleButton('sys.symbol.arrow_right_and_square', () => {
          if (this.chatId !== 0) { this.leaveCurrentChat(); }
        });
      }.width('100%').padding({ left: 12, right: 12 });
      AvatarView({
        avatarPath: this.avatarPath, initials: this.initials,
        colorSeed: this.chatId, avatarSize: 100,
        animPath: this.avatarAnimPath
      })
        // 记下点击处的屏幕坐标，查看器据此决定放大/缩回的中心点。
        .onClick((event: ClickEvent): void => {
          if (this.avatarPath !== '') {
            this.avatarTapX = event.windowX;
            this.avatarTapY = event.windowY;
            this.viewerAvatarPath = this.avatarPath;
          }
        });
      Text(this.title)
        .fontSize(20).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '86%' });
      if (this.subtitle !== '') {
        Text(this.subtitle).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      }
    }
    .width('100%')
    .padding({ top: this.topSafe + 8 });
  }

  @Builder
  // Two fixed rows of at most four buttons each: primary actions on top,
  // secondary/administrative ones below. Seven buttons never fit one row.
  actionsRow() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        // 发消息 is redundant — tapping back returns to the chat. The primary
        // button only appears while joining is still the pending action.
        if (this.membershipState !== 'writable') {
          this.primaryActionButton();
        }
        if (this.chatId !== 0) {
          this.muteButton();
          this.actionButton('sys.symbol.magnifyingglass', '搜索', () => { this.openSearchInChat(); });
          if (this.canManageVideoChats) {
            this.liveButton();
          }
        }
      }.width('100%');
      if (this.chatId !== 0) {
        Row({ space: 8 }) {
          if (!this.isChannel) {
            this.actionButton('sys.symbol.paintpalette', '主题', () => {
              const params: Record<string, Object> = { 'chatId': this.chatId };
              router.pushUrl({ url: 'pages/main/ChatThemePage', params })
                .catch((error: Error): void => {
                  console.error(`ChatProfilePage.openTheme failed: ${error.message}`);
                });
            });
          }
          // Only creators / admins with real rights see the management entry.
          if (this.canManageChat) {
            this.actionButton('sys.symbol.gearshape', '管理', () => {
              const params: Record<string, Object> = { 'chatId': this.chatId };
              router.pushUrl({ url: 'pages/main/GroupAdminPage', params })
                .catch((error: Error): void => {
                  console.error(`ChatProfilePage.openAdmin failed: ${error.message}`);
                });
            });
          }
          this.actionButton('sys.symbol.bolt', '助力', () => { this.boostChat(); });
          this.actionButton('sys.symbol.flag', '举报', () => { this.reportChat(''); });
        }.width('100%');
      }
    }
    .width('100%').padding({ left: 12, right: 12, top: 14 });
  }

  @Builder
  pageStateCard() {
    Column({ space: 10 }) {
      if (this.pageState === 'loading') {
        LoadingProgress().width(28).height(28).color(COLOR_PRIMARY);
        Text('正在获取详情…').fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
      } else {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(28).fontColor([COLOR_TEXT_SECONDARY]);
        Text(this.errorText !== '' ? this.errorText : '无法加载详情')
          .fontSize(14).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center);
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(16).fontColor([COLOR_PRIMARY]);
          Text('重试').fontSize(14).fontColor(COLOR_PRIMARY);
        }
        .height(36).padding({ left: 14, right: 14 }).borderRadius(18)
        .backgroundColor('#123390EC')
        .onClick((): void => {
          if (this.inviteLink !== '') {
            this.loadInvitePreview();
          } else {
            this.startStore();
          }
        });
      }
    }
    .width('100%').padding({ top: 28, bottom: 28, left: 16, right: 16 })
    .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
    .margin({ left: 12, right: 12, top: 16 });
  }

  @Builder
  infoCard() {
    Column() {
      Column() {
        if (this.description !== '') {
          Column({ space: 2 }) {
            ExpandableText({ content: this.description });
            Text('简介').fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%').padding({ top: 8, bottom: 8 });
        }
        if (this.chatUsername !== '') {
          if (this.description !== '') {
            this.sectionDivider();
          }
          Row() {
            Column({ space: 2 }) {
              Text(`@${this.chatUsername}`).fontSize(15).fontColor(COLOR_PRIMARY).copyOption(CopyOptions.LocalDevice);
              Text('链接').fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
            }.alignItems(HorizontalAlign.Start).layoutWeight(1);
            SymbolGlyph($r('sys.symbol.qrcode')).fontSize(22).fontColor([COLOR_TEXT_SECONDARY])
              .onClick(() => { this.openQr(); });
          }
          .width('100%').padding({ top: 8, bottom: 8 })
          .alignItems(VerticalAlign.Center);
        }
        if (this.description === '' && this.chatUsername === '') {
          Text('暂无资料').fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
            .padding({ top: 10, bottom: 10 });
        }
      }
      .width('100%').padding({ left: 12, right: 12, top: 4, bottom: 4 })
      .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
      .alignItems(HorizontalAlign.Start);
    }
    .margin({ left: 12, right: 12, top: 12 });
  }

  @Builder
  detailTabBar() {
    Column() {
      Scroll(this.tabScroller) {
        Stack({ alignContent: Alignment.TopStart }) {
          Row()
            .width(this.detailIndicatorW)
            .height(DETAIL_TAB_INDICATOR_HEIGHT)
            .borderRadius(DETAIL_TAB_INDICATOR_HEIGHT / 2)
            .backgroundColor(COLOR_TAB_PILL_BG)
            .position({
              x: this.detailIndicatorX,
              y: (DETAIL_TAB_BAR_HEIGHT - DETAIL_TAB_INDICATOR_HEIGHT) / 2
            });
          Row() {
            ForEach(this.visibleTabs(), (tab: ProfileTabItem, index: number) => {
              Row() {
                Text(tab.label)
                  .fontSize(14)
                  .fontWeight(index === this.selectedTab ? FontWeight.Medium : FontWeight.Normal)
                  .fontColor(index === this.selectedTab
                    ? COLOR_TAB_SELECTED : COLOR_TAB_UNSELECTED)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
              }
              .height(DETAIL_TAB_BAR_HEIGHT)
              .padding({ left: 12, right: 12 })
              .margin({ right: 2 })
              .borderRadius(DETAIL_TAB_BAR_HEIGHT / 2)
              .stateStyles({ normal: this.tabNormalStyle, pressed: this.tabPressedStyle })
              .onAreaChange((_old: Area, area: Area): void => {
                this.detailTabXs[index] = area.position.x as number;
                this.detailTabWs[index] = area.width as number;
                if (index === this.selectedTab) {
                  this.moveDetailIndicator(index);
                  this.ensureDetailTabVisible(index);
                }
              })
              .onClick((): void => { this.selectTab(index); });
            }, (tab: ProfileTabItem) => tab.key);
          }
          .padding({ left: 8, right: 8 })
          .height(DETAIL_TAB_BAR_HEIGHT);
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .align(Alignment.Start)
      .width('100%')
      .onAreaChange((_old: Area, area: Area): void => {
        this.detailTabViewW = area.width as number;
        this.ensureDetailTabVisible(this.selectedTab);
      });
    }
    .height(DETAIL_TAB_BAR_HEIGHT)
    .width(this.detailTabBarWidth())
    .backgroundColor(CARD_BG)
    .borderRadius(DETAIL_TAB_BAR_HEIGHT / 2)
    .clip(true)
    .alignSelf(ItemAlign.Center)
    .margin({ left: 8, right: 8, bottom: 6 });
  }

  @Builder
  tabsLoadingCard() {
    Row({ space: 9 }) {
      LoadingProgress().width(18).height(18).color(COLOR_PRIMARY);
      Text('正在整理共享内容').fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
    }
    .width('calc(100% - 24vp)').height(52)
    .margin({ left: 12, right: 12, top: 12, bottom: 20 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS);
  }

  @Builder
  membersContent() {
    Column() {
      if (this.members.length > 0) {
        ForEach(this.members, (m: MemberItem, idx: number) => {
          Column() {
            Row({ space: 10 }) {
              AvatarView({ avatarPath: m.avatarPath, initials: m.initials,
                colorSeed: m.userId, avatarSize: 42 });
              Column({ space: 2 }) {
                Text(m.name).fontSize(15).fontColor(COLOR_TEXT_PRIMARY)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                Text(m.status).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
              }.alignItems(HorizontalAlign.Start).layoutWeight(1);
              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(13).fontColor([COLOR_TEXT_SECONDARY]);
            }
            .width('100%').padding({ left: 12, right: 10, top: 8, bottom: 8 })
            .alignItems(VerticalAlign.Center)
            .stateStyles({ normal: this.contentRowNormalStyle, pressed: this.contentRowPressedStyle })
            .onClick((): void => { this.openMemberProfile(m.userId); });
            if (idx < this.members.length - 1) {
              Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 64 });
            }
          }.width('100%');
        }, (m: MemberItem) => `${m.userId}_${m.avatarPath}`);
        if (this.store !== null && this.store.hasMoreMembers) {
          Row({ space: 8 }) {
            LoadingProgress().width(18).height(18).color(COLOR_PRIMARY);
            Text('正在加载更多成员').fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          }.height(52).justifyContent(FlexAlign.Center).width('100%');
        }
      } else if (this.membersState === 'loading') {
        this.inlineState('loading', '正在获取成员…');
      } else if (this.membersState === 'restricted') {
        this.inlineState('restricted', this.isChannel
          ? 'Telegram 未向当前账号开放完整订阅者列表'
          : '当前账号无权查看成员列表');
      } else if (this.membersState === 'error') {
        this.inlineState('error', '成员列表加载失败');
      } else {
        this.inlineState('empty', '暂无可显示的成员');
      }
    }
    .width('calc(100% - 24vp)')
    .margin({ left: 12, right: 12, top: 10, bottom: 24 })
    .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS).clip(true);
  }

  @Builder
  inlineState(kind: string, text: string) {
    Column({ space: 10 }) {
      if (kind === 'loading') {
        LoadingProgress().width(26).height(26).color(COLOR_PRIMARY);
      } else if (kind === 'error') {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(26).fontColor([COLOR_TEXT_SECONDARY]);
      } else if (kind === 'restricted') {
        SymbolGlyph($r('sys.symbol.lock_fill'))
          .fontSize(24).fontColor([COLOR_TEXT_SECONDARY]);
      } else {
        SymbolGlyph($r('sys.symbol.message'))
          .fontSize(25).fontColor([COLOR_TEXT_SECONDARY]);
      }
      Text(text).fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
        .textAlign(TextAlign.Center).maxLines(2);
    }
    .width('100%').height(154).justifyContent(FlexAlign.Center)
    .padding({ left: 28, right: 28 });
  }

  @Builder
  contentPlaceholder() {
    Column({ space: 10 }) {
      if (this.contentState === 'loading') {
        LoadingProgress().width(28).height(28).color(COLOR_PRIMARY);
        Text(`正在加载${this.currentTabLabel()}…`)
          .fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
      } else if (this.contentState === 'error') {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(28).fontColor([COLOR_TEXT_SECONDARY]);
        Text(this.contentErrorText !== '' ? this.contentErrorText : '加载失败')
          .fontSize(14).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center);
        Text('重试').fontSize(14).fontColor(COLOR_PRIMARY)
          .height(34).padding({ left: 16, right: 16 }).textAlign(TextAlign.Center)
          .backgroundColor('#123390EC').borderRadius(17)
          .onClick((): void => { if (this.store !== null) { this.store.retryContent(); } });
      } else {
        SymbolGlyph($r(this.currentTabKey() === PROFILE_TAB_GIFTS
          ? 'sys.symbol.gift' : 'sys.symbol.message'))
          .fontSize(27).fontColor([COLOR_TEXT_SECONDARY]);
        Text(this.emptyStateText()).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
        if (this.currentTabKey() === PROFILE_TAB_GIFTS && this.contentHasMore) {
          Text('继续查找更早消息').fontSize(14).fontColor(COLOR_PRIMARY)
            .height(34).padding({ left: 16, right: 16 }).textAlign(TextAlign.Center)
            .backgroundColor('#123390EC').borderRadius(17)
            .onClick((): void => { if (this.store !== null) { this.store.loadMoreContent(); } });
        }
      }
    }
    .width('calc(100% - 24vp)').height(188)
    .margin({ left: 12, right: 12, top: 10, bottom: 24 })
    .padding({ left: 24, right: 24 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS);
  }

  private mediaCellSize(): number {
    return Math.max(92, (this.screenW - 30) / 3);
  }

  @Builder
  mediaContent() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
      ForEach(this.contentItems, (item: ProfileContentItem) => {
        Stack({ alignContent: Alignment.BottomEnd }) {
          if (item.thumbPath !== '') {
            Image(`file://${item.thumbPath}`).width('100%').height('100%')
              .objectFit(ImageFit.Cover);
          } else {
            Column() {
              SymbolGlyph($r(item.isVideo ? 'sys.symbol.video_fill' : 'sys.symbol.photo_fill'))
                .fontSize(26).fontColor([COLOR_TEXT_SECONDARY]);
            }
            .width('100%').height('100%').justifyContent(FlexAlign.Center)
            .backgroundColor($r('app.color.surface_alt'));
          }
          if (item.isVideo) {
            Row({ space: 3 }) {
              SymbolGlyph($r('sys.symbol.play_fill')).fontSize(10).fontColor([Color.White]);
              if (item.duration !== '') {
                Text(item.duration).fontSize(11).fontColor(Color.White);
              }
            }
            .padding({ left: 5, right: 5, top: 2, bottom: 2 })
            .margin({ right: 5, bottom: 5 })
            .backgroundColor('#70000000').borderRadius(8);
          }
        }
        .width(this.mediaCellSize()).height(this.mediaCellSize())
        .margin({ right: 2, bottom: 2 })
        .stateStyles({ normal: this.tabNormalStyle, pressed: this.tabPressedStyle })
        .onClick((): void => { this.openContentMessage(item.messageId); });
      }, (item: ProfileContentItem) => `${item.messageId}_${item.thumbPath}`);
    }
    .width('calc(100% - 24vp)')
    .margin({ left: 12, right: 12, top: 10 })
    .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS).clip(true);
    this.paginationFooter();
  }

  private contentIcon(item: ProfileContentItem): string {
    if (item.contentType === 'messageDocument') {
      return 'sys.symbol.doc_text';
    }
    if (item.contentType === 'messageVoiceNote') {
      return 'sys.symbol.mic';
    }
    if (item.contentType === 'messageAudio') {
      return 'sys.symbol.play_fill';
    }
    if (item.contentType === 'messagePoll') {
      return 'sys.symbol.checkmark_circle';
    }
    if (item.contentType === 'messageAnimation' || item.contentType === 'messageVideoNote') {
      return 'sys.symbol.video';
    }
    if (item.contentType.indexOf('Gift') >= 0 || item.contentType.indexOf('gift') >= 0) {
      return 'sys.symbol.gift';
    }
    if (this.currentTabKey() === PROFILE_TAB_LINKS) {
      return 'sys.symbol.link';
    }
    return 'sys.symbol.message';
  }

  @Builder
  contentList() {
    Column() {
      ForEach(this.contentItems, (item: ProfileContentItem, index: number) => {
        Column() {
          Row({ space: 11 }) {
            Stack() {
              if (item.thumbPath !== '') {
                Image(`file://${item.thumbPath}`).width(46).height(46)
                  .objectFit(ImageFit.Cover).borderRadius(10);
              } else {
                SymbolGlyph($r(this.contentIcon(item))).fontSize(22).fontColor([COLOR_PRIMARY]);
              }
            }
            .width(46).height(46).borderRadius(10)
            .backgroundColor($r('app.color.surface_alt'));
            Column({ space: 3 }) {
              Text(item.title).fontSize(15).fontWeight(FontWeight.Medium)
                .fontColor(COLOR_TEXT_PRIMARY).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis });
              if (item.preview !== '') {
                Text(item.preview).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
              }
              if (item.meta !== '') {
                Text(item.meta).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
              }
            }.alignItems(HorizontalAlign.Start).layoutWeight(1);
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(13).fontColor([COLOR_TEXT_SECONDARY]);
          }
          .width('100%').constraintSize({ minHeight: 64 })
          .padding({ left: 12, right: 10, top: 9, bottom: 9 })
          .stateStyles({ normal: this.contentRowNormalStyle, pressed: this.contentRowPressedStyle })
          .onClick((): void => { this.openContentMessage(item.messageId); });
          if (index < this.contentItems.length - 1) {
            Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 69 });
          }
        }.width('100%');
      }, (item: ProfileContentItem) => `${item.messageId}_${item.thumbPath}`);
    }
    .width('calc(100% - 24vp)')
    .margin({ left: 12, right: 12, top: 10 })
    .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS).clip(true);
    this.paginationFooter();
  }

  @Builder
  paginationFooter() {
    Row({ space: 8 }) {
      if (this.contentPaging) {
        LoadingProgress().width(18).height(18).color(COLOR_PRIMARY);
        Text('正在加载更多').fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      } else if (this.contentPagingError) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(16).fontColor([COLOR_PRIMARY]);
        Text('加载失败，点击重试').fontSize(13).fontColor(COLOR_PRIMARY);
      } else if (!this.contentHasMore && this.contentItems.length > 0) {
        Text('已经到底了').fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
      }
    }
    .width('100%').height(this.contentItems.length > 0 ? 54 : 0)
    .justifyContent(FlexAlign.Center)
    .onClick((): void => {
      if (this.contentPagingError && this.store !== null) {
        this.store.loadMoreContent();
      }
    });
  }

  @Builder
  selectedTabContent() {
    if (this.currentTabKey() === PROFILE_TAB_MEMBERS) {
      this.membersContent();
    } else if (this.contentState === 'loading' || this.contentState === 'error' ||
      (this.contentState === 'ready' && this.contentItems.length === 0)) {
      this.contentPlaceholder();
    } else if (this.currentTabKey() === PROFILE_TAB_MEDIA) {
      this.mediaContent();
    } else {
      this.contentList();
    }
  }

  build() {
    // 查看器需覆盖整页，故在滚动容器外再包一层 Stack。
    Stack() {
    Scroll() {
      Column() {
        this.header();
        if (this.pageState === 'ready') {
          this.actionsRow();
          this.infoCard();
          if (this.tabsState === 'loading') {
            this.tabsLoadingCard();
          } else if (this.visibleTabs().length > 0) {
            Column() {
              this.detailTabBar();
              Column() {
                this.selectedTabContent();
              }
              .width('100%')
              .priorityGesture(
                PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 12 })
                  .onActionEnd((event: GestureEvent): void => {
                    this.handleDetailTabPan(event.offsetX);
                  })
              );
            }
            .width('100%').margin({ top: 12 });
          }
        } else {
          this.pageStateCard();
        }
      }
      .width('100%');
    }
    .width('100%').height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .backgroundColor($r('app.color.page_bg'))
    .onReachEnd((): void => {
      if (this.store === null) {
        return;
      }
      if (this.currentTabKey() === PROFILE_TAB_MEMBERS) {
        this.store.loadMoreMembers();
      } else {
        this.store.loadMoreContent();
      }
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
    if (this.viewerAvatarPath !== '') {
      AvatarViewer({
        imagePath: this.viewerAvatarPath,
        originX: this.avatarTapX,
        originY: this.avatarTapY,
        onClose: (): void => { this.viewerAvatarPath = ''; }
      });
    }
    }
    .width('100%').height('100%');
  }
}
