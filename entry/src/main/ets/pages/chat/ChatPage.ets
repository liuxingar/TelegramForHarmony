import { router, promptAction } from '@kit.ArkUI';
import { DeleteMessagesDialog } from './DeleteMessagesDialog';
import { pasteboard } from '@kit.BasicServicesKit';
import { i18n } from '@kit.LocalizationKit';
import { PollOptionInfo } from '../../util/formatMsgContent';
import { getStickersForEmoji, rememberRecentSticker } from '../../store/StickerApi';
import { botMiniAppUrl, openMiniApp } from '../../store/BotApi';
import {
  InlineQueryPage, InlineResultRow, getInlineResults, sendInlineResult
} from '../../store/BotApi';
import { common, abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { geoLocationManager } from '@kit.LocationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PollComposeSheet } from './PollComposeSheet';
import { formatPreview } from '../../util/formatPreview';
import { ContactPickerSheet, PickedContact } from './ContactPickerSheet';
import { VideoNoteRecorderView } from './VideoNoteRecorderView';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { VoiceRecorder } from '../../services/VoiceRecorder';
import { formatDateSeparator } from '../../util/formatDateSeparator';
import { formatTime } from '../../util/formatTime';
import { fileOpenMimeType } from '../../util/fileMessage';
import { resolveEmojiStatus } from '../../util/emojiStatus';
import { TgsStickerView } from './TgsStickerView';
import { WebmStickerView } from './WebmStickerView';
import { EmojiPanel } from './EmojiPanel';
import { StickerItem } from './StickerPicker';
import { GifItem } from './GifPicker';
import { getVoicePlayback } from '../../services/VoicePlayback';
import { openLocalFile } from '../../util/openLocalFile';
import { saveMediaToGallery, saveFileToLocal } from '../../util/mediaSaver';
import { getTdClient, getUserStore, getChatStore, getChatThemeStore } from '../../tdkit/Globals';
import { fillColorsOf } from '../../util/backgroundPresentation';
import { MessageStore, MediaSendItem } from '../../store/MessageStore';
import { MessageEntry, buildMessageEntry } from '../../store/MessageEntry';
import { ReplyKeyboard, KeyboardBtn, KB_TEXT } from '../../store/ReplyKeyboard';
import { ChatEntry, computeInitials, isMutedFrom } from '../../store/ChatEntry';
import { MessageBubble } from './MessageBubble';
import { StreamingVideoPlayer } from './StreamingVideoPlayer';
import { setMediaViewerOrientation } from './LiveViewerUi';
import { AlbumGroupDataSource } from './AlbumGroupDataSource';
import { collapseAlbums, groupIndexOf, AlbumGroup } from '../../util/collapseAlbums';
import { AvatarView } from '../chatlist/AvatarView';
import {
  KEY_POWER_ACTIVE, KEY_POWER_CHAT_EFFECTS, KEY_POWER_EMOJI, KEY_POWER_EMOJI_REACTIONS,
  KEY_POWER_EFFECT_BACKGROUND, KEY_POWER_EFFECT_BLUR, KEY_POWER_EFFECT_MENU,
  KEY_POWER_EFFECT_REACTION, KEY_POWER_EFFECT_REPLY, KEY_POWER_PARTICLES,
  KEY_POWER_SMOOTH_TRANSITIONS, KEY_REDUCE_ANIM, KEY_SEND_BY_ENTER, powerAnimationDuration,
  powerFeatureEnabled, powerGroupAnimationDuration, powerGroupFeatureEnabled, autosaveEnabled
} from '../../store/AppSettings';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY, botButtonBg } from '../../util/theme';
import {
  normalizeTelegramLink, bareUsernameOf, inviteLinkOf, chatLinkActionOf,
  chatFolderInviteLinkOf, stickerSetLinkOf
} from '../../util/linkNav';
import {
  openTelegramLink, openInviteLink, openChatLinkAction, openChatFolderInviteLink, openStickerSetLink
} from '../../util/openTelegramLink';
import { openUrl } from '../../util/openUrl';
import {
  AvailableReactionSet, customEmojiReactionKey, parseAvailableReactions, reactionDisplayLabel,
  reactionKeyFrom, reactionTypeOf
} from '../../util/reactions';
import { resolveCustomEmojiThumbs } from '../../util/customEmojiThumbs';
import { openWebUrl } from '../../util/webBrowserNav';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { searchMentions, loadBotCommands, MentionItem, CommandItem } from '../../store/InputSuggestions';
import { floatingLiveWindow } from './LiveFloatingWindow';
import { MUTE_LONG, setMute } from '../../store/ChatActions';
import { liveLocation, LiveLocationState } from '../../services/LiveLocationService';

// One emoji-triggered sticker hint shown above the composer.
interface StickerSuggestion {
  fileId: number;
  thumbId: number;
  thumbPath: string;
}

const PINNED_SEG_MAX: number = 5;
// Scroll-to-bottom FAB: beyond this many groups from the end, reload the newest
// page instead of scrolling row by row through the loaded history.
const JUMP_RELOAD_THRESHOLD: number = 40;
// Grace period before an entered-from-global-search chat runs its in-chat search.
const SEARCH_ENTRY_DELAY_MS: number = 400;
const VIEWER_CHROME_BG: string = '#6e3e3e40';
const VIEWER_MIN_SCALE: number = 1;
const VIEWER_MAX_SCALE: number = 4;
const VIEWER_DOUBLE_TAP_SCALE: number = 2.5;
// 等上下文菜单收起再弹确认框：菜单是独立子窗口，收起过程中弹出的
// 对话框会挂死（Promise 既不 resolve 也不 reject）。
const MENU_DISMISS_MS: number = 150;
const NOW_SEC_TICK_MS: number = 30000;
const STICKER_FLY_MS: number = 260;
const STICKER_GHOST_SIDE: number = 92;
// 绝对像素半径。在高密度屏上 18 远达不到"糊掉"的观感。
const HEADER_BLUR_RADIUS: number = 140;
// 实时位置的上报间隔。Telegram 官方客户端也是分钟级——秒级上报既费电又没有
// 实际意义，收到的一方看到的地图精度远达不到那个粒度。

const CHAT_HEADER_ACTION_SIZE: number = 42;
const CHAT_HEADER_RADIUS: number = 22;
const CHAT_HEADER_NAV_GUARD_MS: number = 700;
const TOP_CARD_LOADING_DELAY_MS: number = 180;
const TOP_CARD_ACTION_GUARD_MS: number = 650;

// Contain-fitted display size (vp) of the fullscreen photo at 1x.
interface ViewerFit {
  w: number;
  h: number;
}
// Emoji offered in the full reaction picker (opened from the long-press menu's
// chevron). Ordered roughly like the official client's reaction sheet.
const REACTION_EMOJIS: string[] = [
  '❤️', '👍', '👎', '🔥', '🥰', '👏', '😁', '🤔', '🤯', '😱', '🤬', '😢',
  '🎉', '🤩', '🤮', '💩', '🙏', '👌', '🕊️', '🤡', '🥱', '🥴', '😍', '🐳',
  '❤️‍🔥', '🌚', '🌭', '💯', '🤣', '⚡', '🍌', '🏆', '💔', '🤨', '😐', '🍓',
  '🍾', '💋', '🖕', '😈', '😴', '😭', '🤓', '👻', '👀', '🎃', '🙈', '😇',
  '😨', '🤝', '✍️', '🤗', '🫡', '🎅', '🎄', '☃️', '💅', '🤪', '🗿', '🆒',
  '💘', '🙉', '🦄', '😘', '💊', '🙊', '😎', '👾', '🤷', '😡'
];

// 反应面板里的一枚自定义 emoji：位图路径为 '' 表示还在下载。
interface CustomEmojiOption {
  id: string;
  path: string;
}

@Entry
@Preview
@Component
struct ChatPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;  // ✅ 新增
  @StorageProp('keyboardHeightVp') @Watch('onKeyboardHeightChanged') keyboardH: number = 0;
  @StorageProp('appIsForeground') @Watch('onAppForegroundChanged') appIsForeground: boolean = true;
  @State messages: MessageEntry[] = [];
  @State messageLoadState: string = 'loading'; // loading | ready | error
  @State messageLoadError: string = '';
  @State olderLoadState: string = 'idle'; // idle | loading | error | end
  @State newerLoadState: string = 'idle'; // idle | loading | error | end
  @State visibleGroupCount: number = 0;
  // Rendered through the LazyForEach data source (incremental notifications keep
  // scroll position on prepend); the plain array mirror serves index lookups.
  // Keep the count reactive because groups itself is intentionally not @State.
  private groups: AlbumGroup[] = [];
  private groupsData: AlbumGroupDataSource = new AlbumGroupDataSource();
  @State subtitle: string = '';
  @State typingLabel: string = '';   // "×× 正在输入…" — overrides subtitle while live
  private typingSenders: Map<number, number> = new Map(); // senderId -> expiry ms
  private typingTimer: number = -1;
  private unsubChatAction: (() => void) | null = null;
  @State title: string = '';
  @State avatarPath: string = '';
  @State initials: string = '?';
  @State draft: string = '';
  // 聊天设置 → 回车键发送.
  @StorageProp(KEY_SEND_BY_ENTER) sendByEnter: boolean = false;
  @StorageProp('screenWidthVp') screenW: number = 360;
  @StorageProp(KEY_POWER_ACTIVE) powerSaving: boolean = false;
  @StorageProp(KEY_POWER_CHAT_EFFECTS) powerChatEffects: boolean = true;
  @StorageProp(KEY_POWER_EFFECT_BACKGROUND) powerBackgroundEffect: boolean = false;
  @StorageProp(KEY_POWER_PARTICLES) powerParticles: boolean = true;
  @StorageProp(KEY_POWER_EMOJI) powerEmoji: boolean = true;
  @StorageProp(KEY_POWER_EMOJI_REACTIONS) powerEmojiReactions: boolean = true;
  @StorageProp(KEY_REDUCE_ANIM) reduceAnimations: boolean = false;
  @State powerBackgroundPhase: boolean = false;
  // TDLib per-chat wallpaper. Solid/gradient fills render immediately;
  // wallpaper and pattern documents appear as soon as downloadFile completes.
  @State chatBackgroundCustom: boolean = false;
  @State chatBackgroundColors: string[] = [];
  @State chatBackgroundAngle: number = 180;
  @State chatBackgroundPath: string = '';
  @State chatBackgroundImageOpacity: number = 1;
  @State chatBackgroundDimming: number = 0;
  @State chatBackgroundBlurred: boolean = false;
  @State themeBubbleOutColor: string = '';
  private chatBackgroundFileId: number = 0;
  private chatBackgroundSignature: string = '';
  private chatBackgroundResolveSeq: number = 0;
  private unsubChatBackground: (() => void) | null = null;
  private unsubTranslatable: (() => void) | null = null;
  private unsubChatTheme: (() => void) | null = null;
  private unsubDefaultBackground: (() => void) | null = null;
  private unsubBackgroundFile: (() => void) | null = null;
  private powerBackgroundTimer: number = -1;
  private readonly powerParticleIds: number[] = [0, 1, 2, 3, 4, 5, 6, 7];
  @State replyToId: number = 0;      // message being replied to (0 = none)
  @State replyToName: string = '';
  @State replyToText: string = '';
  @State editingId: number = 0;      // message being edited (0 = none)
  @State editingPreview: string = '';
  @State editingKind: string = 'text'; // 'text' | 'caption'
  private draftBeforeEdit: string = ''; // composer text stashed while editing
  @State showReactionSheet: boolean = false; // full emoji reaction picker
  @State reactionTargetId: number = 0;
  // Reactions this chat actually allows for the sheet's target message,
  // fetched per open; the static list is only the instant fallback.
  @State sheetReactions: string[] = [];
  // 自定义 emoji（Premium）反应：仅当服务端 allow_custom_emoji 为 true 时展示，
  // 位图异步下载，未就绪时先渲染占位格子。
  @State sheetCustomEmojis: CustomEmojiOption[] = [];
  @State sheetAllowCustomEmoji: boolean = false;
  @State reactionPendingKey: string = '';
  @State paidMediaPendingIds: number[] = [];
  // Forwarding is deliberately kept as an in-page sheet: leaving ChatPage to
  // pick a destination used to discard the long-press/selection context.
  @State showForwardSheet: boolean = false;
  @State showPollSheet: boolean = false;
  @State showContactSheet: boolean = false;
  @State showVideoNoteRecorder: boolean = false;
  @State showScheduledSheet: boolean = false;
  @State scheduledIds: number[] = [];
  @State scheduledPreviews: string[] = [];   // 与 scheduledIds 平行
  @State scheduledTimeLabels: string[] = []; // 与 scheduledIds 平行
  @State scheduledLoadState: string = 'idle'; // idle | loading | ready | error
  @State forwardChats: ChatEntry[] = [];
  @State forwardQuery: string = '';
  @State forwardLoadState: string = 'ready'; // loading | ready | error
  @State forwardSendingChatId: number = 0;
  private forwardMessageIds: number[] = [];
  private forwardPickerSeq: number = 0;
  @State nowSec: number = 0;
  private nowSecTimer: number = -1;
  @State viewerMsgId: number = 0;
  @State chromeVisible: boolean = true;
  @State viewerVideoLandscape: boolean = false;
  @State viewerClosing: boolean = false;
  // GIF playback is page-owned rather than row-owned: LazyForEach replaces a
  // row key as download progress/reactions change, but a user's pause/play
  // choice must survive that replacement.
  @State pausedAnimationIds: number[] = [];
  @State forcedAnimationIds: number[] = [];
  @State failedAnimationIds: number[] = [];
  @State viewerInitIdx: number = 0; // Swiper's initial page when the viewer opens
  // Fullscreen-photo zoom is viewer-owned. Keeping it separate from the
  // message thumbnail prevents the preview gesture/transition from mutating a
  // recycled Image node in the chat list.
  //
  // Model (per the official picture-preview best practice): the Image scales
  // around its own center and pans via translate, so screen = offset + scale
  // * content-point (measured from the image center). Pinch anchoring and
  // boundary clamping are both computed against that model.
  @State viewerPhotoScale: number = VIEWER_MIN_SCALE;
  @State viewerPhotoOffsetX: number = 0;
  @State viewerPhotoOffsetY: number = 0;
  private viewerPinchStartScale: number = VIEWER_MIN_SCALE;
  private viewerPinchStartOffsetX: number = 0;
  private viewerPinchStartOffsetY: number = 0;
  // Pinch anchor relative to the viewer center (vp) — the content point that
  // was under the fingers at pinch start stays under them while zooming.
  private viewerPinchAnchorX: number = 0;
  private viewerPinchAnchorY: number = 0;
  private viewerPanStartOffsetX: number = 0;
  private viewerPanStartOffsetY: number = 0;
  // Viewer viewport size in vp, captured via onAreaChange on the Swiper.
  private viewerAreaW: number = 0;
  private viewerAreaH: number = 0;
  // Some devices synthesize a click when the last finger of a pinch lifts.
  // Ignore that click briefly so a completed zoom is not immediately reset.
  private viewerIgnoreTapUntilMs: number = 0;
  private viewerSwiperCtrl: SwiperController = new SwiperController();
  @State swipeDir: number = 1; // 1 = advancing forward (next), -1 = going back — drives the slide direction
  // Window coordinates (vp) of the tap that opened the viewer — anchor for its
  // expand-from-tap open / shrink-back-to-tap close transition.
  @State tapX: number = 0;
  @State tapY: number = 0;
  @State pinnedPreview: string = '';
  @State pinnedCount: number = 0;
  @State pinnedLoadState: string = 'loading'; // loading | ready | error
  @State pinnedJumpBusy: boolean = false;
  // 正在直播入口条:chat.video_chat.group_call_id > 0 时显示("正在直播").
  @State liveGroupCallId: number = 0;
  @State liveCallIsActive: boolean = false;
  @State liveCallIsRtmp: boolean = false;
  @State liveParticipantCount: number = 0;
  @State livePulseExpanded: boolean = false;
  @State liveLoadState: string = 'loading'; // loading | ready | error
  @State liveDialogOpening: boolean = false;
  @State liveNavigationBusy: boolean = false;
  @State topCardLoadingVisible: boolean = false;
  private unsubVideoChat: (() => void) | null = null;
  private unsubGroupCall: (() => void) | null = null;
  private livePulseTimer: number = -1;
  private liveStateRefreshTimer: number = -1;
  private liveChatRefreshInFlight: boolean = false;
  private liveGroupRefreshInFlight: boolean = false;
  private liveChatResolveSeq: number = 0;
  private liveGroupResolveSeq: number = 0;
  private liveGroupRequestId: number = 0;
  private topCardLoadingTimer: number = -1;
  private topCardActionTimer: number = -1;
  private chatId: number = 0;
  private botCallbackPending: Set<string> = new Set();
  // >0: comment-thread view over the linked discussion group (see onCommentTap)
  private threadRootId: number = 0;
  private topicName: string = '';
  private forumTopicId: number = 0;
  @State isGroup: boolean = false;
  @State isChannel: boolean = false;
  // TDLib keeps membership on the underlying basicGroup/supergroup rather
  // than on chat itself. Public chats opened from search can therefore have
  // readable history while the current user is still outside the chat.
  // writable = normal composer, joinable = bottom "加入" action,
  // blocked = banned/unavailable, checking = waiting for the group object.
  @State membershipState: string = 'writable';
  @State joiningChat: boolean = false;
  // TDLib doesn't consistently return the local "joined" service message in
  // getChatHistory. Keep the confirmed join event as a client-only timeline
  // row until the real service message arrives. It deliberately has no member
  // ids, so it can never leak into viewMessages/read or pagination requests.
  private clientJoinNoticeVisible: boolean = false;
  private clientJoinNoticeIsChannel: boolean = false;
  private clientJoinNoticeDate: number = 0;
  private clientJoinNoticeEntryCache: MessageEntry | null = null;
  private clientJoinNoticeRouteChatId: number = 0;
  private membershipSupergroupId: number = 0;
  private membershipBasicGroupId: number = 0;
  private membershipSeq: number = 0;
  private store: MessageStore | null = null;
  private scroller: Scroller = new Scroller();
  private didInitialScroll: boolean = false;
  private lastMaxId: number = 0;
  @State atBottom: boolean = true;
  @State isMuted: boolean = false;
  // 会话级自动翻译（chat.is_translatable）。单条翻译走 translateMessage，
  // 这个开关让 TDLib 对整个会话建议翻译。
  @State isTranslatable: boolean = false;
  // 是否正在共享实时位置（全局单例状态，不限于当前会话）。
  @State liveLocationActive: boolean = false;
  @State liveLocationMessageId: number = 0;
  // 贴纸"飞出"动画：从点击处向上收缩淡出，动画收尾时才关面板 —— 关面板要
  // 同步卸载整个贴纸网格并触发全页重排（实测 51ms），压在点击那一帧就是可感
  // 的顿挫；挪到运动尾声则被动作本身盖住。
  @State stickerGhostPath: string = '';
  @State stickerGhostX: number = 0;
  @State stickerGhostY: number = 0;
  @State stickerGhostFly: boolean = false;
  private stickerGhostTimer: number = -1;
  private deleteDialog: CustomDialogController | null = null;
  private unsubLiveLocation: (() => void) | null = null;
  @State unreadBadge: number = 0;
  private firstUnreadId: number = 0;
  // Set once the initial scroll parks on the unread boundary; suppresses every
  // auto-scroll-to-bottom until the user first touches the list, so a short
  // unread run isn't glued past the divider by async in-place content growth.
  private stayAtUnread: boolean = false;
  private curStartIdx: number = -1; // topmost visible row index (from onScrollIndex)
  private pendingScrollBottom: boolean = false; // snap to the end once jumpToLatest's page arrives
  @State scrollToBottomBusy: boolean = false;
  private scrollActionSeq: number = 0;
  // Keep the exact viewport when this cached page is temporarily covered by a
  // profile/media route and then becomes visible again.
  private resumeScrollPending: boolean = false;
  private resumeScrollChatId: number = 0;
  private resumeScrollThreadId: number = 0;
  private resumeScrollMessageId: number = 0;
  private resumeScrollItemY: number = 0;
  private resumeScrollAtBottom: boolean = true;
  // @State: the segment indicator renders from this — a plain field wouldn't
  // trigger a re-render when scrolling/tapping moves the shown pinned index.
  @State pinnedCycle: number = 0;
  private pendingJumpId: number = 0;
  private jumpLayoutSeq: number = 0;
  // One-shot gate for loading older pages: a fast fling to the very top used to
  // chain-load page after page (the list stays pinned at the edge, so the
  // trigger zone never clears). Re-armed when the user scrolls clear of the
  // top zone or starts a new touch gesture.
  private olderArmed: boolean = true;
  // Jump-target highlight: a translucent overlay over the target row that
  // gently blinks twice after a reply/pinned/link jump lands.
  @State flashTop: number = 0;
  @State flashHeight: number = 0;
  @State flashAlpha: number = 0;
  @State flashShown: boolean = false;
  private flashSeq: number = 0;
  // Floating date chip: shows the topmost visible message's date while the
  // list scrolls, fades out shortly after scrolling stops (the in-list date
  // pills stay — this is the always-visible companion).
  @State floatDate: string = '';
  @State floatDateShown: boolean = false;
  private floatDateHideTimer: number = -1;
  private floatDateIndex: number = -1;
  private floatDateTimerArmedAt: number = 0;
  private listTouchActive: boolean = false;
  private listUserScrollActive: boolean = false;
  // RESIZE shortens the List while the IME animates in. Preserve the live-tail
  // anchor captured before that resize; otherwise onDidScroll observes the
  // temporary clipped viewport, flips atBottom to false and leaves the last
  // messages behind the newly raised composer.
  private imeTailPinned: boolean = false;
  private imeLayoutSeq: number = 0;
  private lastKeyboardH: number = 0;
  // Message id of a video waiting to be saved to the gallery once downloaded.
  private pendingGallerySaveId: number = 0;
  private autoSavePendingIds: number[] = [];
  private autoSaveInFlight: boolean = false;
  // Separate intents keep "tap to open" and the explicit save action honest:
  // a completed download performs exactly the action the user requested.
  private pendingFileOpenId: number = 0;
  // Message id of a document waiting for the "save as" picker once downloaded.
  private pendingFileSaveId: number = 0;
  private fileOpenInFlightId: number = 0;
  private utilityActionAtMs: number = 0;
  // A tapped music message starts automatically once its on-demand download
  // completes. Only the latest tap owns this slot, so rapid track changes
  // cannot make an older download steal playback later.
  private pendingMusicPlayId: number = 0;
  // Messages with id above this slide in from the bottom (live arrivals only —
  // 0 disables, so rows created while scrolling history never animate).
  @State freshSinceId: number = 0;
  private freshClearSeq: number = 0;
  private prependRestoreSeq: number = 0;
  // '@' mention / '/' command suggestion panels above the input bar.
  @State mentionItems: MentionItem[] = [];
  @State stickerSuggestions: StickerSuggestion[] = []; // emoji-typed sticker hints
  private stickerSuggestSeq: number = 0;
  @State botMiniAppUrlValue: string = ''; // bot menu-button Mini App ('' = none)
  @State inlineResults: InlineResultRow[] = [];  // @bot query results
  private inlineQueryId: string = '';
  private inlineSeq: number = 0;
  private inlineTimer: number = -1;
  @State commandItems: CommandItem[] = [];
  private allCommands: CommandItem[] = [];
  @State commandLoadState: string = 'idle'; // idle | loading | ready | error
  @State commandLoadError: string = '';
  @State commandMenuOpen: boolean = false;
  private commandLoadSeq: number = 0;
  private mentionSeq: number = 0; // drops stale searchChatMembers responses
  // Bot "菜单" pill (private bot chats with registered commands).
  @State botMenuAvailable: boolean = false;
  // Emoji panel above the input bar.
  @State showEmojiPanel: boolean = false;
  @State emojiPanelTab: number = 0;
  @State emojiPanelClosing: boolean = false;
  // Bot custom reply keyboard (null = this chat has none). Always docked when
  // present — no toggle, so there's no state to track beyond the keyboard itself.
  @State replyKeyboard: ReplyKeyboard | null = null;
  // Bot keyboard collapsed by the input-bar toggle (or a one_time keyboard
  // after use). A NEW keyboard from the bot un-collapses automatically.
  @State replyKbCollapsed: boolean = false;
  @State replyKeyboardSendingKey: string = '';
  // Voice recording state.
  @State isRecording: boolean = false;
  @State recordingStarting: boolean = false;
  @State recordSeconds: number = 0;
  private recordTimer: number = -1;
  private voiceRec: VoiceRecorder | null = null;
  private recordingSeq: number = 0;
  @State composerSending: boolean = false;
  @State composerFocused: boolean = false;
  private composerController: TextAreaController = new TextAreaController();
  private mediaPickerOpen: boolean = false;
  private mediaCopySeq: number = 0;
  @State headerMenuShow: boolean = false; // header ⋮ dropdown
  // Header state is kept separate from message-history state. getChat can
  // resolve before history, fail independently, or arrive after a cached row.
  @State headerState: string = 'loading'; // loading | ready | error
  @State headerLoadError: string = '';
  @State headerVisible: boolean = false;
  @State headerProfileOpening: boolean = false;
  @State headerMuteUpdating: boolean = false;
  @State pageClosing: boolean = false;
  private headerPeerUserId: number = 0;
  private headerKind: string = '';
  private headerIdentityResolved: boolean = false;
  private headerResolveSeq: number = 0;
  private headerNavigationTimer: number = -1;
  private headerEntranceTimer: number = -1;
  // In-chat message search (search-mode header + result navigation).
  @State searchMode: boolean = false;
  // Multi-select mode (entered via the long-press menu's 选择 item).
  @State selecting: boolean = false;
  @State selectedIds: number[] = [];
  @State searchQuery: string = '';
  @State searchResults: number[] = []; // message ids, newest → oldest
  @State searchTotal: number = 0;
  @State searchIdx: number = 0;        // 0-based index into searchResults
  // Message id the chat was opened on from global search — becomes the current
  // hit instead of the search jumping to the newest one. 0 = no anchor.
  private searchAnchorId: number = 0;
  private searchSeq: number = 0;       // drops stale responses
  private unsubMsg: (() => void) | null = null;
  private unsubSub: (() => void) | null = null;
  // Peer's premium emoji status (private chats) shown beside the header title.
  @State headerEmojiPath: string = '';
  @State headerEmojiFormat: string = '';
  private headerEmojiFetched: boolean = false;
  private unsubChat: (() => void) | null = null;
  private unsubPinned: (() => void) | null = null;
  private unsubHeaderAvatar: (() => void) | null = null;
  private unsubHeaderTitle: (() => void) | null = null;
  private unsubReplyKb: (() => void) | null = null;
  private unsubMembershipSupergroup: (() => void) | null = null;
  private unsubMembershipBasicGroup: (() => void) | null = null;

  private clearFloatingDate(): void {
    if (this.floatDateHideTimer !== -1) {
      clearTimeout(this.floatDateHideTimer);
      this.floatDateHideTimer = -1;
    }
    this.floatDate = '';
    this.floatDateShown = false;
    this.floatDateIndex = -1;
    this.floatDateTimerArmedAt = 0;
    this.listTouchActive = false;
    this.listUserScrollActive = false;
  }

  private resetScrollSession(): void {
    this.scrollActionSeq++;
    this.jumpLayoutSeq++;
    this.prependRestoreSeq++;
    this.bottomChromeLayoutSeq++;
    this.didInitialScroll = false;
    this.lastMaxId = 0;
    this.atBottom = true;
    this.firstUnreadId = 0;
    this.stayAtUnread = false;
    this.curStartIdx = -1;
    this.pendingScrollBottom = false;
    this.scrollToBottomBusy = false;
    this.pendingJumpId = 0;
    this.pendingFileOpenId = 0;
    this.pendingFileSaveId = 0;
    this.fileOpenInFlightId = 0;
    this.pendingMusicPlayId = 0;
    this.olderArmed = true;
    this.freshSinceId = 0;
    this.freshClearSeq++;
    this.imeTailPinned = false;
    this.imeLayoutSeq++;
    this.lastKeyboardH = this.keyboardH;
    this.cancelFlash();
    this.clearFloatingDate();
    this.messages = [];
    this.messageLoadError = '';
    this.olderLoadState = 'idle';
    this.newerLoadState = 'idle';
    this.groups = [];
    this.visibleGroupCount = 0;
    this.groupsData.update([]);
    this.pausedAnimationIds = [];
    this.forcedAnimationIds = [];
    this.failedAnimationIds = [];
  }

  private resetComposerSession(): void {
    this.recordingSeq++;
    if (this.voiceRec !== null || this.isRecording || this.recordingStarting) {
      this.cancelRecording();
    }
    this.panelReadySeq++;
    this.showEmojiPanel = false;
    this.panelContentReady = false;
    this.emojiPanelClosing = false;
    this.draft = '';
    this.composerSending = false;
    this.composerFocused = false;
    this.imeTailPinned = false;
    this.imeLayoutSeq++;
    this.lastKeyboardH = this.keyboardH;
    this.mentionItems = [];
    this.commandItems = [];
    this.allCommands = [];
    this.commandLoadSeq++;
    this.commandLoadState = 'idle';
    this.commandLoadError = '';
    this.commandMenuOpen = false;
    this.botMenuAvailable = false;
    this.replyKeyboard = null;
    this.replyKbCollapsed = false;
    this.replyKeyboardSendingKey = '';
    this.clearReply();
  }

  private resetMessageActionSession(): void {
    this.selecting = false;
    this.selectedIds = [];
    this.showReactionSheet = false;
    this.reactionTargetId = 0;
    this.reactionPendingKey = '';
    this.paidMediaPendingIds = [];
    this.forwardPickerSeq++;
    this.showForwardSheet = false;
    this.forwardChats = [];
    this.forwardQuery = '';
    this.forwardLoadState = 'ready';
    this.forwardSendingChatId = 0;
    this.forwardMessageIds = [];
  }

  private isRealClientJoinNotice(message: MessageEntry): boolean {
    if (message.contentType !== 'system' || !message.isOutgoing) {
      return false;
    }
    return message.placeholderLabel === '您已加入此群组' ||
      message.placeholderLabel === '您已加入此频道' ||
      message.systemType === 'messageChatJoinByLink' ||
      message.systemType === 'messageChatJoinByRequest';
  }

  private clientJoinNoticeEntry(): MessageEntry {
    if (this.clientJoinNoticeEntryCache !== null) {
      return this.clientJoinNoticeEntryCache;
    }
    const content: TdObject = this.clientJoinNoticeIsChannel
      ? { '@type': 'messageCustomServiceAction', 'text': '您已加入此频道' }
      : { '@type': 'messageChatJoinByLink' };
    const raw: TdObject = {
      '@type': 'message',
      // The row is page-local and memberIds is cleared below. A negative id
      // also makes accidental lookup/action matching impossible.
      'id': -1,
      'chat_id': this.chatId,
      'date': this.clientJoinNoticeDate,
      'is_outgoing': true,
      'content': content
    };
    this.clientJoinNoticeEntryCache = buildMessageEntry(raw, getUserStore());
    return this.clientJoinNoticeEntryCache;
  }

  private groupsWithClientJoinNotice(list: MessageEntry[]): AlbumGroup[] {
    if (this.clientJoinNoticeVisible &&
      list.some((message: MessageEntry): boolean => this.isRealClientJoinNotice(message))) {
      // Replace the local row atomically when TDLib eventually supplies the
      // canonical service message, avoiding a one-frame duplicate.
      this.clientJoinNoticeVisible = false;
      this.clientJoinNoticeEntryCache = null;
    }
    if (!this.clientJoinNoticeVisible) {
      return collapseAlbums(list);
    }
    const displayList: MessageEntry[] = list.slice();
    displayList.push(this.clientJoinNoticeEntry());
    const groups: AlbumGroup[] = collapseAlbums(displayList);
    if (groups.length > 0) {
      const notice: AlbumGroup = groups[groups.length - 1];
      if (notice.head.id === -1) {
        notice.memberIds = [];
        notice.key = `client_join_${this.chatId}_${this.clientJoinNoticeDate}`;
      }
    }
    return groups;
  }

  private showClientJoinNotice(isChannel: boolean): void {
    this.clientJoinNoticeVisible = true;
    this.clientJoinNoticeIsChannel = isChannel;
    this.clientJoinNoticeDate = Math.floor(Date.now() / 1000);
    this.clientJoinNoticeEntryCache = null;
    const groups: AlbumGroup[] = this.groupsWithClientJoinNotice(this.messages);
    this.groups = groups;
    this.visibleGroupCount = groups.length;
    this.groupsData.update(groups);
    if (this.didInitialScroll && this.atBottom) {
      const actionSeq: number = ++this.scrollActionSeq;
      setTimeout((): void => {
        if (actionSeq === this.scrollActionSeq) {
          this.scroller.scrollEdge(Edge.Bottom);
          this.refreshAtBottom();
        }
      }, 0);
    }
  }

  private captureScrollResume(): void {
    this.resumeScrollPending = false;
    if (!this.didInitialScroll || this.groups.length === 0 ||
      this.curStartIdx < 0 || this.curStartIdx >= this.groups.length) {
      return;
    }
    this.resumeScrollChatId = this.chatId;
    this.resumeScrollThreadId = this.threadRootId;
    this.resumeScrollMessageId = this.groups[this.curStartIdx].head.id;
    this.resumeScrollItemY = 0;
    try {
      this.resumeScrollItemY = this.scroller.getItemRect(this.curStartIdx).y;
    } catch (e) {
      this.resumeScrollItemY = 0;
    }
    this.resumeScrollAtBottom = this.atBottom;
    this.resumeScrollPending = true;
  }

  aboutToAppear(): void {
    this.nowSec = Math.floor(Date.now() / 1000);
    const params = router.getParams() as Record<string, Object> | undefined;
    this.chatId = params !== undefined ? (params['chatId'] as number) : 0;
    this.threadRootId = params !== undefined ? ((params['threadRootId'] as number | undefined) ?? 0) : 0;
    // 话题模式（从 ForumTopicsPage 进入）：标题显示话题名而非"评论"。
    this.topicName = params !== undefined ? ((params['topicName'] as string | undefined) ?? '') : '';
    this.forumTopicId = params !== undefined
      ? ((params['forumTopicId'] as number | undefined) ?? 0) : 0;
    const incomingJoinNotice: boolean = params !== undefined
      ? ((params['showJoinedNotice'] as boolean | undefined) ?? false) : false;
    if (incomingJoinNotice && this.clientJoinNoticeRouteChatId !== this.chatId) {
      this.clientJoinNoticeRouteChatId = this.chatId;
      this.clientJoinNoticeVisible = true;
      this.clientJoinNoticeIsChannel = params !== undefined
        ? ((params['joinedNoticeIsChannel'] as boolean | undefined) ?? false) : false;
      this.clientJoinNoticeDate = Math.floor(Date.now() / 1000);
      this.clientJoinNoticeEntryCache = null;
    }
    getVoicePlayback().setMusicCompletionListener((messageId: number): void => {
      this.onMusicCompleted(messageId);
    });
    let scrollResumeWaiting: boolean = this.resumeScrollPending &&
      this.resumeScrollChatId === this.chatId &&
      this.resumeScrollThreadId === this.threadRootId &&
      this.groups.length > 0;
    if (!scrollResumeWaiting) {
      this.resumeScrollPending = false;
      this.resetScrollSession();
      this.resetComposerSession();
      this.resetMessageActionSession();
    } else {
      // Old rows remain visible until the replacement page has arrived. Clear
      // transient overlays/actions, but preserve the captured viewport.
      this.scrollActionSeq++;
      this.jumpLayoutSeq++;
      this.pendingJumpId = 0;
      this.pendingScrollBottom = false;
      this.scrollToBottomBusy = false;
      this.didInitialScroll = true;
      this.clearFloatingDate();
    }
    const cachedChat: ChatEntry | undefined = getChatStore().entryOf(this.chatId);
    if (cachedChat !== undefined &&
      (cachedChat.kind === 'basicGroup' || cachedChat.kind === 'supergroup' || cachedChat.kind === 'channel')) {
      // Avoid briefly exposing a working input field before the async member
      // status of a newly opened public chat arrives.
      this.membershipState = 'checking';
    }
    const jumpTo = params !== undefined ? (params['jumpTo'] as number | undefined) : undefined;
    this.resetHeaderState(cachedChat);
    this.resetTopCardState();
    this.resolveHeaderIdentity();
    // Entered from global search: open directly on this chat's results for the
    // same query (the search header, the hit list and ∧/∨ navigation). With a
    // message hit, that message is the jump target and becomes the current hit
    // — searchAnchorId keeps the search from jumping somewhere else.
    // Deep links like t.me/<name>?text=… open the chat with a prefilled draft.
    const incomingDraft = params !== undefined ? ((params['draftText'] as string | undefined) ?? '') : '';
    if (incomingDraft !== '') {
      this.draft = incomingDraft;
    } else {
      this.restoreServerDraft();
    }
    const incomingQuery = params !== undefined ? ((params['searchQuery'] as string | undefined) ?? '') : '';
    if (incomingQuery !== '') {
      this.searchMode = true;
      this.searchQuery = incomingQuery;
      this.searchAnchorId = jumpTo !== undefined ? jumpTo : 0;
    } else if (params !== undefined && ((params['startSearch'] as boolean | undefined) ?? false)) {
      // Profile-page 搜索 button: open the chat with an empty, focused search.
      this.searchMode = true;
    }
    this.refreshHeader();
    this.unsubChatAction = getTdClient().onUpdate('updateChatAction',
      (u: TdObject): void => this.onChatAction(u));
    this.unsubChat = getChatStore().subscribe((list: ChatEntry[]) => {
      this.refreshHeader();
      if (this.showForwardSheet) {
        this.updateForwardChats(list);
      }
    }, 'main');
    // Chat backgrounds have their own TDLib update and can change without a
    // title/message update. Listen directly so setting or clearing one is
    // visible while the conversation is open.
    this.unsubLiveLocation = liveLocation.subscribe((st: LiveLocationState): void => {
      this.liveLocationActive = st.active;
      // 只有共享发生在当前会话时才在气泡上显示停止按钮。
      this.liveLocationMessageId = st.active && st.chatId === this.chatId ? st.messageId : 0;
    });
    // 在其它设备改了这个开关时同步过来，否则菜单文案会和实际状态不符。
    this.unsubTranslatable = getTdClient().onUpdate('updateChatIsTranslatable',
      (u: TdObject): void => {
        if ((u['chat_id'] as number | undefined) === this.chatId) {
          this.isTranslatable = (u['is_translatable'] as boolean | undefined) ?? false;
        }
      });
    this.unsubChatBackground = getTdClient().onUpdate('updateChatBackground', (u: TdObject) => {
      if ((u['chat_id'] as number | undefined) === this.chatId) {
        const seq = ++this.chatBackgroundResolveSeq;
        const background = this.objectOrNull(u['background']);
        if (background !== null) {
          this.applyChatBackground(background);
        } else {
          this.applyDefaultBackground(seq);
        }
      }
    });
    this.unsubChatTheme = getTdClient().onUpdate('updateChatTheme', (u: TdObject) => {
      if ((u['chat_id'] as number | undefined) !== this.chatId) {
        return;
      }
      const seq = ++this.chatBackgroundResolveSeq;
      const themeName = (u['theme_name'] as string | undefined) ?? '';
      if (themeName === '') {
        const specific = getChatStore().entryOf(this.chatId)?.background ?? null;
        if (specific !== null) {
          this.applyChatBackground(specific);
        } else {
          this.applyDefaultBackground(seq);
        }
      } else {
        this.resolveThemeBackground(themeName, seq);
      }
    });
    this.unsubDefaultBackground = getTdClient().onUpdate('updateDefaultBackground', (u: TdObject) => {
      const forDarkTheme = (u['for_dark_theme'] as boolean | undefined) ?? false;
      if (forDarkTheme !== this.darkResourceMode() || this.hasSpecificBackground()) {
        return;
      }
      const seq = ++this.chatBackgroundResolveSeq;
      const background = this.objectOrNull(u['background']);
      if (background !== null) {
        this.applyChatBackground(background);
      } else {
        this.loadInstalledDefaultBackground(forDarkTheme, seq);
      }
    });
    this.unsubBackgroundFile = getTdClient().onUpdate('updateFile', (u: TdObject) => {
      const file = u['file'] as TdObject | undefined;
      if (file !== undefined) {
        this.applyBackgroundFile(file);
      }
    });
    this.refreshChatBackground();
    this.unsubMembershipSupergroup = getTdClient().onUpdate('updateSupergroup', (u: TdObject) => {
      const supergroup = u['supergroup'] as TdObject | undefined;
      if (supergroup !== undefined &&
        ((supergroup['id'] as number | undefined) ?? 0) === this.membershipSupergroupId) {
        this.applyMembershipStatus(supergroup['status'] as TdObject | undefined);
      }
    });
    this.unsubMembershipBasicGroup = getTdClient().onUpdate('updateBasicGroup', (u: TdObject) => {
      const basicGroup = u['basic_group'] as TdObject | undefined;
      if (basicGroup !== undefined &&
        ((basicGroup['id'] as number | undefined) ?? 0) === this.membershipBasicGroupId) {
        this.applyMembershipStatus(basicGroup['status'] as TdObject | undefined);
      }
    });
    this.refreshMembership();
    this.refreshVideoChat(true);
    this.unsubVideoChat = getTdClient().onUpdate('updateChatVideoChat', (u: TdObject) => {
      if ((u['chat_id'] as number | undefined) === this.chatId) {
        this.liveChatResolveSeq++;
        this.liveChatRefreshInFlight = false;
        this.liveLoadState = 'ready';
        const vc = u['video_chat'] as TdObject | undefined;
        this.setLiveGroupCallId(vc !== undefined ? ((vc['group_call_id'] as number | undefined) ?? 0) : 0);
        this.settleTopCardLoading();
      }
    });
    this.unsubGroupCall = getTdClient().onUpdate('updateGroupCall', (u: TdObject) => {
      const groupCall = u['group_call'] as TdObject | undefined;
      if (groupCall !== undefined &&
        ((groupCall['id'] as number | undefined) ?? 0) === this.liveGroupCallId) {
        this.liveGroupResolveSeq++;
        this.liveGroupRefreshInFlight = false;
        this.liveGroupRequestId = 0;
        this.applyLiveGroupCall(groupCall);
      }
    });
    this.livePulseTimer = setInterval((): void => {
      if (!this.liveCallIsActive || !powerFeatureEnabled(KEY_POWER_PARTICLES)) {
        this.livePulseExpanded = false;
        return;
      }
      this.livePulseExpanded = !this.livePulseExpanded;
    }, 780);
    this.powerBackgroundTimer = setInterval((): void => {
      if (powerGroupFeatureEnabled(KEY_POWER_CHAT_EFFECTS, KEY_POWER_EFFECT_BACKGROUND) ||
        powerFeatureEnabled(KEY_POWER_PARTICLES)) {
        this.powerBackgroundPhase = !this.powerBackgroundPhase;
      } else {
        this.powerBackgroundPhase = false;
      }
    }, 4200);
    // Updates remain the fast path. Polling is a small safety net for devices
    // that resume this cached page after an update was delivered while its
    // subscriptions were inactive.
    this.liveStateRefreshTimer = setInterval((): void => {
      this.refreshVideoChat();
    }, 2000);
    const store = new MessageStore(
      getTdClient(), getUserStore(), this.chatId, this.threadRootId, 30, this.forumTopicId);
    this.store = store;
    if (!scrollResumeWaiting || this.groups.length === 0) {
      this.messageLoadState = 'loading';
    }
    this.unsubMsg = store.subscribe((list: MessageEntry[]) => {
      const historyState: string = store.getInitialHistoryState();
      this.olderLoadState = store.getOlderLoadState();
      this.newerLoadState = store.getNewerLoadState();
      if (!(scrollResumeWaiting && this.groups.length > 0 && historyState === 'loading')) {
        this.messageLoadState = historyState;
        this.messageLoadError = store.getInitialHistoryError();
      }
      // Do not turn an openChat real-time update into the first positioned
      // timeline. MessageStore normally withholds these partial snapshots, and
      // this page-side guard also protects cached-page resume and future data
      // sources that may publish while their initial history is still loading.
      if (historyState === 'loading') {
        return;
      }
      // subscribe() immediately publishes the new store's empty snapshot.
      // During cached-page resume, keep the old viewport on screen until the
      // around/latest request returns instead of flashing a blank conversation.
      if (scrollResumeWaiting && list.length === 0 && this.groups.length > 0 &&
        historyState !== 'ready') {
        return;
      }
      const notifyKind: string = store.getCurrentNotifyKind();
      const maxId: number = list.length > 0 ? list[list.length - 1].id : 0;
      const groups: AlbumGroup[] = this.groupsWithClientJoinNotice(list);
      let prependAnchorId: number = 0;
      let prependAnchorY: number = 0;
      if (this.didInitialScroll && this.groups.length > 0 && groups.length > this.groups.length) {
        const previousFirstIndex: number = groupIndexOf(groups, this.groups[0].head.id);
        const visibleIndex: number = this.curStartIdx;
        if (previousFirstIndex > 0 && visibleIndex >= 0 && visibleIndex < this.groups.length) {
          prependAnchorId = this.groups[visibleIndex].head.id;
          try {
            prependAnchorY = this.scroller.getItemRect(visibleIndex).y;
          } catch (e) {
            prependAnchorY = 0;
          }
        }
      }
      this.messages = list;
      this.reconcileMessageActionTargets(list);
      this.groups = groups;
      this.visibleGroupCount = groups.length;
      if (this.viewerMsgId !== 0 &&
        list.findIndex((m: MessageEntry): boolean => m.id === this.viewerMsgId) < 0) {
        this.closeViewer();
      }
      const updateKind: string = this.groupsData.update(groups);
      this.settlePendingMusic(list);
      // Incremental ops (the normal prepend) keep the viewport anchored via
      // maintainVisibleContentPosition; forcing scrollToIndex on top of that
      // cancelled the user's fling mid-scroll — the load-more stutter. Only a
      // RELOAD rebuild loses the anchor and needs the manual restore.
      if (prependAnchorId > 0 && updateKind === 'reload') {
        this.restorePrependAnchor(groups, prependAnchorId, prependAnchorY);
      }
      let positionHandled: boolean = false;
      if (scrollResumeWaiting && list.length > 0) {
        scrollResumeWaiting = false;
        this.resumeScrollPending = false;
        this.didInitialScroll = true;
        this.lastMaxId = maxId;
        this.firstUnreadId = 0;
        this.stayAtUnread = false;
        positionHandled = true;
        if (this.resumeScrollAtBottom) {
          this.atBottom = false;
          const actionSeq: number = ++this.scrollActionSeq;
          this.scroller.scrollEdge(Edge.Bottom);
          setTimeout((): void => {
            if (actionSeq === this.scrollActionSeq) {
              this.scroller.scrollEdge(Edge.Bottom);
              this.refreshAtBottom();
            }
          }, 60);
        } else {
          const resumeIndex: number = groupIndexOf(groups, this.resumeScrollMessageId);
          this.atBottom = false;
          if (resumeIndex >= 0) {
            this.restoreScrollAnchor(resumeIndex, this.resumeScrollItemY);
          } else {
            this.scroller.scrollEdge(Edge.Bottom);
          }
        }
      }
      // isChannel resolves asynchronously (getSupergroup round-trip) after the
      // first message page can already be showing, so refresh it every notify.
      this.isChannel = this.store !== null ? this.store.getIsChannel() : false;
      // A global-search hit opens around jumpTo and marks the initial scroll as
      // handled before history arrives. Keep the group flag independent of that
      // scroll state; otherwise every incoming bubble is rendered like a private
      // chat and its sender-avatar column is omitted.
      this.isGroup = this.store !== null ? this.store.getIsGroup() : false;
      const liveMediaIds: number[] = store.consumeLiveIncomingMediaIds();
      const autoScope: string = this.isChannel ? 'channel' : (this.isGroup ? 'group' : 'private');
      if (autosaveEnabled(autoScope)) {
        for (const mediaId of liveMediaIds) {
          if (this.autoSavePendingIds.indexOf(mediaId) < 0) {
            this.autoSavePendingIds.push(mediaId);
          }
        }
      }
      // Private peer resolved: probe once for commands. The centralized loader
      // also serves '/' autocomplete, so fast typing cannot start a competing
      // request that overwrites a newer result.
      if (this.commandLoadState === 'idle' && this.store !== null &&
        this.store.getPeerUserId() > 0) {
        this.ensureCommandsLoaded();
      }
      if (!positionHandled && !this.didInitialScroll && list.length > 0) {
        // First real page: jump to the first unread message (Android-style);
        // fully-read chats land at the bottom. (Never anchor on
        // last_read_inbox_message_id here — it only tracks incoming messages,
        // so with an outgoing tail it points at a stale mid-history position.)
        this.didInitialScroll = true;
        this.lastMaxId = maxId;
        const fu: number = this.store !== null ? this.store.getFirstUnreadId() : 0;
        const gidx: number = fu > 0 ? groupIndexOf(groups, fu) : -1;
        this.firstUnreadId = fu > 0 && gidx >= 0 ? groups[gidx].head.id : 0;
        if (gidx >= 0) {
          // Landing mid-history at the unread boundary: atBottom defaults to
          // true, and the bottom-glue branch below would otherwise drag the
          // view to the tail (chain-loading every newer page) before the
          // first scroll event corrects it.
          this.atBottom = false;
          // With only a few unread, ScrollAlign.START can't lift the boundary to
          // the top (too little content below), so it lands near the bottom and
          // the last group becomes visible — onScrollIndex then flips atBottom
          // back to true, and the very next in-place notify (thumbnails/reply
          // quotes filling in) would glue us to the tail, skipping past the
          // unread divider. Latch here so no auto-scroll overrides the boundary
          // until the user actually touches the list.
          this.stayAtUnread = true;
          this.scroller.scrollToIndex(gidx, false, ScrollAlign.START);
        } else {
          this.scroller.scrollEdge(Edge.Bottom);
        }
      } else if (!positionHandled && this.didInitialScroll && maxId > this.lastMaxId) {
        // Only follow to the bottom for genuinely new messages AND only when the
        // user is already near the bottom — never yank them down while they read
        // history or on photo/read-receipt updates.
        // Mark the arrivals as fresh for a beat so their bubbles gently enter;
        // rows rebuilt while scrolling history never animate.
        if (notifyKind === 'update') {
          this.freshSinceId = this.lastMaxId;
          const clearSeq = ++this.freshClearSeq;
          setTimeout(() => {
            if (clearSeq === this.freshClearSeq) {
              this.freshSinceId = 0;
            }
          }, 1500);
        }
        this.lastMaxId = maxId;
        // Never follow while parked at the unread boundary (until the user
        // touches) or while the fullscreen viewer is open — the chat should
        // return to the same underlying message after the preview closes.
        if (notifyKind === 'update' && this.atBottom && !this.stayAtUnread && this.viewerMsgId === 0) {
          this.scroller.scrollEdge(Edge.Bottom);
        }
      } else if (this.didInitialScroll && this.atBottom && !this.stayAtUnread && this.viewerMsgId === 0
        && (this.store === null || !this.store.getHasMoreNewer())) {
        // In-place content growth (thumbnails, reply quotes, forward headers
        // filling in async) changes row heights; when the user is at the
        // bottom, stay glued there instead of letting the tail drift. Never
        // glue while unloaded newer pages exist — being at the window's edge
        // there is NOT the live tail, and gluing chain-loads every page.
        // Also never move the underlying list while the media viewer is open.
        this.scroller.scrollEdge(Edge.Bottom);
      }
      // jumpToLatest's newest page arrived — snap to the end. The dataset was
      // just replaced wholesale, so scroll once now and once after the List has
      // laid the new rows out: the immediate call alone lands at the top of the
      // reloaded page because the final row heights aren't known yet.
      if (this.pendingScrollBottom && list.length > 0) {
        this.pendingScrollBottom = false;
        this.lastMaxId = maxId;
        this.atBottom = true;
        const actionSeq: number = this.scrollActionSeq;
        this.scroller.scrollEdge(Edge.Bottom);
        setTimeout(() => {
          if (actionSeq === this.scrollActionSeq) {
            this.scroller.scrollEdge(Edge.Bottom);
            this.refreshAtBottom();
          }
        }, 60);
      }
      if (notifyKind === 'newer') {
        // An empty newer page is the signal that this history window has
        // reached the live tail. Re-evaluate after layout even when no visible
        // index changed, otherwise the down button can remain stuck onscreen.
        setTimeout((): void => {
          if (this.store === store) {
            this.refreshAtBottom();
          }
        }, 0);
      }
      // A viewer item queued for gallery save finished downloading — always
      // prefer the original photo rather than silently saving its thumbnail.
      if (this.pendingGallerySaveId !== 0) {
        const pe = list.find((m: MessageEntry) => m.id === this.pendingGallerySaveId);
        if (pe !== undefined) {
          if (this.mediaEntryIsVideo(pe) && pe.videoPath !== '') {
            this.pendingGallerySaveId = 0;
            saveMediaToGallery(getContext(this) as common.UIAbilityContext, pe.videoPath, true);
          } else if (this.mediaEntryIsVideo(pe) && pe.videoFailed) {
            this.pendingGallerySaveId = 0;
            promptAction.showToast({ message: '视频下载失败，请重试', duration: 1800 });
          } else if (this.mediaEntryIsPhoto(pe) && pe.photoFullPath !== '') {
            this.pendingGallerySaveId = 0;
            saveMediaToGallery(getContext(this) as common.UIAbilityContext, pe.photoFullPath, false);
          } else if (this.mediaEntryIsPhoto(pe) && pe.photoFullFailed) {
            this.pendingGallerySaveId = 0;
            promptAction.showToast({ message: '原图下载失败，请重试', duration: 1800 });
          }
        }
      }
      this.processAutomaticGallerySave(list);
      // A document queued for "save as" finished downloading — open the picker.
      if (this.pendingFileOpenId !== 0) {
        const openEntry: MessageEntry | undefined =
          list.find((m: MessageEntry): boolean => m.id === this.pendingFileOpenId);
        if (openEntry === undefined || openEntry.contentType !== 'file') {
          this.pendingFileOpenId = 0;
        } else if (openEntry.videoFailed) {
          this.pendingFileOpenId = 0;
          promptAction.showToast({ message: '文件下载失败，请重试', duration: 1800 });
        } else if (openEntry.videoPath !== '') {
          this.pendingFileOpenId = 0;
          this.openDownloadedFile(openEntry);
        }
      }
      if (this.pendingFileSaveId !== 0) {
        const fe = list.find((m: MessageEntry) => m.id === this.pendingFileSaveId);
        if (fe === undefined || fe.contentType !== 'file') {
          this.pendingFileSaveId = 0;
        } else if (fe.videoFailed) {
          this.pendingFileSaveId = 0;
          promptAction.showToast({ message: '文件下载失败，无法保存', duration: 1800 });
        } else if (fe.videoPath !== '') {
          this.pendingFileSaveId = 0;
          saveFileToLocal(getContext(this) as common.UIAbilityContext, fe.videoPath, fe.videoFileName);
        }
      }
      // A pinned/quoted jump target that had to be loaded has now arrived — scroll to it.
      if (this.pendingJumpId !== 0) {
        const jumpTargetId: number = this.pendingJumpId;
        const jg: number = groupIndexOf(groups, jumpTargetId);
        if (jg >= 0) {
          this.pendingJumpId = 0;
          this.finishPinnedJump();
          this.scroller.scrollToIndex(jg, false, ScrollAlign.START);
          // loadAround replaces the window wholesale (list RELOAD) — the
          // immediate scroll can be swallowed before the new rows lay out.
          // Re-issue once layout settles (index recomputed: prepends may have
          // shifted it) and flash after that.
          const jumpSeq: number = ++this.jumpLayoutSeq;
          setTimeout(() => {
            if (jumpSeq !== this.jumpLayoutSeq) {
              return;
            }
            const jg2: number = groupIndexOf(this.groups, jumpTargetId);
            if (jg2 >= 0) {
              this.scroller.scrollToIndex(jg2, false, ScrollAlign.START);
              this.flashAtIndex(jg2);
            }
          }, 80);
        }
      }
    });
    this.unsubSub = store.subscribeSubtitle((s: string) => {
      this.subtitle = s;
      this.fetchHeaderEmojiStatus();
    });
    this.unsubHeaderTitle = store.subscribeHeaderTitle((t: string) => {
      // Fallback header for chats not yet in ChatStore (e.g. opened by t.me link).
      if (t !== '') {
        if (this.threadRootId === 0 && this.forumTopicId === 0) {
          this.title = t;
        }
        this.initials = computeInitials(t);
        this.headerState = 'ready';
        this.headerLoadError = '';
      }
    });
    this.unsubHeaderAvatar = store.subscribeHeaderAvatar((p: string) => {
      if (p !== '') {
        this.avatarPath = p;
        // MessageStore resolves the chat photo independently of ChatStore/FileService
        // (e.g. for a channel only ever surfaced under a folder tab, whose avatar
        // download may never have fired/retried there) — backfill the list entry too,
        // so the chat list shows the avatar without depending on that separate path.
        getChatStore().setAvatarPath(this.chatId, p);
      }
    });
    this.unsubReplyKb = store.subscribeReplyKeyboard((kb: ReplyKeyboard | null) => {
      const prevId = this.replyKeyboard !== null ? this.replyKeyboard.messageId : 0;
      const newId = kb !== null ? kb.messageId : 0;
      if (newId !== prevId) {
        // Present an initial/fresh keyboard, but never yank the composer away
        // while the user is already typing or browsing media.
        this.replyKbCollapsed = this.composerFocused || this.showEmojiPanel;
      }
      this.replyKeyboard = kb;
      if (kb === null) {
        this.replyKbH = 0;
        this.replyKeyboardSendingKey = '';
      }
    });
    this.unsubPinned = store.subscribePinned((s: string) => {
      this.pinnedPreview = s;
      this.pinnedCount = store.getPinnedIds().length;
      this.pinnedLoadState = store.getPinnedLoadState();
      this.pinnedCycle = Math.min(this.pinnedCycle, Math.max(0, this.pinnedCount - 1));
      if (this.pinnedCount === 0) {
        this.pinnedCycle = 0;
        this.finishPinnedJump();
      }
      this.settleTopCardLoading();
    });
    if (scrollResumeWaiting) {
      // Re-open around the captured row unless the old viewport was already
      // at the true live tail, in which case the newest page is sufficient.
      store.open(this.resumeScrollAtBottom || this.resumeScrollMessageId <= 0
        ? undefined : this.resumeScrollMessageId);
    } else if (jumpTo !== undefined && jumpTo > 0) {
      // Opened via a message link: load straight around the target message,
      // without racing an additional latest-history request.
      this.didInitialScroll = true;
      this.pendingJumpId = jumpTo;
      store.open(jumpTo);
    } else if (this.threadRootId > 0) {
      // Comment thread: start at the TOP — the root post — not the newest reply.
      this.didInitialScroll = true;
      this.pendingJumpId = this.threadRootId;
      store.open(this.threadRootId);
    } else {
      store.open();
    }
    if (this.searchMode && this.searchQuery !== '') {
      // Let the initial history land first — runSearch jumps to the newest hit,
      // and that jump would otherwise be undone by the initial scroll-to-bottom.
      setTimeout(() => {
        if (this.searchMode) {
          this.runSearch(0, 0);
        }
      }, SEARCH_ENTRY_DELAY_MS);
    }
  }

  // nowSec 驱动实时位置的倒计时和"已结束"判定，以及消息时间的相对显示。
  // 以前只在 aboutToAppear 赋值一次，于是共享结束后必须重进会话才看得出来。
  // 30 秒一跳：这些标签都是分钟粒度的，再密只是白白唤醒渲染。
  private armNowSecTimer(): void {
    if (this.nowSecTimer !== -1) {
      return;
    }
    this.nowSecTimer = setInterval((): void => {
      this.nowSec = Math.floor(Date.now() / 1000);
    }, NOW_SEC_TICK_MS);
  }

  private clearNowSecTimer(): void {
    if (this.nowSecTimer !== -1) {
      clearInterval(this.nowSecTimer);
      this.nowSecTimer = -1;
    }
  }

  // 停止共享是不可撤销的：一旦结束，那条消息就再也编辑不回来了（服务端直接
  // 判定为不可编辑），只能重新发一条。所以先确认。
  private confirmStopLiveLocation(): void {
    promptAction.showDialog({
      title: '停止共享实时位置',
      message: '停止后这条消息将不再更新位置，且无法恢复共享。',
      buttons: [
        { text: '取消', color: '#8E8E93' },
        { text: '停止共享', color: '#D95B57' }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (result.index !== 1) {
        return;
      }
      liveLocation.stopSharing();
      promptAction.showToast({ message: '已停止共享实时位置', duration: 1500 });
    }).catch((e: Object): void => {
      console.error(`ChatPage.confirmStopLiveLocation failed: ${JSON.stringify(e)}`);
    });
  }

  onPageHide(): void {
    console.info(`[ChatDiag] hide msgs=${this.messages.length} groups=${this.groups.length} ds=${this.groupsData.totalCount()}`);
    // 页面不可见时停表，回来时补一次即时值再续上。
    this.clearNowSecTimer();
  }

  onPageShow(): void {
    console.info(`[ChatDiag] show msgs=${this.messages.length} groups=${this.groups.length} ds=${this.groupsData.totalCount()}`);
    this.nowSec = Math.floor(Date.now() / 1000);
    this.armNowSecTimer();
    // The chat page is cached underneath the live viewer. A successful
    // pushUrl can therefore leave the entry button in its transient busy
    // state when this page becomes visible again. Treat page visibility as
    // the end of navigation and re-confirm the current call state.
    this.liveDialogOpening = false;
    this.liveNavigationBusy = false;
    if (this.chatId > 0) {
      this.refreshVideoChat();
    }
  }

  aboutToDisappear(): void {
    this.clearNowSecTimer();
    if (this.unsubChatAction !== null) {
      this.unsubChatAction();
      this.unsubChatAction = null;
    }
    if (this.typingTimer !== -1) {
      clearInterval(this.typingTimer);
      this.typingTimer = -1;
    }
    // Sync the composer draft to the account (other devices see it). While an
    // edit is in progress the real draft is the stashed pre-edit text.
    this.store?.saveDraft(
      this.editingId !== 0 ? this.draftBeforeEdit : this.draft, this.replyToId
    );
    if (this.viewerVideoLandscape) {
      this.viewerVideoLandscape = false;
      setMediaViewerOrientation(getContext(this) as common.UIAbilityContext, false);
    }
    this.captureScrollResume();
    this.bottomChromeLayoutSeq++;
    this.imeTailPinned = false;
    this.imeLayoutSeq++;
    this.headerResolveSeq++;
    this.headerMenuShow = false;
    this.showReactionSheet = false;
    this.reactionTargetId = 0;
    this.forwardPickerSeq++;
    this.showForwardSheet = false;
    this.forwardSendingChatId = 0;
    this.headerProfileOpening = false;
    this.headerMuteUpdating = false;
    this.pageClosing = false;
    this.headerVisible = false;
    this.liveChatResolveSeq++;
    this.liveGroupResolveSeq++;
    this.liveChatRefreshInFlight = false;
    this.liveGroupRefreshInFlight = false;
    this.liveGroupRequestId = 0;
    this.liveDialogOpening = false;
    this.liveNavigationBusy = false;
    this.pinnedJumpBusy = false;
    this.topCardLoadingVisible = false;
    this.scrollActionSeq++;
    this.jumpLayoutSeq++;
    this.prependRestoreSeq++;
    this.scrollToBottomBusy = false;
    this.pendingScrollBottom = false;
    this.clearFloatingDate();
    if (this.headerNavigationTimer !== -1) {
      clearTimeout(this.headerNavigationTimer);
      this.headerNavigationTimer = -1;
    }
    if (this.headerEntranceTimer !== -1) {
      clearTimeout(this.headerEntranceTimer);
      this.headerEntranceTimer = -1;
    }
    if (this.topCardLoadingTimer !== -1) {
      clearTimeout(this.topCardLoadingTimer);
      this.topCardLoadingTimer = -1;
    }
    if (this.topCardActionTimer !== -1) {
      clearTimeout(this.topCardActionTimer);
      this.topCardActionTimer = -1;
    }
    this.cancelRecording();
    this.pendingFileOpenId = 0;
    this.pendingFileSaveId = 0;
    this.fileOpenInFlightId = 0;
    this.pendingMusicPlayId = 0;
    this.autoSavePendingIds = [];
    this.autoSaveInFlight = false;
    getVoicePlayback().setMusicCompletionListener(null);
    getVoicePlayback().stop();
    if (this.unsubMsg !== null) { this.unsubMsg(); this.unsubMsg = null; }
    if (this.unsubSub !== null) { this.unsubSub(); this.unsubSub = null; }
    if (this.unsubChat !== null) { this.unsubChat(); this.unsubChat = null; }
    if (this.unsubLiveLocation !== null) {
      this.unsubLiveLocation();
      this.unsubLiveLocation = null;
    }
    if (this.unsubTranslatable !== null) {
      this.unsubTranslatable();
      this.unsubTranslatable = null;
    }
    if (this.unsubChatBackground !== null) {
      this.unsubChatBackground();
      this.unsubChatBackground = null;
    }
    if (this.unsubChatTheme !== null) {
      this.unsubChatTheme();
      this.unsubChatTheme = null;
    }
    if (this.unsubDefaultBackground !== null) {
      this.unsubDefaultBackground();
      this.unsubDefaultBackground = null;
    }
    if (this.unsubBackgroundFile !== null) {
      this.unsubBackgroundFile();
      this.unsubBackgroundFile = null;
    }
    if (this.unsubPinned !== null) { this.unsubPinned(); this.unsubPinned = null; }
    if (this.unsubHeaderAvatar !== null) { this.unsubHeaderAvatar(); this.unsubHeaderAvatar = null; }
    if (this.unsubHeaderTitle !== null) { this.unsubHeaderTitle(); this.unsubHeaderTitle = null; }
    if (this.unsubReplyKb !== null) { this.unsubReplyKb(); this.unsubReplyKb = null; }
    if (this.unsubMembershipSupergroup !== null) {
      this.unsubMembershipSupergroup();
      this.unsubMembershipSupergroup = null;
    }
    if (this.unsubMembershipBasicGroup !== null) {
      this.unsubMembershipBasicGroup();
      this.unsubMembershipBasicGroup = null;
    }
    this.membershipSeq++;
    if (this.unsubVideoChat !== null) { this.unsubVideoChat(); this.unsubVideoChat = null; }
    if (this.unsubGroupCall !== null) { this.unsubGroupCall(); this.unsubGroupCall = null; }
    if (this.livePulseTimer !== -1) { clearInterval(this.livePulseTimer); this.livePulseTimer = -1; }
    if (this.powerBackgroundTimer !== -1) {
      clearInterval(this.powerBackgroundTimer);
      this.powerBackgroundTimer = -1;
    }
    if (this.liveStateRefreshTimer !== -1) {
      clearInterval(this.liveStateRefreshTimer);
      this.liveStateRefreshTimer = -1;
    }
    if (this.store !== null) { this.store.close(); this.store = null; }
  }

  private resetTopCardState(): void {
    this.liveChatResolveSeq++;
    this.liveGroupResolveSeq++;
    this.pinnedPreview = '';
    this.pinnedCount = 0;
    this.pinnedCycle = 0;
    this.pinnedLoadState = this.threadRootId > 0 ? 'ready' : 'loading';
    this.pinnedJumpBusy = false;
    this.liveGroupCallId = 0;
    this.liveCallIsActive = false;
    this.liveCallIsRtmp = false;
    this.liveParticipantCount = 0;
    this.livePulseExpanded = false;
    this.liveLoadState = 'loading';
    this.liveDialogOpening = false;
    this.liveNavigationBusy = false;
    this.liveChatRefreshInFlight = false;
    this.liveGroupRefreshInFlight = false;
    this.liveGroupRequestId = 0;
    this.topCardLoadingVisible = false;
    if (this.topCardLoadingTimer !== -1) {
      clearTimeout(this.topCardLoadingTimer);
    }
    this.topCardLoadingTimer = setTimeout((): void => {
      this.topCardLoadingTimer = -1;
      this.topCardLoadingVisible =
        this.pinnedLoadState === 'loading' || this.liveLoadState === 'loading';
    }, powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, TOP_CARD_LOADING_DELAY_MS));
  }

  private settleTopCardLoading(): void {
    if (this.pinnedLoadState === 'loading' || this.liveLoadState === 'loading') {
      return;
    }
    if (this.topCardLoadingTimer !== -1) {
      clearTimeout(this.topCardLoadingTimer);
      this.topCardLoadingTimer = -1;
    }
    this.topCardLoadingVisible = false;
  }

  private topCardHasContent(): boolean {
    return this.pinnedPreview !== '' ||
      (this.liveGroupCallId > 0 && this.liveCallIsActive);
  }

  private topCardShouldShow(): boolean {
    // Pinned/live information is optional chrome. If its background probe
    // fails while TDLib is reconnecting and there is no confirmed content,
    // don't turn that transient transport problem into a persistent banner.
    return this.topCardHasContent() || this.topCardLoadingVisible;
  }

  // Resolve chat.video_chat first, then the referenced group call. Sequence
  // guards make a late response from a previous call/chat unable to restore a
  // banner that has already ended or changed identity.
  private refreshVideoChat(showLoading: boolean = false): void {
    if (this.chatId === 0) {
      this.liveLoadState = 'error';
      this.settleTopCardLoading();
      return;
    }
    if (this.liveChatRefreshInFlight) {
      return;
    }
    this.liveChatRefreshInFlight = true;
    const seq: number = ++this.liveChatResolveSeq;
    if (showLoading && !this.liveCallIsActive) {
      this.liveLoadState = 'loading';
    }
    const req: TdRequest = { '@type': 'getChat' };
    req['chat_id'] = this.chatId;
    getTdClient().send(req).then((chat: TdObject): void => {
      if (seq !== this.liveChatResolveSeq) {
        return;
      }
      this.liveChatRefreshInFlight = false;
      this.liveLoadState = 'ready';
      const vc = chat['video_chat'] as TdObject | undefined;
      this.setLiveGroupCallId(vc !== undefined ? ((vc['group_call_id'] as number | undefined) ?? 0) : 0);
      this.settleTopCardLoading();
    }).catch((e: TdError): void => {
      if (seq !== this.liveChatResolveSeq) {
        return;
      }
      this.liveChatRefreshInFlight = false;
      // A transient refresh failure must not invalidate an active call already
      // confirmed by ChatStore/updateGroupCall.
      if (!this.liveCallIsActive) {
        this.liveLoadState = 'error';
      }
      this.settleTopCardLoading();
      console.error(`ChatPage.refreshVideoChat getChat failed: ${e.message}`);
    });
  }

  private setLiveGroupCallId(groupCallId: number): void {
    const changed = groupCallId !== this.liveGroupCallId;
    if (changed) {
      this.liveGroupResolveSeq++;
      this.liveGroupRefreshInFlight = false;
      this.liveGroupRequestId = 0;
      this.liveGroupCallId = groupCallId;
      this.liveCallIsActive = false;
      this.liveCallIsRtmp = false;
      this.liveParticipantCount = 0;
      this.livePulseExpanded = false;
    }
    if (groupCallId <= 0) {
      this.liveLoadState = 'ready';
      this.settleTopCardLoading();
      return;
    }
    // An unchanged id still needs refreshing because a scheduled call may
    // become active (or an active call end) without changing its identifier.
    if (this.liveGroupRefreshInFlight && this.liveGroupRequestId === groupCallId) {
      return;
    }
    const seq: number = ++this.liveGroupResolveSeq;
    this.liveGroupRefreshInFlight = true;
    this.liveGroupRequestId = groupCallId;
    if (!this.liveCallIsActive) {
      this.liveLoadState = 'loading';
    }
    const request: TdRequest = { '@type': 'getGroupCall' };
    request['group_call_id'] = groupCallId;
    getTdClient().send(request).then((groupCall: TdObject): void => {
      if (seq !== this.liveGroupResolveSeq || this.liveGroupCallId !== groupCallId) {
        return;
      }
      this.liveGroupRefreshInFlight = false;
      this.liveGroupRequestId = 0;
      this.applyLiveGroupCall(groupCall);
    }).catch((error: TdError): void => {
      if (seq !== this.liveGroupResolveSeq || this.liveGroupCallId !== groupCallId) {
        return;
      }
      this.liveGroupRefreshInFlight = false;
      this.liveGroupRequestId = 0;
      if (!this.liveCallIsActive) {
        this.liveLoadState = 'error';
      }
      this.settleTopCardLoading();
      console.error(`ChatPage.getGroupCall failed: ${error.message}`);
    });
  }

  private applyLiveGroupCall(groupCall: TdObject): void {
    this.liveCallIsActive = (groupCall['is_active'] as boolean | undefined) ?? false;
    this.liveCallIsRtmp = (groupCall['is_rtmp_stream'] as boolean | undefined) ?? false;
    this.liveParticipantCount = (groupCall['participant_count'] as number | undefined) ?? 0;
    this.liveLoadState = 'ready';
    if (!this.liveCallIsActive) {
      this.livePulseExpanded = false;
      this.liveDialogOpening = false;
    }
    this.settleTopCardLoading();
  }

  private enterLiveStream(groupCallId: number): void {
    if (this.liveNavigationBusy) {
      return;
    }
    if (groupCallId <= 0 || groupCallId !== this.liveGroupCallId ||
      !this.liveCallIsActive || this.liveLoadState === 'error') {
      promptAction.showToast({ message: '直播已经结束', duration: 1500 });
      return;
    }
    const isRtmp: boolean = this.liveCallIsRtmp;
    const params: Record<string, Object> = {
      'groupCallId': groupCallId,
      'chatId': this.chatId,
      'initialTitle': this.title,
      'initialParticipantCount': this.liveParticipantCount
    };
    this.liveNavigationBusy = true;
    // Returning to the live stream that is already floating must hand the
    // existing Session back to the viewer. Closing it here would briefly leave
    // the call and force the page to join again.
    if (floatingLiveWindow.isShowing(groupCallId, isRtmp)) {
      floatingLiveWindow.restoreFullPage().finally((): void => {
        this.liveNavigationBusy = false;
      });
      return;
    }
    floatingLiveWindow.prepareForOpeningFullPage().finally((): void => {
      if (groupCallId !== this.liveGroupCallId || !this.liveCallIsActive) {
        this.liveNavigationBusy = false;
        promptAction.showToast({ message: '直播已经结束', duration: 1500 });
        return;
      }
      router.pushUrl({
        url: isRtmp
          ? 'pages/chat/RtmpLiveStreamViewerPage' : 'pages/chat/LiveStreamViewerPage',
        params: params
      }).then((): void => {
        // Busy only represents the route transition. Joining/recovery status
        // belongs to the viewer and must not leak into the chat banner.
        this.liveNavigationBusy = false;
      }).catch((error: Error): void => {
        this.liveNavigationBusy = false;
        console.error(`ChatPage.enterLiveStream failed: ${error.message}`);
        promptAction.showToast({ message: '无法进入直播，请重试', duration: 1600 });
      });
    });
  }

  // All live entry points confirm before joining. The viewer itself joins
  // muted, so the dialog can state the privacy behavior precisely.
  private onLiveStreamTap(): void {
    if (this.liveDialogOpening || this.liveNavigationBusy) {
      return;
    }
    if (this.liveLoadState === 'loading') {
      promptAction.showToast({ message: '正在同步直播状态', duration: 1200 });
      return;
    }
    if (this.liveLoadState === 'error') {
      this.refreshVideoChat(true);
      promptAction.showToast({ message: '正在重新获取直播状态', duration: 1200 });
      return;
    }
    if (this.liveGroupCallId <= 0 || !this.liveCallIsActive) {
      promptAction.showToast({ message: '直播已经结束', duration: 1500 });
      return;
    }
    const groupCallId = this.liveGroupCallId;
    const onlineText = this.liveParticipantCount > 0 ? `当前有 ${this.liveParticipantCount} 人在线。` : '';
    const privacyText = this.liveCallIsRtmp
      ? '这是单向直播，进入后只能观看和参与直播互动，不会打开麦克风或摄像头。'
      : '进入后默认静音播放，不会自动打开麦克风；如有发言权限，可在直播间内开麦。';
    this.liveDialogOpening = true;
    promptAction.showDialog({
      title: '进入直播？',
      message: `${onlineText}${privacyText}`,
      buttons: [
        { text: '取消', color: '#8E8E93' },
        { text: '进入直播', color: '#FF405C' }
      ]
    }).then((result): void => {
      this.liveDialogOpening = false;
      if (result.index === 1) { this.enterLiveStream(groupCallId); }
    }).catch((error: Object): void => {
      this.liveDialogOpening = false;
      console.error(`ChatPage live confirmation failed: ${JSON.stringify(error)}`);
    });
  }

  // True-bottom detection off the scroller's end edge, not the visible index
  // range: a single tall last message can be scrolled within without changing
  // any index, so an index-based check leaves atBottom stuck true and the glue
  // keeps snapping back down. Frozen while the media viewer is open so the
  // underlying chat position is stable when the preview closes.
  private refreshAtBottom(): void {
    if (this.viewerMsgId === 0) {
      // During an IME resize the last row is briefly clipped before List has
      // received its new height. Keep the pre-focus verdict until the layout
      // settles; a real list touch clears imeTailPinned first.
      if (this.imeTailPinned) {
        if (!this.atBottom) {
          this.atBottom = true;
        }
        return;
      }
      // The end of a loadAround window is not the live end of the chat. Keep
      // the down button available until MessageStore has actually exhausted
      // newer history.
      const nextAtBottom = this.scroller.isAtEnd() &&
        (this.store === null || !this.store.getHasMoreNewer());
      if (this.atBottom !== nextAtBottom) {
        this.atBottom = nextAtBottom;
      }
    }
  }

  private syncTailAfterImeResize(releaseAfter: boolean = false): void {
    if (!this.imeTailPinned || this.viewerMsgId !== 0) {
      return;
    }
    const seq: number = ++this.imeLayoutSeq;
    this.atBottom = true;
    this.stayAtUnread = false;
    // First pass follows the current resize frame; the second pass catches the
    // final List measurement after the system IME animation has settled.
    setTimeout((): void => {
      if (seq === this.imeLayoutSeq && this.imeTailPinned) {
        this.scroller.scrollEdge(Edge.Bottom);
      }
    }, 0);
    setTimeout((): void => {
      if (seq !== this.imeLayoutSeq || !this.imeTailPinned) {
        return;
      }
      this.scroller.scrollEdge(Edge.Bottom);
      this.atBottom = true;
      if (releaseAfter) {
        this.imeTailPinned = false;
      }
    }, releaseAfter ? 180 : 80);
  }

  private syncTailOnImeFrame(): void {
    if (!this.imeTailPinned || this.viewerMsgId !== 0) {
      return;
    }
    this.atBottom = true;
    this.stayAtUnread = false;
    this.scroller.scrollEdge(Edge.Bottom);
  }

  private onKeyboardHeightChanged(): void {
    const wasVisible: boolean = this.lastKeyboardH > 0;
    const visible: boolean = this.keyboardH > 0;
    if (!wasVisible && visible && !this.imeTailPinned) {
      this.imeTailPinned = this.composerFocused && this.atBottom &&
        this.viewerMsgId === 0 && !this.stayAtUnread;
    }
    this.lastKeyboardH = this.keyboardH;
    if (this.imeTailPinned) {
      if (visible) {
        // keyboardHeightChange follows the system IME animation. Keep the
        // message tail on the same layout frame instead of adding a separate
        // delayed scroll animation with a visibly different velocity.
        this.syncTailOnImeFrame();
      } else {
        // Closing already tracks naturally; retain one settled correction for
        // the final navigation-inset layout.
        this.syncTailAfterImeResize(true);
      }
    }
  }

  private chatEffectDuration(key: string, duration: number): number {
    if (this.reduceAnimations || !powerFeatureEnabled(KEY_POWER_SMOOTH_TRANSITIONS)) {
      return 0;
    }
    return powerGroupAnimationDuration(KEY_POWER_CHAT_EFFECTS, key, duration);
  }

  private reactionEffectDuration(duration: number): number {
    if (!powerGroupFeatureEnabled(KEY_POWER_EMOJI, KEY_POWER_EMOJI_REACTIONS)) {
      return 0;
    }
    return this.chatEffectDuration(KEY_POWER_EFFECT_REACTION, duration);
  }

  private animationPaused(messageId: number): boolean {
    return this.pausedAnimationIds.indexOf(messageId) >= 0;
  }

  private animationForcePlay(messageId: number): boolean {
    return this.forcedAnimationIds.indexOf(messageId) >= 0;
  }

  private animationPlaybackFailed(messageId: number): boolean {
    return this.failedAnimationIds.indexOf(messageId) >= 0;
  }

  private withoutAnimationId(ids: number[], messageId: number): number[] {
    return ids.filter((id: number): boolean => id !== messageId);
  }

  private onAnimationTap(messageId: number, isPlaying: boolean): void {
    const entry = this.entryById(messageId);
    if (entry === null || !entry.isAnimation) {
      return;
    }
    if (entry.videoFileId === 0 && entry.videoPath === '') {
      promptAction.showToast({ message: '这个 GIF 暂时不可用', duration: 1500 });
      return;
    }
    if (isPlaying) {
      this.forcedAnimationIds = this.withoutAnimationId(this.forcedAnimationIds, messageId);
      if (!this.animationPaused(messageId)) {
        this.pausedAnimationIds = [...this.pausedAnimationIds, messageId];
      }
      return;
    }

    // A manual play request has priority over auto-play/power-saving policy,
    // but remains viewport/foreground scoped by MessageBubble.
    this.pausedAnimationIds = this.withoutAnimationId(this.pausedAnimationIds, messageId);
    this.failedAnimationIds = this.withoutAnimationId(this.failedAnimationIds, messageId);
    if (!this.animationForcePlay(messageId)) {
      this.forcedAnimationIds = [...this.forcedAnimationIds, messageId];
    }
    if (entry.videoPath === '') {
      this.store?.requestVideoDownload(messageId, false, entry.videoFailed);
    }
  }

  private onAnimationPlaybackFailed(messageId: number): void {
    if (!this.animationPlaybackFailed(messageId)) {
      this.failedAnimationIds = [...this.failedAnimationIds, messageId];
    }
    this.forcedAnimationIds = this.withoutAnimationId(this.forcedAnimationIds, messageId);
    if (!this.animationPaused(messageId)) {
      this.pausedAnimationIds = [...this.pausedAnimationIds, messageId];
    }
  }

  private mediaEntryIsPhoto(entry: MessageEntry): boolean {
    return entry.contentType === 'photo' ||
      (entry.contentType === 'paidMedia' && !entry.paidMediaLocked &&
        entry.paidMediaKind === 'photo');
  }

  private mediaEntryIsVideo(entry: MessageEntry): boolean {
    // 圆形视频不进全屏查看器——它在气泡里原地播放（见 MessageBubble）。
    return entry.contentType === 'video' ||
      (entry.contentType === 'paidMedia' && !entry.paidMediaLocked &&
        entry.paidMediaKind === 'video');
  }

  // Open/close wrapped in animateTo so the viewer's own transition remains
  // smooth without moving/re-parenting the chat thumbnail Image node.
  private openViewer(messageId: number): void {
    if (this.viewerClosing) {
      return;
    }
    const entry = this.entryById(messageId);
    if (entry === null) {
      return;
    }
    if (entry.contentType === 'paidMedia' && entry.paidMediaLocked) {
      this.onPaidMediaUnlock(messageId);
      return;
    }
    if (!this.mediaEntryIsPhoto(entry) && !this.mediaEntryIsVideo(entry)) {
      return;
    }
    if (this.mediaEntryIsPhoto(entry) && entry.photoPath === '' && entry.photoFailed) {
      this.store?.retryPhoto(messageId);
      promptAction.showToast({ message: '正在重新加载缩略图', duration: 1200 });
      return;
    }
    if (this.mediaEntryIsPhoto(entry) && entry.photoPath === '' &&
      entry.photoFullPath === '' && entry.photoFileId === 0 && entry.photoFullFileId === 0) {
      promptAction.showToast({ message: '这张图片暂时不可用', duration: 1500 });
      return;
    }
    if (this.mediaEntryIsVideo(entry)) {
      if (entry.videoFileId === 0 && entry.videoPath === '') {
        promptAction.showToast({ message: '视频文件暂时不可用', duration: 1500 });
        return;
      }
      // A cover failure must not block a playable video. Retry it quietly so
      // the viewer can gain a poster while the stream starts.
      if (entry.photoPath === '' && entry.photoFailed) {
        this.store?.retryPhoto(messageId);
      }
      // Streaming needs a total size for byte ranges. If TDLib hasn't supplied
      // one yet, finish a normal download first instead of opening a viewer
      // that can only report "无法获取视频大小".
      if (entry.videoPath === '' && entry.videoFileSize <= 0) {
        this.store?.requestVideoDownload(messageId, true, entry.videoFailed);
        promptAction.showToast({ message: '正在获取视频文件，请稍后再试', duration: 1800 });
        return;
      }
      if (entry.videoFailed) {
        // A failed autoplay/save download is recoverable and doesn't prevent
        // the independent streaming player from opening immediately.
        this.store?.requestVideoDownload(messageId, false, true);
      }
    }
    this.viewerIgnoreTapUntilMs = 0;
    this.resetViewerPhotoZoom(false);
    animateTo({ duration: this.chatEffectDuration(KEY_POWER_EFFECT_BLUR, 300), curve: Curve.Friction }, () => {
      this.onMediaTap(messageId);
    });
  }

  private closeViewer(): void {
    if (this.viewerMsgId === 0 || this.viewerClosing) {
      return;
    }
    if (this.viewerVideoLandscape) {
      this.setViewerVideoLandscape(false);
    }
    const duration: number = this.chatEffectDuration(KEY_POWER_EFFECT_BLUR, 260);
    this.viewerClosing = true;
    animateTo({ duration, curve: Curve.Friction }, () => {
      this.viewerPhotoScale = VIEWER_MIN_SCALE;
      this.viewerPhotoOffsetX = 0;
      this.viewerPhotoOffsetY = 0;
      this.viewerPinchStartScale = VIEWER_MIN_SCALE;
      this.viewerIgnoreTapUntilMs = 0;
      this.viewerMsgId = 0;
      this.viewerInitIdx = 0;
      this.chromeVisible = true;
    });
    setTimeout((): void => { this.viewerClosing = false; }, Math.max(80, duration));
  }

  // System back (gesture/hardware button): close the fullscreen viewer first
  // if it's open, rather than popping all the way back to the chat list.
  onBackPress(): boolean {
    // 录制浮层盖住整页，返回键必须先关它（组件退场时会取消录制并删掉临时文件）。
    if (this.showVideoNoteRecorder) {
      this.showVideoNoteRecorder = false;
      return true;
    }
    if (this.headerMenuShow) {
      this.headerMenuShow = false;
      return true;
    }
    if (this.showForwardSheet) {
      this.closeForwardSheet();
      return true;
    }
    if (this.showReactionSheet) {
      this.closeReactionSheet();
      return true;
    }
    if (this.viewerMsgId !== 0) {
      if (this.viewerVideoLandscape) {
        this.setViewerVideoLandscape(false);
        return true;
      }
      this.closeViewer();
      return true;
    }
    if (this.selecting) {
      this.exitSelect();
      return true;
    }
    if (this.searchMode) {
      this.exitSearch();
      return true;
    }
    return false;
  }

  // Private chat: the peer's emoji status appears beside the header title.
  private fetchHeaderEmojiStatus(): void {
    if (this.headerEmojiFetched) {
      return;
    }
    const uid = this.headerPeerUserId > 0
      ? this.headerPeerUserId : (this.store !== null ? this.store.getPeerUserId() : 0);
    if (uid <= 0) {
      return;
    }
    const resolveSeq = this.headerResolveSeq;
    this.headerEmojiFetched = true;
    const req: TdRequest = { '@type': 'getUser' };
    req['user_id'] = uid;
    getTdClient().send(req).then((user: TdObject) => {
      resolveEmojiStatus(user['emoji_status'] as TdObject | undefined, (path: string, format: string) => {
        const currentUid = this.headerPeerUserId > 0
          ? this.headerPeerUserId : (this.store !== null ? this.store.getPeerUserId() : 0);
        if (resolveSeq !== this.headerResolveSeq || uid !== currentUid) {
          return;
        }
        this.headerEmojiPath = path;
        this.headerEmojiFormat = format;
      });
    }).catch((e: TdError) => {
      if (resolveSeq === this.headerResolveSeq) {
        this.headerEmojiFetched = false;
      }
      console.error(`ChatPage.fetchHeaderEmojiStatus failed: ${e.message}`);
    });
  }

  // Refresh the floating date chip from the topmost visible row and (re)arm
  // its fade-out. This is called only for a touch-originated scroll session:
  // initial positioning and reply/pinned jumps must not flash the chip.
  private updateFloatDate(start: number): void {
    if (!this.didInitialScroll || start < 0 || start >= this.groups.length) {
      return;
    }
    const now = Date.now();
    // onDidScroll fires every rendered frame. If the top row hasn't changed,
    // skip the group scan, date formatting and @State writes; only refresh the
    // hide timer at a coarse cadence so a long drag keeps the chip visible.
    if (start === this.floatDateIndex && this.floatDateShown) {
      if (now - this.floatDateTimerArmedAt < 180) {
        return;
      }
      this.armFloatDateHide(now);
      return;
    }
    let date: number = 0;
    for (let i = start; i < this.groups.length; i++) {
      if (this.groups[i].head.date > 0) {
        date = this.groups[i].head.date;
        break;
      }
    }
    if (date <= 0) {
      return;
    }
    const nextLabel = formatDateSeparator(date);
    if (this.floatDate !== nextLabel) {
      this.floatDate = nextLabel;
    }
    if (!this.floatDateShown) {
      this.floatDateShown = true;
    }
    if (!this.listUserScrollActive) {
      this.listUserScrollActive = true;
    }
    this.floatDateIndex = start;
    this.armFloatDateHide(now);
  }

  private armFloatDateHide(now: number): void {
    this.floatDateTimerArmedAt = now;
    if (this.floatDateHideTimer !== -1) {
      clearTimeout(this.floatDateHideTimer);
    }
    this.floatDateHideTimer = setTimeout(() => {
      this.floatDateHideTimer = -1;
      this.floatDateShown = false;
      this.listUserScrollActive = false;
      this.floatDateIndex = -1;
    }, 820);
  }

  private prepareUserJump(): void {
    this.clearFloatingDate();
    this.stayAtUnread = false;
    this.jumpLayoutSeq++;
    this.cancelFlash();
  }

  // The banner tracks the scroll position: it shows the newest pinned message
  // strictly ABOVE the viewport top (the one a tap would jump to). Scrolling
  // past a pinned message therefore switches the banner to its neighbor, and
  // after a tap-jump lands this naturally advances to the next older one.
  private updatePinnedFromScroll(start: number): void {
    if (this.store === null || this.pinnedCount === 0 || start < 0 || start >= this.groups.length) {
      return;
    }
    const ids: number[] = this.store.getPinnedIds(); // newest → oldest
    const previews: string[] = this.store.getPinnedPreviews();
    const topId: number = this.groups[start].head.id;
    let idx = -1;
    for (let i = 0; i < ids.length; i++) {
      if (ids[i] < topId) {
        idx = i;
        break;
      }
    }
    if (idx < 0) {
      idx = ids.length - 1; // viewport is above every pinned message → nearest is the oldest
    }
    if (idx !== this.pinnedShownIdx()) {
      this.pinnedCycle = idx;
      if (idx < previews.length) {
        this.pinnedPreview = previews[idx];
      }
    }
  }

  // Tap the pinned banner: jump to the pinned message it currently shows.
  // Once at/above the oldest pinned message, tapping wraps back to the bottom.
  private onPinnedTap(): void {
    if (this.pinnedJumpBusy) {
      return;
    }
    if (this.pinnedLoadState === 'error') {
      this.store?.refreshPinned();
      promptAction.showToast({ message: '正在重新同步置顶消息', duration: 1200 });
      return;
    }
    if (this.store === null) {
      return;
    }
    const ids: number[] = this.store.getPinnedIds();
    if (ids.length === 0) {
      this.pinnedPreview = '';
      this.pinnedCount = 0;
      return;
    }
    this.startPinnedJumpGuard(2500);
    this.prepareUserJump();
    const idx: number = this.pinnedShownIdx();
    const targetId: number = ids[idx];
    const topId: number = this.curStartIdx >= 0 && this.curStartIdx < this.groups.length
      ? this.groups[this.curStartIdx].head.id : 0;
    if (idx === ids.length - 1 && topId !== 0 && topId <= targetId) {
      this.scrollToLatest();
      this.startPinnedJumpGuard(TOP_CARD_ACTION_GUARD_MS);
      return;
    }
    const gidx: number = groupIndexOf(this.groups, targetId);
    if (gidx >= 0) {
      this.scroller.scrollToIndex(gidx, false, ScrollAlign.START);
      this.flashAtIndex(gidx);
      this.startPinnedJumpGuard(TOP_CARD_ACTION_GUARD_MS);
    } else {
      this.pendingJumpId = targetId;
      this.store.loadAround(targetId, (found: boolean): void => {
        if (!found && this.pendingJumpId === targetId) {
          this.pendingJumpId = 0;
          this.finishPinnedJump();
          this.store?.refreshPinned();
          promptAction.showToast({ message: '这条置顶消息已不可用', duration: 1500 });
        }
      });
    }
  }

  private startPinnedJumpGuard(duration: number): void {
    this.pinnedJumpBusy = true;
    if (this.topCardActionTimer !== -1) {
      clearTimeout(this.topCardActionTimer);
    }
    this.topCardActionTimer = setTimeout((): void => {
      this.topCardActionTimer = -1;
      this.pinnedJumpBusy = false;
    }, duration);
  }

  private finishPinnedJump(): void {
    this.pinnedJumpBusy = false;
    if (this.topCardActionTimer !== -1) {
      clearTimeout(this.topCardActionTimer);
      this.topCardActionTimer = -1;
    }
  }

  // Bottom inset for bars (empirically tuned on device): with the keyboard up
  // the bar needs lifting clear of the IME edge; without it the layout already
  // sits above the gesture bar, so only minimal padding applies.
  private bottomInset(): number {
    return this.keyboardH > 0 ? Math.max(this.bottomSafe, 12) : this.bottomSafe;
  }

  // Fire at most one loadOlder per arm (see olderArmed).
  private maybeLoadOlder(): void {
    if (this.olderArmed && this.store !== null) {
      const started = this.store.loadOlder();
      if (started || !this.store.getHasMoreOlder()) {
        this.olderArmed = false;
      }
    }
  }

  // A history page is inserted before the current window. Keep the exact
  // message and its partial row offset under the user's finger; the newly
  // loaded rows should only appear as they continue scrolling upward.
  private restorePrependAnchor(groups: AlbumGroup[], messageId: number, itemY: number): void {
    const targetIndex: number = groupIndexOf(groups, messageId);
    if (targetIndex < 0) {
      return;
    }
    this.restoreScrollAnchor(targetIndex, itemY);
  }

  private restoreScrollAnchor(targetIndex: number, itemY: number): void {
    const seq: number = ++this.prependRestoreSeq;
    setTimeout((): void => {
      if (seq !== this.prependRestoreSeq || this.pendingJumpId !== 0 || this.pendingScrollBottom) {
        return;
      }
      this.scroller.scrollToIndex(targetIndex, false, ScrollAlign.START);
      if (itemY < -0.5) {
        this.scroller.scrollBy(0, -itemY);
      }
    }, 0);
  }

  private resetHeaderState(cached: ChatEntry | undefined): void {
    this.headerResolveSeq++;
    this.headerState = 'loading';
    this.headerLoadError = '';
    this.headerPeerUserId = 0;
    this.headerKind = '';
    this.headerIdentityResolved = false;
    this.headerEmojiPath = '';
    this.headerEmojiFormat = '';
    this.headerEmojiFetched = false;
    this.headerMenuShow = false;
    this.headerProfileOpening = false;
    this.headerMuteUpdating = false;
    this.pageClosing = false;
    this.headerVisible = false;
    this.subtitle = '';
    this.avatarPath = '';
    this.initials = '?';
    this.title = this.forumTopicId > 0
      ? (this.topicName !== '' ? this.topicName : '话题')
      : (this.threadRootId > 0 ? (this.topicName !== '' ? this.topicName : '评论') : '');
    this.isMuted = false;
    if (cached !== undefined) {
      if (this.threadRootId === 0 && this.forumTopicId === 0) {
        this.title = cached.title;
      }
      this.initials = cached.initials;
      this.avatarPath = cached.avatarPath;
      this.isMuted = cached.isMuted;
      if (cached.kind === 'private') {
        // TDLib private-chat identifiers equal the peer user identifier.
        this.headerKind = 'private';
        this.headerPeerUserId = cached.id;
        this.headerIdentityResolved = true;
      } else if (cached.kind === 'basicGroup' || cached.kind === 'supergroup' ||
        cached.kind === 'channel') {
        this.headerKind = cached.kind === 'channel' ? 'channel' : 'group';
        this.headerIdentityResolved = true;
      } else {
        this.headerKind = 'secret';
      }
      if (cached.title !== '') {
        this.headerState = 'ready';
      }
    }
    if (this.headerEntranceTimer !== -1) {
      clearTimeout(this.headerEntranceTimer);
    }
    this.headerEntranceTimer = setTimeout((): void => {
      this.headerEntranceTimer = -1;
      this.headerVisible = true;
    }, powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 24));
  }

  private applyResolvedHeaderChat(chat: TdObject, seq: number): void {
    if (seq !== this.headerResolveSeq) {
      return;
    }
    const resolvedTitle = (chat['title'] as string | undefined) ?? '';
    if (resolvedTitle !== '') {
      if (this.threadRootId === 0 && this.forumTopicId === 0) {
        this.title = resolvedTitle;
      }
      this.initials = computeInitials(resolvedTitle);
    }
    const settings = chat['notification_settings'] as TdObject | undefined;
    if (settings !== undefined && !this.headerMuteUpdating) {
      this.isMuted = isMutedFrom(settings);
      this.isTranslatable = (chat['is_translatable'] as boolean | undefined) ?? false;
    }
    const photo = chat['photo'] as TdObject | undefined;
    const small = photo !== undefined ? (photo['small'] as TdObject | undefined) : undefined;
    const local = small !== undefined ? (small['local'] as TdObject | undefined) : undefined;
    const localPath = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
    const localReady = local !== undefined
      ? ((local['is_downloading_completed'] as boolean | undefined) ?? false) : false;
    if (localReady && localPath !== '') {
      this.avatarPath = localPath;
    }
    const type = chat['type'] as TdObject | undefined;
    const typeName = type !== undefined ? ((type['@type'] as string | undefined) ?? '') : '';
    if (typeName === 'chatTypePrivate') {
      this.headerKind = 'private';
      this.headerPeerUserId = (type!['user_id'] as number | undefined) ?? this.chatId;
      this.headerIdentityResolved = this.headerPeerUserId > 0;
      this.isGroup = false;
      this.isChannel = false;
      this.refreshBotMiniApp(this.headerPeerUserId);
    } else if (typeName === 'chatTypeBasicGroup') {
      this.headerKind = 'group';
      this.headerIdentityResolved = true;
      this.isGroup = true;
      this.isChannel = false;
    } else if (typeName === 'chatTypeSupergroup') {
      this.isChannel = (type!['is_channel'] as boolean | undefined) ?? false;
      this.headerKind = this.isChannel ? 'channel' : 'group';
      this.headerIdentityResolved = true;
      this.isGroup = true;
    } else if (typeName === 'chatTypeSecret') {
      this.headerKind = 'secret';
      this.isGroup = false;
      this.isChannel = false;
      const secretId = (type!['secret_chat_id'] as number | undefined) ?? 0;
      if (secretId > 0) {
        const secretReq: TdRequest = { '@type': 'getSecretChat' };
        secretReq['secret_chat_id'] = secretId;
        getTdClient().send(secretReq).then((secret: TdObject): void => {
          if (seq !== this.headerResolveSeq) {
            return;
          }
          this.headerPeerUserId = (secret['user_id'] as number | undefined) ?? 0;
          this.headerIdentityResolved = this.headerPeerUserId > 0;
          this.fetchHeaderEmojiStatus();
        }).catch((error: TdError): void => {
          console.error(`ChatPage.getSecretChat header failed: ${error.message}`);
        });
      }
    }
    this.headerState = resolvedTitle !== '' || this.title !== '' ? 'ready' : 'error';
    this.headerLoadError = this.headerState === 'error' ? '会话信息暂不可用' : '';
    this.fetchHeaderEmojiStatus();
  }

  private resolveHeaderIdentity(): void {
    if (this.chatId === 0) {
      this.headerState = 'error';
      this.headerLoadError = '会话参数无效';
      return;
    }
    const seq = ++this.headerResolveSeq;
    if (this.title === '') {
      this.headerState = 'loading';
      this.headerLoadError = '';
    }
    const request: TdRequest = { '@type': 'getChat' };
    request['chat_id'] = this.chatId;
    getTdClient().send(request).then((chat: TdObject): void => {
      this.applyResolvedHeaderChat(chat, seq);
    }).catch((error: TdError): void => {
      if (seq !== this.headerResolveSeq) {
        return;
      }
      if (this.title === '') {
        this.headerState = 'error';
        this.headerLoadError = '会话信息加载失败，点击重试';
      }
      console.error(`ChatPage.resolveHeaderIdentity failed: ${error.message}`);
    });
  }

  private headerTitleText(): string {
    if (this.title !== '') {
      return this.title;
    }
    return this.headerState === 'error' ? '无法读取聊天' : '正在加载';
  }

  private headerSubtitleText(): string {
    if (this.subtitle !== '') {
      return this.subtitle;
    }
    if (this.headerState === 'loading') {
      return '正在获取会话信息…';
    }
    if (this.headerState === 'error') {
      return this.headerLoadError !== '' ? this.headerLoadError : '点击重试';
    }
    if (this.headerKind === 'channel') {
      return '频道';
    }
    if (this.headerKind === 'group') {
      return '群组';
    }
    if (this.headerKind === 'secret') {
      return '加密聊天';
    }
    return 'Telegram 用户';
  }

  private refreshHeader(): void {
    if (this.threadRootId > 0) {
      // Comment-thread view: fixed title, the rest of the header still shows
      // the discussion group's avatar/mute state.
      this.title = '评论';
    }
    const e: ChatEntry | undefined = getChatStore().entryOf(this.chatId);
    if (e !== undefined) {
      if (this.threadRootId === 0 && this.forumTopicId === 0) {
        this.title = e.title;
      }
      // Don't clobber a MessageStore-resolved avatar (channels/folders) with an empty one.
      if (e.avatarPath !== '') { this.avatarPath = e.avatarPath; }
      this.initials = e.initials;
      if (!this.headerMuteUpdating) {
        this.isMuted = e.isMuted;
      }
      this.unreadBadge = e.unreadCount; // live unread count for the scroll-to-bottom badge
      if (e.title !== '') {
        this.headerState = 'ready';
        this.headerLoadError = '';
      }
      if (!this.headerIdentityResolved) {
        if (e.kind === 'private') {
          this.headerKind = 'private';
          this.headerPeerUserId = e.id;
          this.headerIdentityResolved = true;
        } else if (e.kind === 'basicGroup' || e.kind === 'supergroup' || e.kind === 'channel') {
          this.headerKind = e.kind === 'channel' ? 'channel' : 'group';
          this.headerIdentityResolved = true;
        }
      }
      if (e.background !== null) {
        this.applyChatBackground(e.background);
      }
      this.syncLiveFromChatEntry(e);
    }
  }

  // ChatStore already resolves updateChatVideoChat + updateGroupCall for the
  // chat list. Reuse that confirmed state as the fast path when entering or
  // resuming a chat instead of hiding the live banner until a second
  // getChat/getGroupCall round trip finishes. The direct probe below remains
  // authoritative and will still remove a call once TDLib confirms it ended.
  private syncLiveFromChatEntry(entry: ChatEntry): void {
    if (entry.liveGroupCallId <= 0) {
      // A cache miss is not proof that a call ended: getChat may already have
      // found a newer call which hasn't reached ChatStore yet.
      return;
    }
    if (entry.liveGroupCallId !== this.liveGroupCallId) {
      this.setLiveGroupCallId(entry.liveGroupCallId);
    }
    if (!entry.isLive || entry.liveGroupCallId !== this.liveGroupCallId) {
      return;
    }
    this.liveCallIsActive = true;
    this.liveCallIsRtmp = entry.isRtmpLive;
    this.liveLoadState = 'ready';
    this.settleTopCardLoading();
  }

  private objectOrNull(value: Object | null | undefined): TdObject | null {
    return value !== undefined && value !== null ? value as TdObject : null;
  }

  private tdColor(value: number): string {
    let hex = (value & 0xFFFFFF).toString(16).toUpperCase();
    while (hex.length < 6) {
      hex = `0${hex}`;
    }
    return `#${hex}`;
  }

  private fillColors(fill: TdObject | null): string[] {
    if (fill === null) {
      return [];
    }
    const type = (fill['@type'] as string | undefined) ?? '';
    if (type === 'backgroundFillSolid') {
      return [this.tdColor((fill['color'] as number | undefined) ?? 0)];
    }
    if (type === 'backgroundFillGradient') {
      return [
        this.tdColor((fill['top_color'] as number | undefined) ?? 0),
        this.tdColor((fill['bottom_color'] as number | undefined) ?? 0)
      ];
    }
    if (type === 'backgroundFillFreeformGradient') {
      const values = (fill['colors'] as number[] | undefined) ?? [];
      return values.map((color: number): string => this.tdColor(color));
    }
    return [];
  }

  private backgroundFile(background: TdObject, pattern: boolean): TdObject | null {
    const document = this.objectOrNull(background['document']);
    if (document === null) {
      return null;
    }
    if (pattern) {
      const thumbnail = this.objectOrNull(document['thumbnail']);
      const thumbnailFile = thumbnail !== null ? this.objectOrNull(thumbnail['file']) : null;
      if (thumbnailFile !== null) {
        return thumbnailFile;
      }
    }
    return this.objectOrNull(document['document']);
  }

  private localFilePath(file: TdObject): string {
    const local = this.objectOrNull(file['local']);
    if (local === null ||
      !((local['is_downloading_completed'] as boolean | undefined) ?? false)) {
      return '';
    }
    return (local['path'] as string | undefined) ?? '';
  }

  private applyBackgroundFile(file: TdObject): void {
    const fileId = (file['id'] as number | undefined) ?? 0;
    if (fileId === 0 || fileId !== this.chatBackgroundFileId) {
      return;
    }
    const path = this.localFilePath(file);
    if (path !== '' && path !== this.chatBackgroundPath) {
      this.chatBackgroundPath = path;
      console.info(`[ChatBackground] chat=${this.chatId} file=${fileId} ready=true`);
    }
  }

  private requestBackgroundFile(file: TdObject): void {
    const fileId = (file['id'] as number | undefined) ?? 0;
    this.chatBackgroundFileId = fileId;
    if (fileId <= 0) {
      return;
    }
    const localPath = this.localFilePath(file);
    if (localPath !== '') {
      this.chatBackgroundPath = localPath;
      console.info(`[ChatBackground] chat=${this.chatId} file=${fileId} cached=true`);
      return;
    }
    console.info(`[ChatBackground] chat=${this.chatId} file=${fileId} download=true`);
    const request: TdRequest = { '@type': 'downloadFile' };
    request['file_id'] = fileId;
    request['priority'] = 1;
    request['offset'] = 0;
    request['limit'] = 0;
    request['synchronous'] = false;
    getTdClient().send(request).then((downloaded: TdObject): void => {
      this.applyBackgroundFile(downloaded);
    }).catch((error: TdError): void => {
      console.error(`ChatPage background download ${fileId} failed: ${error.message}`);
    });
  }

  private applyChatBackground(chatBackground: TdObject | null): void {
    const signature = chatBackground !== null ? JSON.stringify(chatBackground) : 'none';
    if (signature === this.chatBackgroundSignature) {
      return;
    }
    this.chatBackgroundSignature = signature;
    this.chatBackgroundCustom = false;
    this.chatBackgroundColors = [];
    this.chatBackgroundAngle = 180;
    this.chatBackgroundPath = '';
    this.chatBackgroundImageOpacity = 1;
    this.chatBackgroundDimming = 0;
    this.chatBackgroundBlurred = false;
    this.chatBackgroundFileId = 0;
    if (chatBackground === null) {
      return;
    }

    // Chat.background is a chatBackground wrapper around the reusable
    // background object. Accept a bare background too for API compatibility.
    const nested = this.objectOrNull(chatBackground['background']);
    const background = nested !== null ? nested : chatBackground;
    const type = this.objectOrNull(background['type']);
    if (type === null) {
      return;
    }
    const typeName = (type['@type'] as string | undefined) ?? '';
    if (typeName === 'backgroundTypeChatTheme') {
      const themeName = (type['theme_name'] as string | undefined) ?? '';
      if (themeName !== '') {
        const seq = ++this.chatBackgroundResolveSeq;
        this.resolveThemeBackground(themeName, seq);
      }
      return;
    }
    let fill: TdObject | null = null;
    let pattern = false;
    if (typeName === 'backgroundTypeFill' || typeName === 'backgroundTypePattern') {
      fill = this.objectOrNull(type['fill']);
      pattern = typeName === 'backgroundTypePattern';
    }
    const colors = this.fillColors(fill);
    const rotation = fill !== null
      ? ((fill['rotation_angle'] as number | undefined) ?? 180) : 180;
    const file = this.backgroundFile(background, pattern);
    const fileId = file !== null ? ((file['id'] as number | undefined) ?? 0) : 0;
    console.info(
      `[ChatBackground] chat=${this.chatId} type=${typeName} colors=${colors.length} file=${fileId}`
    );
    if (colors.length === 0 && fileId === 0) {
      return;
    }

    this.chatBackgroundCustom = true;
    this.chatBackgroundColors = colors;
    this.chatBackgroundAngle = rotation;
    this.chatBackgroundDimming = Math.max(0, Math.min(
      1, ((chatBackground['dark_theme_dimming'] as number | undefined) ?? 0) / 100
    ));
    this.chatBackgroundBlurred =
      typeName === 'backgroundTypeWallpaper' &&
      ((type['is_blurred'] as boolean | undefined) ?? false);
    if (pattern) {
      const intensity = Math.abs((type['intensity'] as number | undefined) ?? 50);
      this.chatBackgroundImageOpacity = Math.max(0.08, Math.min(1, intensity / 100));
    }
    if (file !== null) {
      this.requestBackgroundFile(file);
    }
  }

  private refreshChatBackground(): void {
    // Reset the theme bubble tint; the theme path below re-derives it in the
    // same tick when this chat still carries a theme.
    this.themeBubbleOutColor = '';
    const cached = getChatStore().entryOf(this.chatId);
    if (cached?.background !== null && cached?.background !== undefined) {
      this.applyChatBackground(cached.background);
    }
    const seq = ++this.chatBackgroundResolveSeq;
    const request: TdRequest = { '@type': 'getChat' };
    request['chat_id'] = this.chatId;
    getTdClient().send(request).then((chat: TdObject): void => {
      if (seq !== this.chatBackgroundResolveSeq) {
        return;
      }
      const background = this.objectOrNull(chat['background']);
      const themeName = (chat['theme_name'] as string | undefined) ?? '';
      console.info(
        `[ChatBackground] getChat chat=${this.chatId} background=${background !== null} theme=${themeName !== ''}`
      );
      if (background !== null || themeName === '') {
        if (background !== null) {
          this.applyChatBackground(background);
        } else {
          this.applyDefaultBackground(seq);
        }
      } else {
        this.resolveThemeBackground(themeName, seq);
      }
    }).catch((error: TdError): void => {
      console.error(`ChatPage background getChat failed: ${error.message}`);
    });
  }

  private darkResourceMode(): boolean {
    try {
      const color = (getContext(this) as common.UIAbilityContext)
        .resourceManager.getColorSync($r('app.color.chat_bg'));
      const red = (color >>> 16) & 0xFF;
      const green = (color >>> 8) & 0xFF;
      const blue = color & 0xFF;
      return red * 0.299 + green * 0.587 + blue * 0.114 < 128;
    } catch (_error) {
      return false;
    }
  }

  private hasSpecificBackground(): boolean {
    const entry = getChatStore().entryOf(this.chatId);
    return entry !== undefined &&
      (entry.background !== null || entry.themeName !== '');
  }

  private applyDefaultBackground(seq: number): void {
    const forDarkTheme = this.darkResourceMode();
    const store = getChatStore();
    if (store.defaultBackgroundKnown(forDarkTheme)) {
      const background = store.defaultBackground(forDarkTheme);
      if (background !== null) {
        console.info(
          `[ChatBackground] chat=${this.chatId} source=default-cache dark=${forDarkTheme}`
        );
        this.applyChatBackground(background);
        return;
      }
    }
    this.loadInstalledDefaultBackground(forDarkTheme, seq);
  }

  private loadInstalledDefaultBackground(forDarkTheme: boolean, seq: number): void {
    const request: TdRequest = { '@type': 'getInstalledBackgrounds' };
    request['for_dark_theme'] = forDarkTheme;
    getTdClient().send(request).then((result: TdObject): void => {
      if (seq !== this.chatBackgroundResolveSeq || this.hasSpecificBackground()) {
        return;
      }
      const backgrounds = (result['backgrounds'] as TdObject[] | undefined) ?? [];
      const matchingDefaults = backgrounds.filter((item: TdObject): boolean =>
        ((item['is_default'] as boolean | undefined) ?? false) &&
        (((item['is_dark'] as boolean | undefined) ?? false) === forDarkTheme)
      );
      const matchingTheme = backgrounds.filter((item: TdObject): boolean =>
        (((item['is_dark'] as boolean | undefined) ?? false) === forDarkTheme)
      );
      const selected = matchingDefaults.length > 0
        ? matchingDefaults[0] : (matchingTheme.length > 0 ? matchingTheme[0] : null);
      console.info(
        `[ChatBackground] chat=${this.chatId} source=installed dark=${forDarkTheme} ` +
        `count=${backgrounds.length} defaults=${matchingDefaults.length} ` +
        `selectedDark=${selected !== null
          ? ((selected['is_dark'] as boolean | undefined) ?? false) : 'none'}`
      );
      // Never use an arbitrary background from the opposite color scheme.
      // When TDLib has no matching candidate, the renderer keeps chat_bg.
      this.applyChatBackground(selected);
    }).catch((error: TdError): void => {
      console.error(`ChatPage getInstalledBackgrounds failed: ${error.message}`);
      if (seq === this.chatBackgroundResolveSeq) {
        this.applyChatBackground(null);
      }
    });
  }

  // theme_name backgrounds are stored in TDLib's chat theme catalog rather
  // than directly on Chat.background. Resolve the settings matching the
  // currently active light/dark resource mode.
  private resolveThemeBackground(themeName: string, seq: number): void {
    // TDLib has no getChatThemes request — the list arrives once per connection
    // via updateChatThemes and is cached by ChatThemeStore.
    if (seq !== this.chatBackgroundResolveSeq) {
      return;
    }
    const themes = getChatThemeStore().chatThemes();
    const theme = themes.find((item: TdObject): boolean =>
      ((item['name'] as string | undefined) ?? '') === themeName
    );
    if (theme === undefined) {
      this.themeBubbleOutColor = '';
      this.applyChatBackground(null);
      return;
    }
    const settingsName = this.darkResourceMode() ? 'dark_settings' : 'light_settings';
    const settings = this.objectOrNull(theme[settingsName]);
    const bubbleColors = fillColorsOf(settings !== null
      ? this.objectOrNull(settings['outgoing_message_fill']) : null);
    this.themeBubbleOutColor = bubbleColors.length > 0 ? bubbleColors[0] : '';
    this.applyChatBackground(settings !== null
      ? this.objectOrNull(settings['background']) : null);
  }

  private backgroundGradientStops(): Array<[ResourceColor, number]> {
    const result: Array<[ResourceColor, number]> = [];
    if (this.chatBackgroundColors.length === 0) {
      return result;
    }
    if (this.chatBackgroundColors.length === 1) {
      result.push([this.chatBackgroundColors[0], 0]);
      result.push([this.chatBackgroundColors[0], 1]);
      return result;
    }
    const last = this.chatBackgroundColors.length - 1;
    this.chatBackgroundColors.forEach((color: string, index: number): void => {
      result.push([color, index / last]);
    });
    return result;
  }

  // Resolve the underlying group object because chat itself doesn't contain
  // the current user's membership status.
  private refreshMembership(): void {
    const seq: number = ++this.membershipSeq;
    const req: TdRequest = { '@type': 'getChat' };
    req['chat_id'] = this.chatId;
    getTdClient().send(req).then((chat: TdObject): void => {
      if (seq !== this.membershipSeq) {
        return;
      }
      const type = chat['type'] as TdObject | undefined;
      const typeName = (type?.['@type'] as string | undefined) ?? '';
      if (typeName === 'chatTypeSupergroup') {
        this.membershipSupergroupId = (type?.['supergroup_id'] as number | undefined) ?? 0;
        this.membershipBasicGroupId = 0;
        this.isGroup = true;
        this.isChannel = (type?.['is_channel'] as boolean | undefined) ?? this.isChannel;
        this.membershipState = 'checking';
        const groupReq: TdRequest = { '@type': 'getSupergroup' };
        groupReq['supergroup_id'] = this.membershipSupergroupId;
        getTdClient().send(groupReq).then((supergroup: TdObject): void => {
          if (seq === this.membershipSeq) {
            this.applyMembershipStatus(supergroup['status'] as TdObject | undefined);
          }
        }).catch((e: TdError): void => {
          if (seq === this.membershipSeq) {
            this.membershipState = 'writable';
          }
          console.error(`ChatPage.getSupergroup membership failed: ${e.message}`);
        });
        return;
      }
      if (typeName === 'chatTypeBasicGroup') {
        this.membershipBasicGroupId = (type?.['basic_group_id'] as number | undefined) ?? 0;
        this.membershipSupergroupId = 0;
        this.isGroup = true;
        this.isChannel = false;
        this.membershipState = 'checking';
        const groupReq: TdRequest = { '@type': 'getBasicGroup' };
        groupReq['basic_group_id'] = this.membershipBasicGroupId;
        getTdClient().send(groupReq).then((basicGroup: TdObject): void => {
          if (seq === this.membershipSeq) {
            this.applyMembershipStatus(basicGroup['status'] as TdObject | undefined);
          }
        }).catch((e: TdError): void => {
          if (seq === this.membershipSeq) {
            this.membershipState = 'writable';
          }
          console.error(`ChatPage.getBasicGroup membership failed: ${e.message}`);
        });
        return;
      }
      this.membershipSupergroupId = 0;
      this.membershipBasicGroupId = 0;
      this.membershipState = 'writable';
    }).catch((e: TdError): void => {
      if (seq === this.membershipSeq) {
        // Don't leave private/secret chats with a permanently hidden composer
        // if the supplementary status request fails.
        this.membershipState = 'writable';
      }
      console.error(`ChatPage.getChat membership failed: ${e.message}`);
    });
  }

  private applyMembershipStatus(status: TdObject | undefined): void {
    const type: string = (status?.['@type'] as string | undefined) ?? '';
    if (type === '') {
      return;
    }
    let next: string = 'writable';
    if (type === 'chatMemberStatusLeft') {
      next = 'joinable';
    } else if (type === 'chatMemberStatusRestricted') {
      const isMember: boolean = (status?.['is_member'] as boolean | undefined) ?? false;
      next = isMember ? 'writable' : 'joinable';
    } else if (type === 'chatMemberStatusBanned') {
      next = 'blocked';
    } else if (this.isChannel && type === 'chatMemberStatusMember') {
      // Broadcast-channel subscribers can never post — only the creator and
      // admins with posting rights get the composer.
      next = 'readonly';
    } else if (this.isChannel && type === 'chatMemberStatusAdministrator') {
      const rights = status?.['rights'] as TdObject | undefined;
      next = ((rights?.['can_post_messages'] as boolean | undefined) ?? false)
        ? 'writable' : 'readonly';
    }
    this.membershipState = next;
    if (next === 'writable') {
      this.joiningChat = false;
      return;
    }
    // A membership update can arrive while the cached page still has composer
    // UI open. Close every composer-owned surface before replacing the bar.
    this.joiningChat = false;
    this.setEmojiPanel(false);
    this.mentionItems = [];
    this.commandItems = [];
    this.commandMenuOpen = false;
    this.replyToId = 0;
    this.replyToName = '';
    this.replyToText = '';
    if (this.isRecording) {
      this.cancelRecording();
    }
  }

  private joinCurrentChat(): void {
    if (this.joiningChat || this.membershipState !== 'joinable') {
      return;
    }
    this.joiningChat = true;
    const req: TdRequest = { '@type': 'joinChat' };
    req['chat_id'] = this.chatId;
    getTdClient().send(req).then((): void => {
      this.joiningChat = false;
      // updateSupergroup/updateBasicGroup normally arrives first; setting this
      // eagerly keeps the UI responsive even if that update is delayed.
      this.membershipState = 'writable';
      this.showClientJoinNotice(this.isChannel);
      this.refreshMembership();
    }).catch((e: TdError): void => {
      this.joiningChat = false;
      console.error(`ChatPage.joinChat failed: ${e.message}`);
      promptAction.showToast({ message: '加入失败，请稍后重试', duration: 2000 });
    });
  }

  // Mark read up to the bottom-most visible message, so only what the user has
  // actually scrolled past gets marked read (entering without scrolling leaves
  // the rest unread).
  private markVisibleRead(end: number): void {
    if (this.store === null || end < 0 || end >= this.groups.length) {
      return;
    }
    let maxId: number = 0;
    // A client-only service row has no member ids. Walk back to the newest
    // visible real row so its presence can't prevent the actual tail from
    // being marked read.
    for (let groupIndex: number = end; groupIndex >= 0 && maxId === 0; groupIndex--) {
      const g: AlbumGroup = this.groups[groupIndex];
      for (const id of g.memberIds) {
        if (id > maxId) {
          maxId = id;
        }
      }
    }
    if (maxId > 0) {
      this.store.markViewed(maxId);
      getChatStore().markReadLocally(this.chatId, maxId);
    }
  }

  // A tapped in-message link: Telegram links (t.me/<name>, t.me/<name>/<msgId>,
  // @<name>) resolve via TDLib and open the target chat inside the app, jumped
  // to the specific message when the link points to one; everything else opens
  // in the system browser.
  private onLinkTap(url: string): void {
    // Bot commands are active entities in Telegram. A deliberate tap sends
    // the command immediately, while sharing the composer's in-flight guard so
    // double taps cannot enqueue duplicates.
    if (url.startsWith('tg-command:')) {
      const command = url.substring('tg-command:'.length);
      const store: MessageStore | null = this.store;
      if (command === '' || store === null || this.composerSending) {
        return;
      }
      const replyId = this.replyToId;
      this.composerSending = true;
      this.atBottom = true;
      this.stayAtUnread = false;
      store.sendAsync(command, replyId).then((): void => {
        this.composerSending = false;
        if (this.replyToId === replyId) {
          this.clearReply();
        }
      }).catch((e: TdError): void => {
        this.composerSending = false;
        console.error(`ChatPage.botCommand failed: ${e.message}`);
        promptAction.showToast({ message: '命令发送失败，请重试', duration: 1600 });
      });
      return;
    }
    if (url.startsWith('tg-copy:')) {
      this.copyPlainText(url.substring('tg-copy:'.length), '已复制号码');
      return;
    }
    // Hashtag tap → global search across all chats.
    if (url.startsWith('tg-hashtag:')) {
      const tag = url.substring('tg-hashtag:'.length);
      if (tag !== '') {
        const params: Record<string, Object> = { 'query': tag };
        router.pushUrl({ url: 'pages/search/GlobalSearchPage', params: params });
      }
      return;
    }
    // Text mention (no username): the entity carries the user id directly.
    if (url.startsWith('tg://user?id=')) {
      const uid = Number(url.substring('tg://user?id='.length));
      if (uid > 0) {
        const params: Record<string, Object> = { 'userId': uid };
        router.pushUrl({ url: 'pages/profile/ProfilePage', params: params });
      }
      return;
    }
    const folderInvite = chatFolderInviteLinkOf(url);
    if (folderInvite !== '') {
      openChatFolderInviteLink(folderInvite);
      return;
    }
    const stickerSet = stickerSetLinkOf(url);
    if (stickerSet !== null) {
      openStickerSetLink(stickerSet);
      return;
    }
    // Private invite link: preview → confirm → join in-app.
    const invite = inviteLinkOf(url);
    if (invite !== '') {
      openInviteLink(getContext(this) as common.UIAbilityContext, invite, url);
      return;
    }
    const linkAction = chatLinkActionOf(url);
    if (linkAction !== null) {
      openChatLinkAction(getContext(this) as common.UIAbilityContext, linkAction, url, true);
      return;
    }
    const bareName = bareUsernameOf(url);
    if (bareName !== '') {
      openTelegramLink(getContext(this) as common.UIAbilityContext, url, true);
      return;
    }
    const tgUrl = normalizeTelegramLink(url);
    if (tgUrl === '') {
      openTelegramLink(getContext(this) as common.UIAbilityContext, url, true);
      return;
    }
    const req: TdRequest = { '@type': 'getMessageLinkInfo' };
    req['url'] = tgUrl;
    getTdClient().send(req).then((info: TdObject) => {
      const chatId = info['chat_id'] as number | undefined;
      if (chatId === undefined || chatId === 0) {
        openTelegramLink(getContext(this) as common.UIAbilityContext, url, true);
        return;
      }
      const msg = info['message'] as TdObject | undefined;
      const msgId = msg !== undefined ? (msg['id'] as number | undefined) : undefined;
      // A link to a message already in this chat: scroll in place (same as the
      // pinned-message jump) instead of pushing a duplicate ChatPage instance —
      // that duplication was why repeat taps looked like they did nothing.
      if (chatId === this.chatId) {
        if (msgId !== undefined && msgId > 0) {
          this.prepareUserJump();
          const gidx = groupIndexOf(this.groups, msgId);
          if (gidx >= 0) {
            this.scroller.scrollToIndex(gidx, false, ScrollAlign.START);
            this.flashAtIndex(gidx);
          } else {
            this.pendingJumpId = msgId;
            if (this.store !== null) {
              const targetId: number = msgId;
              this.store.loadAround(targetId, (found: boolean): void => {
                if (!found && this.pendingJumpId === targetId) {
                  this.pendingJumpId = 0;
                  promptAction.showToast({ message: '无法定位这条消息', duration: 1500 });
                }
              });
            }
          }
        }
        return;
      }
      const params: Record<string, Object> = { 'chatId': chatId };
      if (msgId !== undefined && msgId > 0) {
        params['jumpTo'] = msgId;
      }
      router.pushUrl({ url: 'pages/chat/ChatPage', params: params });
    }).catch((e: TdError) => {
      console.error(`ChatPage.getMessageLinkInfo failed: ${e.message}`);
      openTelegramLink(getContext(this) as common.UIAbilityContext, url, true);
    });
  }

  // Resolve a bare @username: a user opens the profile card; a group/channel
  // opens its chat page. `original` is the raw tapped URL for browser fallback.
  private openByUsername(name: string, original: string): void {
    const req: TdRequest = { '@type': 'searchPublicChat' };
    req['username'] = name;
    getTdClient().send(req).then((chat: TdObject) => {
      const chatId = (chat['id'] as number | undefined) ?? 0;
      const type = chat['type'] as TdObject | undefined;
      const typeName = type !== undefined ? ((type['@type'] as string | undefined) ?? '') : '';
      if (typeName === 'chatTypePrivate') {
        const uid = ((type as TdObject)['user_id'] as number | undefined) ?? 0;
        if (uid > 0) {
          const params: Record<string, Object> = { 'userId': uid };
          router.pushUrl({ url: 'pages/profile/ProfilePage', params: params });
          return;
        }
      }
      if (chatId !== 0) {
        const params: Record<string, Object> = { 'chatId': chatId };
        router.pushUrl({ url: 'pages/chat/ChatPage', params: params });
        return;
      }
      openWebUrl(getContext(this) as common.UIAbilityContext, original);
    }).catch((e: TdError) => {
      console.error(`ChatPage.searchPublicChat(${name}) failed: ${e.message}`);
      openWebUrl(getContext(this) as common.UIAbilityContext, original);
    });
  }

  // Reply-quote tap: jump to the quoted original message (same in-place scroll
  // as a same-chat link jump).
  // --- in-chat search ---
  private enterSearch(): void {
    this.searchMode = true;
    this.searchQuery = '';
    this.searchResults = [];
    this.searchTotal = 0;
    this.searchIdx = 0;
  }

  private exitSearch(): void {
    this.searchMode = false;
    this.searchQuery = '';
    this.searchResults = [];
    this.searchTotal = 0;
    this.searchIdx = 0;
    this.searchSeq++;
    this.cancelFlash();
  }

  private updateSearchQuery(value: string): void {
    if (value === this.searchQuery) {
      return;
    }
    this.searchQuery = value;
    this.searchResults = [];
    this.searchTotal = 0;
    this.searchIdx = 0;
    this.searchSeq++;
    this.cancelFlash();
  }

  // Run a search page. fromMsgId 0 = fresh search; otherwise fetch the page
  // older than that message (pagination for the ∧ button past the first 50).
  private runSearch(fromMsgId: number, thenJumpTo: number): void {
    const q = this.searchQuery.trim();
    if (q === '') {
      return;
    }
    const seq = ++this.searchSeq;
    const req: TdRequest = { '@type': 'searchChatMessages' };
    req['chat_id'] = this.chatId;
    req['query'] = q;
    req['from_message_id'] = fromMsgId;
    req['offset'] = 0;
    req['limit'] = 50;
    getTdClient().send(req).then((res: TdObject) => {
      if (seq !== this.searchSeq || !this.searchMode) {
        return;
      }
      const msgs = (res['messages'] as TdObject[] | undefined) ?? [];
      const ids: number[] = [];
      for (const m of msgs) {
        const id = (m['id'] as number | undefined) ?? 0;
        if (id > 0) {
          ids.push(id);
        }
      }
      this.searchTotal = (res['total_count'] as number | undefined) ?? ids.length;
      this.searchResults = fromMsgId === 0 ? ids : [...this.searchResults, ...ids];
      if (this.searchResults.length === 0) {
        promptAction.showToast({ message: '未找到相关消息', duration: 1500 });
        return;
      }
      // Entered on a specific hit (a message tapped in global search): it is
      // already the jump target, so just make it the current hit.
      if (this.searchAnchorId !== 0) {
        const at = this.searchResults.indexOf(this.searchAnchorId);
        this.searchAnchorId = 0;
        if (at >= 0) {
          this.searchIdx = at;
          return;
        }
      }
      this.jumpToResult(thenJumpTo);
    }).catch((e: TdError) => {
      console.error(`ChatPage.searchChatMessages failed: ${e.message}`);
    });
  }

  private jumpToResult(idx: number): void {
    if (idx < 0 || idx >= this.searchResults.length) {
      return;
    }
    this.searchIdx = idx;
    this.onReplyTap(this.searchResults[idx]); // same jump + double-blink flash
  }

  // ∧ = older result. Past the loaded window → fetch the next page first.
  private searchOlder(): void {
    const next = this.searchIdx + 1;
    if (next < this.searchResults.length) {
      this.jumpToResult(next);
    } else if (this.searchResults.length < this.searchTotal && this.searchResults.length > 0) {
      this.runSearch(this.searchResults[this.searchResults.length - 1], next);
    }
  }

  // ∨ = newer result.
  private searchNewer(): void {
    if (this.searchIdx > 0) {
      this.jumpToResult(this.searchIdx - 1);
    }
  }

  private onReplyTap(messageId: number): void {
    if (messageId <= 0) {
      return;
    }
    this.prepareUserJump();
    const gidx = groupIndexOf(this.groups, messageId);
    if (gidx >= 0) {
      this.scroller.scrollToIndex(gidx, false, ScrollAlign.START);
      this.flashAtIndex(gidx);
    } else if (this.store !== null) {
      this.pendingJumpId = messageId;
      this.store.loadAround(messageId, (found: boolean): void => {
        if (!found && this.pendingJumpId === messageId) {
          this.pendingJumpId = 0;
          promptAction.showToast({ message: '原消息已不可用', duration: 1500 });
        }
      });
    }
  }

  // Gently blink the row at gidx twice — visual confirmation of where a
  // reply/pinned/link jump landed. Waits a beat for the scroll to settle so
  // getItemRect sees the laid-out row.
  private flashAtIndex(gidx: number): void {
    const seq = ++this.flashSeq;
    setTimeout(() => {
      if (seq !== this.flashSeq) {
        return;
      }
      let top = 0;
      let height = 0;
      try {
        const rect = this.scroller.getItemRect(gidx);
        top = rect.y;
        height = rect.height;
      } catch (e) {
        return; // row not laid out (jump superseded) — skip the highlight
      }
      if (height <= 0) {
        return;
      }
      this.flashTop = top;
      this.flashHeight = height;
      this.flashShown = true;
      this.flashAlpha = 0;
      this.runBlink(seq, 2);
    }, 150);
  }

  private runBlink(seq: number, remaining: number): void {
    if (seq !== this.flashSeq) {
      return;
    }
    if (remaining <= 0) {
      this.flashShown = false;
      this.flashAlpha = 0;
      return;
    }
    animateTo({
      duration: this.chatEffectDuration(KEY_POWER_EFFECT_REPLY, 320), curve: Curve.EaseInOut
    }, () => { this.flashAlpha = 1; });
    setTimeout(() => {
      if (seq !== this.flashSeq) {
        return;
      }
      animateTo({
        duration: this.chatEffectDuration(KEY_POWER_EFFECT_REPLY, 320), curve: Curve.EaseInOut
      }, () => { this.flashAlpha = 0; });
      setTimeout(() => { this.runBlink(seq, remaining - 1); }, 340);
    }, 340);
  }

  // Any new touch cancels the highlight (it's viewport-anchored, so it would
  // visibly detach from the row once the user scrolls).
  private cancelFlash(): void {
    this.flashSeq++;
    this.flashShown = false;
    this.flashAlpha = 0;
  }

  // "N Comments" tap: resolve the channel post's discussion thread and open it
  // as a normal chat page on the linked discussion group, jumped to the post.
  // "转发自 X" tapped: open the original post in its channel/chat, or — for a
  // forward from a user — that user's private chat.
  private onForwardTap(originChatId: number, originMsgId: number, originUserId: number): void {
    if (originChatId !== 0) {
      const params: Record<string, Object> = { 'chatId': originChatId };
      if (originMsgId !== 0) {
        params['jumpTo'] = originMsgId;
      }
      router.pushUrl({ url: 'pages/chat/ChatPage', params: params });
      return;
    }
    if (originUserId === 0) {
      return;
    }
    const req: TdRequest = { '@type': 'createPrivateChat' };
    req['user_id'] = originUserId;
    req['force'] = true;
    getTdClient().send(req).then((chat: TdObject) => {
      const id = (chat['id'] as number | undefined) ?? 0;
      if (id !== 0) {
        const params: Record<string, Object> = { 'chatId': id };
        router.pushUrl({ url: 'pages/chat/ChatPage', params: params });
      }
    }).catch((e: TdError) => {
      console.error(`ChatPage.onForwardTap createPrivateChat failed: ${e.message}`);
      promptAction.showToast({ message: '无法打开来源', duration: 1500 });
    });
  }

  private onCommentTap(messageId: number): void {
    const req: TdRequest = { '@type': 'getMessageThread' };
    req['chat_id'] = this.chatId;
    req['message_id'] = messageId;
    getTdClient().send(req).then((info: TdObject) => {
      const discussionChatId = info['chat_id'] as number | undefined;
      const threadId = info['message_thread_id'] as number | undefined;
      if (discussionChatId === undefined) {
        return;
      }
      const params: Record<string, Object> = { 'chatId': discussionChatId };
      if (threadId !== undefined && threadId > 0) {
        // Thread-scoped view: only this post's replies (getMessageThreadHistory),
        // not the whole discussion group's history.
        params['threadRootId'] = threadId;
      }
      router.pushUrl({ url: 'pages/chat/ChatPage', params: params });
    }).catch((e: TdError) => {
      console.error(`ChatPage.getMessageThread failed: ${e.message}`);
    });
  }

  // Open the fullscreen viewer for a photo/video message. Photos still upgrade
  // to full-res on demand; videos are streamed by the fullscreen AVPlayer.
  private onMediaTap(messageId: number): void {
    if (this.store === null) {
      return;
    }
    const idx = this.messages.findIndex((m: MessageEntry) => m.id === messageId);
    if (idx < 0) {
      return;
    }
    const m = this.messages[idx];
    if (!this.mediaEntryIsPhoto(m) && !this.mediaEntryIsVideo(m)) {
      return;
    }
    if (this.mediaEntryIsPhoto(m)) {
      this.store.requestFullPhoto(messageId);
    }
    // Position the viewer Swiper on the tapped album member.
    const sib = this.siblingIdsFor(messageId);
    this.viewerInitIdx = Math.max(0, sib.indexOf(messageId));
    this.viewerMsgId = messageId;
    this.chromeVisible = true;
    this.viewerVideoLandscape = false;
    this.viewerClosing = false;
  }

  // Album member ids for an arbitrary message (single-element list when the
  // message isn't part of a multi-item album).
  private siblingIdsFor(messageId: number): number[] {
    for (const g of this.groups) {
      if (g.memberIds.indexOf(messageId) >= 0 && g.memberIds.length > 1) {
        return g.memberIds;
      }
    }
    return [messageId];
  }

  private toggleChrome(): void {
    this.chromeVisible = !this.chromeVisible;
  }

  private setViewerVideoLandscape(landscape: boolean): void {
    if (landscape && !this.viewerIsVideo()) {
      return;
    }
    if (this.viewerVideoLandscape === landscape) {
      return;
    }
    this.viewerVideoLandscape = landscape;
    this.chromeVisible = true;
    setMediaViewerOrientation(getContext(this) as common.UIAbilityContext, landscape);
  }

  private onAppForegroundChanged(): void {
    // 停留在会话页切后台时必须 closeChat，否则 TDLib 认为用户正在看这个
    // 会话，不会为它生成任何通知。
    if (this.appIsForeground) {
      this.store?.resumeOpenChat();
    } else {
      this.store?.suspendOpenChat();
    }
    if (!this.appIsForeground) {
      getVoicePlayback().pauseForBackground();
    }
    if (!this.appIsForeground && this.viewerVideoLandscape) {
      this.setViewerVideoLandscape(false);
    }
  }

  private viewerZoomed(): boolean {
    return this.viewerPhotoScale > VIEWER_MIN_SCALE + 0.01;
  }

  // Contain-fitted display size of the current photo at 1x, in vp. Falls back
  // to the viewport itself when the photo's pixel size is unknown.
  private viewerFittedSize(): ViewerFit {
    const w = this.viewerAreaW;
    const h = this.viewerAreaH;
    const e = this.viewerEntry();
    const pw = e !== null ? e.photoWidth : 0;
    const ph = e !== null ? e.photoHeight : 0;
    if (w <= 0 || h <= 0 || pw <= 0 || ph <= 0) {
      return { w: w, h: h };
    }
    const fit = Math.min(w / pw, h / ph);
    return { w: pw * fit, h: ph * fit };
  }

  // Boundary restriction (per the official best practice): an axis whose
  // scaled size still fits the viewport stays centered; otherwise the photo
  // edge stops at the viewport edge — no black gaps, never dragged off-screen.
  private clampViewerOffset(): void {
    const s = this.viewerPhotoScale;
    const fitted = this.viewerFittedSize();
    const maxX = Math.max(0, (fitted.w * s - this.viewerAreaW) / 2);
    const maxY = Math.max(0, (fitted.h * s - this.viewerAreaH) / 2);
    this.viewerPhotoOffsetX = Math.min(maxX, Math.max(-maxX, this.viewerPhotoOffsetX));
    this.viewerPhotoOffsetY = Math.min(maxY, Math.max(-maxY, this.viewerPhotoOffsetY));
  }

  private resetViewerPhotoZoom(animated: boolean): void {
    this.viewerPinchStartScale = VIEWER_MIN_SCALE;
    if (animated) {
      animateTo({
        duration: this.chatEffectDuration(KEY_POWER_EFFECT_BLUR, 180), curve: Curve.EaseOut
      }, () => {
        this.viewerPhotoScale = VIEWER_MIN_SCALE;
        this.viewerPhotoOffsetX = 0;
        this.viewerPhotoOffsetY = 0;
      });
    } else {
      this.viewerPhotoScale = VIEWER_MIN_SCALE;
      this.viewerPhotoOffsetX = 0;
      this.viewerPhotoOffsetY = 0;
    }
  }

  private onViewerPinchStart(event: GestureEvent): void {
    this.viewerPinchStartScale = this.viewerPhotoScale;
    this.viewerPinchStartOffsetX = this.viewerPhotoOffsetX;
    this.viewerPinchStartOffsetY = this.viewerPhotoOffsetY;
    this.viewerPinchAnchorX = event.pinchCenterX - this.viewerAreaW / 2;
    this.viewerPinchAnchorY = event.pinchCenterY - this.viewerAreaH / 2;
    this.viewerIgnoreTapUntilMs = Number.MAX_VALUE;
  }

  // Keep the content point that was under the initial pinch center glued to
  // the CURRENT pinch center: zooming follows the fingers and moving both
  // fingers together doubles as a two-finger pan.
  private onViewerPinchUpdate(event: GestureEvent): void {
    const s0 = this.viewerPinchStartScale;
    const next = Math.max(VIEWER_MIN_SCALE, Math.min(VIEWER_MAX_SCALE, s0 * event.scale));
    const ratio = next / s0;
    const px = event.pinchCenterX - this.viewerAreaW / 2;
    const py = event.pinchCenterY - this.viewerAreaH / 2;
    this.viewerPhotoScale = next;
    this.viewerPhotoOffsetX = px - (this.viewerPinchAnchorX - this.viewerPinchStartOffsetX) * ratio;
    this.viewerPhotoOffsetY = py - (this.viewerPinchAnchorY - this.viewerPinchStartOffsetY) * ratio;
    this.clampViewerOffset();
  }

  private onViewerPinchEnd(): void {
    this.viewerIgnoreTapUntilMs = Date.now() + 200;
    if (!this.viewerZoomed()) {
      this.resetViewerPhotoZoom(false);
    } else {
      this.viewerPinchStartScale = this.viewerPhotoScale;
    }
  }

  private onViewerPanStart(): void {
    this.viewerPanStartOffsetX = this.viewerPhotoOffsetX;
    this.viewerPanStartOffsetY = this.viewerPhotoOffsetY;
    this.viewerEdgeOverscroll = 0;
  }

  // 放大态下拖到左右边界后继续拖动的累计量。达到阈值即翻页，
  // 让"滑到边上还能翻下一张"在放大时也成立（此时 Swiper 收不到手势）。
  private viewerEdgeOverscroll: number = 0;

  private onViewerPanEnd(): void {
    if (!this.viewerZoomed() || Math.abs(this.viewerEdgeOverscroll) < 60) {
      this.viewerEdgeOverscroll = 0;
      return;
    }
    const forward: boolean = this.viewerEdgeOverscroll < 0; // 向左拖 = 看下一张
    this.viewerEdgeOverscroll = 0;
    // 翻页前回到 1x，否则新图会沿用上一张的缩放与偏移。
    this.resetViewerPhotoZoom(false);
    if (forward) {
      this.viewerSwiperCtrl.showNext();
    } else {
      this.viewerSwiperCtrl.showPrevious();
    }
  }

  // One-finger drag pans the zoomed photo; clamping keeps it on-screen. At
  // the fitted 1x size this is a no-op and the Swiper keeps paging instead.
  private onViewerPanUpdate(event: GestureEvent): void {
    if (!this.viewerZoomed()) {
      return;
    }
    const desiredX: number = this.viewerPanStartOffsetX + event.offsetX;
    this.viewerPhotoOffsetX = desiredX;
    this.viewerPhotoOffsetY = this.viewerPanStartOffsetY + event.offsetY;
    this.clampViewerOffset();
    // clamp 吃掉的水平位移就是"已经贴边还在继续拖"的量。
    this.viewerEdgeOverscroll = desiredX - this.viewerPhotoOffsetX;
  }

  // A single tap toggles chrome at every zoom level. Closing is explicit via
  // the top-left button/back gesture, preventing an ordinary inspection tap
  // from unexpectedly throwing the user back into the chat.
  private onViewerPhotoTap(): void {
    if (Date.now() < this.viewerIgnoreTapUntilMs) {
      return;
    }
    this.toggleChrome();
  }

  // Double tap zooms around the actual touch point instead of the center of the
  // screen. A second double tap is a quick way back to the fitted 1x image.
  private onViewerPhotoDoubleTap(event: GestureEvent): void {
    if (this.viewerZoomed()) {
      this.resetViewerPhotoZoom(true);
      return;
    }
    let px = 0;
    let py = 0;
    if (event.fingerList.length > 0) {
      px = event.fingerList[0].localX - this.viewerAreaW / 2;
      py = event.fingerList[0].localY - this.viewerAreaH / 2;
    }
    this.viewerPinchStartScale = VIEWER_DOUBLE_TAP_SCALE;
    animateTo({
      duration: this.chatEffectDuration(KEY_POWER_EFFECT_BLUR, 200), curve: Curve.EaseOut
    }, () => {
      this.viewerPhotoScale = VIEWER_DOUBLE_TAP_SCALE;
      this.viewerPhotoOffsetX = px * (1 - VIEWER_DOUBLE_TAP_SCALE);
      this.viewerPhotoOffsetY = py * (1 - VIEWER_DOUBLE_TAP_SCALE);
      this.clampViewerOffset();
    });
  }

  private viewerEntry(): MessageEntry | null {
    const idx = this.messages.findIndex((m: MessageEntry) => m.id === this.viewerMsgId);
    return idx >= 0 ? this.messages[idx] : null;
  }

  private viewerFileName(): string {
    const e = this.viewerEntry();
    return e !== null ? e.videoFileName : '';
  }

  private viewerInfoTitle(): string {
    const e: MessageEntry | null = this.viewerEntry();
    if (e === null) {
      return this.title;
    }
    if (this.mediaEntryIsVideo(e) && e.videoFileName !== '') {
      return e.videoFileName;
    }
    return e.senderName !== '' ? e.senderName : this.title;
  }

  private viewerInfoSubtitle(): string {
    const e: MessageEntry | null = this.viewerEntry();
    if (e === null) {
      return '';
    }
    const ids: number[] = this.viewerSiblingIds();
    const index: number = ids.indexOf(this.viewerMsgId);
    const position: string = ids.length > 1 && index >= 0 ? `${index + 1} / ${ids.length} · ` : '';
    return `${position}${formatTime(e.date, this.nowSec)}`;
  }

  // The album (media group) containing the viewer's current message, if any.
  private viewerGroup(): AlbumGroup | null {
    for (const g of this.groups) {
      if (g.memberIds.indexOf(this.viewerMsgId) >= 0) {
        return g;
      }
    }
    return null;
  }

  // Sibling message ids for swipe/filmstrip navigation — just the current
  // message when it isn't part of a multi-item album.
  private viewerSiblingIds(): number[] {
    const g = this.viewerGroup();
    if (g !== null && g.memberIds.length > 1) {
      return g.memberIds;
    }
    return this.viewerMsgId !== 0 ? [this.viewerMsgId] : [];
  }

  private viewerSiblingPath(id: number): string {
    const g = this.viewerGroup();
    if (g !== null) {
      const idx = g.memberIds.indexOf(id);
      if (idx >= 0 && idx < g.photoPaths.length) {
        return g.photoPaths[idx];
      }
    }
    const idx2 = this.messages.findIndex((m: MessageEntry) => m.id === id);
    return idx2 >= 0 ? this.messages[idx2].photoPath : '';
  }

  private viewerSiblingIsVideo(id: number): boolean {
    const idx = this.messages.findIndex((m: MessageEntry) => m.id === id);
    return idx >= 0 && this.mediaEntryIsVideo(this.messages[idx]);
  }

  private entryById(id: number): MessageEntry | null {
    const idx = this.messages.findIndex((m: MessageEntry) => m.id === id);
    return idx >= 0 ? this.messages[idx] : null;
  }

  // Best available image for a viewer page: full-res once downloaded, else thumbnail.
  private photoSrcFor(id: number): string {
    const e = this.entryById(id);
    if (e === null) {
      return '';
    }
    const p = e.photoFullPath !== '' ? e.photoFullPath : e.photoPath;
    return p.startsWith('/') ? `file://${p}` : p;
  }

  // Programmatic paging: the Swiper animates the transition; onChange keeps
  // viewerMsgId in sync.
  private switchViewer(delta: number): void {
    if (delta > 0) {
      this.viewerSwiperCtrl.showNext();
    } else {
      this.viewerSwiperCtrl.showPrevious();
    }
  }

  // Filmstrip tap: page the Swiper to the tapped album member.
  private jumpToSibling(id: number): void {
    const i = this.viewerSiblingIds().indexOf(id);
    if (i >= 0) {
      this.viewerSwiperCtrl.changeIndex(i, true);
    }
  }

  private onViewerPageChange(index: number): void {
    const ids = this.viewerSiblingIds();
    if (index < 0 || index >= ids.length) {
      return;
    }
    const id = ids[index];
    if (id === this.viewerMsgId) {
      this.viewerInitIdx = index;
      return;
    }
    if (this.viewerVideoLandscape) {
      this.setViewerVideoLandscape(false);
    }
    this.resetViewerPhotoZoom(false);
    this.viewerInitIdx = index;
    this.viewerMsgId = id;
    if (this.store !== null && !this.viewerSiblingIsVideo(id)) {
      this.store.requestFullPhoto(id);
    }
  }

  private viewerIsVideo(): boolean {
    const e = this.viewerEntry();
    return e !== null && this.mediaEntryIsVideo(e);
  }

  private viewerVideoLocalPath(): string {
    const e = this.viewerEntry();
    return e !== null ? e.videoPath : '';
  }

  private viewerVideoProgress(): number {
    const e = this.viewerEntry();
    return e !== null ? e.videoProgress : 0;
  }

  private viewerVideoReady(): boolean {
    const e = this.viewerEntry();
    return e !== null && e.videoPath !== '';
  }

  private viewerVideoFileId(): number {
    const e = this.viewerEntry();
    return e !== null ? e.videoFileId : 0;
  }

  private viewerVideoFileSize(): number {
    const e = this.viewerEntry();
    return e !== null ? e.videoFileSize : 0;
  }

  private viewerVideoMimeType(): string {
    const e = this.viewerEntry();
    return e !== null ? e.videoMimeType : '';
  }

  private viewerVideoWidth(): number {
    const e = this.viewerEntry();
    return e !== null ? e.photoWidth : 0;
  }

  private viewerVideoHeight(): number {
    const e = this.viewerEntry();
    return e !== null ? e.photoHeight : 0;
  }

  private viewerPhotoSrc(): string {
    const e = this.viewerEntry();
    if (e === null) {
      return '';
    }
    const p = e.photoFullPath !== '' ? e.photoFullPath : e.photoPath;
    return p.startsWith('/') ? `file://${p}` : p;
  }

  private viewerPhotoUpgrading(): boolean {
    const e = this.viewerEntry();
    return e !== null && e.photoFullPath === '' && e.photoFullFileId !== 0 &&
      !e.photoFullFailed;
  }

  private viewerPhotoProgress(): number {
    const e = this.viewerEntry();
    if (e === null) {
      return 0;
    }
    return e.photoFullProgress > 0 ? e.photoFullProgress : e.photoProgress;
  }

  private viewerPhotoFailed(): boolean {
    const e: MessageEntry | null = this.viewerEntry();
    if (e === null) {
      return true;
    }
    if (e.photoFullFailed) {
      return true;
    }
    return e.photoPath === '' && e.photoFullPath === '' &&
      e.photoFileId === 0 && e.photoFullFileId === 0;
  }

  private retryViewerPhoto(): void {
    if (this.store === null || this.viewerMsgId === 0) {
      return;
    }
    this.store.retryPhoto(this.viewerMsgId);
  }

  @Builder
  viewerPhotoLoadingState() {
    Column({ space: 10 }) {
      if (this.viewerPhotoProgress() > 0) {
        Stack() {
          Progress({ value: this.viewerPhotoProgress(), total: 100, type: ProgressType.Ring })
            .width(44).height(44).color(Color.White);
          Text(`${this.viewerPhotoProgress()}%`).fontSize(10).fontColor(Color.White);
        }
      } else {
        LoadingProgress().width(38).height(38).color(Color.White);
      }
      Text('正在加载图片').fontSize(13).fontColor('#D9FFFFFF');
    }
    .padding({ left: 18, right: 18, top: 16, bottom: 16 })
    .backgroundColor(VIEWER_CHROME_BG).borderRadius(16)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 0.92, y: 0.92 }))
      .animation({ duration: this.chatEffectDuration(KEY_POWER_EFFECT_BLUR, 180), curve: Curve.EaseOut }));
  }

  @Builder
  viewerPhotoErrorState() {
    Column({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(30).fontColor([Color.White]);
      Text('图片加载失败').fontSize(14).fontColor(Color.White).fontWeight(FontWeight.Medium);
      Text('点击重试').fontSize(12).fontColor('#D9FFFFFF');
    }
    .padding({ left: 22, right: 22, top: 16, bottom: 16 })
    .backgroundColor(VIEWER_CHROME_BG).borderRadius(16)
    .stateStyles({
      normal: this.suggestionRowNormalStyle,
      pressed: this.suggestionRowPressedStyle
    })
    .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120), curve: Curve.EaseOut })
    .onClick((): void => { this.retryViewerPhoto(); });
  }

  // Fullscreen viewer content: a Swiper over the album's members, so pages
  // follow the finger and slide continuously to the neighbor. Only the CURRENT
  // page mounts a video player; inactive video pages show their thumbnail.
  @Builder
  viewerContent() {
    Swiper(this.viewerSwiperCtrl) {
      ForEach(this.viewerSiblingIds(), (id: number) => {
        Stack() {
          if (this.viewerSiblingIsVideo(id)) {
            if (id === this.viewerMsgId && this.viewerVideoFileId() !== 0) {
              StreamingVideoPlayer({
                fileId: this.viewerVideoFileId(),
                fileSize: this.viewerVideoFileSize(),
                mimeType: this.viewerVideoMimeType(),
                videoWidth: this.viewerVideoWidth(),
                videoHeight: this.viewerVideoHeight(),
                localPath: this.viewerVideoLocalPath(),
                posterPath: this.viewerSiblingPath(id),
                showControls: this.chromeVisible,
                landscape: this.viewerVideoLandscape,
                onBackgroundTap: () => { this.toggleChrome(); },
                onSwipeNext: () => { this.switchViewer(1); },
                onSwipePrev: () => { this.switchViewer(-1); },
                onOrientationChange: (landscape: boolean) => {
                  this.setViewerVideoLandscape(landscape);
                }
              });
            } else {
              if (this.viewerSiblingPath(id) !== '') {
                Image(this.viewerSiblingPath(id).startsWith('/')
                  ? `file://${this.viewerSiblingPath(id)}` : this.viewerSiblingPath(id))
                  .objectFit(ImageFit.Contain).width('100%').height('100%');
              }
              Stack() {
                Circle({ width: 56, height: 56 }).fill('#00000066');
                Text('▶').fontSize(24).fontColor(Color.White);
              }.width(56).height(56);
            }
          } else {
            // Gestures live on this UNSCALED wrapper, not on the Image: a
            // scaled component reports gesture coordinates/offsets in its own
            // scaled space, which made panning lag the finger by the zoom
            // factor. The Image only carries the scale/translate transform.
            Stack() {
              if (this.photoSrcFor(id) !== '') {
                Image(this.photoSrcFor(id))
                  .objectFit(ImageFit.Contain).width('100%').height('100%')
                  .scale({
                    x: id === this.viewerMsgId ? this.viewerPhotoScale : VIEWER_MIN_SCALE,
                    y: id === this.viewerMsgId ? this.viewerPhotoScale : VIEWER_MIN_SCALE
                  })
                  .translate({
                    x: id === this.viewerMsgId ? this.viewerPhotoOffsetX : 0,
                    y: id === this.viewerMsgId ? this.viewerPhotoOffsetY : 0
                  });
              }
            }
            .width('100%').height('100%')
            // Exclusive tap recognition delays the single-tap action just
            // enough to determine whether the user is double tapping.
            .gesture(
              GestureGroup(GestureMode.Exclusive,
                TapGesture({ count: 2, fingers: 1 })
                  .onAction((event: GestureEvent) => { this.onViewerPhotoDoubleTap(event); }),
                TapGesture({ count: 1, fingers: 1 })
                  .onAction(() => { this.onViewerPhotoTap(); })
              )
            )
            .priorityGesture(
              GestureGroup(GestureMode.Parallel,
                PinchGesture({ fingers: 2 })
                  .onActionStart((event: GestureEvent) => { this.onViewerPinchStart(event); })
                  .onActionUpdate((event: GestureEvent) => { this.onViewerPinchUpdate(event); })
                  .onActionEnd(() => { this.onViewerPinchEnd(); })
                  .onActionCancel(() => { this.onViewerPinchEnd(); }),
                // Dynamic distance resolves the Swiper conflict (official
                // best practice): a large threshold at 1x lets the Swiper's
                // own pan win and page the album; a small one while zoomed
                // keeps single-finger panning responsive.
                PanGesture({ fingers: 1, distance: this.viewerZoomed() ? 3 : 50 })
                  .onActionStart(() => { this.onViewerPanStart(); })
                  .onActionUpdate((event: GestureEvent) => { this.onViewerPanUpdate(event); })
                  .onActionEnd(() => { this.onViewerPanEnd(); })
              )
            );
          }
        }.width('100%').height('100%');
      }, (id: number) => `vm_${id}`);
    }
    .indicator(false)
    .loop(false)
    .index(this.viewerInitIdx)
    // While enlarged, one-finger movement must not page the album out from
    // under the zoomed photo. Resetting to 1x re-enables normal paging.
    .disableSwipe(this.viewerZoomed() || this.viewerVideoLandscape)
    .onChange((i: number) => { this.onViewerPageChange(i); })
    .onAreaChange((_old: Area, area: Area) => {
      this.viewerAreaW = Number(area.width);
      this.viewerAreaH = Number(area.height);
    })
    .width('100%').height('100%');
    if (!this.viewerIsVideo() && this.viewerPhotoSrc() === '') {
      Column() {
        if (this.viewerPhotoFailed()) {
          this.viewerPhotoErrorState();
        } else {
          this.viewerPhotoLoadingState();
        }
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      .hitTestBehavior(HitTestMode.Transparent);
    } else if (!this.viewerIsVideo() && this.viewerPhotoUpgrading() && this.chromeVisible) {
      Row({ space: 7 }) {
        LoadingProgress().width(15).height(15).color(Color.White);
        Text(this.viewerPhotoProgress() > 0
          ? `正在加载原图 ${this.viewerPhotoProgress()}%` : '正在加载原图')
          .fontSize(12).fontColor(Color.White);
      }
      .padding({ left: 11, right: 11, top: 7, bottom: 7 })
      .backgroundColor(VIEWER_CHROME_BG).borderRadius(16)
      .position({ x: 14, y: this.topSafe + 76 })
      .hitTestBehavior(HitTestMode.None)
      .transition(TransitionEffect.OPACITY
        .combine(TransitionEffect.translate({ y: -5 }))
        .animation({ duration: this.chatEffectDuration(KEY_POWER_EFFECT_BLUR, 160), curve: Curve.EaseOut }));
    } else if (!this.viewerIsVideo() && this.viewerPhotoFailed() && this.chromeVisible) {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(14).fontColor([Color.White]);
        Text('原图加载失败，点击重试').fontSize(12).fontColor(Color.White);
      }
      .padding({ left: 11, right: 11, top: 7, bottom: 7 })
      .backgroundColor(VIEWER_CHROME_BG).borderRadius(16)
      .position({ x: 14, y: this.topSafe + 76 })
      .onClick((): void => { this.retryViewerPhoto(); });
    }
  }

  // Thumbnail strip for the current message's album (photo/video list) —
  // tap a thumbnail to switch the viewer to that item.
  @Builder
  viewerFilmstrip() {
    Scroll() {
      Row({ space: 6 }) {
        ForEach(this.viewerSiblingIds(), (id: number) => {
          Stack() {
            if (this.viewerSiblingPath(id) !== '') {
              Image(this.viewerSiblingPath(id).startsWith('/') ? `file://${this.viewerSiblingPath(id)}` : this.viewerSiblingPath(id))
                .width(52).height(52).borderRadius(6).objectFit(ImageFit.Cover);
            } else {
              Column().width(52).height(52).borderRadius(6).backgroundColor('#333333');
            }
            if (this.viewerSiblingIsVideo(id)) {
              Text('▶').fontSize(14).fontColor(Color.White);
            }
          }
          .width(52).height(52)
          .border({ width: id === this.viewerMsgId ? 2 : 0, color: Color.White })
          .borderRadius(6)
          .opacity(id === this.viewerMsgId ? 1 : 0.68)
          .scale({ x: id === this.viewerMsgId ? 1 : 0.92, y: id === this.viewerMsgId ? 1 : 0.92 })
          .animation({
            duration: this.chatEffectDuration(KEY_POWER_EFFECT_BLUR, 160),
            curve: Curve.EaseOut
          })
          .onClick(() => { this.jumpToSibling(id); });
        }, (id: number) => `film_${id}`);
      }.padding({ left: 12, right: 12 });
    }.scrollable(ScrollDirection.Horizontal).width('100%');
  }

  // Bot inline-keyboard callback button: send the payload to the bot. The bot
  // reacts by editing the message / sending a new one (handled by updates).
  // Callback answers may also carry a toast/dialog or URL; ignoring those made
  // valid game and interaction buttons appear to do nothing.
  private onBotCallback(messageId: number, data: string): void {
    const payload: TdObject = { '@type': 'callbackQueryPayloadData' };
    payload['data'] = data;
    this.requestBotCallback(messageId, payload, `data_${data}`);
  }

  private onGameOpen(messageId: number): void {
    const payload: TdObject = { '@type': 'callbackQueryPayloadGame' };
    this.requestBotCallback(messageId, payload, 'game');
  }

  private requestBotCallback(messageId: number, payload: TdObject, suffix: string): void {
    const key = `${messageId}_${suffix}`;
    if (this.botCallbackPending.has(key)) {
      return;
    }
    this.botCallbackPending.add(key);
    const req: TdRequest = { '@type': 'getCallbackQueryAnswer' };
    req['chat_id'] = this.chatId;
    req['message_id'] = messageId;
    req['payload'] = payload;
    getTdClient().send(req).then((answer: TdObject): void => {
      this.botCallbackPending.delete(key);
      const url = (answer['url'] as string | undefined) ?? '';
      const text = (answer['text'] as string | undefined) ?? '';
      const showAlert = (answer['show_alert'] as boolean | undefined) ?? false;
      if (url.trim() !== '') {
        openWebUrl(getContext(this) as common.UIAbilityContext, url, (): void => {
          promptAction.showToast({ message: '无法打开互动内容', duration: 1800 });
        });
      }
      if (text.trim() !== '') {
        if (showAlert) {
          promptAction.showDialog({
            title: '提示',
            message: text,
            buttons: [{ text: '知道了', color: '#3390EC' }]
          });
        } else {
          promptAction.showToast({ message: text, duration: 1800 });
        }
      }
    }).catch((e: TdError) => {
      this.botCallbackPending.delete(key);
      console.error(`ChatPage.getCallbackQueryAnswer failed: ${e.message}`);
      promptAction.showToast({
        message: suffix === 'game' ? '游戏暂时无法打开' : '操作失败，请重试',
        duration: 1800
      });
    });
  }

  private onPollVote(messageId: number, optionIds: number[]): void {
    if (this.store === null) {
      promptAction.showToast({ message: '投票暂时不可用', duration: 1500 });
      return;
    }
    this.store.votePoll(messageId, optionIds, (ok: boolean, error: string): void => {
      if (!ok && error.trim() !== '') {
        promptAction.showToast({ message: error, duration: 1800 });
      }
    });
  }

  private paidMediaPending(messageId: number): boolean {
    return this.paidMediaPendingIds.indexOf(messageId) >= 0;
  }

  private setPaidMediaPending(messageId: number, pending: boolean): void {
    const next = this.paidMediaPendingIds.filter((id: number): boolean => id !== messageId);
    if (pending) {
      next.push(messageId);
    }
    this.paidMediaPendingIds = next;
  }

  private paidMediaInvoice(messageId: number): TdObject {
    const invoice: TdObject = { '@type': 'inputInvoiceMessage' };
    invoice['chat_id'] = this.chatId;
    invoice['message_id'] = messageId;
    return invoice;
  }

  private onPaidMediaUnlock(messageId: number): void {
    const entry = this.entryById(messageId);
    if (entry === null || entry.contentType !== 'paidMedia' ||
      !entry.paidMediaLocked || entry.paidMediaStarCount <= 0 ||
      this.paidMediaPending(messageId)) {
      return;
    }
    this.setPaidMediaPending(messageId, true);
    const propertiesReq: TdRequest = { '@type': 'getMessageProperties' };
    propertiesReq['chat_id'] = this.chatId;
    propertiesReq['message_id'] = messageId;
    getTdClient().send(propertiesReq).then((properties: TdObject): Promise<TdObject> => {
      if (!((properties['can_be_paid'] as boolean | undefined) ?? false)) {
        throw new TdError(400, '这条付费内容当前无法购买');
      }
      const formReq: TdRequest = { '@type': 'getPaymentForm' };
      formReq['input_invoice'] = this.paidMediaInvoice(messageId);
      return getTdClient().send(formReq);
    }).then((form: TdObject): void => {
      const formType = form['type'] as TdObject | undefined;
      const typeName = formType !== undefined
        ? ((formType['@type'] as string | undefined) ?? '') : '';
      if (typeName !== 'paymentFormTypeStars') {
        this.setPaidMediaPending(messageId, false);
        promptAction.showToast({ message: '当前支付方式暂不支持', duration: 1800 });
        return;
      }
      const formStars = Math.max(0,
        (formType!['star_count'] as number | undefined) ?? entry.paidMediaStarCount);
      const formId = (form['id'] as number | undefined) ?? 0;
      if (formStars <= 0 || formId === 0) {
        this.setPaidMediaPending(messageId, false);
        promptAction.showToast({ message: '支付信息不完整，请稍后重试', duration: 1800 });
        return;
      }
      promptAction.showDialog({
        title: '解锁付费媒体',
        message: `将支付 ${formStars} 颗 Telegram 星星。付款完成后，这条消息会更新为已解锁状态。`,
        buttons: [
          { text: '取消', color: '#8E8E93' },
          { text: `支付 ${formStars} ⭐`, color: '#3390EC' }
        ]
      }).then((result): void => {
        if (result.index !== 1) {
          this.setPaidMediaPending(messageId, false);
          return;
        }
        const paymentReq: TdRequest = { '@type': 'sendPaymentForm' };
        paymentReq['input_invoice'] = this.paidMediaInvoice(messageId);
        paymentReq['payment_form_id'] = formId;
        paymentReq['order_info_id'] = '';
        paymentReq['shipping_option_id'] = '';
        paymentReq['tip_amount'] = 0;
        getTdClient().send(paymentReq).then((paymentResult: TdObject): void => {
          this.setPaidMediaPending(messageId, false);
          const success = (paymentResult['success'] as boolean | undefined) ?? false;
          const verificationUrl =
            (paymentResult['verification_url'] as string | undefined) ?? '';
          if (success) {
            promptAction.showToast({ message: '已解锁付费媒体', duration: 1600 });
            return;
          }
          if (verificationUrl !== '') {
            openWebUrl(getContext(this) as common.UIAbilityContext, verificationUrl, (): void => {
              promptAction.showToast({ message: '无法打开支付验证页', duration: 1800 });
            });
            return;
          }
          promptAction.showToast({ message: '支付未完成', duration: 1600 });
        }).catch((e: TdError): void => {
          this.setPaidMediaPending(messageId, false);
          console.error(`ChatPage.sendPaymentForm failed: ${e.message}`);
          promptAction.showToast({ message: '支付失败，请稍后重试', duration: 1800 });
        });
      }).catch((): void => {
        this.setPaidMediaPending(messageId, false);
      });
    }).catch((e: TdError): void => {
      this.setPaidMediaPending(messageId, false);
      console.error(`ChatPage.get paid media payment form failed: ${e.message}`);
      promptAction.showToast({
        message: e.message !== '' ? e.message : '无法获取支付信息',
        duration: 1800
      });
    });
  }

  private onPaidMediaOpen(messageId: number): void {
    const entry = this.entryById(messageId);
    if (entry === null || entry.contentType !== 'paidMedia' || entry.paidMediaLocked) {
      return;
    }
    this.openViewer(messageId);
  }

  private onGiftCodeCopy(code: string): void {
    if (code.trim() === '') {
      promptAction.showToast({ message: '兑换码暂不可用', duration: 1500 });
      return;
    }
    this.copyPlainText(code, '兑换码已复制');
  }

  private onGiveawayOpen(chatId: number, messageId: number): void {
    if (messageId <= 0) {
      return;
    }
    if (chatId === 0 || chatId === this.chatId) {
      this.onReplyTap(messageId);
      return;
    }
    const params: Record<string, Object> = {
      'chatId': chatId,
      'jumpTo': messageId
    };
    router.pushUrl({ url: 'pages/chat/ChatPage', params });
  }

  // Header avatar/title tap → detail page: users/bots get the personal
  // profile, groups/channels the chat profile.
  private openProfile(): void {
    if (this.headerProfileOpening || this.pageClosing) {
      return;
    }
    if (this.headerState === 'error') {
      this.resolveHeaderIdentity();
      return;
    }
    const storeUid = this.store !== null ? this.store.getPeerUserId() : 0;
    const uid = this.headerPeerUserId > 0 ? this.headerPeerUserId : storeUid;
    let url = '';
    let params: Record<string, Object>;
    if (uid > 0) {
      url = 'pages/profile/ProfilePage';
      params = { 'userId': uid };
    } else if (this.headerIdentityResolved ||
      (this.store !== null && this.store.getIsGroup())) {
      url = 'pages/profile/ChatProfilePage';
      params = { 'chatId': this.chatId };
    } else {
      promptAction.showToast({ message: '会话资料正在加载', duration: 1200 });
      this.resolveHeaderIdentity();
      return;
    }
    this.headerProfileOpening = true;
    if (this.headerNavigationTimer !== -1) {
      clearTimeout(this.headerNavigationTimer);
    }
    this.headerNavigationTimer = setTimeout((): void => {
      this.headerNavigationTimer = -1;
      this.headerProfileOpening = false;
    }, CHAT_HEADER_NAV_GUARD_MS);
    router.pushUrl({ url, params }).catch((error: Error): void => {
      if (this.headerNavigationTimer !== -1) {
        clearTimeout(this.headerNavigationTimer);
        this.headerNavigationTimer = -1;
      }
      this.headerProfileOpening = false;
      console.error(`ChatPage.openProfile failed: ${error.message}`);
      promptAction.showToast({ message: '无法打开会话资料', duration: 1600 });
    });
  }

  // Refresh the '@' mention / '/' command suggestion panels for the new draft.
  private updateSuggestions(v: string): void {
    this.commandMenuOpen = false;
    const cmd = v.match(/^\/([a-zA-Z0-9_]*)(?:@([a-zA-Z0-9_]*))?$/);
    if (cmd !== null) {
      this.mentionItems = [];
      this.refreshCommands();
      return;
    }
    this.commandItems = [];
    const at = v.match(/(?:^|\s)@([a-zA-Z0-9_]*)$/);
    if (at !== null && this.isGroup && !this.isChannel) {
      this.refreshMentions(at[1]);
      return;
    }
    this.mentionItems = [];
    this.refreshInlineQuery(v);
    this.refreshStickerSuggestions(v);
  }

  // Bots can expose a Mini App on their menu button — surface it as a composer
  // icon that opens the app in the in-app browser.
  private refreshBotMiniApp(userId: number): void {
    this.botMiniAppUrlValue = '';
    if (userId <= 0) { return; }
    botMiniAppUrl(userId).then((url: string): void => {
      if (this.headerPeerUserId === userId) { this.botMiniAppUrlValue = url; }
    }).catch((): void => {});
  }

  private openBotMiniApp(): void {
    const url = this.botMiniAppUrlValue;
    if (url === '' || this.headerPeerUserId <= 0) { return; }
    openMiniApp(this.chatId, this.headerPeerUserId, url).then((resolved: string): void => {
      if (resolved === '') {
        promptAction.showToast({ message: '无法打开 Mini App', duration: 1600 });
        return;
      }
      openWebUrl(getContext(this) as common.UIAbilityContext, resolved);
    }).catch((e: TdError): void => {
      console.error(`ChatPage.openBotMiniApp failed: ${e.message}`);
      promptAction.showToast({ message: '无法打开 Mini App', duration: 1600 });
    });
  }

  // "@bot query" in the composer runs an inline query and shows the bot's
  // results above the input bar (tap one to send it).
  private refreshInlineQuery(v: string): void {
    const match = v.match(/^@([A-Za-z0-9_]{3,32})\s+(.*)$/);
    if (match === null) {
      if (this.inlineResults.length > 0) {
        this.inlineResults = [];
        this.inlineQueryId = '';
      }
      return;
    }
    const username = match[1];
    const query = match[2];
    const seq = ++this.inlineSeq;
    if (this.inlineTimer !== -1) { clearTimeout(this.inlineTimer); }
    this.inlineTimer = setTimeout((): void => {
      this.inlineTimer = -1;
      const req: TdRequest = { '@type': 'searchPublicChat' };
      req['username'] = username;
      getTdClient().send(req, 10000).then((chat: TdObject): Promise<InlineQueryPage> => {
        const type = chat['type'] as TdObject | undefined;
        const botId = type !== undefined ? ((type['user_id'] as number | undefined) ?? 0) : 0;
        if (botId === 0) { return Promise.reject(new TdError(404, 'not a bot')); }
        return getInlineResults(botId, this.chatId, query);
      }).then((page: InlineQueryPage): void => {
        if (seq !== this.inlineSeq) { return; }
        this.inlineQueryId = page.queryId;
        this.inlineResults = page.rows.slice(0, 24);
        for (const row of this.inlineResults) { this.downloadInlineThumb(row, seq); }
      }).catch((): void => {
        if (seq !== this.inlineSeq) { return; }
        this.inlineResults = [];
        this.inlineQueryId = '';
      });
    }, 320);
  }

  private downloadInlineThumb(row: InlineResultRow, seq: number): void {
    if (row.thumbFileId === 0) { return; }
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = row.thumbFileId;
    req['priority'] = 2;
    req['synchronous'] = true;
    getTdClient().send(req, 15000).then((file: TdObject): void => {
      if (seq !== this.inlineSeq) { return; }
      const local = file['local'] as TdObject | undefined;
      const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
      if (path === '') { return; }
      this.inlineResults = this.inlineResults.map(
        (it: InlineResultRow): InlineResultRow => it.resultId === row.resultId
          ? {
            resultId: it.resultId, title: it.title, description: it.description,
            thumbFileId: it.thumbFileId, thumbPath: path, kind: it.kind
          } : it);
    }).catch((): void => {});
  }

  private pickInlineResult(row: InlineResultRow): void {
    if (this.inlineQueryId === '') { return; }
    const replyId = this.replyToId;
    sendInlineResult(this.chatId, this.inlineQueryId, row.resultId, replyId).then((): void => {
      this.draft = '';
      this.inlineResults = [];
      this.inlineQueryId = '';
      this.clearReply();
      this.atBottom = true;
    }).catch((e: TdError): void => {
      console.error(`ChatPage.sendInlineResult failed: ${e.message}`);
      promptAction.showToast({ message: '发送内联结果失败', duration: 1600 });
    });
  }

  @Builder
  inlineResultsBar() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.inlineResults, (row: InlineResultRow) => {
          Column({ space: 3 }) {
            Stack({ alignContent: Alignment.Center }) {
              if (row.thumbPath !== '') {
                Image(`file://${row.thumbPath}`).width(56).height(56)
                  .objectFit(ImageFit.Cover).borderRadius(8);
              } else {
                SymbolGlyph($r('sys.symbol.doc')).fontSize(22)
                  .fontColor([COLOR_TEXT_SECONDARY]);
              }
            }.width(58).height(58)
            .backgroundColor($r('app.color.surface_alt')).borderRadius(8);
            if (row.title !== '') {
              Text(row.title).fontSize(10).fontColor(COLOR_TEXT_SECONDARY)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: 62 });
            }
          }
          .onClick((): void => this.pickInlineResult(row));
        }, (row: InlineResultRow): string => `ir_${row.resultId}`);
      }.padding({ left: 10, right: 10, top: 6, bottom: 6 });
    }
    .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    .width('100%').height(88)
    .backgroundColor($r('app.color.surface'))
    .border({ width: { top: 0.7 }, color: $r('app.color.divider') });
  }

  // Typing a bare emoji offers matching stickers above the composer, as the
  // official clients do.
  private refreshStickerSuggestions(v: string): void {
    const text = v.trim();
    // Only a short pure-emoji draft qualifies (no letters/digits/spaces).
    const isEmojiOnly = text.length > 0 && text.length <= 8 &&
      !/[A-Za-z0-9\s]/.test(text);
    if (!isEmojiOnly) {
      if (this.stickerSuggestions.length > 0) { this.stickerSuggestions = []; }
      return;
    }
    const seq = ++this.stickerSuggestSeq;
    getStickersForEmoji(text).then((raw: TdObject[]): void => {
      if (seq !== this.stickerSuggestSeq) { return; }
      const items: StickerSuggestion[] = [];
      for (const st of raw.slice(0, 12)) {
        const file = st['sticker'] as TdObject | undefined;
        const fileId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
        const thumb = st['thumbnail'] as TdObject | undefined;
        const thumbFile = thumb !== undefined ? (thumb['file'] as TdObject | undefined) : undefined;
        const thumbId = thumbFile !== undefined ? ((thumbFile['id'] as number | undefined) ?? 0) : 0;
        if (fileId === 0) { continue; }
        items.push({ fileId, thumbId, thumbPath: '' });
      }
      this.stickerSuggestions = items;
      for (const item of items) { this.downloadSuggestionThumb(item, seq); }
    }).catch((): void => {});
  }

  private downloadSuggestionThumb(item: StickerSuggestion, seq: number): void {
    if (item.thumbId === 0) { return; }
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = item.thumbId;
    req['priority'] = 2;
    req['synchronous'] = true;
    getTdClient().send(req, 15000).then((file: TdObject): void => {
      if (seq !== this.stickerSuggestSeq) { return; }
      const local = file['local'] as TdObject | undefined;
      const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
      if (path === '') { return; }
      this.stickerSuggestions = this.stickerSuggestions.map(
        (row: StickerSuggestion): StickerSuggestion => row.fileId === item.fileId
          ? { fileId: row.fileId, thumbId: row.thumbId, thumbPath: path } : row);
    }).catch((): void => {});
  }

  private sendSuggestedSticker(fileId: number): void {
    this.store?.sendSticker(fileId, 512, 512);
    rememberRecentSticker(fileId);
    this.draft = '';
    this.stickerSuggestions = [];
    this.stickerSuggestSeq++;
  }

  @Builder
  stickerSuggestionBar() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.stickerSuggestions, (row: StickerSuggestion) => {
          Stack({ alignContent: Alignment.Center }) {
            if (row.thumbPath !== '') {
              Image(`file://${row.thumbPath}`).width(56).height(56).objectFit(ImageFit.Contain);
            } else {
              LoadingProgress().width(20).height(20).color(COLOR_TEXT_SECONDARY);
            }
          }
          .width(62).height(62)
          .onClick((): void => this.sendSuggestedSticker(row.fileId));
        }, (row: StickerSuggestion): string => `sg_${row.fileId}`);
      }.padding({ left: 10, right: 10 });
    }
    .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    .width('100%').height(70)
    .backgroundColor($r('app.color.surface'))
    .border({ width: { top: 0.7 }, color: $r('app.color.divider') });
  }

  private refreshCommands(): void {
    this.ensureCommandsLoaded();
    this.applyCommandFilter();
  }

  private ensureCommandsLoaded(force: boolean = false): void {
    if (!force && (this.commandLoadState === 'loading' || this.commandLoadState === 'ready')) {
      return;
    }
    const seq: number = ++this.commandLoadSeq;
    const chatId: number = this.chatId;
    const peer: number = this.store !== null ? this.store.getPeerUserId() : 0;
    this.commandLoadState = 'loading';
    this.commandLoadError = '';
    loadBotCommands(getTdClient(), chatId, peer).then((items: CommandItem[]) => {
      if (seq !== this.commandLoadSeq || chatId !== this.chatId) {
        return;
      }
      this.allCommands = items;
      this.commandLoadState = 'ready';
      this.commandLoadError = '';
      // Telegram's persistent 菜单 pill belongs to a private bot chat. Group
      // commands remain available through '/' and include @bot usernames.
      this.botMenuAvailable = peer > 0 && items.length > 0;
      this.applyCommandFilter();
    }).catch((e: TdError) => {
      if (seq !== this.commandLoadSeq || chatId !== this.chatId) {
        return;
      }
      console.error(`ChatPage.loadBotCommands failed: ${e.message}`);
      this.allCommands = [];
      this.commandItems = [];
      this.commandLoadState = 'error';
      this.commandLoadError = '命令加载失败';
      this.botMenuAvailable = false;
    });
  }

  private commandText(item: CommandItem): string {
    return `/${item.command}${item.botUsername !== '' ? `@${item.botUsername}` : ''}`;
  }

  private commandPanelActive(): boolean {
    return this.commandMenuOpen ||
      this.draft.match(/^\/([a-zA-Z0-9_]*)(?:@([a-zA-Z0-9_]*))?$/) !== null;
  }

  // Filter against the CURRENT draft, so a slow catalog load can't show stale results.
  private applyCommandFilter(): void {
    if (this.commandMenuOpen) {
      this.commandItems = this.commandLoadState === 'ready' ? this.allCommands.slice(0, 20) : [];
      return;
    }
    const m = this.draft.match(/^\/([a-zA-Z0-9_]*)(?:@([a-zA-Z0-9_]*))?$/);
    if (m === null) {
      this.commandItems = [];
      return;
    }
    if (this.commandLoadState !== 'ready') {
      this.commandItems = [];
      return;
    }
    const q = m[1].toLowerCase();
    const botQuery = (m[2] ?? '').toLowerCase();
    this.commandItems = this.allCommands.filter((c: CommandItem): boolean =>
      c.command.toLowerCase().startsWith(q) &&
      (botQuery === '' || c.botUsername.toLowerCase().startsWith(botQuery))).slice(0, 20);
  }

  private refreshMentions(query: string): void {
    const seq = ++this.mentionSeq;
    searchMentions(getTdClient(), this.chatId, query).then((items: MentionItem[]) => {
      // Drop the response if a newer query fired or the '@' trigger is gone.
      if (seq !== this.mentionSeq || this.draft.match(/(?:^|\s)@([a-zA-Z0-9_]*)$/) === null) {
        return;
      }
      this.mentionItems = items;
    });
  }

  // Replace the trailing '@token' with the chosen member.
  private pickMention(item: MentionItem): void {
    const idx = this.draft.lastIndexOf('@');
    const head = idx >= 0 ? this.draft.substring(0, idx) : this.draft;
    const token = item.username !== '' ? `@${item.username}` : item.name;
    this.draft = `${head}${token} `;
    this.mentionItems = [];
    setTimeout((): void => { focusControl.requestFocus('chat_composer'); }, 0);
  }

  private pickCommand(item: CommandItem): void {
    this.draft = this.commandText(item);
    this.commandItems = [];
    this.commandMenuOpen = false;
    this.doSend();
  }

  // Viewer "保存到相册": photos save right away (full-res preferred); a video
  // that isn't fully local yet starts its download and saves automatically on
  // completion (see the pendingGallerySaveId check in the store subscription).
  private saveViewerMedia(): void {
    const e = this.entryById(this.viewerMsgId);
    if (e === null) {
      return;
    }
    const ctx = getContext(this) as common.UIAbilityContext;
    if (this.mediaEntryIsVideo(e)) {
      if (e.videoPath !== '') {
        saveMediaToGallery(ctx, e.videoPath, true);
      } else {
        this.pendingGallerySaveId = e.id;
        if (this.store !== null) {
          this.store.requestVideoDownload(e.id, true, e.videoFailed);
        }
        promptAction.showToast({ message: '视频下载中，完成后自动保存到相册', duration: 2500 });
      }
      return;
    }
    if (e.photoFullPath !== '') {
      saveMediaToGallery(ctx, e.photoFullPath, false);
      return;
    }
    if (e.photoFullFileId !== 0) {
      this.pendingGallerySaveId = e.id;
      if (this.store !== null) {
        this.store.requestFullPhoto(e.id, e.photoFullFailed);
      }
      promptAction.showToast({ message: '正在下载原图，完成后自动保存', duration: 2200 });
      return;
    }
    if (e.photoPath !== '') {
      saveMediaToGallery(ctx, e.photoPath, false);
    } else {
      promptAction.showToast({ message: '图片不可用', duration: 1800 });
    }
  }

  private processAutomaticGallerySave(list: MessageEntry[]): void {
    if (this.autoSaveInFlight || this.autoSavePendingIds.length === 0) { return; }
    let target: MessageEntry | undefined = undefined;
    let path: string = '';
    let video: boolean = false;
    for (const messageId of this.autoSavePendingIds) {
      const entry = list.find((item: MessageEntry): boolean => item.id === messageId);
      if (entry === undefined || entry.isOutgoing ||
        (entry.contentType !== 'photo' && entry.contentType !== 'video')) {
        this.autoSavePendingIds = this.autoSavePendingIds.filter((id: number): boolean => id !== messageId);
        continue;
      }
      if (entry.contentType === 'video') {
        if (entry.videoFailed) {
          this.autoSavePendingIds = this.autoSavePendingIds.filter((id: number): boolean => id !== messageId);
          continue;
        }
        if (entry.videoPath !== '') { target = entry; path = entry.videoPath; video = true; break; }
      } else {
        if (entry.photoFullFailed) {
          this.autoSavePendingIds = this.autoSavePendingIds.filter((id: number): boolean => id !== messageId);
          continue;
        }
        if (entry.photoFullPath !== '') { target = entry; path = entry.photoFullPath; break; }
        if (entry.photoFullFileId === 0 && entry.photoPath !== '') {
          target = entry; path = entry.photoPath; break;
        }
      }
    }
    if (target === undefined || path === '') { return; }
    const id = target.id;
    this.autoSavePendingIds = this.autoSavePendingIds.filter((value: number): boolean => value !== id);
    this.autoSaveInFlight = true;
    saveMediaToGallery(getContext(this) as common.UIAbilityContext, path, video).then((): void => {
      this.autoSaveInFlight = false;
      this.processAutomaticGallerySave(this.messages);
    }).catch((): void => {
      this.autoSaveInFlight = false;
      this.processAutomaticGallerySave(this.messages);
    });
  }

  private openDownloadedFile(message: MessageEntry): void {
    if (message.videoPath === '' || this.fileOpenInFlightId !== 0) {
      return;
    }
    const messageId: number = message.id;
    this.fileOpenInFlightId = messageId;
    openLocalFile(
      getContext(this) as common.UIAbilityContext,
      message.videoPath,
      fileOpenMimeType(message.videoFileName, message.videoMimeType)
    ).then((opened: boolean): void => {
      if (this.fileOpenInFlightId === messageId) {
        this.fileOpenInFlightId = 0;
      }
      if (!opened) {
        promptAction.showToast({
          message: '没有可打开此文件的应用，可尝试另存为',
          duration: 2200
        });
      }
    }).catch((caught: Object): void => {
      if (this.fileOpenInFlightId === messageId) {
        this.fileOpenInFlightId = 0;
      }
      console.error(`ChatPage.openDownloadedFile failed: ${JSON.stringify(caught)}`);
      promptAction.showToast({ message: '文件打开失败', duration: 1800 });
    });
  }

  // Document card tap: an on-demand download retains the open intent, so the
  // file launches immediately when TDLib reports completion.
  private onFileTap(messageId: number): void {
    const m = this.messages.find((x: MessageEntry) => x.id === messageId);
    if (m === undefined || m.contentType !== 'file' || this.store === null) {
      return;
    }
    // The most recent file action wins. This avoids racing an external viewer
    // and the save picker when the user changes intent during a download.
    this.pendingFileSaveId = 0;
    if (m.videoPath !== '') {
      this.pendingFileOpenId = 0;
      this.openDownloadedFile(m);
      return;
    }
    if (m.videoFileId === 0) {
      this.pendingFileOpenId = 0;
      promptAction.showToast({ message: '这个文件暂时不可用', duration: 1600 });
      return;
    }
    this.pendingFileOpenId = messageId;
    this.store.requestVideoDownload(messageId, true, m.videoFailed);
    promptAction.showToast({
      message: m.videoFailed ? '正在重新下载文件'
        : (m.mediaDownloadActive ? '文件正在下载，完成后自动打开' : '开始下载文件'),
      duration: 1700
    });
  }

  private utilityActionAllowed(): boolean {
    const now = Date.now();
    if (now - this.utilityActionAtMs < 550) {
      return false;
    }
    this.utilityActionAtMs = now;
    return true;
  }

  private openSharedContact(userId: number, phone: string, vcard: string): void {
    if (!this.utilityActionAllowed()) {
      return;
    }
    if (userId > 0) {
      const params: Record<string, Object> = { 'userId': userId };
      router.pushUrl({ url: 'pages/profile/ProfilePage', params: params }).catch(() => {
        promptAction.showToast({ message: '无法打开联系人资料', duration: 1500 });
      });
      return;
    }
    if (vcard.trim() !== '') {
      const context = getContext(this) as common.UIAbilityContext;
      const path = `${context.cacheDir}/shared_contact_${Date.now()}.vcf`;
      try {
        const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
        fs.writeSync(file.fd, vcard);
        fs.closeSync(file);
        openLocalFile(context, path, 'text/vcard').then((opened: boolean): void => {
          if (!opened) {
            this.copyPlainText(vcard, '名片内容已复制');
          }
        }).catch((caught: Object): void => {
          console.error(`ChatPage.openSharedContact failed: ${JSON.stringify(caught)}`);
          this.copyPlainText(vcard, '名片内容已复制');
        });
      } catch (caught) {
        console.error(`ChatPage.write shared contact failed: ${caught}`);
        this.copyPlainText(vcard, '名片内容已复制');
      }
      return;
    }
    this.openSharedPhone(phone, true);
  }

  private openSharedPhone(phone: string, skipGuard: boolean = false): void {
    if (!skipGuard && !this.utilityActionAllowed()) {
      return;
    }
    const normalized = phone.trim().replace(/[^0-9+*#]/g, '');
    if (normalized === '') {
      promptAction.showToast({ message: '联系人没有可用电话号码', duration: 1500 });
      return;
    }
    openUrl(getContext(this) as common.UIAbilityContext, `tel:${normalized}`, (): void => {
      promptAction.showToast({ message: '未找到可拨号的应用', duration: 1600 });
    });
  }

  private openSharedLocation(
    latitude: number,
    longitude: number,
    label: string,
    valid: boolean
  ): void {
    if (!this.utilityActionAllowed()) {
      return;
    }
    const cleanLabel = label.trim();
    if (!valid && cleanLabel === '') {
      promptAction.showToast({ message: '这条消息没有可用位置', duration: 1500 });
      return;
    }
    const coordinate = `${latitude},${longitude}`;
    const query = encodeURIComponent(cleanLabel !== '' ? cleanLabel : coordinate);
    const geoUri = valid ? `geo:${latitude},${longitude}?q=${query}` : `geo:0,0?q=${query}`;
    const webFallback = valid
      ? `https://www.openstreetmap.org/?mlat=${latitude}&mlon=${longitude}#map=16/${latitude}/${longitude}`
      : `https://www.openstreetmap.org/search?query=${query}`;
    openUrl(getContext(this) as common.UIAbilityContext, geoUri, (): void => {
      openUrl(getContext(this) as common.UIAbilityContext, webFallback, (): void => {
        promptAction.showToast({ message: '未找到可打开位置的应用', duration: 1700 });
      });
    });
  }

  // Document card save arrow: opens the system "save as" picker once the file
  // is local; otherwise starts the download and saves automatically when done.
  private onFileSave(messageId: number): void {
    const m = this.messages.find((x: MessageEntry) => x.id === messageId);
    if (m === undefined || m.contentType !== 'file' || this.store === null) {
      return;
    }
    this.pendingFileOpenId = 0;
    if (m.videoPath !== '') {
      this.pendingFileSaveId = 0;
      saveFileToLocal(getContext(this) as common.UIAbilityContext, m.videoPath, m.videoFileName);
      return;
    }
    if (m.videoFileId === 0) {
      this.pendingFileSaveId = 0;
      promptAction.showToast({ message: '这个文件暂时不可用', duration: 1600 });
      return;
    }
    this.pendingFileSaveId = messageId;
    this.store.requestVideoDownload(messageId, true, m.videoFailed);
    promptAction.showToast({
      message: m.videoFailed ? '正在重新下载，完成后选择保存位置'
        : '文件下载中，完成后选择保存位置',
      duration: 2200
    });
  }

  // --- header "more" menu actions ---
  private toggleChatMute(): void {
    if (this.headerMuteUpdating) {
      return;
    }
    const previous = this.isMuted;
    const next = !previous;
    this.headerMuteUpdating = true;
    this.isMuted = next;
    // setMute 会先读取完整通知设置，所以在 TDLib 接受修改前保持更新锁；
    // 否则任意一次聊天刷新都会立刻用 ChatStore 的旧值覆盖乐观状态。
    setMute(this.chatId, next ? MUTE_LONG : 0).then((success: boolean): void => {
      if (!success) {
        this.isMuted = previous;
      }
      this.headerMuteUpdating = false;
    });
  }

  private confirmClearHistory(): void {
    AlertDialog.show({
      message: '确定清空此聊天的历史记录吗？',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: (): void => {}
      },
      secondaryButton: {
        value: '清空',
        fontColor: '#FF3B30',
        action: (): void => {
          const req: TdRequest = { '@type': 'deleteChatHistory' };
          req['chat_id'] = this.chatId;
          req['remove_from_chat_list'] = false;
          req['revoke'] = false;
          getTdClient().send(req).then(() => {
            promptAction.showToast({ message: '聊天记录已清空', duration: 2000 });
          }).catch((e: TdError) => {
            console.error(`ChatPage.deleteChatHistory failed: ${e.message}`);
            promptAction.showToast({ message: '清空失败', duration: 2000 });
          });
        }
      }
    });
  }

  private confirmLeaveChat(): void {
    AlertDialog.show({
      message: `确定退出「${this.title}」吗？`,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: (): void => {}
      },
      secondaryButton: {
        value: '退出',
        fontColor: '#FF3B30',
        action: (): void => {
          const req: TdRequest = { '@type': 'leaveChat' };
          req['chat_id'] = this.chatId;
          getTdClient().send(req).then(() => {
            router.back();
          }).catch((e: TdError) => {
            console.error(`ChatPage.leaveChat failed: ${e.message}`);
            promptAction.showToast({ message: '退出失败', duration: 2000 });
          });
        }
      }
    });
  }

  @Builder
  headerMenuRow(symbol: string, label: string, danger: boolean, onTap: () => void) {
    Row({ space: 10 }) {
      SymbolGlyph($r(symbol)).fontSize(18)
        .fontColor([danger ? '#FF3B30' : COLOR_TEXT_PRIMARY]);
      Text(label).fontSize(15).fontColor(danger ? '#FF3B30' : COLOR_TEXT_PRIMARY);
    }
    .width('100%').padding({ left: 14, right: 14, top: 11, bottom: 11 })
    .alignItems(VerticalAlign.Center)
    .stateStyles({
      normal: this.headerMenuRowNormalStyle,
      pressed: this.headerMenuRowPressedStyle
    })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 100),
      curve: Curve.EaseOut
    })
    .onClick(() => {
      this.headerMenuShow = false;
      onTap();
    });
  }

  @Builder
  headerMenu() {
    Column() {
      this.headerMenuRow('sys.symbol.magnifyingglass', '搜索', false, () => { this.enterSearch(); });
      Divider().color($r('app.color.divider')).strokeWidth(0.7);
      this.headerMenuRow('sys.symbol.info_circle', '资料', false, () => { this.openProfile(); });
      Divider().color($r('app.color.divider')).strokeWidth(0.7);
      this.headerMenuRow(this.isMuted ? 'sys.symbol.bell' : 'sys.symbol.bell_slash',
        this.headerMuteUpdating ? '正在更新通知' : (this.isMuted ? '取消静音' : '静音'),
        false, () => { this.toggleChatMute(); });
      Divider().color($r('app.color.divider')).strokeWidth(0.7);
      Divider().color($r('app.color.divider')).strokeWidth(0.7);
      this.headerMenuRow('sys.symbol.clock', '自动删除消息', false, () => { this.chooseAutoDelete(); });
      Divider().color($r('app.color.divider')).strokeWidth(0.7);
      this.headerMenuRow('sys.symbol.calendar', '定时消息', false, () => { this.openScheduledSheet(); });
      this.headerMenuRow('sys.symbol.calendar_badge_clock', '跳转到日期', false,
        () => { this.pickJumpDate(); });
      if (this.liveLocationActive) {
        this.headerMenuRow('sys.symbol.stop_circle', '停止共享位置', true,
          () => { this.confirmStopLiveLocation(); });
      }
      Divider().color($r('app.color.divider')).strokeWidth(0.7);
      this.headerMenuRow('sys.symbol.translate',
        this.isTranslatable ? '关闭自动翻译' : '开启自动翻译', false,
        () => { this.toggleTranslatable(); });
      this.headerMenuRow('sys.symbol.xmark_circle', '清空聊天记录', false, () => { this.confirmClearHistory(); });
      if (this.isGroup && this.membershipState === 'writable') {
        Divider().color($r('app.color.divider')).strokeWidth(0.7);
        this.headerMenuRow('sys.symbol.trash', this.isChannel ? '退出频道' : '退出群组', true,
          () => { this.confirmLeaveChat(); });
      }
    }
    .width(200)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(14)
    .shadow({ radius: 10, color: '#26000000', offsetX: 0, offsetY: 4 })
    .clip(true);
  }

  // Horizontal center (vp, window coords) of the smiley button — the anchor
  // the emoji panel scales out of / back into.
  private emojiBtnCx: number = 48;
  @State inputBarH: number = 64;
  // 顶部悬浮 chrome（标题栏 + 横幅）的实测高度，用来给列表让位。
  @State headerChromeH: number = 0;
  @State listViewportH: number = 0;
  // Height of every persistent bottom surface (composer/reply/Bot keyboard or
  // membership/search bar). The List uses it only as END offset: rows still
  // travel behind the floating input, while the final row can clear it.
  @State bottomChromeH: number = 76;
  private bottomChromeLayoutSeq: number = 0;
  // Measured bot-keyboard height; with the input bar it makes up the bottom
  // chrome the scroll-to-bottom FAB has to clear.
  @State replyKbH: number = 0;
  // "Fake" animation: the open/close transition flies an empty white shell;
  // the real panel content (hundreds of emoji + sticker players) mounts only
  // after the animation lands, so frames stay cheap.
  @State panelContentReady: boolean = false;
  private panelReadySeq: number = 0;

  private composerBottomGap(): number {
    return this.keyboardH > 0 ? 6 : Math.max(8, this.bottomSafe);
  }

  // TextArea's intrinsic minimum is taller than the old 48vp input capsule on
  // some phones/font scales. Give it an explicit content-driven height so the
  // empty composer keeps the original silhouette and only grows after typing.
  private composerEditorHeight(): number {
    const chunks: string[] = this.draft.split('\n');
    let lines: number = 0;
    for (let i: number = 0; i < chunks.length; i++) {
      lines += Math.max(1, Math.ceil(chunks[i].length / 18));
    }
    return Math.min(104, 40 + Math.max(0, lines - 1) * 20);
  }

  // 渐变模糊：只在顶部 chrome 那一条区域内从"全糊"过渡到"清晰"。
  // fractionStops 是 [模糊比例, 位置]，位置沿 direction 从 0 到 1；
  // direction 取 Bottom 时 0 就是列表顶端。
  private headerBlurStops(): [number, number][] {
    const viewport: number = this.listViewportH;
    if (viewport <= 0 || this.headerChromeH <= 0) {
      return [[0, 0], [0, 1]];
    }
    // 过渡带正好是 chrome 那一条：列表顶端（也就是屏幕最上沿）全糊，到 bar
    // 的下边缘归零。消息往上滑时是连续糊掉的，不是撞上一条硬边。
    //
    // 上半段是**全糊的平台段**而不是单点：只在位置 0 取 1 的话，全糊处是条
    // 零宽度的线，肉眼看到的最糊程度远达不到 100%。
    const end: number = Math.min(0.6, this.headerChromeH / viewport);
    return [[1, 0], [1, end * 0.62], [0, end]];
  }

  // 只看省电：这里的顾虑是逐帧实时渲染的功耗，跟"聊天背景特效"是两回事。
  // 先前误用了 backgroundEffectsEnabled()，它还附带自定义背景/特效开关的条件，
  // 会把模糊直接打成 0。
  private headerBlurRadius(): number {
    return !this.powerSaving && this.headerChromeH > 0 ? HEADER_BLUR_RADIUS : 0;
  }

  private updateBottomChromeHeight(height: number): void {
    if (height <= 0 || Math.abs(height - this.bottomChromeH) < 0.5) {
      return;
    }
    const keepTailVisible: boolean = this.atBottom && this.viewerMsgId === 0;
    this.bottomChromeH = height;
    if (keepTailVisible) {
      const seq: number = ++this.bottomChromeLayoutSeq;
      setTimeout((): void => {
        if (seq === this.bottomChromeLayoutSeq && this.atBottom) {
          this.scroller.scrollEdge(Edge.Bottom);
        }
      }, 0);
    }
  }

  private toggleReplyKeyboard(): void {
    if (this.replyKeyboard === null || this.replyKeyboardSendingKey !== '') {
      return;
    }
    const openingCustom: boolean = this.replyKbCollapsed;
    this.setEmojiPanel(false);
    this.mentionItems = [];
    this.commandItems = [];
    this.commandMenuOpen = false;
    if (openingCustom) {
      this.composerController.stopEditing();
      this.composerFocused = false;
    }
    this.replyKbCollapsed = !this.replyKbCollapsed;
    if (!openingCustom) {
      // Switching from the Bot keyboard back to text input should actually
      // present the IME rather than leaving an empty gap below the composer.
      setTimeout((): void => { focusControl.requestFocus('chat_composer'); }, 0);
    }
  }

  // Show/hide the emoji/sticker panel without resizing the message viewport.
  // 发出去之后的收尾。残影是独立浮层，和面板收起**并行**跑：先前把关面板
  // 排在飞出动画之后，串行等待让面板要一秒多才下去，感觉像卡住了。
  private finishStickerSend(thumbPath: string, x: number, y: number): void {
    if (this.stickerGhostTimer !== -1) {
      clearTimeout(this.stickerGhostTimer);
      this.stickerGhostTimer = -1;
    }
    // 立刻开始收面板（内部已把卸载与动画分帧）。
    this.setEmojiPanel(false);
    const duration: number = this.chatEffectDuration(KEY_POWER_EFFECT_MENU, STICKER_FLY_MS);
    if (duration === 0 || thumbPath === '') {
      this.stickerGhostPath = '';
      return;
    }
    this.stickerGhostPath = thumbPath;
    this.stickerGhostX = x;
    this.stickerGhostY = y;
    this.stickerGhostFly = false;
    // 起始态先落地一帧，否则终态和初始态在同一帧里，动画不会跑。
    setTimeout((): void => { this.stickerGhostFly = true; }, 16);
    this.stickerGhostTimer = setTimeout((): void => {
      this.stickerGhostTimer = -1;
      this.stickerGhostPath = '';
      this.stickerGhostFly = false;
    }, duration + 40);
  }

  private setEmojiPanel(show: boolean): void {
    if (this.showEmojiPanel === show) {
      return;
    }
    const seq = ++this.panelReadySeq;
    const duration: number = this.chatEffectDuration(KEY_POWER_EFFECT_MENU, 220);
    if (show) {
      this.emojiPanelClosing = false;
      this.composerController.stopEditing();
      this.composerFocused = false;
      this.replyKbCollapsed = true;
      animateTo({
        duration, curve: Curve.EaseOut
      }, () => {
        this.showEmojiPanel = true;
      });
      if (duration === 0) {
        this.panelContentReady = true;
        return;
      }
      setTimeout(() => {
        if (seq === this.panelReadySeq && this.showEmojiPanel) {
          this.panelContentReady = true; // content pops in after the shell lands
        }
      }, duration + 20);
    } else {
      this.emojiPanelClosing = true;
      // 卸载重内容和启动收起动画必须分帧。面板里同时挂着三个 picker（自定义
      // 表情常驻，贴纸/GIF 访问过就常驻），一次性卸掉实测 ~51ms；和 animateTo
      // 挤在同一个同步块里，动画一开场就已经掉帧。
      //
      // 先在没有动画运行时卸载 —— 这一下花在静止状态下，观感是内容一闪而空；
      // 下一帧再对着一个空面板启动收起动画，动画本身就是廉价的。
      this.panelContentReady = false;
      setTimeout((): void => {
        if (seq !== this.panelReadySeq) {
          return;
        }
        animateTo({
          duration, curve: Curve.EaseOut
        }, () => {
          this.showEmojiPanel = false;
          this.emojiPanelClosing = false;
        });
      }, 0);
    }
  }

  // 菜单 pill: toggle the full bot-command catalog in the suggestion panel.
  private toggleBotMenu(): void {
    if (this.commandMenuOpen) {
      this.commandMenuOpen = false;
      this.commandItems = [];
    } else {
      this.mentionItems = [];
      this.setEmojiPanel(false);
      this.replyKbCollapsed = true;
      this.commandMenuOpen = true;
      this.ensureCommandsLoaded();
      this.applyCommandFilter();
    }
  }

  private insertEmoji(e: string): void {
    this.draft = `${this.draft}${e}`;
    this.updateSuggestions(this.draft);
  }

  // Copy a picker URI into the sandbox so TDLib can read it; '' on failure.
  private copyUriToCache(uri: string): string {
    try {
      const name = decodeURIComponent(uri.substring(uri.lastIndexOf('/') + 1));
      const copyId = ++this.mediaCopySeq;
      const dest =
        `${(getContext(this) as common.UIAbilityContext).cacheDir}/send_${Date.now()}_${copyId}_${name}`;
      const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      fs.copyFileSync(src.fd, dest);
      fs.closeSync(src);
      return dest;
    } catch (e) {
      console.error(`ChatPage.copyUriToCache failed: ${e}`);
      return '';
    }
  }

  // Voice bubble asked for its file (eager download hasn't landed yet).
  private onVoiceTap(messageId: number): void {
    const entry: MessageEntry | null = this.entryById(messageId);
    if (entry === null || entry.contentType !== 'voice') {
      return;
    }
    if (entry.videoFileId === 0) {
      promptAction.showToast({ message: '这个语音文件暂时不可用', duration: 1600 });
      return;
    }
    if (this.store !== null) {
      this.store.requestVideoDownload(messageId, false, entry.videoFailed);
    }
    promptAction.showToast({
      message: entry.videoFailed ? '正在重新下载语音' : '语音加载中，请稍候',
      duration: 1400
    });
  }

  private onVoicePlaybackStarted(messageId: number): void {
    this.store?.markVoiceListened(messageId);
  }

  private musicQueueLength(): number {
    let count: number = 0;
    for (const entry of this.messages) {
      if (entry.contentType === 'audio') {
        count++;
      }
    }
    return count;
  }

  private musicQueuePosition(messageId: number): number {
    let position: number = 0;
    for (const entry of this.messages) {
      if (entry.contentType !== 'audio') {
        continue;
      }
      position++;
      if (entry.id === messageId) {
        return position;
      }
    }
    return 0;
  }

  private adjacentMusicEntry(messageId: number, direction: number): MessageEntry | null {
    const music: MessageEntry[] =
      this.messages.filter((entry: MessageEntry): boolean => entry.contentType === 'audio');
    const index: number = music.findIndex((entry: MessageEntry): boolean => entry.id === messageId);
    const nextIndex: number = index + (direction < 0 ? -1 : 1);
    return index >= 0 && nextIndex >= 0 && nextIndex < music.length ? music[nextIndex] : null;
  }

  private musicHasPrevious(messageId: number): boolean {
    return this.adjacentMusicEntry(messageId, -1) !== null;
  }

  private musicHasNext(messageId: number): boolean {
    return this.adjacentMusicEntry(messageId, 1) !== null;
  }

  private playMusicEntry(messageId: number, forceStart: boolean): void {
    const entry: MessageEntry | null = this.entryById(messageId);
    if (entry === null || entry.contentType !== 'audio') {
      return;
    }
    if (entry.videoFileId === 0 && entry.videoPath === '') {
      this.pendingMusicPlayId = 0;
      promptAction.showToast({ message: '这个音频文件暂时不可用', duration: 1600 });
      return;
    }
    if (entry.videoPath === '') {
      this.pendingMusicPlayId = messageId;
      if (this.store !== null) {
        this.store.requestVideoDownload(messageId, false, entry.videoFailed);
      }
      promptAction.showToast({
        message: entry.videoFailed ? '正在重新下载音乐'
          : (entry.mediaDownloadActive ? '音乐正在下载' : '开始下载音乐'),
        duration: 1400
      });
      return;
    }
    this.pendingMusicPlayId = 0;
    if (forceStart) {
      getVoicePlayback().startMusic(messageId, entry.videoPath, entry.videoDuration);
    } else {
      getVoicePlayback().toggleMusic(messageId, entry.videoPath, entry.videoDuration);
    }
  }

  private onAudioTap(messageId: number): void {
    this.playMusicEntry(messageId, false);
  }

  private onAudioPrevious(messageId: number): void {
    const current = getVoicePlayback().current();
    if (current.mode === 'music' && current.playingId === messageId && current.positionMs > 3000) {
      getVoicePlayback().seek(messageId, 0);
      return;
    }
    const previous: MessageEntry | null = this.adjacentMusicEntry(messageId, -1);
    if (previous !== null) {
      this.playMusicEntry(previous.id, true);
    } else if (current.mode === 'music' && current.playingId === messageId) {
      getVoicePlayback().seek(messageId, 0);
    }
  }

  private onAudioNext(messageId: number): void {
    const next: MessageEntry | null = this.adjacentMusicEntry(messageId, 1);
    if (next !== null) {
      this.playMusicEntry(next.id, true);
    }
  }

  private onAudioSeek(messageId: number, fraction: number): void {
    getVoicePlayback().seek(messageId, fraction);
  }

  private onMusicCompleted(messageId: number): void {
    const next: MessageEntry | null = this.adjacentMusicEntry(messageId, 1);
    if (next !== null) {
      this.playMusicEntry(next.id, true);
    }
  }

  private settlePendingMusic(list: MessageEntry[]): void {
    if (this.pendingMusicPlayId === 0) {
      return;
    }
    const pendingId: number = this.pendingMusicPlayId;
    const entry: MessageEntry | undefined =
      list.find((item: MessageEntry): boolean => item.id === pendingId);
    if (entry === undefined || entry.contentType !== 'audio') {
      this.pendingMusicPlayId = 0;
      return;
    }
    if (entry.videoFailed) {
      this.pendingMusicPlayId = 0;
      promptAction.showToast({ message: '音乐下载失败，请重试', duration: 1800 });
      return;
    }
    if (entry.videoPath !== '') {
      this.pendingMusicPlayId = 0;
      getVoicePlayback().startMusic(entry.id, entry.videoPath, entry.videoDuration);
    }
  }

  // Paperclip → 照片或视频: system photo picker, send each as photo/video.
  // Replace the media of an already-sent photo/video message, keeping its
  // caption (editMessageMedia).
  private replaceMedia(messageId: number): void {
    const msg = this.findMsg(messageId);
    const store = this.store;
    if (msg === null || store === null || this.mediaPickerOpen) { return; }
    this.mediaPickerOpen = true;
    const photoPicker = new photoAccessHelper.PhotoViewPicker();
    const opts = new photoAccessHelper.PhotoSelectOptions();
    opts.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_VIDEO_TYPE;
    opts.maxSelectNumber = 1;
    photoPicker.select(opts).then((res: photoAccessHelper.PhotoSelectResult): void => {
      this.mediaPickerOpen = false;
      if (res.photoUris.length === 0) { return; }
      const path = this.copyUriToCache(res.photoUris[0]);
      if (path === '') {
        promptAction.showToast({ message: '无法读取所选文件', duration: 1600 });
        return;
      }
      const isVideo = path.toLowerCase().endsWith('.mp4') || path.toLowerCase().endsWith('.mov');
      store.editMediaAsync(messageId, path, isVideo, msg.text).then((): void => {
        promptAction.showToast({ message: '媒体已替换', duration: 1500 });
      }).catch((e: TdError): void => {
        console.error(`ChatPage.replaceMedia failed: ${e.message}`);
        promptAction.showToast({ message: '替换失败，原消息未改动', duration: 1700 });
      });
    }).catch((): void => { this.mediaPickerOpen = false; });
  }

  private pickAndSendMedia(): void {
    if (this.mediaPickerOpen || this.composerSending || this.store === null) {
      return;
    }
    this.mediaPickerOpen = true;
    const photoPicker = new photoAccessHelper.PhotoViewPicker();
    const opts = new photoAccessHelper.PhotoSelectOptions();
    opts.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_VIDEO_TYPE;
    opts.maxSelectNumber = 9;
    photoPicker.select(opts).then((res: photoAccessHelper.PhotoSelectResult) => {
      this.mediaPickerOpen = false;
      if (res.photoUris.length === 0 || this.store === null) {
        return;
      }
      const captionSnapshot = this.draft;
      const caption = captionSnapshot.trim();
      const replyId = this.replyToId;
      const items: MediaSendItem[] = [];
      let skipped = 0;
      for (const uri of res.photoUris) {
        const path = this.copyUriToCache(uri);
        if (path === '') {
          skipped++;
          continue;
        }
        const ext = path.substring(path.lastIndexOf('.') + 1).toLowerCase();
        const isVideo = ext === 'mp4' || ext === 'mov' || ext === 'mkv' || ext === 'avi' || ext === 'webm';
        items.push({ path, isVideo });
      }
      if (items.length === 0) {
        promptAction.showToast({ message: '所选媒体读取失败', duration: 1800 });
        return;
      }
      if (skipped > 0) {
        promptAction.showToast({ message: `${skipped} 项媒体读取失败，已发送其余内容`, duration: 1800 });
      }
      const store: MessageStore = this.store;
      this.composerSending = true;
      this.atBottom = true;
      this.stayAtUnread = false;
      store.sendMedia(items, caption, replyId).then((): void => {
        if (this.draft === captionSnapshot) {
          this.draft = '';
        }
        if (this.replyToId === replyId) {
          this.clearReply();
        }
        this.composerSending = false;
      }).catch((e: TdError): void => {
        this.composerSending = false;
        console.error(`ChatPage.sendMedia failed: ${e.message}`);
        promptAction.showToast({ message: '图片发送失败，文字与回复状态已保留', duration: 2000 });
      });
    }).catch((e: Object) => {
      this.mediaPickerOpen = false;
      console.error(`ChatPage.pickAndSendMedia failed: ${JSON.stringify(e)}`);
      promptAction.showToast({ message: '无法打开媒体选择器', duration: 1800 });
    });
  }

  // --- voice recording (mic button) ---
  private startRecording(): void {
    if (this.recordingStarting || this.isRecording || this.store === null) {
      return;
    }
    this.setEmojiPanel(false);
    this.replyKbCollapsed = true;
    this.mentionItems = [];
    this.commandItems = [];
    this.commandMenuOpen = false;
    this.composerController.stopEditing();
    this.composerFocused = false;
    this.recordingStarting = true;
    const seq: number = ++this.recordingSeq;
    const rec = new VoiceRecorder();
    this.voiceRec = rec;
    rec.start(getContext(this) as common.UIAbilityContext).then((ok: boolean) => {
      if (seq !== this.recordingSeq) {
        rec.cancel();
        return;
      }
      this.recordingStarting = false;
      if (!ok) {
        this.voiceRec = null;
        promptAction.showToast({ message: '无法开始录音（请检查麦克风权限）', duration: 2500 });
        return;
      }
      this.isRecording = true;
      this.recordSeconds = 0;
      this.recordTimer = setInterval(() => { this.recordSeconds += 1; }, 1000);
    }).catch((e: Object): void => {
      if (seq !== this.recordingSeq) {
        return;
      }
      this.recordingStarting = false;
      this.voiceRec = null;
      console.error(`ChatPage.startRecording failed: ${JSON.stringify(e)}`);
      promptAction.showToast({ message: '无法开始录音', duration: 1800 });
    });
  }

  private stopRecordTimer(): void {
    if (this.recordTimer !== -1) {
      clearInterval(this.recordTimer);
      this.recordTimer = -1;
    }
  }

  private finishRecording(): void {
    this.recordingSeq++;
    const rec = this.voiceRec;
    this.voiceRec = null;
    this.recordingStarting = false;
    this.stopRecordTimer();
    this.isRecording = false;
    if (rec === null) {
      return;
    }
    rec.stop().then((duration: number) => {
      if (rec.path !== '' && this.store !== null) {
        this.atBottom = true;
        this.store.sendVoiceNote(rec.path, duration);
      }
    });
  }

  private cancelRecording(): void {
    this.recordingSeq++;
    const rec = this.voiceRec;
    this.voiceRec = null;
    this.recordingStarting = false;
    this.stopRecordTimer();
    this.isRecording = false;
    if (rec !== null) {
      rec.cancel();
    }
  }

  private formatRecSeconds(): string {
    const m = Math.floor(this.recordSeconds / 60);
    const s = this.recordSeconds % 60;
    return `${m}:${`${s}`.padStart(2, '0')}`;
  }

  // --- 定时消息管理 ---

  private openScheduledSheet(): void {
    this.headerMenuShow = false;
    this.showScheduledSheet = true;
    this.loadScheduled();
  }

  private loadScheduled(): void {
    this.scheduledLoadState = 'loading';
    const req: TdRequest = { '@type': 'getChatScheduledMessages' };
    req['chat_id'] = this.chatId;
    getTdClient().send(req).then((res: TdObject): void => {
      const messages: TdObject[] = (res['messages'] as TdObject[] | undefined) ?? [];
      const ids: number[] = [];
      const previews: string[] = [];
      const timeLabels: string[] = [];
      for (const message of messages) {
        const id: number = (message['id'] as number | undefined) ?? 0;
        if (id === 0) {
          continue;
        }
        ids.push(id);
        previews.push(formatPreview(message));
        const scheduling = message['scheduling_state'] as TdObject | undefined;
        const schedulingType: string = scheduling !== undefined
          ? ((scheduling['@type'] as string | undefined) ?? '') : '';
        if (schedulingType === 'messageSchedulingStateSendWhenOnline') {
          timeLabels.push('对方上线时发送');
        } else {
          const sendDate: number = scheduling !== undefined
            ? ((scheduling['send_date'] as number | undefined) ?? 0) : 0;
          const at = new Date(sendDate * 1000);
          const two = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
          timeLabels.push(sendDate > 0
            ? `${at.getMonth() + 1}月${at.getDate()}日 ${two(at.getHours())}:${two(at.getMinutes())}`
            : '');
        }
      }
      this.scheduledIds = ids;
      this.scheduledPreviews = previews;
      this.scheduledTimeLabels = timeLabels;
      this.scheduledLoadState = 'ready';
    }).catch((e: TdError): void => {
      console.error(`ChatPage.loadScheduled failed: ${e.message}`);
      this.scheduledLoadState = 'error';
    });
  }

  // 立即发送：不带 scheduling_state 的 editMessageSchedulingState。
  private sendScheduledNow(messageId: number): void {
    const req: TdRequest = { '@type': 'editMessageSchedulingState' };
    req['chat_id'] = this.chatId;
    req['message_id'] = messageId;
    getTdClient().send(req).then((): void => {
      this.loadScheduled();
    }).catch((e: TdError): void => {
      console.error(`ChatPage.sendScheduledNow failed: ${e.message}`);
      promptAction.showToast({ message: '发送失败，请稍后重试', duration: 1700 });
    });
  }

  private deleteScheduled(messageId: number): void {
    const req: TdRequest = { '@type': 'deleteMessages' };
    req['chat_id'] = this.chatId;
    req['message_ids'] = [messageId];
    req['revoke'] = true;
    getTdClient().send(req).then((): void => {
      this.loadScheduled();
    }).catch((e: TdError): void => {
      console.error(`ChatPage.deleteScheduled failed: ${e.message}`);
      promptAction.showToast({ message: '删除失败，请稍后重试', duration: 1700 });
    });
  }

  @Builder
  scheduledSheet() {
    Column() {
      Column().layoutWeight(1).onClick((): void => {
        this.showScheduledSheet = false;
      });
      Column({ space: 10 }) {
        Row().width(40).height(4).borderRadius(2).backgroundColor('#D0D0D0');
        Text('定时消息').fontSize(17).fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY);
        if (this.scheduledLoadState === 'loading') {
          LoadingProgress().width(28).height(28).margin({ top: 24, bottom: 24 });
        } else if (this.scheduledLoadState === 'error') {
          Text('定时消息加载失败').fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
            .margin({ top: 24, bottom: 24 });
        } else if (this.scheduledIds.length === 0) {
          Text('没有待发送的定时消息').fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
            .margin({ top: 24, bottom: 24 });
        } else {
          List({ space: 6 }) {
            ForEach(this.scheduledIds, (id: number, itemIndex: number) => {
              ListItem() {
                Row({ space: 10 }) {
                  Column({ space: 3 }) {
                    Text(this.scheduledPreviews[itemIndex] ?? '')
                      .fontSize(14).fontColor(COLOR_TEXT_PRIMARY)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                    Text(this.scheduledTimeLabels[itemIndex] ?? '')
                      .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
                  }
                  .alignItems(HorizontalAlign.Start).layoutWeight(1);
                  Button('立即发送').fontSize(12).height(30)
                    .onClick((): void => this.sendScheduledNow(id));
                  Row() {
                    SymbolGlyph($r('sys.symbol.trash')).fontSize(17)
                      .fontColor(['#E5484D']);
                  }
                  .width(34).height(34).borderRadius(17)
                  .justifyContent(FlexAlign.Center)
                  .onClick((): void => this.deleteScheduled(id));
                }
                .width('100%').padding({ top: 6, bottom: 6 });
              }
            }, (id: number): string => `scheduled_${id}`);
          }
          .constraintSize({ maxHeight: 320 });
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 24 })
      .backgroundColor($r('app.color.surface'))
      .borderRadius({ topLeft: 16, topRight: 16 });
    }
    .width('100%').height('100%')
    .backgroundColor('#66000000');
  }

  private attachMenuItems(): MenuElement[] {
    const items: MenuElement[] = [
      { value: '照片或视频', action: (): void => {
        this.setEmojiPanel(false);
        this.pickAndSendMedia();
      } } as MenuElement,
      { value: '圆形视频', action: (): void => {
        this.setEmojiPanel(false);
        this.openVideoNoteRecorder();
      } } as MenuElement,
      { value: '文件', action: (): void => {
        this.setEmojiPanel(false);
        this.pickAndSendFile();
      } } as MenuElement,
      { value: '音乐', action: (): void => {
        this.setEmojiPanel(false);
        this.pickAndSendAudio();
      } } as MenuElement,
      { value: '位置', action: (): void => {
        this.setEmojiPanel(false);
        this.chooseLocationKind();
      } } as MenuElement,
      { value: '联系人', action: (): void => {
        this.setEmojiPanel(false);
        this.openContactPicker();
      } } as MenuElement
    ];
    // 投票仅群/频道可发（Telegram 限制私聊不能发投票）。
    if (this.isGroup || this.isChannel) {
      items.push({ value: '投票', action: (): void => {
        this.setEmojiPanel(false);
        this.openPollComposer();
      } } as MenuElement);
    }
    items.push({ value: '骰子', action: (): void => {
      this.setEmojiPanel(false);
      this.showDiceMenu();
    } } as MenuElement);
    return items;
  }

  private openPollComposer(): void {
    this.showPollSheet = true;
  }

  // 圆形视频走附件菜单而不是麦克风按钮：麦克风已经是"点一下开始录音"的
  // 单击语义，再叠一个长按会和录音的起录竞争，误触率高；附件菜单里它和
  // 照片/文件是同一类"选一种内容发出去"的入口，心智更一致。
  private openVideoNoteRecorder(): void {
    if (this.store === null) {
      return;
    }
    this.cancelRecording();
    this.composerController.stopEditing();
    this.composerFocused = false;
    this.showVideoNoteRecorder = true;
  }

  private openContactPicker(): void {
    this.showContactSheet = true;
  }

  // 音乐：文件选择器按音频后缀过滤，复制沙箱后按音频消息发送。
  private pickAndSendAudio(): void {
    const docPicker = new picker.DocumentViewPicker(getContext(this) as common.UIAbilityContext);
    const opts = new picker.DocumentSelectOptions();
    opts.maxSelectNumber = 1;
    opts.fileSuffixFilters = ['.mp3', '.m4a', '.flac', '.ogg', '.wav', '.aac'];
    docPicker.select(opts).then((uris: string[]) => {
      if (uris.length === 0) {
        return;
      }
      try {
        const uri = uris[0];
        const name = decodeURIComponent(uri.substring(uri.lastIndexOf('/') + 1));
        const dest = `${(getContext(this) as common.UIAbilityContext).cacheDir}/send_${Date.now()}_${name}`;
        const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
        fs.copyFileSync(src.fd, dest);
        fs.closeSync(src);
        if (this.store !== null) {
          this.atBottom = true;
          this.store.sendAudio(dest, this.draft.trim());
          this.draft = '';
        }
      } catch (e) {
        console.error(`ChatPage.pickAndSendAudio copy failed: ${e}`);
        promptAction.showToast({ message: '音频读取失败', duration: 2000 });
      }
    }).catch((e: Object) => {
      console.error(`ChatPage.pickAndSendAudio select failed: ${JSON.stringify(e)}`);
    });
  }

  // 位置入口：先问是发静态点还是实时共享。
  private chooseLocationKind(): void {
    this.getUIContext().getPromptAction().showActionMenu({
      title: '发送位置',
      buttons: [
        { text: '当前位置', color: COLOR_TEXT_PRIMARY as string },
        { text: '实时位置 · 15 分钟', color: COLOR_TEXT_PRIMARY as string },
        { text: '实时位置 · 1 小时', color: COLOR_TEXT_PRIMARY as string },
        { text: '实时位置 · 8 小时', color: COLOR_TEXT_PRIMARY as string }
      ]
    }).then((res: promptAction.ActionMenuSuccessResponse): void => {
      const periods: number[] = [0, 15 * 60, 3600, 8 * 3600];
      const period: number = periods[res.index] ?? 0;
      if (period === 0) {
        this.sendCurrentLocation();
      } else {
        this.startLiveLocation(period);
      }
    }).catch((): void => {});
  }

  // 实时位置：发出后按固定间隔用新坐标 editMessageLiveLocation。TDLib 不会
  // 替我们采集位置，更新完全由客户端驱动，所以这里自己维护定时器；页面销毁
  // 或时长到期就停，避免后台一直定位耗电。
  private startLiveLocation(periodSec: number): void {
    this.withLocationPermission((): void => {
      this.currentLocation(10000).then((loc: geoLocationManager.Location): void => {
        const store = this.store;
        if (store === null) { return; }
        this.atBottom = true;
        store.sendLiveLocation(loc.latitude, loc.longitude, periodSec)
          .then((messageId: number): void => {
            if (messageId === 0) {
              promptAction.showToast({ message: '实时位置发送失败', duration: 1800 });
              return;
            }
            // 交给独立服务：退出会话、切后台都要继续共享。
            liveLocation.start(this.chatId, messageId, periodSec);
            promptAction.showToast({ message: '已开始共享实时位置', duration: 1600 });
          });
      }).catch((): void => {
        promptAction.showToast({ message: '定位失败，请确认已开启定位服务', duration: 2000 });
      });
    });
  }

  private withLocationPermission(run: () => void): void {
    const context = getContext(this) as common.UIAbilityContext;
    const permissions: Permissions[] =
      ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.LOCATION'];
    abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, permissions)
      .then((result): void => {
        if (result.authResults.length > 0 && result.authResults[0] === 0) {
          run();
          return;
        }
        promptAction.showToast({ message: '需要定位权限才能发送位置', duration: 1800 });
      })
      .catch((e: BusinessError): void => {
        console.error(`ChatPage location permission failed: ${e.message}`);
      });
  }

  private currentLocation(timeoutMs: number): Promise<geoLocationManager.Location> {
    const request: geoLocationManager.SingleLocationRequest = {
      locatingPriority: geoLocationManager.LocatingPriority.PRIORITY_LOCATING_SPEED,
      locatingTimeoutMs: timeoutMs
    };
    return geoLocationManager.getCurrentLocation(request);
  }

  // 位置：申请定位权限 → 取当前坐标 → 发送。无地图选点（Map Kit 需 AGC 凭据）。
  private sendCurrentLocation(): void {
    const context = getContext(this) as common.UIAbilityContext;
    const permissions: Permissions[] =
      ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.LOCATION'];
    abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, permissions)
      .then((result): void => {
        const granted: boolean = result.authResults.length > 0 && result.authResults[0] === 0;
        if (!granted) {
          promptAction.showToast({ message: '需要定位权限才能发送位置', duration: 1800 });
          return;
        }
        promptAction.showToast({ message: '正在获取位置…', duration: 1200 });
        const request: geoLocationManager.SingleLocationRequest = {
          locatingPriority: geoLocationManager.LocatingPriority.PRIORITY_LOCATING_SPEED,
          locatingTimeoutMs: 10000
        };
        geoLocationManager.getCurrentLocation(request)
          .then((location: geoLocationManager.Location): void => {
            if (this.store !== null) {
              this.atBottom = true;
              this.store.sendLocation(location.latitude, location.longitude);
            }
          })
          .catch((e: BusinessError): void => {
            console.error(`ChatPage.sendCurrentLocation failed: ${e.message}`);
            promptAction.showToast({ message: '定位失败，请确认已开启定位服务', duration: 2000 });
          });
      })
      .catch((e: BusinessError): void => {
        console.error(`ChatPage location permission failed: ${e.message}`);
      });
  }

  // 骰子：系统动作菜单六选一（正好是 showActionMenu 的按钮上限）。
  // 🎰 老虎机由 DiceBubble 叠 5 层 TGS 渲染。
  private showDiceMenu(): void {
    const emojis: string[] = ['🎲', '🎯', '🏀', '⚽', '🎳', '🎰'];
    promptAction.showActionMenu({
      title: '掷一个',
      buttons: [
        { text: '🎲 骰子', color: '#007AFF' }, { text: '🎯 飞镖', color: '#007AFF' },
        { text: '🏀 篮球', color: '#007AFF' }, { text: '⚽ 足球', color: '#007AFF' },
        { text: '🎳 保龄球', color: '#007AFF' }, { text: '🎰 老虎机', color: '#007AFF' }
      ]
    }).then((result): void => {
      const index: number = result.index;
      if (index >= 0 && index < emojis.length && this.store !== null) {
        this.atBottom = true;
        this.store.sendDice(emojis[index]);
      }
    }).catch((): void => {});
  }

  // Paperclip: pick a document, copy it into the app sandbox (TDLib can't read
  // picker URIs), then send it as a document message.
  private pickAndSendFile(): void {
    const docPicker = new picker.DocumentViewPicker(getContext(this) as common.UIAbilityContext);
    const opts = new picker.DocumentSelectOptions();
    opts.maxSelectNumber = 1;
    docPicker.select(opts).then((uris: string[]) => {
      if (uris.length === 0) {
        return;
      }
      try {
        const uri = uris[0];
        const name = decodeURIComponent(uri.substring(uri.lastIndexOf('/') + 1));
        const dest = `${(getContext(this) as common.UIAbilityContext).cacheDir}/send_${Date.now()}_${name}`;
        const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
        fs.copyFileSync(src.fd, dest);
        fs.closeSync(src);
        if (this.store !== null) {
          this.atBottom = true;
          this.store.sendDocument(dest, this.draft.trim());
          this.draft = '';
        }
      } catch (e) {
        console.error(`ChatPage.pickAndSendFile copy failed: ${e}`);
        promptAction.showToast({ message: '文件读取失败', duration: 2000 });
      }
    }).catch((e: Object) => {
      console.error(`ChatPage.pickAndSendFile select failed: ${JSON.stringify(e)}`);
    });
  }

  private doSend(): void {
    if (this.editingId !== 0) {
      this.commitEdit();
      return;
    }
    const draftSnapshot: string = this.draft;
    const text: string = draftSnapshot.trim();
    const store: MessageStore | null = this.store;
    if (text === '' || store === null || this.composerSending) {
      return;
    }
    const replyId: number = this.replyToId;
    this.composerSending = true;
    this.commandMenuOpen = false;
    this.atBottom = true;
    this.stayAtUnread = false;
    store.sendAsync(text, replyId).then((): void => {
      // The user may already have started the next message while TDLib was
      // accepting this one. Never erase newer input or a newly selected reply.
      if (this.draft === draftSnapshot) {
        this.draft = '';
      }
      if (this.replyToId === replyId) {
        this.clearReply();
      }
      this.mentionItems = [];
      this.commandItems = [];
      this.commandMenuOpen = false;
      this.composerSending = false;
    }).catch((e: TdError): void => {
      this.composerSending = false;
      console.error(`ChatPage.doSend failed: ${e.message}`);
      promptAction.showToast({ message: '发送失败，消息已保留', duration: 1800 });
    });
  }

  // Bot reply-keyboard button. keyboardButtonTypeText simply sends its own label
  // as an ordinary message. The other types (location / phone number / poll /
  // web app) need capabilities we don't have, so they're rejected rather than
  // silently doing nothing — a button that lies is worse than one that says no.
  private onReplyKeyboardTap(btn: KeyboardBtn, key: string): void {
    // Older TDLib payloads can omit keyboardButtonTypeText entirely; an empty
    // type is still the ordinary text-button behavior.
    if (btn.type !== '' && btn.type !== KB_TEXT) {
      promptAction.showToast({ message: '暂不支持这种按钮', duration: 1500 });
      return;
    }
    if (this.store === null || this.replyKeyboardSendingKey !== '') {
      return;
    }
    const store: MessageStore = this.store;
    const replyId: number = this.replyToId;
    const keyboardId: number = this.replyKeyboard !== null ? this.replyKeyboard.messageId : 0;
    const oneTime: boolean = this.replyKeyboard !== null && this.replyKeyboard.oneTime;
    this.replyKeyboardSendingKey = key;
    this.atBottom = true;
    this.stayAtUnread = false;
    store.sendAsync(btn.text, replyId).then((): void => {
      this.replyKeyboardSendingKey = '';
      if (this.replyToId === replyId) {
        this.clearReply();
      }
      // one_time keyboards fold only after TDLib accepts the message. A failed
      // tap leaves the controls visible so the user can retry.
      if (oneTime && this.replyKeyboard !== null &&
        this.replyKeyboard.messageId === keyboardId) {
        this.replyKbCollapsed = true;
      }
    }).catch((e: TdError): void => {
      this.replyKeyboardSendingKey = '';
      console.error(`ChatPage.replyKeyboard send failed: ${e.message}`);
      promptAction.showToast({ message: '发送失败，请重试', duration: 1600 });
    });
  }

  private findMsg(messageId: number): MessageEntry | null {
    for (const m of this.messages) {
      if (m.id === messageId) {
        return m;
      }
    }
    return null;
  }

  private clearReply(): void {
    this.replyToId = 0;
    this.replyToName = '';
    this.replyToText = '';
  }

  private replySnippet(m: MessageEntry): string {
    if (m.text.trim() !== '') {
      return m.text;
    }
    if (m.placeholderLabel.trim() !== '') {
      return m.placeholderLabel;
    }
    if (m.contentType === 'sticker') {
      return '贴纸';
    }
    if (m.contentType === 'photo') {
      return '图片';
    }
    if (m.contentType === 'video') {
      return '视频';
    }
    if (m.contentType === 'paidMedia') {
      return m.paidMediaLocked ? '付费媒体' : '已解锁媒体';
    }
    if (m.contentType === 'voice') {
      return '语音消息';
    }
    return '媒体消息';
  }

  // Long-press menu: reply. Populates the reply preview above the input bar;
  // doSend() then attaches reply_to.
  private startReply(messageId: number): void {
    const m = this.findMsg(messageId);
    if (m === null) {
      return;
    }
    ContextMenu.close();
    this.closeReactionSheet();
    this.replyToId = messageId;
    this.replyToName = m.senderName !== '' ? m.senderName : this.title;
    this.replyToText = this.replySnippet(m);
    this.setEmojiPanel(false);
    this.replyKbCollapsed = true;
    setTimeout((): void => {
      focusControl.requestFocus('chat_composer');
    }, 0);
  }

  // --- multi-select ---
  private enterSelect(messageId: number): void {
    ContextMenu.close();
    this.closeReactionSheet();
    this.setEmojiPanel(false);
    this.selecting = true;
    this.selectedIds = [messageId];
  }

  private exitSelect(): void {
    this.selecting = false;
    this.selectedIds = [];
  }

  private rowSelected(g: AlbumGroup): boolean {
    for (const id of g.memberIds) {
      if (this.selectedIds.indexOf(id) >= 0) {
        return true;
      }
    }
    return false;
  }

  // Toggle a whole display row (an album row selects all its members).
  private toggleSelectRow(g: AlbumGroup): void {
    if (g.head.contentType === 'system' || g.head.contentType === 'hidden') {
      return;
    }
    if (this.rowSelected(g)) {
      this.selectedIds = this.selectedIds.filter((id: number) => g.memberIds.indexOf(id) < 0);
    } else {
      this.selectedIds = [...this.selectedIds, ...g.memberIds];
    }
    if (this.selectedIds.length === 0) {
      this.exitSelect();
    }
  }

  private reconcileMessageActionTargets(list: MessageEntry[]): void {
    if (this.selecting) {
      this.selectedIds = this.selectedIds.filter((id: number): boolean =>
        list.findIndex((m: MessageEntry): boolean => m.id === id) >= 0
      );
      if (this.selectedIds.length === 0) {
        this.exitSelect();
      }
    }
    if (this.showReactionSheet && this.reactionTargetId !== 0 &&
      list.findIndex((m: MessageEntry): boolean => m.id === this.reactionTargetId) < 0) {
      this.closeReactionSheet();
    }
  }

  private copySelected(): void {
    const sorted = [...this.selectedIds].sort((a: number, b: number) => a - b);
    const parts: string[] = [];
    for (const id of sorted) {
      const m = this.findMsg(id);
      if (m !== null && m.text !== '') {
        parts.push(m.text);
      }
    }
    if (parts.length === 0) {
      promptAction.showToast({ message: '没有可复制的文本', duration: 1500 });
      return;
    }
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, parts.join('\n\n'));
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      promptAction.showToast({ message: `已复制 ${parts.length} 条消息`, duration: 1200 });
      this.exitSelect();
    }).catch((e: Object) => { console.error(`ChatPage.copySelected failed: ${JSON.stringify(e)}`); });
  }

  // "同时为对方删除"是一个开关，不是第三个按钮：做成三按钮时用户要在两个
  // 红色危险项之间辨认，容易点错。所以用带复选框的自定义弹窗。
  private deleteSelected(): void {
    const ids: number[] = [...this.selectedIds];
    if (ids.length === 0) {
      return;
    }
    this.deleteDialog = new CustomDialogController({
      builder: DeleteMessagesDialog({
        peerName: this.isGroup || this.isChannel ? '' : this.headerTitleText(),
        onConfirm: (revoke: boolean): void => { this.doDeleteMessages(ids, revoke); }
      }),
      autoCancel: true,
      customStyle: true,
      alignment: DialogAlignment.Center
    });
    this.deleteDialog.open();
  }

  private doDeleteMessages(ids: number[], revoke: boolean): void {
    const req: TdRequest = { '@type': 'deleteMessages' };
    req['chat_id'] = this.chatId;
    req['message_ids'] = ids;
    req['revoke'] = revoke;
    getTdClient().send(req).then(() => {
      this.exitSelect();
    }).catch((e: TdError) => {
      console.error(`ChatPage.deleteMessages failed: ${e.message}`);
      promptAction.showToast({ message: `删除失败：${e.message}`, duration: 2000 });
    });
  }

  private copyMessageText(messageId: number): void {
    const m = this.findMsg(messageId);
    if (m === null || m.text === '') {
      promptAction.showToast({ message: '没有可复制的文本', duration: 1500 });
      return;
    }
    this.copyPlainText(m.text, '已复制');
  }

  private copyPlainText(text: string, successMessage: string): void {
    if (text === '') {
      return;
    }
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      promptAction.showToast({ message: successMessage, duration: 1200 });
    }).catch((e: Object) => { console.error(`ChatPage.copyPlainText failed: ${JSON.stringify(e)}`); });
  }

  private copyMessageLink(messageId: number): void {
    if (this.store === null) {
      return;
    }
    this.store.messageLink(messageId, (url: string) => {
      if (url === '') {
        promptAction.showToast({ message: '无法获取链接（可能是私密聊天）', duration: 1800 });
        return;
      }
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
      pasteboard.getSystemPasteboard().setData(data).then(() => {
        promptAction.showToast({ message: '链接已复制', duration: 1200 });
      }).catch((e: Object) => { console.error(`ChatPage.copyMessageLink failed: ${JSON.stringify(e)}`); });
    });
  }

  // reactionKey：标准 emoji 原样，自定义 emoji 为 'ce:<custom_emoji_id>'。
  private toggleReaction(messageId: number, reactionKey: string, isChosen: boolean): void {
    const store: MessageStore | null = this.store;
    const key: string = `${messageId}_${reactionKey}`;
    if (store === null || this.reactionPendingKey !== '') {
      return;
    }
    ContextMenu.close();
    this.reactionPendingKey = key;
    store.setReaction(messageId, reactionKey, isChosen).then((): void => {
      if (this.reactionPendingKey === key) {
        this.reactionPendingKey = '';
      }
    }).catch((e: TdError): void => {
      if (this.reactionPendingKey === key) {
        this.reactionPendingKey = '';
      }
      console.error(`ChatPage.toggleReaction failed: ${e.message}`);
      promptAction.showToast({ message: '回应失败，请重试', duration: 1600 });
    });
  }

  // 语音转文字。Premium 功能，非会员会被服务端拒绝，这里把原始错误呈现出来
  // 而不是笼统说"失败"——用户能据此判断是要开会员还是网络问题。
  // 会话级自动翻译开关。本地先翻转让菜单立刻反映，失败再回滚——这个操作
  // 很轻，等一次往返反而显得迟钝。
  // 跳转到某一天。用 getChatMessageByDate 而不是 getChatMessageCalendar——
  // 后者明确不支持 searchMessagesFilterEmpty，只能按媒体类型分日统计，做不了
  // "跳到任意一天"。前者直接返回不晚于给定时刻的最后一条消息，正是所需。
  private pickJumpDate(): void {
    const now = new Date();
    // 会话第一条消息之前的日期没有意义，但客户端不知道那是哪天，
    // 下界给 2013（Telegram 上线年份）足够宽松。
    this.getUIContext().showDatePickerDialog({
      start: new Date('2013-01-01'),
      end: now,
      selected: now,
      onDateAccept: (value: Date): void => { this.jumpToDate(value); }
    });
  }

  private jumpToDate(day: Date): void {
    const store = this.store;
    if (store === null) { return; }
    // 取当天 23:59:59：getChatMessageByDate 返回"不晚于该时刻"的最后一条，
    // 用当天结束时刻才能落在这一天之内，用 00:00 会落到前一天。
    const end = new Date(day.getFullYear(), day.getMonth(), day.getDate(), 23, 59, 59);
    const req: TdRequest = { '@type': 'getChatMessageByDate' };
    req['chat_id'] = this.chatId;
    req['date'] = Math.floor(end.getTime() / 1000);
    getTdClient().send(req, 15000).then((message: TdObject): void => {
      const id: number = (message['id'] as number | undefined) ?? 0;
      if (id === 0) {
        promptAction.showToast({ message: '那天没有消息', duration: 1600 });
        return;
      }
      this.jumpToMessageId(id);
    }).catch((e: TdError): void => {
      // 404 是合法结果：该日期之前没有任何消息。
      const code: number = e.code !== undefined ? e.code : 0;
      promptAction.showToast({
        message: code === 404 ? '这个日期之前没有消息' : `跳转失败：${e.message}`,
        duration: 1600
      });
    });
  }

  // 跳到指定消息：已在当前页就直接滚动并高亮，否则围绕它重新拉一页。
  private jumpToMessageId(targetId: number): void {
    const gidx: number = groupIndexOf(this.groups, targetId);
    if (gidx >= 0) {
      this.scroller.scrollToIndex(gidx, false, ScrollAlign.START);
      this.flashAtIndex(gidx);
      return;
    }
    this.pendingJumpId = targetId;
    this.store?.loadAround(targetId, (found: boolean): void => {
      if (!found && this.pendingJumpId === targetId) {
        this.pendingJumpId = 0;
        promptAction.showToast({ message: '无法定位到那条消息', duration: 1500 });
      }
    });
  }

  private toggleTranslatable(): void {
    const previous: boolean = this.isTranslatable;
    const next: boolean = !previous;
    this.isTranslatable = next;
    const req: TdRequest = { '@type': 'toggleChatIsTranslatable' };
    req['chat_id'] = this.chatId;
    req['is_translatable'] = next;
    getTdClient().send(req).then((): void => {
      promptAction.showToast({
        message: next ? '已开启自动翻译' : '已关闭自动翻译', duration: 1500
      });
    }).catch((e: TdError): void => {
      this.isTranslatable = previous;
      console.error(`ChatPage.toggleTranslatable failed: ${e.message}`);
      promptAction.showToast({ message: `设置失败：${e.message}`, duration: 1800 });
    });
  }

  private recognizeSpeech(messageId: number): void {
    this.store?.recognizeSpeech(messageId).catch((e: TdError): void => {
      const message: string = e.message !== undefined ? e.message : '';
      promptAction.showToast({
        message: message.indexOf('PREMIUM') >= 0 || message.indexOf('premium') >= 0
          ? '转文字是 Telegram Premium 功能' : `转文字失败：${message}`,
        duration: 2200
      });
    });
  }

  private openReactionSheet(messageId: number): void {
    ContextMenu.close();
    if (this.findMsg(messageId) === null) {
      return;
    }
    this.reactionTargetId = messageId;
    this.sheetReactions = REACTION_EMOJIS;
    this.sheetCustomEmojis = [];
    this.sheetAllowCustomEmoji = false;
    this.showReactionSheet = true;
    this.loadAvailableReactions(messageId);
  }

  // Channels/groups can restrict which reactions are allowed; ask TDLib for
  // the real list so the sheet never offers an emoji the server would reject.
  private loadAvailableReactions(messageId: number): void {
    const req: TdRequest = { '@type': 'getMessageAvailableReactions' };
    req['chat_id'] = this.chatId;
    req['message_id'] = messageId;
    req['row_size'] = 8;
    getTdClient().send(req, 10000).then((result: TdObject): void => {
      if (this.reactionTargetId !== messageId || !this.showReactionSheet) { return; }
      const available: AvailableReactionSet = parseAvailableReactions(result);
      if (available.emojis.length > 0) { this.sheetReactions = available.emojis; }
      this.sheetAllowCustomEmoji = available.allowCustomEmoji;
      if (!available.allowCustomEmoji || available.customEmojiIds.length === 0) { return; }
      this.sheetCustomEmojis = available.customEmojiIds.map((id: string): CustomEmojiOption => {
        return { id, path: '' };
      });
      resolveCustomEmojiThumbs(available.customEmojiIds, (id: string, path: string): void => {
        if (this.reactionTargetId !== messageId || !this.showReactionSheet) { return; }
        this.applyCustomEmojiThumb(id, path);
      });
    }).catch((e: TdError): void => {
      console.error(`ChatPage.availableReactions failed: ${e.message}`);
    });
  }

  // 逐个替换而不是整批重建：先到的位图立刻可见，其余仍显示占位。
  private applyCustomEmojiThumb(customEmojiId: string, path: string): void {
    this.sheetCustomEmojis = this.sheetCustomEmojis.map(
      (option: CustomEmojiOption): CustomEmojiOption => {
        return option.id === customEmojiId ? { id: option.id, path } : option;
      });
  }

  // 从长按菜单里直接调全局 promptAction.showDialog 会静默挂死：菜单是独立
  // 子窗口，收起过程中弹出的对话框没有可依附的 UI 上下文，Promise 既不
  // resolve 也不 reject（见 ChatRow.showConfirm 的同类修复）。
  private showMenuConfirm(
    options: promptAction.ShowDialogOptions, what: string,
    onConfirm: (index: number) => void
  ): void {
    const prompt = this.getUIContext().getPromptAction();
    setTimeout((): void => {
      prompt.showDialog(options).then((res: promptAction.ShowDialogSuccessResponse): void => {
        onConfirm(res.index);
      }).catch((e: Object): void => {
        console.info(`ChatPage.${what} dialog dismissed: ${JSON.stringify(e)}`);
      });
    }, MENU_DISMISS_MS);
  }

  private stopPoll(messageId: number): void {
    this.showMenuConfirm({
      title: '结束投票',
      message: '结束后不能再投票，结果将保留。',
      buttons: [
        { text: '取消', color: '#8E8E93' },
        { text: '结束', color: '#E5484D' }
      ]
    }, 'stopPoll', (index: number): void => {
      if (index !== 1) { return; }
      this.store?.stopPollAsync(messageId).then((): void => {
        promptAction.showToast({ message: '投票已结束', duration: 1500 });
      }).catch((e: TdError): void => {
        console.error(`ChatPage.stopPoll failed: ${e.message}`);
        promptAction.showToast({ message: '结束投票失败', duration: 1600 });
      });
    });
  }

  // Public polls only: list who picked each option.
  private showPollVoters(messageId: number): void {
    const msg = this.findMsg(messageId);
    const store = this.store;
    if (msg === null || store === null) { return; }
    const lines: string[] = [];
    const tasks: Promise<void>[] = [];
    msg.pollOptions.forEach((option: PollOptionInfo, index: number): void => {
      tasks.push(store.pollVotersAsync(messageId, index).then((result: TdObject): void => {
        const senders = (result['senders'] as TdObject[] | undefined) ?? [];
        const names: string[] = [];
        for (const sender of senders) {
          if (sender['@type'] === 'messageSenderUser') {
            const uid = (sender['user_id'] as number | undefined) ?? 0;
            const name = getUserStore().displayName(uid);
            if (name === '') { getUserStore().ensure(uid); }
            names.push(name !== '' ? name : `用户 ${uid}`);
          }
        }
        if (names.length > 0) {
          lines.push(`${option.text}：${names.join('、')}`);
        }
      }).catch((): void => {}));
    });
    Promise.all(tasks).then((): void => {
      promptAction.showDialog({
        title: '投票人',
        message: lines.length > 0 ? lines.join('\n\n') : '暂无公开的投票记录',
        buttons: [{ text: '关闭', color: '#3390EC' }]
      }).catch((): void => {});
    }).catch((): void => {});
  }

  private setDefaultReaction(emoji: string): void {
    const rt: TdObject = { '@type': 'reactionTypeEmoji' };
    rt['emoji'] = emoji;
    const req: TdRequest = { '@type': 'setDefaultReactionType' };
    req['reaction_type'] = rt;
    getTdClient().send(req).then((): void => {
      promptAction.showToast({ message: `已将 ${emoji} 设为默认回应`, duration: 1600 });
    }).catch((e: TdError): void => {
      console.error(`ChatPage.setDefaultReaction failed: ${e.message}`);
      promptAction.showToast({ message: '设置默认回应失败', duration: 1600 });
    });
  }

  // Chat-level auto-delete timer (阅后即焚).
  private chooseAutoDelete(): void {
    const labels: string[] = ['关闭', '1 天', '1 周', '1 个月'];
    const seconds: number[] = [0, 86400, 604800, 2678400];
    promptAction.showActionMenu({
      title: '消息自动删除',
      buttons: labels.map((text: string): promptAction.Button =>
        ({ text, color: '#3390EC' } as promptAction.Button)) as
        [promptAction.Button, promptAction.Button?, promptAction.Button?,
          promptAction.Button?, promptAction.Button?, promptAction.Button?]
    }).then((chosen): void => {
      const value = seconds[chosen.index];
      if (value === undefined) { return; }
      this.store?.setAutoDeleteAsync(value).then((): void => {
        promptAction.showToast({
          message: value === 0 ? '已关闭自动删除' : `新消息将在${labels[chosen.index]}后删除`,
          duration: 1800
        });
      }).catch((e: TdError): void => {
        console.error(`ChatPage.autoDelete failed: ${e.message}`);
        promptAction.showToast({ message: '设置失败，可能没有权限', duration: 1700 });
      });
    }).catch((): void => {});
  }

  // Long-press the send button: schedule or send silently.
  private showSendOptions(): void {
    if (this.draft.trim() === '' || this.editingId !== 0) { return; }
    const labels: string[] = ['静音发送', '1 小时后发送', '明天早上 9 点发送'];
    promptAction.showActionMenu({
      title: '发送选项',
      buttons: labels.map((text: string): promptAction.Button =>
        ({ text, color: '#3390EC' } as promptAction.Button)) as
        [promptAction.Button, promptAction.Button?, promptAction.Button?,
          promptAction.Button?, promptAction.Button?, promptAction.Button?]
    }).then((chosen): void => {
      const nowSeconds = Math.floor(Date.now() / 1000);
      let sendDate = 0;
      let silent = false;
      if (chosen.index === 0) {
        silent = true;
      } else if (chosen.index === 1) {
        sendDate = nowSeconds + 3600;
      } else if (chosen.index === 2) {
        const tomorrow = new Date();
        tomorrow.setDate(tomorrow.getDate() + 1);
        tomorrow.setHours(9, 0, 0, 0);
        sendDate = Math.floor(tomorrow.getTime() / 1000);
      } else {
        return;
      }
      const text = this.draft.trim();
      const replyId = this.replyToId;
      this.store?.sendScheduledAsync(text, replyId, sendDate, silent).then((): void => {
        this.draft = '';
        this.clearReply();
        promptAction.showToast({
          message: sendDate > 0 ? '已安排定时发送' : '已静音发送', duration: 1600
        });
      }).catch((e: TdError): void => {
        console.error(`ChatPage.sendScheduled failed: ${e.message}`);
        promptAction.showToast({ message: '发送失败', duration: 1600 });
      });
    }).catch((): void => {});
  }

  private togglePinMessage(messageId: number, unpin: boolean): void {
    const store = this.store;
    if (store === null) { return; }
    const task: Promise<void> = unpin
      ? store.unpinAsync(messageId) : store.pinAsync(messageId);
    task.then((): void => {
      promptAction.showToast({ message: unpin ? '已取消置顶' : '已置顶', duration: 1400 });
    }).catch((e: TdError): void => {
      console.error(`ChatPage.togglePin failed: ${e.message}`);
      promptAction.showToast({
        message: e.message.indexOf('not enough rights') >= 0 || e.message.indexOf('ADMIN') >= 0
          ? '没有置顶权限' : (unpin ? '取消置顶失败' : '置顶失败'),
        duration: 1700
      });
    });
  }

  // Live "typing…" from peers (updateChatAction). Entries expire after 6s —
  // TDLib sends chatActionCancel, but a dropped cancel must not stick forever.
  private onChatAction(update: TdObject): void {
    if (((update['chat_id'] as number | undefined) ?? 0) !== this.chatId) { return; }
    const sender = update['sender_id'] as TdObject | undefined;
    if (sender === undefined || sender['@type'] !== 'messageSenderUser') { return; }
    const uid = (sender['user_id'] as number | undefined) ?? 0;
    if (uid <= 0) { return; }
    const action = update['action'] as TdObject | undefined;
    const actionType = action !== undefined ? ((action['@type'] as string | undefined) ?? '') : '';
    if (actionType === 'chatActionCancel') {
      this.typingSenders.delete(uid);
    } else {
      this.typingSenders.set(uid, Date.now() + 6000);
      getUserStore().ensure(uid);
    }
    this.rebuildTypingLabel();
    if (this.typingTimer === -1 && this.typingSenders.size > 0) {
      this.typingTimer = setInterval((): void => {
        const now = Date.now();
        let changed = false;
        for (const key of Array.from(this.typingSenders.keys())) {
          if ((this.typingSenders.get(key) ?? 0) < now) {
            this.typingSenders.delete(key);
            changed = true;
          }
        }
        if (changed) { this.rebuildTypingLabel(); }
        if (this.typingSenders.size === 0 && this.typingTimer !== -1) {
          clearInterval(this.typingTimer);
          this.typingTimer = -1;
        }
      }, 1500);
    }
  }

  private rebuildTypingLabel(): void {
    const ids = Array.from(this.typingSenders.keys());
    if (ids.length === 0) {
      this.typingLabel = '';
      return;
    }
    if (this.headerKind === 'private' || this.headerKind === 'secret') {
      this.typingLabel = '正在输入…';
      return;
    }
    if (ids.length > 1) {
      this.typingLabel = `${ids.length} 人正在输入…`;
      return;
    }
    const name = getUserStore().displayName(ids[0]);
    this.typingLabel = `${name !== '' ? name.split(' ')[0] : '有人'}正在输入…`;
  }

  // Pick up the draft synced from other devices (chat.draft_message). Only
  // fills an empty composer — never overwrites what the user is typing.
  private restoreServerDraft(): void {
    const req: TdRequest = { '@type': 'getChat' };
    req['chat_id'] = this.chatId;
    getTdClient().send(req).then((chat: TdObject): void => {
      if (this.draft !== '') { return; }
      const draft = chat['draft_message'] as TdObject | undefined;
      const content = draft !== undefined
        ? (draft['input_message_text'] as TdObject | undefined) : undefined;
      const ft = content !== undefined ? (content['text'] as TdObject | undefined) : undefined;
      const text = ft !== undefined ? ((ft['text'] as string | undefined) ?? '') : '';
      if (text !== '') { this.draft = text; }
    }).catch((): void => {});
  }

  // Translate a message's text/caption into the system language and show the
  // result in place (dialog). TDLib needs an explicit ISO 639-1 target code.
  private translateMessage(messageId: number): void {
    let target = 'zh';
    try {
      const lang = i18n.System.getSystemLanguage();
      if (lang.length >= 2) { target = lang.split('-')[0]; }
    } catch (_e) { /* keep zh */ }
    const req: TdRequest = { '@type': 'translateMessageText' };
    req['chat_id'] = this.chatId;
    req['message_id'] = messageId;
    req['to_language_code'] = target;
    getTdClient().send(req, 20000).then((result: TdObject): void => {
      const text = (result['text'] as string | undefined) ?? '';
      if (text === '') {
        promptAction.showToast({ message: '没有可翻译的内容', duration: 1600 });
        return;
      }
      promptAction.showDialog({
        title: '翻译',
        message: text,
        buttons: [
          { text: '复制', color: '#3390EC' },
          { text: '关闭', color: '#8E8E93' }
        ]
      }).then((chosen): void => {
        if (chosen.index === 0) {
          const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
          pasteboard.getSystemPasteboard().setData(data).then((): void => {
            promptAction.showToast({ message: '已复制', duration: 1300 });
          }).catch((): void => {});
        }
      }).catch((): void => {});
    }).catch((e: TdError): void => {
      console.error(`ChatPage.translate failed: ${e.message}`);
      promptAction.showToast({ message: '翻译失败，请稍后重试', duration: 1700 });
    });
  }

  // Long-press on a reaction chip: who reacted with it.
  private showReactors(messageId: number, reactionKey: string): void {
    const req: TdRequest = { '@type': 'getMessageAddedReactions' };
    req['chat_id'] = this.chatId;
    req['message_id'] = messageId;
    req['reaction_type'] = reactionTypeOf(reactionKey);
    req['offset'] = '';
    req['limit'] = 50;
    getTdClient().send(req, 10000).then((result: TdObject): void => {
      const rows = (result['reactions'] as TdObject[] | undefined) ?? [];
      const total = (result['total_count'] as number | undefined) ?? rows.length;
      const names: string[] = [];
      for (const row of rows) {
        const sender = row['sender_id'] as TdObject | undefined;
        if (sender === undefined) { continue; }
        if (sender['@type'] === 'messageSenderUser') {
          const uid = (sender['user_id'] as number | undefined) ?? 0;
          const name = getUserStore().displayName(uid);
          if (name === '') { getUserStore().ensure(uid); }
          names.push(name !== '' ? name : `用户 ${uid}`);
        } else {
          const cid = (sender['chat_id'] as number | undefined) ?? 0;
          const entry = getChatStore().entryOf(cid);
          names.push(entry !== undefined ? entry.title : '匿名身份');
        }
      }
      promptAction.showDialog({
        title: `${reactionDisplayLabel(reactionKey)} 共 ${total} 人`,
        message: names.length > 0 ? names.join('\n') : '暂无详情',
        buttons: [{ text: '关闭', color: '#3390EC' }]
      }).catch((): void => {});
    }).catch((e: TdError): void => {
      console.error(`ChatPage.showReactors failed: ${e.message}`);
      promptAction.showToast({ message: '无法获取回应详情', duration: 1600 });
    });
  }

  private closeReactionSheet(): void {
    this.showReactionSheet = false;
    this.reactionTargetId = 0;
    this.sheetCustomEmojis = [];
    this.sheetAllowCustomEmoji = false;
  }

  private targetReactionChosen(reactionKey: string): boolean {
    const m: MessageEntry | null = this.findMsg(this.reactionTargetId);
    if (m === null) {
      return false;
    }
    for (const reaction of m.reactions) {
      if (reactionKeyFrom(reaction.emoji, reaction.customEmojiId) === reactionKey) {
        return reaction.isChosen;
      }
    }
    return false;
  }

  // The full sheet mirrors the quick row: tapping an already-selected emoji
  // removes it instead of issuing a redundant add request.
  private pickReaction(reactionKey: string): void {
    const targetId: number = this.reactionTargetId;
    if (targetId === 0 || this.reactionPendingKey !== '') {
      return;
    }
    const chosen: boolean = this.targetReactionChosen(reactionKey);
    this.closeReactionSheet();
    this.toggleReaction(targetId, reactionKey, chosen);
  }

  private updateForwardChats(list: ChatEntry[]): void {
    this.forwardChats = list.filter((chat: ChatEntry): boolean => chat.id > 0);
    if (this.forwardChats.length > 0) {
      this.forwardLoadState = 'ready';
    }
  }

  private forwardableMessageIds(ids: number[]): number[] {
    const result: number[] = [];
    for (const id of ids) {
      const m: MessageEntry | null = this.findMsg(id);
      if (m !== null && m.contentType !== 'system' && m.contentType !== 'hidden' &&
        result.indexOf(id) < 0) {
        result.push(id);
      }
    }
    return result;
  }

  private openForwardPicker(ids: number[]): void {
    const validIds: number[] = this.forwardableMessageIds(ids);
    ContextMenu.close();
    if (validIds.length === 0) {
      promptAction.showToast({ message: '这条消息无法转发', duration: 1500 });
      return;
    }
    this.closeReactionSheet();
    this.setEmojiPanel(false);
    this.forwardMessageIds = validIds;
    this.forwardQuery = '';
    this.forwardSendingChatId = 0;
    this.updateForwardChats(getChatStore().getChats('main'));
    this.forwardLoadState = this.forwardChats.length > 0 ? 'ready' : 'loading';
    this.showForwardSheet = true;
    const seq: number = ++this.forwardPickerSeq;
    getChatStore().ensureLoaded('main').then((success: boolean): void => {
      if (seq !== this.forwardPickerSeq || !this.showForwardSheet) {
        return;
      }
      this.updateForwardChats(getChatStore().getChats('main'));
      if (!success && this.forwardChats.length === 0) {
        this.forwardLoadState = 'error';
      } else {
        this.forwardLoadState = 'ready';
      }
    });
  }

  private retryForwardChats(): void {
    if (!this.showForwardSheet || this.forwardLoadState === 'loading') {
      return;
    }
    this.forwardLoadState = 'loading';
    const seq: number = ++this.forwardPickerSeq;
    getChatStore().loadMore('main').then((): void => {
      if (seq !== this.forwardPickerSeq || !this.showForwardSheet) {
        return;
      }
      this.updateForwardChats(getChatStore().getChats('main'));
      this.forwardLoadState = this.forwardChats.length > 0 ? 'ready' : 'error';
    });
  }

  private closeForwardSheet(): void {
    this.forwardPickerSeq++;
    this.showForwardSheet = false;
    this.forwardQuery = '';
    this.forwardSendingChatId = 0;
    this.forwardMessageIds = [];
  }

  private filteredForwardChats(): ChatEntry[] {
    const q: string = this.forwardQuery.trim().toLowerCase();
    if (q === '') {
      return this.forwardChats;
    }
    return this.forwardChats.filter((chat: ChatEntry): boolean =>
      chat.title.toLowerCase().indexOf(q) >= 0
    );
  }

  private forwardToChat(chat: ChatEntry): void {
    if (this.forwardSendingChatId !== 0 || this.forwardMessageIds.length === 0) {
      return;
    }
    const ids: number[] = [...this.forwardMessageIds];
    const sourceChatId: number = this.chatId;
    const seq: number = this.forwardPickerSeq;
    this.forwardSendingChatId = chat.id;
    const req: TdRequest = { '@type': 'forwardMessages' };
    req['chat_id'] = chat.id;
    req['message_thread_id'] = chat.id === sourceChatId ? this.threadRootId : 0;
    req['from_chat_id'] = sourceChatId;
    req['message_ids'] = ids;
    req['send_copy'] = false;
    req['remove_caption'] = false;
    getTdClient().send(req).then((): void => {
      if (seq !== this.forwardPickerSeq || !this.showForwardSheet) {
        return;
      }
      const count: number = ids.length;
      this.closeForwardSheet();
      if (this.selecting) {
        this.exitSelect();
      }
      promptAction.showToast({
        message: count > 1 ? `已转发 ${count} 条消息` : `已转发到 ${chat.title}`,
        duration: 1500
      });
    }).catch((e: TdError): void => {
      if (seq !== this.forwardPickerSeq || !this.showForwardSheet) {
        return;
      }
      this.forwardSendingChatId = 0;
      console.error(`ChatPage.forwardMessages failed: ${e.message}`);
      promptAction.showToast({ message: '转发失败，请选择其他会话或稍后重试', duration: 2000 });
    });
  }

  @Styles
  headerActionNormalStyle() {
    .backgroundColor($r('app.color.surface'))
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  headerActionPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.72)
    .scale({ x: 0.9, y: 0.9 })
  }

  @Styles
  headerIdentityNormalStyle() {
    .backgroundColor($r('app.color.surface'))
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  headerIdentityPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.78)
    .scale({ x: 0.985, y: 0.96 })
  }

  @Styles
  headerMenuRowNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
  }

  @Styles
  headerMenuRowPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.68)
  }

  @Styles
  topCardRowNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  topCardRowPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.82)
    .scale({ x: 0.992, y: 0.97 })
  }

  @Styles
  timelineStatusNormalStyle() {
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  timelineStatusPressedStyle() {
    .opacity(0.76)
    .scale({ x: 0.97, y: 0.97 })
  }

  @Styles
  liveEntryNormalStyle() {
    .backgroundColor('#FF405C')
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  liveEntryPressedStyle() {
    .backgroundColor('#E93652')
    .opacity(0.82)
    .scale({ x: 0.94, y: 0.94 })
  }

  @Styles
  scrollFabNormalStyle() {
    .backgroundColor($r('app.color.surface'))
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  scrollFabPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.84)
    .scale({ x: 0.92, y: 0.92 })
  }

  @Styles
  composerIconNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  composerIconPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.72)
    .scale({ x: 0.9, y: 0.9 })
  }

  @Styles
  composerPrimaryNormalStyle() {
    .backgroundColor(COLOR_PRIMARY)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  composerPrimaryPressedStyle() {
    .backgroundColor('#287BC8')
    .opacity(0.84)
    .scale({ x: 0.92, y: 0.92 })
  }

  @Styles
  suggestionRowNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  suggestionRowPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.76)
    .scale({ x: 0.985, y: 0.96 })
  }

  @Styles
  botKeyboardButtonNormalStyle() {
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  botKeyboardButtonPressedStyle() {
    .opacity(0.72)
    .scale({ x: 0.96, y: 0.9 })
  }

  private closeChatPage(): void {
    if (this.pageClosing) {
      return;
    }
    this.pageClosing = true;
    this.headerMenuShow = false;
    if (this.headerNavigationTimer !== -1) {
      clearTimeout(this.headerNavigationTimer);
    }
    this.headerNavigationTimer = setTimeout((): void => {
      this.headerNavigationTimer = -1;
      this.pageClosing = false;
    }, CHAT_HEADER_NAV_GUARD_MS);
    router.back();
  }

  @Builder
  circleButton(symbol: string, onTap: () => void) {
    Row() {
      SymbolGlyph($r(symbol)).fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
    }
    .width(CHAT_HEADER_ACTION_SIZE)
    .height(CHAT_HEADER_ACTION_SIZE)
    .borderRadius(CHAT_HEADER_RADIUS)
    .justifyContent(FlexAlign.Center)
    .shadow({ radius: 4, color: '#12000000', offsetX: 0, offsetY: 1 })
    .stateStyles({
      normal: this.headerActionNormalStyle,
      pressed: this.headerActionPressedStyle
    })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120),
      curve: Curve.EaseOut
    })
    .onClick(onTap);
  }

  // Multi-select header: ✕ / count / copy / delete.
  @Builder
  selectionHeader() {
    Row({ space: 8 }) {
      this.circleButton('sys.symbol.xmark', () => { this.exitSelect(); });
      Text(`已选择 ${this.selectedIds.length}`)
        .fontSize(16).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1).margin({ left: 6 });
      this.circleButton('sys.symbol.arrowshape_turn_up_right', () => {
        this.openForwardPicker(this.selectedIds);
      });
      this.circleButton('sys.symbol.plus_square_on_square', () => { this.copySelected(); });
      Row() {
        SymbolGlyph($r('sys.symbol.trash')).fontSize(22).fontColor(['#FF3B30']);
      }
      .width(CHAT_HEADER_ACTION_SIZE)
      .height(CHAT_HEADER_ACTION_SIZE)
      .borderRadius(CHAT_HEADER_RADIUS)
      .justifyContent(FlexAlign.Center)
      .shadow({ radius: 4, color: '#12000000', offsetX: 0, offsetY: 1 })
      .stateStyles({
        normal: this.headerActionNormalStyle,
        pressed: this.headerActionPressedStyle
      })
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120),
        curve: Curve.EaseOut
      })
      .onClick(() => { this.deleteSelected(); });
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: this.topSafe + 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: -5 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }

  // Search owns the complete top bar. Keeping the regular avatar/title beside
  // the field squeezed group/channel queries into a narrow trailing slot and
  // made the mode look like an accessory instead of navigation state.
  @Builder
  searchHeader() {
    Row({ space: 4 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
      }
        .width(40).height(40)
        .borderRadius(20)
        .justifyContent(FlexAlign.Center)
        .stateStyles({
          normal: this.headerMenuRowNormalStyle,
          pressed: this.headerMenuRowPressedStyle
        })
        .animation({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
          curve: Curve.EaseOut
        })
        .onClick((): void => { this.exitSearch(); })
        .accessibilityText('返回聊天');
      TextInput({ text: this.searchQuery, placeholder: '搜索消息' })
        .layoutWeight(1).height(40).fontSize(16)
        .backgroundColor(Color.Transparent).padding(0).borderRadius(0)
        .placeholderColor(COLOR_TEXT_SECONDARY)
        .caretColor(COLOR_PRIMARY)
        .enterKeyType(EnterKeyType.Search)
        .defaultFocus(true)
        .onChange((v: string): void => { this.updateSearchQuery(v); })
        .onSubmit((): void => { this.runSearch(0, 0); });
      if (this.searchQuery !== '') {
        Row() {
          SymbolGlyph($r('sys.symbol.xmark_circle'))
            .fontSize(19).fontColor([COLOR_TEXT_SECONDARY]);
        }
        .width(34).height(34)
        .borderRadius(17)
        .justifyContent(FlexAlign.Center)
        .stateStyles({
          normal: this.headerMenuRowNormalStyle,
          pressed: this.headerMenuRowPressedStyle
        })
        .animation({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
          curve: Curve.EaseOut
        })
        .onClick((): void => { this.updateSearchQuery(''); })
        .accessibilityText('清空搜索');
      }
    }
    .width('calc(100% - 24vp)').height(46)
    .padding({ left: 3, right: 6 })
    .margin({ left: 12, right: 12, top: this.topSafe + 8, bottom: 8 })
    .backgroundColor($r('app.color.surface'))
    .border({ width: 0.5, color: $r('app.color.divider') })
    .borderRadius(23)
    .shadow({ radius: 5, color: '#16000000', offsetX: 0, offsetY: 1 })
    .alignItems(VerticalAlign.Center)
    .opacity(this.headerVisible ? 1 : 0)
    .translate({ y: this.headerVisible ? 0 : -6 })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 220),
      curve: Curve.EaseOut
    })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: -5 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      this.circleButton('sys.symbol.chevron_left', () => { this.closeChatPage(); });
      Row({ space: 10 }) {
        AvatarView({
          avatarPath: this.avatarPath,
          initials: this.initials,
          colorSeed: this.chatId,
          avatarSize: 38
        });
        Column() {
          Row() {
            Text(this.headerTitleText())
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLOR_TEXT_PRIMARY)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .flexShrink(1);
            if (this.headerState === 'loading' || this.headerProfileOpening) {
              LoadingProgress()
                .width(15)
                .height(15)
                .color(COLOR_PRIMARY)
                .margin({ left: 5 });
            } else if (this.headerEmojiPath !== '') {
              if (this.headerEmojiFormat === 'tgs') {
                TgsStickerView({
                  tgsPath: this.headerEmojiPath,
                  boxWidth: 18,
                  boxHeight: 18,
                  powerCategory: 'emojiStatus'
                })
                  .margin({ left: 4 });
              } else if (this.headerEmojiFormat === 'webm') {
                WebmStickerView({
                  webmPath: this.headerEmojiPath,
                  boxWidth: 18,
                  boxHeight: 18,
                  powerCategory: 'emojiStatus'
                })
                  .margin({ left: 4 });
              } else {
                Image(`file://${this.headerEmojiPath}`)
                  .width(18)
                  .height(18)
                  .objectFit(ImageFit.Contain)
                  .margin({ left: 4 });
              }
            }
            if (this.headerMuteUpdating) {
              LoadingProgress()
                .width(14)
                .height(14)
                .color(COLOR_TEXT_SECONDARY)
                .margin({ left: 4 });
            } else if (this.isMuted) {
              SymbolGlyph($r('sys.symbol.bell_slash'))
                .fontSize(14)
                .fontColor([COLOR_TEXT_SECONDARY])
                .margin({ left: 4 });
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center);
          Text(this.headerSubtitleText())
            .fontSize(12)
            .fontColor(this.headerState === 'error' ? '#E64646' : COLOR_TEXT_SECONDARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 1 });
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1);
      }
      .layoutWeight(1)
      .constraintSize({ minHeight: CHAT_HEADER_ACTION_SIZE })
      .padding({ left: 7, right: 12, top: 4, bottom: 4 })
      .borderRadius(CHAT_HEADER_RADIUS)
      .shadow({ radius: 4, color: '#12000000', offsetX: 0, offsetY: 1 })
      .stateStyles({
        normal: this.headerIdentityNormalStyle,
        pressed: this.headerIdentityPressedStyle
      })
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 140),
        curve: Curve.EaseOut
      })
      .accessibilityText(`${this.headerTitleText()}，${this.headerSubtitleText()}，查看资料`)
      .onClick((): void => {
        if (this.headerState === 'error') {
          this.resolveHeaderIdentity();
        } else {
          this.openProfile();
        }
      });
      Row() {
        // 菜单展开时汉堡变叉。两个图标叠着做交叉淡入淡出 + 反向旋转，比直接
        // 替换更像"同一个东西转过去了"。SVG 是位图路径、没法真正形变，这是
        // 视觉上最接近的做法。
        //
        // 系统符号库里没有汉堡线条（list_bullet 带项目符号，不是一回事），
        // 所以横线用自带的 SVG；fillColor 能染色，深浅色主题下跟其它图标一致。
        Stack() {
          Image($r('app.media.ic_header_menu'))
            .width(18).height(18)
            .fillColor(COLOR_TEXT_PRIMARY)
            .draggable(false)
            .opacity(this.headerMenuShow ? 0 : 1)
            .rotate({ angle: this.headerMenuShow ? 90 : 0 })
            // animation 必须挂在**属性发生变化的那个节点**上。挂在外层 Stack
            // 上不会生效——隐式动画只作用于同一节点自身的属性变化。
            .animation({
              duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
              curve: Curve.EaseInOut
            });
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(19).fontColor([COLOR_TEXT_PRIMARY])
            .opacity(this.headerMenuShow ? 1 : 0)
            .rotate({ angle: this.headerMenuShow ? 0 : -90 })
            .animation({
              duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
              curve: Curve.EaseInOut
            });
        }
        .width(CHAT_HEADER_ACTION_SIZE).height(CHAT_HEADER_ACTION_SIZE);
      }
      .width(CHAT_HEADER_ACTION_SIZE)
      .height(CHAT_HEADER_ACTION_SIZE)
      .borderRadius(CHAT_HEADER_RADIUS)
      .justifyContent(FlexAlign.Center)
      .shadow({ radius: 4, color: '#12000000', offsetX: 0, offsetY: 1 })
      .stateStyles({
        normal: this.headerActionNormalStyle,
        pressed: this.headerActionPressedStyle
      })
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120),
        curve: Curve.EaseOut
      })
      .bindMenu(this.headerMenuShow, this.headerMenu(), {
        onDisappear: (): void => { this.headerMenuShow = false; }
      })
      .enabled(!this.pageClosing && this.chatId !== 0)
      .accessibilityText('更多聊天操作')
      .onClick((): void => {
        if (!this.headerMenuShow) {
          this.headerMenuShow = true;
        }
      });
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: this.topSafe + 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .opacity(this.headerVisible ? 1 : 0)
    .translate({ y: this.headerVisible ? 0 : -6 })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 220),
      curve: Curve.EaseOut
    })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: -5 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }

  // Suggestion panel above the input bar: group members for a trailing '@',
  // bot commands for a leading '/'.
  @Builder
  suggestionPanel() {
    Column() {
      if (this.commandPanelActive()) {
        Row({ space: 7 }) {
          Text('/').fontSize(18).fontWeight(FontWeight.Bold).fontColor(COLOR_PRIMARY);
          Text('Bot 命令').fontSize(13).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
          Blank().layoutWeight(1);
          if (this.commandLoadState === 'ready' && this.allCommands.length > 0) {
            Text(`${this.allCommands.length}`)
              .fontSize(11).fontColor(COLOR_TEXT_SECONDARY)
              .padding({ left: 7, right: 7, top: 2, bottom: 2 })
              .backgroundColor($r('app.color.surface_alt')).borderRadius(9);
          }
        }
        .width('100%').height(34).padding({ left: 14, right: 14 })
        .border({ width: { bottom: 0.7 }, color: $r('app.color.divider') });
        if (this.commandLoadState === 'loading' || this.commandLoadState === 'idle') {
          Row({ space: 9 }) {
            LoadingProgress().width(18).height(18).color(COLOR_PRIMARY);
            Text('正在加载命令').fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          }
          .width('100%').height(72).justifyContent(FlexAlign.Center);
        } else if (this.commandLoadState === 'error') {
          Column({ space: 7 }) {
            Text(this.commandLoadError !== '' ? this.commandLoadError : '命令加载失败')
              .fontSize(13).fontColor(COLOR_TEXT_PRIMARY);
            Text('重新加载')
              .fontSize(13).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium)
              .padding({ left: 14, right: 14, top: 6, bottom: 6 })
              .backgroundColor($r('app.color.selected_pill')).borderRadius(14)
              .onClick(() => { this.ensureCommandsLoaded(true); });
          }
          .width('100%').height(86).justifyContent(FlexAlign.Center);
        } else if (this.commandItems.length === 0) {
          Column({ space: 5 }) {
            Text(this.allCommands.length === 0 ? '没有可用的 Bot 命令' : '没有匹配的命令')
              .fontSize(13).fontColor(COLOR_TEXT_PRIMARY);
            Text(this.allCommands.length === 0 ? '这个聊天暂未提供命令' : '继续输入或换个关键词')
              .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
          }
          .width('100%').height(82).justifyContent(FlexAlign.Center);
        } else {
          List() {
            ForEach(this.commandItems, (it: CommandItem) => {
              ListItem() {
                Row({ space: 10 }) {
                  Row() {
                    Text('/').fontSize(18).fontWeight(FontWeight.Bold).fontColor(COLOR_PRIMARY);
                  }
                  .width(32).height(32).borderRadius(10)
                  .justifyContent(FlexAlign.Center)
                  .backgroundColor($r('app.color.selected_pill'));
                  Column({ space: 2 }) {
                    Text(this.commandText(it))
                      .fontSize(14).fontColor(COLOR_TEXT_PRIMARY).fontWeight(FontWeight.Medium)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                    if (it.description !== '') {
                      Text(it.description).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                    }
                  }
                  .alignItems(HorizontalAlign.Start).layoutWeight(1);
                  SymbolGlyph($r('sys.symbol.paperplane'))
                    .fontSize(14).fontColor([COLOR_TEXT_SECONDARY]);
                }
                .width('100%').padding({ left: 12, right: 12, top: 7, bottom: 7 })
                .alignItems(VerticalAlign.Center)
                .stateStyles({
                  normal: this.suggestionRowNormalStyle,
                  pressed: this.suggestionRowPressedStyle
                })
                .animation({
                  duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
                  curve: Curve.EaseOut
                })
                .onClick(() => { this.pickCommand(it); });
              }
            }, (it: CommandItem) => `c_${it.command}_${it.botUserId}_${it.botUsername}`);
          }
          .width('100%').constraintSize({ maxHeight: 206 })
          .divider({ strokeWidth: 0.7, color: $r('app.color.divider'), startMargin: 54, endMargin: 12 });
        }
      } else {
        List() {
          ForEach(this.mentionItems, (it: MentionItem) => {
            ListItem() {
              Row({ space: 10 }) {
                AvatarView({ avatarPath: '', initials: it.name.substring(0, 1).toUpperCase(),
                  colorSeed: it.userId, avatarSize: 32 });
                Text(it.name).fontSize(15).fontColor(COLOR_TEXT_PRIMARY).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis });
                if (it.username !== '') {
                  Text(`@${it.username}`).fontSize(13).fontColor(COLOR_TEXT_SECONDARY).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis });
                }
              }
              .width('100%').padding({ left: 12, right: 12, top: 7, bottom: 7 })
              .alignItems(VerticalAlign.Center)
              .stateStyles({
                normal: this.suggestionRowNormalStyle,
                pressed: this.suggestionRowPressedStyle
              })
              .animation({
                duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
                curve: Curve.EaseOut
              })
              .onClick(() => { this.pickMention(it); });
            }
          }, (it: MentionItem) => `m${it.userId}`);
        }
        .width('100%').constraintSize({ maxHeight: 240 })
        .divider({ strokeWidth: 0.7, color: $r('app.color.divider'), startMargin: 54, endMargin: 12 });
      }
    }
    .width('calc(100% - 28vp)')
    .backgroundColor($r('app.color.surface'))
    .borderRadius(16).clip(true)
    .shadow({ radius: 8, color: '#1A000000', offsetX: 0, offsetY: 2 })
    .margin({ left: 14, right: 14, bottom: 2 })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: 8 }))
      .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180), curve: Curve.EaseOut }));
  }

  private startEdit(messageId: number): void {
    const msg = this.store?.getMessages().find(
      (m: MessageEntry): boolean => m.id === messageId);
    const captionTypes: string[] = ['photo', 'video', 'file', 'audio', 'voice'];
    if (msg === undefined || !msg.isOutgoing ||
      (msg.contentType !== 'text' && captionTypes.indexOf(msg.contentType) < 0)) {
      return;
    }
    if (this.editingId === 0) {
      this.draftBeforeEdit = this.draft;
    }
    this.editingId = messageId;
    this.editingKind = msg.contentType === 'text' ? 'text' : 'caption';
    this.editingPreview = msg.text !== '' ? msg.text
      : (this.editingKind === 'caption' ? '（无说明文字）' : '');
    this.draft = msg.text;
  }

  private cancelEdit(): void {
    if (this.editingId === 0) { return; }
    this.editingId = 0;
    this.editingPreview = '';
    this.draft = this.draftBeforeEdit;
    this.draftBeforeEdit = '';
  }

  private commitEdit(): void {
    const store = this.store;
    const editId = this.editingId;
    const text = this.draft.trim();
    // Captions may be cleared (empty); message text may not.
    if (store === null || editId === 0 || this.composerSending ||
      (text === '' && this.editingKind === 'text')) {
      return;
    }
    this.composerSending = true;
    const task: Promise<void> = this.editingKind === 'caption'
      ? store.editCaptionAsync(editId, text) : store.editTextAsync(editId, text);
    task.then((): void => {
      this.composerSending = false;
      if (this.editingId === editId) {
        this.editingId = 0;
        this.editingPreview = '';
        this.draft = this.draftBeforeEdit;
        this.draftBeforeEdit = '';
      }
    }).catch((e: TdError): void => {
      this.composerSending = false;
      console.error(`ChatPage.commitEdit failed: ${e.message}`);
      promptAction.showToast({
        message: e.message.indexOf('MESSAGE_NOT_MODIFIED') >= 0
          ? '内容没有变化' : '编辑失败，原消息未改动',
        duration: 1800
      });
    });
  }

  // Edit strip above the input bar: pencil accent + original excerpt + ✕.
  @Builder
  editPreview() {
    Row({ space: 10 }) {
      Row().width(3).height(34).borderRadius(2).backgroundColor(COLOR_PRIMARY);
      Column({ space: 1 }) {
        Text(this.editingKind === 'caption' ? '编辑说明文字' : '编辑消息')
          .fontSize(13).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium);
        Text(this.editingPreview).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1);
      Row() {
        SymbolGlyph($r('sys.symbol.xmark')).fontSize(16).fontColor([COLOR_TEXT_SECONDARY]);
      }
      .width(32).height(32).borderRadius(16)
      .justifyContent(FlexAlign.Center)
      .onClick(() => { this.cancelEdit(); });
    }
    .width('100%').height(44).padding({ left: 12, right: 8 })
    .backgroundColor($r('app.color.surface'));
  }

  // Reply preview strip above the input bar (Telegram style): accent bar, sender
  // name, message excerpt, and an ✕ to cancel.
  @Builder
  replyPreview() {
    Row({ space: 10 }) {
      Row().width(3).height(34).borderRadius(2).backgroundColor(COLOR_PRIMARY);
      Column({ space: 1 }) {
        Text(this.replyToName).fontSize(13).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(this.replyToText).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1)
      .onClick(() => { this.onReplyTap(this.replyToId); });
      Row() {
        SymbolGlyph($r('sys.symbol.xmark')).fontSize(16).fontColor([COLOR_TEXT_SECONDARY]);
      }
      .width(32).height(32).borderRadius(16)
      .justifyContent(FlexAlign.Center)
      .stateStyles({
        normal: this.suggestionRowNormalStyle,
        pressed: this.suggestionRowPressedStyle
      })
      .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110), curve: Curve.EaseOut })
        .onClick(() => { this.clearReply(); });
    }
    .width('100%').padding({ left: 16, right: 16, top: 7, bottom: 7 })
    .backgroundColor($r('app.color.surface'))
    .border({ width: { top: 0.7 }, color: $r('app.color.divider') })
    .alignItems(VerticalAlign.Center)
    .transition(
      TransitionEffect.translate({ y: 12 })
        .combine(TransitionEffect.OPACITY)
        .animation({ duration: this.chatEffectDuration(KEY_POWER_EFFECT_REPLY, 180), curve: Curve.EaseOut })
    );
  }

  // 自定义 emoji（Premium 表情）反应区。只在服务端允许时才出现，避免用户点
  // 一个必然被拒的反应。
  @Builder
  customEmojiReactionSection() {
    Column({ space: 6 }) {
      Row() {
        Text('自定义表情').fontSize(13).fontColor(COLOR_TEXT_SECONDARY).layoutWeight(1);
      }
      .width('100%').padding({ left: 6, right: 6 });
      Scroll() {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(this.sheetCustomEmojis, (option: CustomEmojiOption) => {
            Row() {
              if (option.path !== '') {
                Image(option.path.startsWith('/') ? `file://${option.path}` : option.path)
                  .width(30).height(30).objectFit(ImageFit.Contain)
                  .draggable(false);
              } else {
                // 位图未就绪：灰底占位保持格子尺寸，不闪空白。
                Row().width(30).height(30).borderRadius(8)
                  .backgroundColor($r('app.color.surface_alt'));
              }
            }
            .width(44).height(44).borderRadius(22)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(this.targetReactionChosen(customEmojiReactionKey(option.id))
              ? $r('app.color.selected_pill') : Color.Transparent)
            .stateStyles({
              normal: this.suggestionRowNormalStyle,
              pressed: this.suggestionRowPressedStyle
            })
            .animation({ duration: this.reactionEffectDuration(130), curve: Curve.EaseOut })
            .accessibilityText('自定义表情回应')
            .onClick(() => { this.pickReaction(customEmojiReactionKey(option.id)); });
          }, (option: CustomEmojiOption) => `ce_${option.id}_${option.path}`);
        }.width('100%');
      }.constraintSize({ maxHeight: 108 }).scrollBar(BarState.Off);
    }
    .width('100%');
  }

  // Full emoji reaction picker (opened from the long-press menu chevron): a
  // bottom sheet grid; tapping an emoji adds it as a reaction to the target.
  @Builder
  reactionSheet() {
    Column() {
      Column().layoutWeight(1)
        .onClick(() => { this.closeReactionSheet(); });
      Column({ space: 8 }) {
        Row().width(40).height(4).borderRadius(2).backgroundColor('#D0D0D0');
        Row() {
          Text('选择表情回应').fontSize(16).fontColor(COLOR_TEXT_PRIMARY).fontWeight(FontWeight.Medium)
            .layoutWeight(1);
          Text('再次点击可取消')
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
        }
        .width('100%').padding({ left: 6, right: 6 });
        Scroll() {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(this.sheetReactions, (e: string) => {
              Row() {
                Text(e).fontSize(27);
              }
                .width(44).height(44).borderRadius(22)
                .justifyContent(FlexAlign.Center)
                .backgroundColor(this.targetReactionChosen(e) ? $r('app.color.selected_pill') : Color.Transparent)
                .stateStyles({
                  normal: this.suggestionRowNormalStyle,
                  pressed: this.suggestionRowPressedStyle
                })
                .animation({ duration: this.reactionEffectDuration(130), curve: Curve.EaseOut })
                .onClick(() => { this.pickReaction(e); });
            }, (e: string) => e);
          }.width('100%');
        }.constraintSize({ maxHeight: 240 }).scrollBar(BarState.Off);
        if (this.sheetAllowCustomEmoji && this.sheetCustomEmojis.length > 0) {
          this.customEmojiReactionSection();
        }
      }
      .width('calc(100% - 16vp)')
      .padding({ left: 10, right: 10, top: 10, bottom: 14 + this.bottomInset() })
      .backgroundColor($r('app.color.surface'))
      .borderRadius(20)
      .shadow({ radius: 12, color: '#26000000', offsetX: 0, offsetY: -2 })
      .margin({ left: 8, right: 8, bottom: 8 });
    }
    .width('100%').height('100%')
    .backgroundColor('#00000066')
    .transition(
      TransitionEffect.translate({ y: 24 })
        .combine(TransitionEffect.OPACITY)
        .animation({ duration: this.reactionEffectDuration(220), curve: Curve.EaseOut })
    );
  }

  @Builder
  forwardSheet() {
    Column() {
      Column().layoutWeight(1)
        .onClick(() => { this.closeForwardSheet(); });
      Column({ space: 10 }) {
        Row({ space: 10 }) {
          Row().width(40).height(4).borderRadius(2).backgroundColor('#D0D0D0');
        }
        .width('100%').justifyContent(FlexAlign.Center);
        Row() {
          Column({ space: 2 }) {
            Text(this.forwardMessageIds.length > 1
              ? `转发 ${this.forwardMessageIds.length} 条消息`
              : '转发消息')
              .fontSize(17).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
            Text('选择接收会话').fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
          }
          .alignItems(HorizontalAlign.Start).layoutWeight(1);
          Row() {
            SymbolGlyph($r('sys.symbol.xmark')).fontSize(16).fontColor([COLOR_TEXT_SECONDARY]);
          }
          .width(34).height(34).borderRadius(17).justifyContent(FlexAlign.Center)
          .stateStyles({
            normal: this.suggestionRowNormalStyle,
            pressed: this.suggestionRowPressedStyle
          })
          .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110), curve: Curve.EaseOut })
          .onClick(() => { this.closeForwardSheet(); });
        }
        .width('100%');
        TextInput({ text: this.forwardQuery, placeholder: '搜索聊天' })
          .width('100%').height(40)
          .padding({ left: 14, right: 14 })
          .backgroundColor($r('app.color.surface_alt')).borderRadius(20)
          .onChange((value: string): void => { this.forwardQuery = value; });
        if (this.forwardLoadState === 'loading') {
          Column({ space: 10 }) {
            LoadingProgress().width(26).height(26).color(COLOR_PRIMARY);
            Text('正在加载会话').fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          }
          .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
        } else if (this.forwardLoadState === 'error') {
          Column({ space: 10 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
              .fontSize(28).fontColor([COLOR_TEXT_SECONDARY]);
            Text('会话列表加载失败').fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
            Button('重试')
              .fontSize(14).fontColor(Color.White)
              .height(36).padding({ left: 20, right: 20 })
              .backgroundColor(COLOR_PRIMARY).borderRadius(18)
              .onClick(() => { this.retryForwardChats(); });
          }
          .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
        } else if (this.filteredForwardChats().length === 0) {
          Column({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(28).fontColor([COLOR_TEXT_SECONDARY]);
            Text(this.forwardQuery.trim() === '' ? '暂无可转发的会话' : '没有匹配的聊天')
              .fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
          }
          .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
        } else {
          List() {
            ForEach(this.filteredForwardChats(), (chat: ChatEntry) => {
              ListItem() {
                Row({ space: 12 }) {
                  AvatarView({
                    avatarPath: chat.avatarPath,
                    initials: chat.initials,
                    colorSeed: chat.id,
                    avatarSize: 42
                  });
                  Column({ space: 3 }) {
                    Text(chat.title).fontSize(15).fontWeight(FontWeight.Medium)
                      .fontColor(COLOR_TEXT_PRIMARY).maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis });
                    Text(chat.id === this.chatId ? '当前聊天' :
                      (chat.lastMessageText !== '' ? chat.lastMessageText : '点击转发'))
                      .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis });
                  }
                  .alignItems(HorizontalAlign.Start).layoutWeight(1);
                  if (this.forwardSendingChatId === chat.id) {
                    LoadingProgress().width(20).height(20).color(COLOR_PRIMARY);
                  } else {
                    SymbolGlyph($r('sys.symbol.paperplane'))
                      .fontSize(18).fontColor([COLOR_PRIMARY]);
                  }
                }
                .width('100%').padding({ left: 6, right: 6, top: 8, bottom: 8 })
                .alignItems(VerticalAlign.Center)
                .opacity(this.forwardSendingChatId === 0 || this.forwardSendingChatId === chat.id ? 1 : 0.45)
                .stateStyles({
                  normal: this.suggestionRowNormalStyle,
                  pressed: this.suggestionRowPressedStyle
                })
                .animation({
                  duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120),
                  curve: Curve.EaseOut
                })
                .onClick(() => { this.forwardToChat(chat); });
              }
            }, (chat: ChatEntry): string => `forward_${chat.id}_${chat.revision}`);
          }
          .layoutWeight(1).width('100%')
          .divider({ strokeWidth: 0.7, color: $r('app.color.divider'), startMargin: 60, endMargin: 6 })
          .scrollBar(BarState.Auto)
          .onReachEnd((): void => { getChatStore().loadMore('main'); });
        }
      }
      .width('calc(100% - 16vp)').height('64%')
      .padding({ left: 12, right: 12, top: 10, bottom: 12 + this.bottomInset() })
      .backgroundColor($r('app.color.surface')).borderRadius(20)
      .shadow({ radius: 12, color: '#26000000', offsetX: 0, offsetY: -2 })
      .margin({ left: 8, right: 8, bottom: 8 });
    }
    .width('100%').height('100%')
    .backgroundColor('#00000066')
    .transition(
      TransitionEffect.translate({ y: 24 })
        .combine(TransitionEffect.OPACITY)
        .animation({ duration: this.chatEffectDuration(KEY_POWER_EFFECT_REPLY, 220), curve: Curve.EaseOut })
    );
  }

  // The reply keyboard sits below the input bar, so while it's up it carries
  // the bottom safe-area inset instead of the input row.
  private replyKbVisible(): boolean {
    return this.membershipState === 'writable' &&
      this.replyKeyboard !== null && !this.replyKbCollapsed;
  }

  private composerPlaceholder(): string {
    // Live typing state borrows the composer's gray placeholder — costs no
    // space and can never cover a message.
    if (this.typingLabel !== '') {
      return this.typingLabel;
    }
    if (this.replyKbVisible() && this.replyKeyboard !== null &&
      this.replyKeyboard.placeholder.trim() !== '') {
      return this.replyKeyboard.placeholder;
    }
    return '发消息';
  }

  // Bot custom reply keyboard: full-width button rows under the input bar.
  @Builder
  replyKeyboardPanel() {
    Scroll() {
      Column({ space: 6 }) {
        ForEach(this.replyKeyboard!.rows, (row: KeyboardBtn[], rowIdx: number) => {
          Row({ space: 6 }) {
            ForEach(row, (btn: KeyboardBtn, btnIdx: number) => {
              Row({ space: 6 }) {
                if (this.replyKeyboardSendingKey === `${rowIdx}_${btnIdx}_${btn.text}`) {
                  LoadingProgress()
                    .width(16).height(16)
                    .color(btn.style !== '' ? Color.White : COLOR_PRIMARY);
                }
                Text(btn.text)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(btn.style !== '' ? Color.White : COLOR_TEXT_PRIMARY)
                  .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .textAlign(TextAlign.Center);
                if (btn.type !== '' && btn.type !== KB_TEXT) {
                  SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
                    .fontSize(12)
                    .fontColor([btn.style !== '' ? Color.White : COLOR_TEXT_SECONDARY]);
                }
              }
              .layoutWeight(1)
              .constraintSize({ minHeight: 42 })
              .padding({ left: 8, right: 8, top: 7, bottom: 7 })
              .backgroundColor(botButtonBg(btn.style, $r('app.color.surface')))
              .borderRadius(10)
              .justifyContent(FlexAlign.Center)
              .stateStyles({
                normal: this.botKeyboardButtonNormalStyle,
                pressed: this.botKeyboardButtonPressedStyle
              })
              .animation({
                duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
                curve: Curve.EaseOut
              })
              .enabled(this.replyKeyboardSendingKey === '')
              .onClick(() => {
                this.onReplyKeyboardTap(btn, `${rowIdx}_${btnIdx}_${btn.text}`);
              });
            }, (btn: KeyboardBtn, btnIdx: number) => `kb_${rowIdx}_${btnIdx}_${btn.text}`);
          }.width('100%');
        }, (_row: KeyboardBtn[], rowIdx: number) => `kbrow_${rowIdx}`);
      }
      .width('100%');
    }
    .width('calc(100% - 16vp)')
    .constraintSize({ maxHeight: this.replyKeyboard!.resize ? 210 : 280 })
    .scrollBar(BarState.Auto)
    .padding(8)
    .margin({ left: 8, right: 8, bottom: this.composerBottomGap() })
    .backgroundColor($r('app.color.surface_alt'))
    .borderRadius(16)
    .shadow({ radius: 6, color: '#16000000', offsetX: 0, offsetY: 2 })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: 10 }))
      .animation({ duration: this.chatEffectDuration(KEY_POWER_EFFECT_MENU, 190), curve: Curve.EaseOut }))
    .onAreaChange((_old: Area, area: Area) => { this.replyKbH = area.height as number; });
  }

  // Replaces the composer for public groups/channels the current user hasn't
  // joined yet, matching Telegram's full-width bottom action.
  @Builder
  membershipBar() {
    Row({ space: 8 }) {
      if (this.membershipState === 'checking') {
        LoadingProgress()
          .width(20).height(20).color(COLOR_PRIMARY);
        Text('正在获取成员状态')
          .fontSize(15).fontColor(COLOR_TEXT_SECONDARY);
      } else if (this.membershipState === 'blocked') {
        Text('你无法加入此聊天')
          .fontSize(16).fontColor(COLOR_TEXT_SECONDARY).fontWeight(FontWeight.Medium);
      } else if (this.membershipState === 'readonly') {
        SymbolGlyph($r(this.isMuted ? 'sys.symbol.bell' : 'sys.symbol.bell_slash'))
          .fontSize(17).fontColor([COLOR_PRIMARY]);
        Text(this.isMuted ? '取消静音' : '静音')
          .fontSize(16).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium);
      } else {
        if (this.joiningChat) {
          LoadingProgress()
            .width(20).height(20).color(COLOR_PRIMARY);
        }
        Text(this.joiningChat ? '正在加入…' : '加入')
          .fontSize(16).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium);
      }
    }
    .width('100%')
    .height(52 + this.composerBottomGap())
    .padding({ left: 12, right: 12, bottom: this.composerBottomGap() })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.surface'))
    .border({ width: { top: 0.7 }, color: $r('app.color.divider') })
    .enabled((this.membershipState === 'joinable' && !this.joiningChat) ||
      this.membershipState === 'readonly')
    .onClick(() => {
      if (this.membershipState === 'readonly') {
        this.toggleChatMute();
      } else {
        this.joinCurrentChat();
      }
    })
    .onAreaChange((_old: Area, area: Area) => { this.inputBarH = area.height as number; });
  }

  @Builder
  inputBar() {
    Row() {
      Row({ space: 6 }) {
        if (this.isRecording) {
          // Recording mode: red dot + timer, 取消, send.
          Row({ space: 7 }) {
            Circle({ width: 8, height: 8 }).fill('#FF3B30');
            Text(this.formatRecSeconds()).fontSize(15).fontColor(COLOR_TEXT_PRIMARY);
            Text('正在录音...').fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          }.layoutWeight(1).alignItems(VerticalAlign.Center);
          Button('取消').fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
            .stateStyles({
              normal: this.composerIconNormalStyle,
              pressed: this.composerIconPressedStyle
            })
            .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120), curve: Curve.EaseOut })
            .onClick(() => { this.cancelRecording(); });
          Button() {
            SymbolGlyph($r('sys.symbol.paperplane')).fontSize(20).fontColor([Color.White]);
          }
          .width(40).height(40).borderRadius(20)
          .stateStyles({
            normal: this.composerPrimaryNormalStyle,
            pressed: this.composerPrimaryPressedStyle
          })
          .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120), curve: Curve.EaseOut })
          .onClick(() => { this.finishRecording(); });
        } else {
          if (this.botMenuAvailable) {
            // Bot 菜单 pill — toggles the full command catalog.
            Row({ space: 4 }) {
              SymbolGlyph($r(this.commandMenuOpen ? 'sys.symbol.xmark' : 'sys.symbol.line_3_horizontal'))
                .fontSize(15).fontColor([Color.White]);
              Text(this.commandMenuOpen ? '关闭' : '菜单').fontSize(13).fontColor(Color.White);
            }
            .padding({ left: 9, right: 10, top: 6, bottom: 6 })
            .borderRadius(15)
            .stateStyles({
              normal: this.composerPrimaryNormalStyle,
              pressed: this.composerPrimaryPressedStyle
            })
            .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120), curve: Curve.EaseOut })
            .onClick(() => { this.toggleBotMenu(); });
          }
          SymbolGlyph($r(this.showEmojiPanel ? 'sys.symbol.face_smiling_fill' : 'sys.symbol.face_smiling'))
            .fontSize(24)
            .fontColor([this.showEmojiPanel ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY])
            .onAreaChange((_old: Area, area: Area) => {
              const gx = area.globalPosition.x as number;
              this.emojiBtnCx = gx + (area.width as number) / 2;
            })
            .onClick(() => {
              this.setEmojiPanel(!this.showEmojiPanel);
              this.mentionItems = [];
              this.commandItems = [];
              this.commandMenuOpen = false;
            });
          TextArea({ text: this.draft, placeholder: this.composerPlaceholder(), controller: this.composerController })
            .layoutWeight(1)
            .height(this.composerEditorHeight())
            .maxLines(5)
            .maxLength(4096)
            .fontSize(15)
            .lineHeight(22)
            .fontColor(COLOR_TEXT_PRIMARY)
            .caretColor(COLOR_PRIMARY)
            .padding({ left: 3, right: 3, top: 9, bottom: 9 })
            .backgroundColor(Color.Transparent)
            .key('chat_composer')
            .onChange((v: string) => {
              this.draft = v;
              this.updateSuggestions(v);
              if (v.trim() !== '' && this.editingId === 0) {
                this.store?.notifyTyping();
              }
            })
            // 聊天设置 → 回车键发送: the IME's action key becomes 发送 and submits;
            // otherwise TextArea keeps the ordinary newline action.
            .enterKeyType(this.sendByEnter ? EnterKeyType.Send : EnterKeyType.NEW_LINE)
            .onSubmit(() => {
              if (this.sendByEnter) {
                this.doSend();
              }
            })
            .onFocus(() => {
              // Capture this before RESIZE starts changing the List viewport.
              // Only a chat already at the live tail should follow the IME;
              // focusing while reading older messages must preserve position.
              this.imeTailPinned = this.atBottom && this.viewerMsgId === 0 &&
                !this.stayAtUnread;
              this.composerFocused = true;
              this.setEmojiPanel(false);
              this.replyKbCollapsed = true;
              this.commandMenuOpen = false;
              if (this.keyboardH > 0) {
                this.syncTailOnImeFrame();
              }
            })
            .onBlur(() => { this.composerFocused = false; });
          if (this.replyKeyboard !== null) {
            // Bot-keyboard toggle: tinted while the keyboard is up, gray when
            // collapsed — tapping flips between the two.
            Row() {
              SymbolGlyph($r('sys.symbol.keyboard'))
                .fontSize(21)
                .fontColor([this.replyKbCollapsed ? COLOR_TEXT_SECONDARY : COLOR_PRIMARY]);
            }
            .width(34).height(34).borderRadius(17)
            .justifyContent(FlexAlign.Center)
            .stateStyles({
              normal: this.composerIconNormalStyle,
              pressed: this.composerIconPressedStyle
            })
            .animation({
              duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
              curve: Curve.EaseOut
            })
            .accessibilityText(this.replyKbCollapsed ? '打开 Bot 键盘' : '切换到文字输入')
            .onClick(() => { this.toggleReplyKeyboard(); });
          }
          if (this.botMiniAppUrlValue !== '') {
            SymbolGlyph($r('sys.symbol.square_grid_2x2'))
              .fontSize(22).fontColor([COLOR_PRIMARY])
              .accessibilityText('打开 Mini App')
              .onClick((): void => { this.openBotMiniApp(); });
          }
          SymbolGlyph($r('sys.symbol.paperclip'))
            .fontSize(22)
            .fontColor([COLOR_TEXT_SECONDARY])
            .bindMenu(this.attachMenuItems());
          // Mic ↔ send swap: outgoing icon shrinks/fades while the incoming one
          // scales in (the send button adds a small un-rotate flourish).
          Stack() {
            if (this.draft.trim() === '') {
              Button() {
                if (this.recordingStarting) {
                  LoadingProgress().width(18).height(18).color(Color.White);
                } else {
                  SymbolGlyph($r('sys.symbol.mic')).fontSize(20).fontColor([Color.White]);
                }
              }
              .width(40).height(40).borderRadius(20)
              .stateStyles({
                normal: this.composerPrimaryNormalStyle,
                pressed: this.composerPrimaryPressedStyle
              })
              .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120), curve: Curve.EaseOut })
              .enabled(!this.recordingStarting)
              .transition(TransitionEffect.OPACITY
                .combine(TransitionEffect.scale({ x: 0.3, y: 0.3 }))
                .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 200), curve: Curve.EaseOut }))
              .onClick(() => { this.startRecording(); });
            } else {
              Button() {
                if (this.composerSending) {
                  LoadingProgress().width(18).height(18).color(Color.White);
                } else {
                  SymbolGlyph($r('sys.symbol.paperplane')).fontSize(20).fontColor([Color.White]);
                }
              }
              .width(40).height(40).borderRadius(20)
              .stateStyles({
                normal: this.composerPrimaryNormalStyle,
                pressed: this.composerPrimaryPressedStyle
              })
              .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120), curve: Curve.EaseOut })
              .enabled(!this.composerSending)
              .transition(TransitionEffect.OPACITY
                .combine(TransitionEffect.scale({ x: 0.3, y: 0.3 }))
                .combine(TransitionEffect.rotate({ angle: -45 }))
                .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 200), curve: Curve.EaseOut }))
              .onClick(() => { this.doSend(); })
              // Long-press: schedule / silent send.
              .gesture(LongPressGesture().onAction(() => { this.showSendOptions(); }));
            }
          }.width(40).height(40);
        }
      }
      .width('100%')
      .constraintSize({ minHeight: 48, maxHeight: 120 })
      .padding({ left: 12, right: 4, top: 4, bottom: 4 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(24);
    }.width('100%')
    .padding({
      left: 14,
      right: 14,
      top: 6,
      bottom: this.replyKbVisible() ? 8 : this.composerBottomGap()
    })
    .alignItems(VerticalAlign.Center)
    .onAreaChange((_old: Area, area: Area) => { this.inputBarH = area.height as number; });
  }

  @Builder
  searchBottomBar() {
    Row() {
      Text(this.searchResults.length > 0
        ? `${this.searchTotal - this.searchIdx} / ${this.searchTotal}`
        : (this.searchTotal === 0 && this.searchQuery.trim() !== '' ? '' : '输入关键词搜索'))
        .fontSize(15).fontColor(COLOR_TEXT_PRIMARY);
      Blank().layoutWeight(1);
      if (this.searchResults.length > 0) {
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_up')).fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
        }
        .width(42).height(42).justifyContent(FlexAlign.Center)
        .opacity(this.searchIdx + 1 < this.searchTotal ? 1 : 0.4)
        .onClick(() => { this.searchOlder(); });
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
        }
        .width(42).height(42).justifyContent(FlexAlign.Center)
        .opacity(this.searchIdx > 0 ? 1 : 0.4)
        .onClick(() => { this.searchNewer(); });
      }
    }
    .width('100%').height(52 + this.composerBottomGap())
    .padding({ left: 20, right: 10, bottom: this.composerBottomGap() })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.surface'))
    .border({ width: { top: 0.7 }, color: $r('app.color.divider') });
  }

  @Builder
  bottomDock() {
    Column() {
      if (this.selecting) {
        // Selection owns the header actions; removing the composer also drops
        // its reserved list inset so messages expand naturally into the space.
        Column().width('100%').height(0);
      } else if (this.searchMode) {
        this.searchBottomBar();
      } else if (this.membershipState !== 'writable') {
        this.membershipBar();
      } else {
        Column() {
          if (this.editingId !== 0) {
            this.editPreview();
          } else if (this.replyToId !== 0) {
            this.replyPreview();
          }
          this.inputBar();
          if (this.replyKbVisible()) {
            this.replyKeyboardPanel();
          }
        }
        .width('100%');
      }
    }
    .width('100%')
    .onAreaChange((_old: Area, area: Area) => {
      this.updateBottomChromeHeight(area.height as number);
    });
  }

  // Segmented indicator like Telegram: short vertical bars, the currently-shown
  // pinned message highlighted. A sliding window of up to PINNED_SEG_MAX bars so
  // the highlight moves on every tap (and the window scrolls past the window size).
  private pinnedShownIdx(): number {
    return Math.min(this.pinnedCycle, Math.max(0, this.pinnedCount - 1));
  }

  private pinnedSegCount(): number {
    return Math.min(this.pinnedCount, PINNED_SEG_MAX);
  }

  // Segments run oldest (top) → newest (bottom), so the newest pinned message
  // highlights the BOTTOM bar. pinnedShownIdx() is in newest-first space and
  // gets flipped into this display space.
  private pinnedDispActive(): number {
    return Math.max(0, this.pinnedCount - 1 - this.pinnedShownIdx());
  }

  private pinnedSegStart(): number {
    const n: number = this.pinnedSegCount();
    if (this.pinnedCount <= n) {
      return 0;
    }
    const s: number = this.pinnedDispActive() - (n - 1);
    return Math.max(0, Math.min(s, this.pinnedCount - n));
  }

  private pinnedSegs(): number[] {
    const n: number = this.pinnedSegCount();
    const a: number[] = [];
    for (let i = 0; i < n; i++) {
      a.push(i);
    }
    return a;
  }

  private pinnedActiveSeg(): number {
    return this.pinnedDispActive() - this.pinnedSegStart();
  }

  @Builder
  pinnedBanner() {
    Row({ space: 10 }) {
      Column() {
        ForEach(this.pinnedSegs(), (i: number) => {
          Column().width(3).layoutWeight(1)
            .backgroundColor(i === this.pinnedActiveSeg() ? COLOR_PRIMARY : '#303E3E40')
            .borderRadius(1.5).margin({ top: 1, bottom: 1 });
        }, (i: number) => `seg_${i}_${i === this.pinnedActiveSeg()}`);
      }.height(34).width(3);
      Column({ space: 2 }) {
        Row({ space: 6 }) {
          Text('置顶消息').fontSize(12).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium);
          if (this.pinnedCount > 1) {
            Text(`${this.pinnedShownIdx() + 1}/${this.pinnedCount}`)
              .fontSize(10)
              .fontColor(COLOR_TEXT_SECONDARY);
          }
          if (this.pinnedLoadState === 'loading') {
            LoadingProgress().width(12).height(12).color(COLOR_PRIMARY);
          }
        }
        Text(this.pinnedPreview).fontSize(13).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1);
      if (this.pinnedJumpBusy) {
        LoadingProgress().width(18).height(18).color(COLOR_PRIMARY);
      } else {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(15)
          .fontColor([COLOR_TEXT_SECONDARY]);
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 54 })
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .stateStyles({
      normal: this.topCardRowNormalStyle,
      pressed: this.topCardRowPressedStyle
    })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 130),
      curve: Curve.EaseOut
    })
    .enabled(!this.pinnedJumpBusy)
    .accessibilityText(`置顶消息，${this.pinnedPreview}，点击定位`)
    .onClick(() => { this.onPinnedTap(); });
  }

  // Pinned and live rows are separate actions inside one shared card. This
  // preserves both features when they coexist while keeping their hierarchy
  // explicit: pinned content first, active live session second.
  @Builder
  liveStreamBanner() {
    Row({ space: 10 }) {
      Column()
        .width(3).height(34).backgroundColor('#FF405C').borderRadius(1.5)
        .opacity(this.livePulseExpanded ? 1 : 0.62)
        .scale({ x: 1, y: this.livePulseExpanded ? 1 : 0.82 })
        .animation({ duration: powerAnimationDuration(KEY_POWER_PARTICLES, 720), curve: Curve.EaseInOut });
      Column({ space: 2 }) {
        Row({ space: 6 }) {
          Text('正在直播').fontSize(12).fontColor('#FF405C').fontWeight(FontWeight.Medium);
          if (this.liveCallIsRtmp) {
            Text('单向').fontSize(9).fontColor(Color.White).fontWeight(FontWeight.Bold)
              .padding({ left: 5, right: 5, top: 2, bottom: 2 })
              .backgroundColor('#FF405C').borderRadius(6);
          }
          Circle({ width: 6, height: 6 }).fill('#FF405C')
            .opacity(this.livePulseExpanded ? 1 : 0.45);
        }
        Text(this.liveParticipantCount > 0 ? `${this.liveParticipantCount} 人在线` : '直播进行中')
          .fontSize(13).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1);
      Button() {
        Row({ space: 5 }) {
          if (this.liveDialogOpening || this.liveNavigationBusy) {
            LoadingProgress().width(13).height(13).color(Color.White);
          }
          Text(this.liveNavigationBusy ? '正在进入' : '进入')
            .fontSize(12)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Medium);
        }
      }
        .height(32).padding({ left: 12, right: 12 })
        .borderRadius(16)
        .stateStyles({
          normal: this.liveEntryNormalStyle,
          pressed: this.liveEntryPressedStyle
        })
        .enabled(!this.liveDialogOpening && !this.liveNavigationBusy)
        .onClick((): void => { this.onLiveStreamTap(); });
    }
    .width('100%')
    .constraintSize({ minHeight: 54 })
    .padding({ left: 14, right: 12, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .stateStyles({
      normal: this.topCardRowNormalStyle,
      pressed: this.topCardRowPressedStyle
    })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 130),
      curve: Curve.EaseOut
    })
    .accessibilityText(`正在直播，${this.liveParticipantCount > 0 ?
      `${this.liveParticipantCount} 人在线` : '直播进行中'}，点击进入`)
    .onClick((): void => { this.onLiveStreamTap(); });
  }

  @Builder
  topCardLoadingBanner() {
    Row({ space: 12 }) {
      LoadingProgress().width(22).height(22).color(COLOR_PRIMARY);
      Column({ space: 2 }) {
        Text('正在同步会话动态')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY);
        Text('检查置顶消息与直播状态…')
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY);
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
    }
    .width('100%')
    .constraintSize({ minHeight: 54 })
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .accessibilityText('正在同步置顶消息与直播状态');
  }

  @Builder
  topBanners() {
    Column() {
      if (this.topCardHasContent()) {
        if (this.pinnedPreview !== '') {
          this.pinnedBanner();
        }
        if (this.pinnedPreview !== '' && this.liveGroupCallId > 0 && this.liveCallIsActive) {
          Divider()
            .strokeWidth(0.5)
            .color($r('app.color.divider'))
            .margin({ left: 14, right: 14 });
        }
        if (this.liveGroupCallId > 0 && this.liveCallIsActive) {
          this.liveStreamBanner();
        }
      } else if (this.topCardLoadingVisible) {
        this.topCardLoadingBanner();
      }
    }
    .width('calc(100% - 24vp)')
    .backgroundColor($r('app.color.surface'))
    .borderRadius(14)
    .margin({ left: 12, right: 12, bottom: 2 })
    .shadow({ radius: 5, color: '#12000000', offsetX: 0, offsetY: 1 })
    .clip(true)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: -6 }))
      .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 240), curve: Curve.EaseOut }));
  }

  private scrollFabBadgeWidth(): number {
    if (this.unreadBadge > 99) {
      return 34;
    }
    return this.unreadBadge > 9 ? 27 : 22;
  }

  @Builder
  scrollFab() {
    Stack() {
      Button() {
        if (this.scrollToBottomBusy) {
          LoadingProgress().width(20).height(20).color(COLOR_PRIMARY);
        } else {
          SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
        }
      }
      .width(46).height(46).borderRadius(23)
      .stateStyles({
        normal: this.scrollFabNormalStyle,
        pressed: this.scrollFabPressedStyle
      })
      .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 130), curve: Curve.EaseOut })
      .shadow({ radius: 7, color: '#26000000', offsetX: 0, offsetY: 2 })
      .enabled(!this.scrollToBottomBusy)
      .accessibilityText(this.scrollToBottomBusy ? '正在返回最新消息' : '返回最新消息')
      .onClick(() => { this.scrollToLatest(); })
      .position({ x: 6, y: 10 });
      if (this.unreadBadge > 0) {
        Row() {
          Text(this.unreadBadge > 99 ? '99+' : `${this.unreadBadge}`)
            .fontSize(12).fontColor(Color.White).fontWeight(FontWeight.Medium)
            .maxLines(1).textAlign(TextAlign.Center);
        }
        .width(this.scrollFabBadgeWidth()).height(22)
        .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
        .backgroundColor(COLOR_PRIMARY).borderRadius(11)
        .border({ width: 1.5, color: $r('app.color.surface') })
        .shadow({ radius: 3, color: '#24000000', offsetX: 0, offsetY: 1 })
        .position({ x: 52 - this.scrollFabBadgeWidth(), y: 0 })
        .animation({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 140),
          curve: Curve.EaseOut
        })
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.72, y: 0.72 }))
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160),
            curve: Curve.EaseOut
          }))
        .enabled(!this.scrollToBottomBusy)
        .onClick((): void => { this.scrollToLatest(); })
        .accessibilityText(`${this.unreadBadge} 条未读消息，返回最新消息`);
      }
    }
    .width(52).height(56)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 0.72, y: 0.72 }))
      .combine(TransitionEffect.translate({ y: 10 }))
      .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 220), curve: Curve.EaseOut }));
  }

  private scrollToLatest(): void {
    if (this.store === null || this.scrollToBottomBusy) {
      return;
    }
    this.prepareUserJump();
    // Far from the live tail — unloaded pages below, OR a long stretch of
    // already-loaded history (scrollToIndex over thousands of lazy rows still
    // lays them out one by one and visibly crawls): atomically replace the
    // window with the newest page.
    const farFromEnd: boolean = this.groups.length - this.curStartIdx > JUMP_RELOAD_THRESHOLD;
    if (this.store.getHasMoreNewer() || farFromEnd) {
      const actionSeq: number = ++this.scrollActionSeq;
      this.scrollToBottomBusy = true;
      this.pendingScrollBottom = true;
      this.store.jumpToLatest((success: boolean): void => {
        if (actionSeq !== this.scrollActionSeq) {
          return;
        }
        this.scrollToBottomBusy = false;
        if (!success) {
          this.pendingScrollBottom = false;
          this.atBottom = false;
          promptAction.showToast({ message: '无法加载最新消息，请重试', duration: 1600 });
        } else if (this.groups.length === 0) {
          this.pendingScrollBottom = false;
          this.atBottom = true;
        }
      });
      return;
    }
    // Close to the end and fully loaded — snap instantly, no animated crawl.
    const actionSeq: number = ++this.scrollActionSeq;
    this.scroller.scrollToIndex(Math.max(0, this.groups.length - 1), false, ScrollAlign.END);
    setTimeout((): void => {
      if (actionSeq === this.scrollActionSeq) {
        this.scroller.scrollEdge(Edge.Bottom);
        this.refreshAtBottom();
      }
    }, 60);
  }

  private backgroundEffectsEnabled(): boolean {
    return !this.chatBackgroundCustom &&
      !this.powerSaving && this.powerChatEffects && this.powerBackgroundEffect;
  }

  private particlesEnabled(): boolean {
    return !this.chatBackgroundCustom && !this.powerSaving && this.powerParticles;
  }

  private emptyHistoryTitle(): string {
    if (this.threadRootId > 0) {
      return '还没有回复';
    }
    if (this.membershipState === 'blocked') {
      return '无法显示聊天内容';
    }
    if (this.isChannel) {
      return '频道暂无内容';
    }
    if (this.isGroup) {
      return '群组还没有消息';
    }
    return '还没有消息';
  }

  private emptyHistoryIcon(): string {
    if (this.membershipState === 'blocked') {
      return 'sys.symbol.lock_fill';
    }
    if (this.membershipState === 'joinable') {
      return 'sys.symbol.person_badge_plus';
    }
    if (this.threadRootId > 0) {
      return 'sys.symbol.arrowshape_turn_up_left';
    }
    return 'sys.symbol.message';
  }

  private emptyHistoryHint(): string {
    if (this.threadRootId > 0) {
      return this.membershipState === 'writable' ? '发送第一条回复' : '这里暂时没有可显示的回复';
    }
    if (this.membershipState === 'joinable') {
      return '加入后即可参与聊天和发送消息';
    }
    if (this.membershipState === 'blocked') {
      return '你可能已被移出，或此聊天已不可用';
    }
    if (this.membershipState === 'checking') {
      return '正在确认成员状态';
    }
    if (this.isChannel) {
      return '发布内容后会显示在这里';
    }
    if (this.isGroup) {
      return '发送第一条群组消息';
    }
    return '发一条消息，开始聊天吧';
  }

  @Builder
  messageListState() {
    Column({ space: 9 }) {
      if (this.messageLoadState === 'loading') {
        Stack({ alignContent: Alignment.Center }) {
          Circle({ width: 56, height: 56 }).fill($r('app.color.surface_alt'));
          LoadingProgress()
            .width(30).height(30).color(COLOR_PRIMARY);
        }.width(56).height(56);
        Text('正在同步消息')
          .fontSize(16).fontColor(COLOR_TEXT_PRIMARY).fontWeight(FontWeight.Medium);
        Text('聊天记录马上就好')
          .fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      } else if (this.messageLoadState === 'error') {
        Stack({ alignContent: Alignment.Center }) {
          Circle({ width: 56, height: 56 }).fill('#12E64646');
          SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
            .fontSize(30).fontColor(['#E64646']);
        }.width(56).height(56);
        Text('消息加载失败')
          .fontSize(16).fontColor(COLOR_TEXT_PRIMARY).fontWeight(FontWeight.Medium);
        Text(this.messageLoadError !== '' ? this.messageLoadError : '请检查网络后重试')
          .fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
          .textAlign(TextAlign.Center).maxLines(2);
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(14).fontColor([Color.White]);
          Text('重试').fontSize(13).fontColor(Color.White).fontWeight(FontWeight.Medium);
        }
        .height(34).padding({ left: 14, right: 14 })
        .borderRadius(17)
        .stateStyles({
          normal: this.composerPrimaryNormalStyle,
          pressed: this.composerPrimaryPressedStyle
        })
        .animation({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120),
          curve: Curve.EaseOut
        })
        .onClick((): void => { this.store?.retryInitialHistory(); });
      } else {
        Stack({ alignContent: Alignment.Center }) {
          Circle({ width: 56, height: 56 }).fill($r('app.color.surface_alt'));
          SymbolGlyph($r(this.emptyHistoryIcon()))
            .fontSize(28).fontColor([COLOR_PRIMARY]);
        }.width(56).height(56);
        Text(this.emptyHistoryTitle())
          .fontSize(16).fontColor(COLOR_TEXT_PRIMARY).fontWeight(FontWeight.Medium);
        Text(this.emptyHistoryHint())
          .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center);
      }
    }
    .constraintSize({ minWidth: 210, maxWidth: this.screenW - 48 })
    .padding({ left: 24, right: 24, top: 22, bottom: 22 })
    .backgroundColor($r('app.color.surface'))
    .border({ width: 0.5, color: $r('app.color.divider') })
    .borderRadius(20)
    .shadow({ radius: 8, color: '#18000000', offsetX: 0, offsetY: 3 })
    .alignItems(HorizontalAlign.Center)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: 8 }))
      .combine(TransitionEffect.scale({ x: 0.97, y: 0.97 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 200),
        curve: Curve.EaseOut
      }));
  }

  private timelineStateMode(): string {
    if (this.visibleGroupCount <= 0) {
      return '';
    }
    if (this.messageLoadState === 'error') {
      return 'syncError';
    }
    if (this.messageLoadState === 'loading') {
      return 'syncLoading';
    }
    if (this.olderLoadState === 'error') {
      return 'olderError';
    }
    if (this.newerLoadState === 'error') {
      return 'newerError';
    }
    if (this.olderLoadState === 'loading') {
      return 'olderLoading';
    }
    if (this.newerLoadState === 'loading') {
      return 'newerLoading';
    }
    return '';
  }

  private timelineStateText(mode: string): string {
    if (mode === 'syncError') {
      return '消息同步失败';
    }
    if (mode === 'syncLoading') {
      return '正在同步最新消息';
    }
    if (mode === 'olderError') {
      return '更早消息加载失败';
    }
    if (mode === 'newerError') {
      return '较新消息加载失败';
    }
    return mode === 'olderLoading' ? '正在加载更早消息' : '正在加载较新消息';
  }

  private timelineStateRetry(mode: string): void {
    if (this.store === null) {
      return;
    }
    if (mode === 'syncError') {
      this.store.retryInitialHistory();
    } else if (mode === 'olderError') {
      this.olderArmed = false;
      this.store.retryOlder();
    } else if (mode === 'newerError') {
      this.store.retryNewer();
    }
  }

  @Builder
  timelineStatePill() {
    Column() {
      Row({ space: 7 }) {
        if (this.timelineStateMode().indexOf('Loading') >= 0) {
          LoadingProgress().width(15).height(15).color(COLOR_PRIMARY);
        } else {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
            .fontSize(15).fontColor(['#E64646']);
        }
        Text(this.timelineStateText(this.timelineStateMode()))
          .fontSize(12.5).fontColor(COLOR_TEXT_PRIMARY).fontWeight(FontWeight.Medium);
        if (this.timelineStateMode().indexOf('Error') >= 0) {
          Divider().vertical(true).height(14).color($r('app.color.divider'));
          Text('重试').fontSize(12.5).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium);
        }
      }
      .height(32)
      .padding({ left: 11, right: 11 })
      .backgroundColor($r('app.color.surface'))
      .border({ width: 0.5, color: $r('app.color.divider') })
      .borderRadius(16)
      .shadow({ radius: 5, color: '#1A000000', offsetX: 0, offsetY: 2 })
      .stateStyles({
        normal: this.timelineStatusNormalStyle,
        pressed: this.timelineStatusPressedStyle
      })
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
        curve: Curve.EaseOut
      })
      .onClick((): void => { this.timelineStateRetry(this.timelineStateMode()); })
      .accessibilityText(this.timelineStateMode().indexOf('Error') >= 0
        ? `${this.timelineStateText(this.timelineStateMode())}，点击重试`
        : this.timelineStateText(this.timelineStateMode()));
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: this.floatDate !== '' ? 42 : 8 })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: -6 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  messageListStateLayer() {
    Column() {
      this.messageListState();
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ bottom: this.bottomChromeH + 28 })
    .hitTestBehavior(HitTestMode.Transparent);
  }

  @Builder
  chatBackgroundLayer() {
    Stack() {
      if (this.chatBackgroundColors.length > 0) {
        Column()
          .width('100%').height('100%')
          .linearGradient({
            angle: this.chatBackgroundAngle,
            colors: this.backgroundGradientStops()
          });
      } else {
        Column().width('100%').height('100%')
          .backgroundColor($r('app.color.chat_bg'));
      }
      if (this.chatBackgroundPath !== '') {
        Image(this.chatBackgroundPath.startsWith('/')
          ? `file://${this.chatBackgroundPath}` : this.chatBackgroundPath)
          .width('100%').height('100%')
          .objectFit(ImageFit.Cover)
          .opacity(this.chatBackgroundImageOpacity)
          // Blurring needs a little overscan or transparent edge pixels become
          // visible around the viewport.
          .scale({
            x: this.chatBackgroundBlurred ? 1.08 : 1,
            y: this.chatBackgroundBlurred ? 1.08 : 1
          })
          .blur(this.chatBackgroundBlurred ? 12 : 0);
      }
      if (this.chatBackgroundDimming > 0) {
        Column().width('100%').height('100%')
          .backgroundColor(Color.Black)
          .opacity(this.chatBackgroundDimming);
      }
    }
    .width('100%').height('100%')
    .hitTestBehavior(HitTestMode.None);
  }

  @Builder
  chatPowerBackground() {
    Stack() {
      this.chatBackgroundLayer();
      if (this.backgroundEffectsEnabled()) {
        Circle({ width: 250, height: 250 })
          .fill('#142A9FE8')
          .position({ x: this.powerBackgroundPhase ? this.screenW - 150 : -90, y: 110 })
          .opacity(this.powerBackgroundPhase ? 0.42 : 0.18)
          .animation({
            duration: this.chatEffectDuration(KEY_POWER_EFFECT_BACKGROUND, 4200),
            curve: Curve.EaseInOut
          });
        Circle({ width: 210, height: 210 })
          .fill('#1056C76F')
          .position({ x: this.powerBackgroundPhase ? -70 : this.screenW - 130, y: 500 })
          .opacity(this.powerBackgroundPhase ? 0.16 : 0.36)
          .animation({
            duration: this.chatEffectDuration(KEY_POWER_EFFECT_BACKGROUND, 4200),
            curve: Curve.EaseInOut
          });
      }
      if (this.particlesEnabled()) {
        ForEach(this.powerParticleIds, (id: number) => {
          Circle({ width: 3 + (id % 3), height: 3 + (id % 3) })
            .fill(id % 2 === 0 ? '#462A9FE8' : '#3D56C76F')
            .position({
              x: 22 + ((id * 67 + (this.powerBackgroundPhase ? 34 : 0)) % Math.max(40, this.screenW - 44)),
              y: 120 + ((id * 151 + (this.powerBackgroundPhase ? 90 : 0)) % 650)
            })
            .opacity(this.powerBackgroundPhase ? 0.2 + (id % 3) * 0.12 : 0.48 - (id % 3) * 0.08)
            .animation({ duration: powerAnimationDuration(KEY_POWER_PARTICLES, 4200), curve: Curve.EaseInOut });
        }, (id: number): string => `power_particle_${id}`);
      }
    }
    .width('100%').height('100%')
    .hitTestBehavior(HitTestMode.None);
  }

  build() {
    Stack() {
      this.chatPowerBackground();
      Column() {
        Stack() {
        List({ scroller: this.scroller }) {
          // LazyForEach (not ForEach) is required for maintainVisibleContentPosition
          // to hold the scroll position when older pages are prepended above.
          LazyForEach(this.groupsData, (g: AlbumGroup) => {
            ListItem() {
              Stack({ alignContent: Alignment.Start }) {
              // Selection mode shifts the row right into a left check gutter
              // (instead of overlaying the check on the avatars).
              Row() {
              if (this.selecting && g.head.contentType !== 'system' && g.head.contentType !== 'hidden') {
                Column() {
                  if (this.rowSelected(g)) {
                    SymbolGlyph($r('sys.symbol.checkmark_circle'))
                      .fontSize(22).fontColor([COLOR_PRIMARY]);
                  } else {
                    Row()
                      .width(20).height(20).borderRadius(10)
                      .border({ width: 1.5, color: '#8E8E93' });
                  }
                }
                .width(34)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center);
              }
              Column() {
              MessageBubble({ msg: g.head, nowSec: this.nowSec, isGroup: this.isGroup, isChannel: this.isChannel,
                liveSharingId: this.liveLocationMessageId,
                onStopLiveLocation: (): void => { this.confirmStopLiveLocation(); },
                themeBubbleOut: this.themeBubbleOutColor,
                showUnreadDivider: this.firstUnreadId !== 0 &&
                  g.memberIds.indexOf(this.firstUnreadId) >= 0,
                dateLabel: g.dateLabel,
                albumPaths: g.photoPaths, albumFileIds: g.photoFileIds, albumRatios: g.photoRatios,
                albumMemberIds: g.memberIds, albumIsVideo: g.photoIsVideo,
                albumProgress: g.photoProgress, albumFailed: g.photoFailed,
                albumCaption: g.caption,
                albumCaptionEntities: g.captionEntities,
                onMediaTap: (id: number, x: number, y: number): void => {
                  this.tapX = x;
                  this.tapY = y;
                  this.openViewer(id);
                },
                onLinkTap: (u: string): void => { this.onLinkTap(u); },
                onCommentTap: (id: number): void => { this.onCommentTap(id); },
                onForwardTap: (cid: number, mid: number, uid: number): void => {
                  this.onForwardTap(cid, mid, uid);
                },
                onBotCallback: (id: number, data: string): void => { this.onBotCallback(id, data); },
                onAvatarTap: (uid: number): void => {
                  const params: Record<string, Object> = { 'userId': uid };
                  router.pushUrl({ url: 'pages/profile/ProfilePage', params: params });
                },
                onReplyTap: (id: number): void => { this.onReplyTap(id); },
                onEditMsg: (id: number): void => { this.startEdit(id); },
                onShowReactors: (id: number, emoji: string): void => {
                  this.showReactors(id, emoji);
                },
                onTranslateMsg: (id: number): void => { this.translateMessage(id); },
                onPinMsg: (id: number, unpin: boolean): void => { this.togglePinMessage(id, unpin); },
                onStopPoll: (id: number): void => { this.stopPoll(id); },
                onReplaceMedia: (id: number): void => { this.replaceMedia(id); },
                onPollVoters: (id: number): void => { this.showPollVoters(id); },
                onSetDefaultReaction: (emoji: string): void => { this.setDefaultReaction(emoji); },
                isPinnedMsg: (this.store?.getPinnedIds() ?? []).indexOf(g.head.id) >= 0,
                onFileTap: (id: number): void => { this.onFileTap(id); },
                onFileSave: (id: number): void => { this.onFileSave(id); },
                onStickerRetry: (id: number): void => { this.store?.retrySticker(id); },
                onLinkPreviewRetry: (id: number): void => { this.store?.retryLinkPreviewPhoto(id); },
                onContactOpen: (userId: number, phone: string, vcard: string): void => {
                  this.openSharedContact(userId, phone, vcard);
                },
                onPhoneOpen: (phone: string): void => { this.openSharedPhone(phone); },
                onLocationOpen: (
                  latitude: number,
                  longitude: number,
                  label: string,
                  valid: boolean
                ): void => {
                  this.openSharedLocation(latitude, longitude, label, valid);
                },
                onPollVote: (id: number, optionIds: number[]): void => {
                  this.onPollVote(id, optionIds);
                },
                onGameOpen: (id: number): void => { this.onGameOpen(id); },
                onGamePhotoRetry: (id: number): void => { this.store?.retryPhoto(id); },
                paidMediaPending: this.paidMediaPending(g.head.id),
                onPaidMediaUnlock: (id: number): void => {
                  this.onPaidMediaUnlock(id);
                },
                onPaidMediaOpen: (id: number): void => {
                  this.onPaidMediaOpen(id);
                },
                onSpecialPhotoRetry: (id: number): void => {
                  this.store?.retryPhoto(id);
                },
                onGiftCodeCopy: (code: string): void => {
                  this.onGiftCodeCopy(code);
                },
                onGiveawayOpen: (chatId: number, messageId: number): void => {
                  this.onGiveawayOpen(chatId, messageId);
                },
                onVoiceTap: (id: number): void => { this.onVoiceTap(id); },
                onVoicePlaybackStarted: (id: number): void => {
                  this.onVoicePlaybackStarted(id);
                },
                audioQueuePosition: this.musicQueuePosition(g.head.id),
                audioQueueLength: this.musicQueueLength(),
                audioHasPrevious: this.musicHasPrevious(g.head.id),
                audioHasNext: this.musicHasNext(g.head.id),
                onAudioTap: (id: number): void => { this.onAudioTap(id); },
                onAudioPrevious: (id: number): void => { this.onAudioPrevious(id); },
                onAudioNext: (id: number): void => { this.onAudioNext(id); },
                onAudioSeek: (id: number, fraction: number): void => {
                  this.onAudioSeek(id, fraction);
                },
                onAutoplayVideoNeedDownload: (id: number): void => {
                  this.store?.requestVideoDownload(id);
                },
                animationPaused: this.animationPaused(g.head.id),
                animationForcePlay: this.animationForcePlay(g.head.id),
                animationPlaybackFailed: this.animationPlaybackFailed(g.head.id),
                onAnimationTap: (id: number, playing: boolean): void => {
                  this.onAnimationTap(id, playing);
                },
                onAnimationPlaybackFailed: (id: number): void => {
                  this.onAnimationPlaybackFailed(id);
                },
                onSetReaction: (id: number, emoji: string, chosen: boolean): void => { this.toggleReaction(id, emoji, chosen); },
                onReplyTo: (id: number): void => { this.startReply(id); },
                onCopyText: (id: number): void => { this.copyMessageText(id); },
                onCopyCode: (text: string): void => { this.copyPlainText(text, '代码已复制'); },
                onCopyLink: (id: number): void => { this.copyMessageLink(id); },
                onForwardMsg: (_id: number): void => { this.openForwardPicker(g.memberIds); },
                onReportMsg: (id: number): void => { promptAction.showToast({ message: '举报功能开发中', duration: 1500 }); },
                onSelectMsg: (id: number): void => { this.enterSelect(id); },
                onOpenReactions: (id: number): void => { this.openReactionSheet(id); },
                onRecognizeSpeech: (id: number): void => { this.recognizeSpeech(id); },
                onVideoNoteDownload: (id: number): void => {
                  this.store?.requestVideoDownload(id, true);
                },
                liveGroupCallId: this.liveCallIsActive ? this.liveGroupCallId : 0,
                // Reuses the same navigation as the "正在直播" banner (onLiveStreamTap
                // already reads this.liveGroupCallId and no-ops if it's gone stale).
                onLiveStreamTap: (): void => { this.onLiveStreamTap(); },
                showAvatar: g.showAvatar,
                showSenderName: g.showSenderName,
                animateIn: this.freshSinceId !== 0 && g.head.id > this.freshSinceId });
              }
              .layoutWeight(1);
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .backgroundColor(this.selecting && this.rowSelected(g) ? $r('app.color.select_highlight') : Color.Transparent)
              .animation({
                duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 150),
                curve: Curve.EaseOut
              })
              // Selection mode: the row itself takes every tap (children are
              // excluded from hit-testing), so any tap toggles selection.
              .hitTestBehavior(this.selecting && g.head.contentType !== 'system' && g.head.contentType !== 'hidden'
                ? HitTestMode.Block : HitTestMode.Default)
              .onClick(() => {
                if (this.selecting) {
                  this.toggleSelectRow(g);
                }
              });
              }
            }
          }, (g: AlbumGroup): string =>
            `message_group_${g.head.id}_${g.memberIds.join('_')}`);
        }
        .width('100%').height('100%')
        // 顶部 chrome 是悬浮的，用 contentStartOffset 让位——和底部的
        // contentEndOffset 对称。不用 padding：padding 会改变内容区尺寸，
        // 而滚动锚点、getItemRect 那一套都吃列表几何。
        .contentStartOffset(this.headerChromeH)
        // 消息滑到标题栏下面时逐渐糊掉，而不是被一条硬边切断。
        // 省电模式下关掉——渐变模糊是逐帧实时渲染，代价不低。
        .linearGradientBlur(this.headerBlurRadius(), {
          fractionStops: this.headerBlurStops(),
          direction: GradientDirection.Bottom
        })
        .contentEndOffset(this.bottomChromeH + 8)
        // Pre-build a few offscreen rows so a fling doesn't pay the full
        // MessageBubble construction cost inside the visible frame.
        .cachedCount(4)
        // Keep the visible messages pinned in place when an older page is
        // prepended above — without this, the List stays index-anchored and
        // visibly jumps to the top of the newly loaded page.
        .maintainVisibleContentPosition(true)
        .onReachStart(() => { this.maybeLoadOlder(); })
        // Each new touch gesture re-arms one older-page load: a fling that ends
        // pinned at the very top (start index never leaves the trigger zone)
        // would otherwise never re-arm, leaving the user unable to load more.
        .onTouch((e: TouchEvent) => {
          if (e.type === TouchType.Down) {
            // A real gesture transfers scroll ownership to the user; never
            // snap back to the bottom while they inspect older messages.
            this.imeTailPinned = false;
            this.imeLayoutSeq++;
            this.listTouchActive = true;
            this.olderArmed = true;
            // The highlight overlay is viewport-anchored — drop it as soon as
            // the user starts interacting, before it can detach from its row.
            this.cancelFlash();
            // Tapping outside the emoji/sticker panel dismisses it.
            this.setEmojiPanel(false);
          } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
            this.listTouchActive = false;
          }
        })
        .onScrollIndex((start: number, end: number) => {
          this.refreshAtBottom();
          this.curStartIdx = start;
          this.markVisibleRead(end);
          this.updatePinnedFromScroll(start);
          // Prefetch: kick off the previous/next page a few rows before the edge,
          // so scrolling never actually hits an empty top/bottom. loadOlder is
          // one-shot per arm (see maybeLoadOlder) so a fling that stays pinned
          // at the top can't chain-load page after page.
          if (start > 4) {
            this.olderArmed = true; // moved clear of the top zone — re-arm
          } else {
            this.maybeLoadOlder();
          }
          if (this.store !== null && end >= this.groups.length - 5) {
            this.store.loadNewer();
          }
        })
        // onScrollIndex only fires when the visible index RANGE changes, so
        // scrolling up inside one tall last message (index unchanged) never
        // updates atBottom. onDidScroll fires on every scroll frame — track the
        // true bottom edge here so the glue stops fighting the user.
        .onDidScroll(() => {
          this.refreshAtBottom();
          if (this.listTouchActive) {
            // A tap alone does not release the initial unread anchor. Only an
            // actual drag gives scroll ownership to the user.
            if (this.stayAtUnread) {
              this.stayAtUnread = false;
            }
            if (!this.listUserScrollActive) {
              this.listUserScrollActive = true;
            }
          }
          if (this.listUserScrollActive) {
            this.updateFloatDate(this.curStartIdx);
          }
        });
        if (this.visibleGroupCount === 0) {
          this.messageListStateLayer();
        } else if (this.timelineStateMode() !== '') {
          this.timelineStatePill();
        }
        // Jump-target highlight overlay (gentle double blink over the row a
        // reply/pinned/link jump just landed on). Coordinates come from
        // scroller.getItemRect, which is relative to the List — hence the Stack.
        if (this.flashShown) {
          Column()
            .width('100%').height(this.flashHeight)
            .backgroundColor('#4D67A0DC')
            .borderRadius(8)
            .opacity(this.flashAlpha)
            .position({ x: 0, y: this.flashTop })
            .hitTestBehavior(HitTestMode.None);
        }
        // Floating date chip at the top of the viewport — tracks the topmost
        // visible message while scrolling, fades away when scrolling stops.
        if (this.floatDate !== '') {
          Row() {
            Row() {
              Text(this.floatDate)
                .fontSize(12)
                .fontColor(COLOR_TEXT_PRIMARY)
                .fontWeight(FontWeight.Medium);
            }
            .height(28)
            .padding({ left: 12, right: 12 })
            .backgroundColor($r('app.color.surface'))
            .border({ width: 0.5, color: $r('app.color.divider') })
            .borderRadius(14)
            .shadow({ radius: 5, color: '#22000000', offsetX: 0, offsetY: 2 });
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .margin({ top: this.headerChromeH + 8 })
          .opacity(this.floatDateShown ? 1 : 0)
          .scale({ x: this.floatDateShown ? 1 : 0.9, y: this.floatDateShown ? 1 : 0.9 })
          .translate({ y: this.floatDateShown ? 0 : -5 })
          .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 200), curve: Curve.EaseOut })
          .hitTestBehavior(HitTestMode.None);
        }
        Column() {
          if (this.membershipState === 'writable' && !this.showEmojiPanel && !this.replyKbVisible() &&
            (this.mentionItems.length > 0 || this.commandPanelActive())) {
            this.suggestionPanel();
          }
          if (this.membershipState === 'writable' && !this.showEmojiPanel &&
            this.mentionItems.length === 0 && !this.commandPanelActive() &&
            this.inlineResults.length > 0) {
            this.inlineResultsBar();
          }
          if (this.membershipState === 'writable' && !this.showEmojiPanel &&
            this.mentionItems.length === 0 && !this.commandPanelActive() &&
            this.inlineResults.length === 0 && this.stickerSuggestions.length > 0) {
            this.stickerSuggestionBar();
          }
          this.bottomDock();
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.End)
        .hitTestBehavior(HitTestMode.None);

        // 顶部 chrome 放在最后 = 叠在最上层，消息从它下面穿过去。
        Column() {
          if (this.selecting) {
            this.selectionHeader();
          } else if (this.searchMode) {
            this.searchHeader();
          } else {
            this.header();
          }
          if (this.topCardShouldShow()) {
            this.topBanners();
          }
        }
        .width('100%')
        .onAreaChange((_old: Area, area: Area): void => {
          const h: number = area.height as number;
          if (Math.abs(h - this.headerChromeH) > 0.5) {
            this.headerChromeH = h;
          }
        });
        }
        .layoutWeight(1).width('100%')
        .alignContent(Alignment.TopStart)
        // RESIZE changes this viewport in step with the system keyboard. The
        // area callback runs after the new List height is known, so pinning
        // here keeps message and composer motion visually locked together.
        .onAreaChange((_old: Area, area: Area) => {
          const h: number = area.height as number;
          if (Math.abs(h - this.listViewportH) > 0.5) {
            this.listViewportH = h;
          }
          if (this.keyboardH > 0 && this.imeTailPinned) {
            this.syncTailOnImeFrame();
          }
        });
      }
      .width('100%').height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .backgroundColor(Color.Transparent);

      // 贴纸飞出的残影。叠在最外层、不参与命中测试，纯视觉。
      if (this.stickerGhostPath !== '') {
        Image(this.stickerGhostPath)
          .width(STICKER_GHOST_SIDE).height(STICKER_GHOST_SIDE)
          .objectFit(ImageFit.Contain)
          .draggable(false)
          .position({
            x: this.stickerGhostX - STICKER_GHOST_SIDE / 2,
            y: this.stickerGhostY - STICKER_GHOST_SIDE / 2
          })
          .scale({
            x: this.stickerGhostFly ? 0.34 : 1,
            y: this.stickerGhostFly ? 0.34 : 1
          })
          .translate({ y: this.stickerGhostFly ? -170 : 0 })
          .opacity(this.stickerGhostFly ? 0 : 0.95)
          .animation({ duration: STICKER_FLY_MS, curve: Curve.FastOutSlowIn })
          .hitTestBehavior(HitTestMode.None);
      }

      // Emoji/sticker panel OVERLAYS the chat (not in the layout flow): the
      // message list keeps its height, so its scrollbar/FAB stay put, and the
      // open/close animation doesn't relayout the LazyForEach every frame.
      if (this.showEmojiPanel && this.membershipState === 'writable') {
        // Full-height wrapper only positions the panel above the input bar;
        // Transparent hit-testing lets taps outside the panel reach the list.
        Column() {
          Column() {
            if (this.panelContentReady) {
              EmojiPanel({
                tab: $emojiPanelTab,
                onPick: (e: string): void => { this.insertEmoji(e); },
                onPickCustomEmoji: (e: string, ceId: string): void => {
                  if (this.store !== null) {
                    this.atBottom = true;
                    this.store.sendCustomEmoji(e, ceId);
                    this.finishStickerSend('', 0, 0);
                  }
                },
                onPickSticker: (s: StickerItem, x: number, y: number): void => {
                  if (this.store !== null) {
                    this.atBottom = true;
                    this.store.sendSticker(s.fileId, s.width, s.height);
                    this.finishStickerSend(s.thumbPath, x, y);
                  }
                },
                onPickGif: (g: GifItem): void => {
                  if (this.store !== null) {
                    this.atBottom = true;
                    this.store.sendAnimation(g.fileId, g.width, g.height, g.duration);
                    this.finishStickerSend('', 0, 0);
                  }
                }
              });
            } else if (!this.emojiPanelClosing) {
              Column({ space: 8 }) {
                LoadingProgress().width(26).height(26).color(COLOR_PRIMARY);
                Text('正在打开面板').fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
              }
              .width('100%').height('100%')
              .justifyContent(FlexAlign.Center);
            }
          }
          .width('calc(100% - 16vp)').height(300)
          .backgroundColor($r('app.color.surface'))
          .border({ width: { top: 0.7 }, color: $r('app.color.divider') })
          .borderRadius(18)
          .clip(true)
          .shadow({ radius: 8, color: '#1A000000', offsetX: 0, offsetY: -2 })
          // 只做位移 + 淡出，不做 scale。缩放一个 300px 高、带 clip 和阴影的
          // 复杂子树，每帧都要重新栅格化 —— 系统 jank 事件实测这一下 80ms，
          // 而卸载内容本身是 0ms。位移和透明度是纯合成操作，不触发重栅格化。
          .transition(TransitionEffect.translate({ y: 18 })
            .combine(TransitionEffect.OPACITY)
            .animation({ duration: this.chatEffectDuration(KEY_POWER_EFFECT_MENU, 220), curve: Curve.EaseOut }));
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.End).alignItems(HorizontalAlign.Center)
        .padding({ bottom: this.bottomChromeH + 6 })
        // None (not Transparent): the wrapper itself never hit-tests, so the
        // panel child blocks touches over its own area (Transparent leaked
        // panel taps through to the list, whose onTouch dismissed the panel),
        // while the area outside the panel still reaches the list/input bar.
        .hitTestBehavior(HitTestMode.None);
      }
      if (this.showReactionSheet) {
        this.reactionSheet();
      }
      if (this.showForwardSheet) {
        this.forwardSheet();
      }
      if (this.showScheduledSheet) {
        this.scheduledSheet();
      }
      if (this.showPollSheet) {
        PollComposeSheet({
          onSubmit: (question: string, options: string[], isAnonymous: boolean,
            isQuiz: boolean, correctOptionId: number): void => {
            this.showPollSheet = false;
            if (this.store !== null) {
              this.atBottom = true;
              this.store.sendPoll(question, options, isAnonymous, isQuiz, correctOptionId);
            }
          },
          onClose: (): void => {
            this.showPollSheet = false;
          }
        });
      }
      if (this.showContactSheet) {
        ContactPickerSheet({
          onPick: (contact: PickedContact): void => {
            this.showContactSheet = false;
            if (this.store !== null) {
              this.atBottom = true;
              this.store.sendContact(
                contact.phone, contact.firstName, contact.lastName, contact.userId);
            }
          },
          onClose: (): void => {
            this.showContactSheet = false;
          }
        });
      }
      if (this.showVideoNoteRecorder) {
        VideoNoteRecorderView({
          onCaptured: (path: string, durationSec: number, length: number): void => {
            if (this.store !== null) {
              this.atBottom = true;
              this.store.sendVideoNote(path, durationSec, length);
            }
          },
          onClose: (): void => {
            this.showVideoNoteRecorder = false;
          }
        });
      }
      // The latest-message FAB belongs to the chat layer. Keeping it visible
      // while the media panel is open puts it above (and blocks) the GIF tab.
      if (!this.atBottom && !this.searchMode && !this.showEmojiPanel) {
        Column() {
          this.scrollFab();
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.End).alignItems(HorizontalAlign.End)
        .padding({ right: 14, bottom: this.bottomChromeH + 8 })
        .hitTestBehavior(HitTestMode.Transparent);
      }

      if (this.viewerMsgId !== 0) {
        Stack() {
          this.viewerContent();
          if (this.chromeVisible) {
            // Content-height wrapper pinned to the top — a full-screen wrapper here
            // (default hit-test mode) would block ALL touches on the player below it.
            Row() {
              Row({ space: 10 }) {
                Stack() {
                  Circle({ width: 36, height: 36 }).fill('#12000000');
                  SymbolGlyph($r('sys.symbol.xmark')).fontSize(18).fontColor([Color.White]);
                }
                .width(40).height(40).borderRadius(20)
                .stateStyles({
                  normal: this.suggestionRowNormalStyle,
                  pressed: this.suggestionRowPressedStyle
                })
                .animation({
                  duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120),
                  curve: Curve.EaseOut
                })
                .onClick(() => { this.closeViewer(); });
                Column({ space: 1 }) {
                  Text(this.viewerInfoTitle()).fontSize(13).fontColor(Color.White).fontWeight(FontWeight.Medium)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    .constraintSize({ maxWidth: 220 });
                  if (this.viewerInfoSubtitle() !== '') {
                    Text(this.viewerInfoSubtitle()).fontSize(11).fontColor('#BFFFFFFF')
                      .maxLines(1);
                  }
                }
                .alignItems(HorizontalAlign.Start).flexShrink(1);
              }
              .padding({ left: 12, right: 14, top: 10, bottom: 10 })
              .backgroundColor(VIEWER_CHROME_BG)
              .borderRadius(18)
              .alignItems(VerticalAlign.Center)
              .flexShrink(1);
              Blank().layoutWeight(1).hitTestBehavior(HitTestMode.None);
              // No download indicator up here: the seek bar's lighter track shows
              // the downloaded span, and a stalled player draws a centered ring.
              // "⋮" menu — 保存到相册 etc.
              Stack() {
                Circle({ width: 36, height: 36 }).fill(VIEWER_CHROME_BG);
                SymbolGlyph($r('sys.symbol.more')).fontSize(18).fontColor([Color.White]);
              }
              .width(40).height(40).borderRadius(20)
              .stateStyles({
                normal: this.suggestionRowNormalStyle,
                pressed: this.suggestionRowPressedStyle
              })
              .animation({
                duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120),
                curve: Curve.EaseOut
              })
              .bindMenu([{
                value: '保存到相册',
                action: (): void => { this.saveViewerMedia(); }
              } as MenuElement]);
            }
            .width('100%')
            .position({ x: 0, y: 0 })
            .padding({ left: 12, right: 12, top: this.topSafe + 12 })
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.translate({ y: -8 }))
              .animation({
                duration: this.chatEffectDuration(KEY_POWER_EFFECT_BLUR, 180),
                curve: Curve.EaseOut
              }));
          }
          if (this.chromeVisible && this.viewerSiblingIds().length > 1) {
            Column() {
              this.viewerFilmstrip();
            }
            .width('100%').height('100%')
            .justifyContent(FlexAlign.End)
            .padding({ bottom: this.viewerIsVideo() ? 110 : 30 })
            .hitTestBehavior(HitTestMode.Transparent)
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.translate({ y: 10 }))
              .animation({
                duration: this.chatEffectDuration(KEY_POWER_EFFECT_BLUR, 180),
                curve: Curve.EaseOut
              }));
          }
        }
        .width('100%').height('100%').backgroundColor(Color.Black)
        // The fullscreen surface owns its transition. The chat thumbnail stays
        // mounted and decoded underneath, so closing can never leave that cell
        // as a grey/background placeholder or an empty Image node.
        .transition(
          TransitionEffect.scale({ x: 0.25, y: 0.25, centerX: this.tapX, centerY: this.tapY })
            .combine(TransitionEffect.OPACITY)
            .animation({ duration: this.chatEffectDuration(KEY_POWER_EFFECT_BLUR, 300), curve: Curve.Friction })
        )
      }
    }.width('100%').height('100%');
  }
}
