import { TdObject } from '../tdkit/TdTypes';
import { formatPreview } from './formatPreview';

export interface PollOptionInfo {
  text: string;
  voterCount: number;
  votePercentage: number;
  isChosen: boolean;
  isBeingChosen: boolean;
}

export interface MsgContent {
  contentType: string;
  text: string;
  photoFileId: number;
  photoWidth: number;
  photoHeight: number;
  placeholderLabel: string;
  entities: TdObject[];
  linkSiteName: string;
  linkTitle: string;
  linkDescription: string;
  linkDescriptionEntities: TdObject[];
  linkPhotoFileId: number;
  linkUrl: string;
  linkPreviewType?: string;
  linkPhotoWidth?: number;
  linkPhotoHeight?: number;
  linkPhotoLocalPath?: string;
  linkPhotoInitialProgress?: number;
  linkPhotoInitialActive?: boolean;
  videoDuration: number; // seconds, 0 for non-video content
  videoFileId: number;   // full-resolution video file id, 0 for non-video content
  videoFileSize: number; // bytes, 0 when unknown/non-video
  videoMimeType: string; // e.g. video/mp4, video/webm
  videoFileName: string; // original file name, '' when unknown/non-video
  photoFullFileId: number; // full-resolution photo file id, 0 when no upgrade exists
  isAnimation?: boolean;   // Telegram GIF/messageAnimation, not a normal video
  stickerFileId?: number;  // animated sticker source file (TGS), 0/absent otherwise
  customEmojiId?: string;  // single custom-emoji text message (resolved async)
  stickerFormat?: string;  // 'webp' | 'tgs' | 'webm', absent for non-stickers
  isEmojiSticker?: boolean; // messageAnimatedEmoji/custom emoji, not a regular sticker
  voiceWaveform?: string;  // base64 packed 5-bit waveform for voice notes
  voiceListened?: boolean; // TDLib messageVoiceNote.is_listened
  audioTitle?: string;     // messageAudio.audio.title
  audioPerformer?: string; // messageAudio.audio.performer
  photoLocalPath?: string; // already downloaded inline sticker/thumbnail
  photoInitialProgress?: number;
  photoInitialActive?: boolean;
  videoLocalPath?: string; // already downloaded TDLib file from history
  videoInitialProgress?: number;
  videoInitialActive?: boolean;
  stickerLocalPath?: string; // already downloaded TGS/WEBM sticker source
  stickerInitialProgress?: number;
  stickerInitialActive?: boolean;
  contactPhone?: string;
  contactFirstName?: string;
  contactLastName?: string;
  contactVcard?: string;
  contactUserId?: number;
  locationLatitude?: number;
  locationLongitude?: number;
  locationAccuracy?: number;
  locationValid?: boolean;
  locationLivePeriod?: number;
  locationExpiresIn?: number;
  locationHeading?: number;
  locationProximityRadius?: number;
  venueTitle?: string;
  venueAddress?: string;
  venueProvider?: string;
  venueId?: string;
  venueType?: string;
  pollId?: string;
  pollQuestion?: string;
  pollOptions?: PollOptionInfo[];
  pollTotalVoterCount?: number;
  pollIsAnonymous?: boolean;
  pollIsQuiz?: boolean;
  pollAllowMultiple?: boolean;
  pollCorrectOptionId?: number;
  pollExplanation?: string;
  pollOpenPeriod?: number;
  pollCloseDate?: number;
  pollIsClosed?: boolean;
  diceEmoji?: string;
  diceValue?: number;
  diceSuccessFrame?: number;
  diceHasFinalState?: boolean;
  diceLayerFileIds?: number[];
  diceLayerPaths?: string[];
  gameId?: string;
  gameShortName?: string;
  gameTitle?: string;
  gameDescription?: string;
  gameText?: string;
  paidMediaLocked?: boolean;
  paidMediaStarCount?: number;
  paidMediaCount?: number;
  paidMediaKind?: string;
  giftKind?: string;
  giftTitle?: string;
  giftValue?: string;
  giftStatus?: string;
  giftCode?: string;
  giftRefunded?: boolean;
  giveawayState?: string;
  giveawayWinnerCount?: number;
  giveawayPrize?: string;
  giveawayDescription?: string;
  giveawaySelectionDate?: number;
  giveawayUnclaimedCount?: number;
  giveawayMessageId?: number;
  giveawayBoostedChatId?: number;
  giveawayRefunded?: boolean;
  giveawayOnlyNewMembers?: boolean;
}

interface PhotoSize {
  fileId: number;
  width: number;
  height: number;
}

interface LocalFileState {
  path: string;
  progress: number;
  active: boolean;
}

function localFileState(file: TdObject | undefined): LocalFileState {
  if (file === undefined) {
    return { path: '', progress: 0, active: false };
  }
  const local = file['local'] as TdObject | undefined;
  if (local === undefined) {
    return { path: '', progress: 0, active: false };
  }
  const completed: boolean =
    (local['is_downloading_completed'] as boolean | undefined) ?? false;
  const path: string = (local['path'] as string | undefined) ?? '';
  const size: number = ((file['size'] as number | undefined) ?? 0) ||
    ((file['expected_size'] as number | undefined) ?? 0);
  const downloaded: number = (local['downloaded_size'] as number | undefined) ?? 0;
  return {
    path: completed && path !== '' ? path : '',
    progress: completed && path !== '' ? 100
      : (size > 0 ? Math.min(100, Math.floor((downloaded / size) * 100)) : 0),
    active: !completed &&
      ((local['is_downloading_active'] as boolean | undefined) ?? false)
  };
}

interface LinkPreviewInfo {
  siteName: string;
  title: string;
  description: string;
  descriptionEntities: TdObject[];
  photoFileId: number;
  photoWidth: number;
  photoHeight: number;
  photoPath: string;
  photoProgress: number;
  photoActive: boolean;
  typeName: string;
  url: string;
}

interface LinkPreviewImage {
  fileId: number;
  width: number;
  height: number;
  path: string;
  progress: number;
  active: boolean;
}

const EMPTY_LINK_PREVIEW_IMAGE: LinkPreviewImage = {
  fileId: 0, width: 0, height: 0, path: '', progress: 0, active: false
};

const EMPTY_LINK_PREVIEW: LinkPreviewInfo = {
  siteName: '', title: '', description: '', descriptionEntities: [],
  photoFileId: 0, photoWidth: 0, photoHeight: 0,
  photoPath: '', photoProgress: 0, photoActive: false,
  typeName: '', url: ''
};

function previewImageFromFile(file: TdObject | undefined, width: number = 0,
    height: number = 0): LinkPreviewImage {
  if (file === undefined) {
    return EMPTY_LINK_PREVIEW_IMAGE;
  }
  const fileId: number = (file['id'] as number | undefined) ?? 0;
  if (fileId === 0) {
    return EMPTY_LINK_PREVIEW_IMAGE;
  }
  const local: LocalFileState = localFileState(file);
  return {
    fileId, width, height,
    path: local.path, progress: local.progress, active: local.active
  };
}

// Preview cards should use a compact thumbnail instead of the largest photo.
// Besides faster initial display, this avoids competing with the message-media
// viewer for bandwidth when a history page contains several rich links.
function previewImageFromPhoto(photo: TdObject | undefined): LinkPreviewImage {
  if (photo === undefined) {
    return EMPTY_LINK_PREVIEW_IMAGE;
  }
  const sizes: TdObject[] = (photo['sizes'] as TdObject[] | undefined) ?? [];
  if (sizes.length > 0) {
    const size: TdObject = sizes[Math.min(1, sizes.length - 1)];
    return previewImageFromFile(
      size['photo'] as TdObject | undefined,
      (size['width'] as number | undefined) ?? 0,
      (size['height'] as number | undefined) ?? 0
    );
  }
  // linkPreviewTypeChat/User can carry chatPhoto rather than photo. The small
  // avatar is exactly the right source for an inline card.
  const small: TdObject | undefined = photo['small'] as TdObject | undefined;
  if (small !== undefined) {
    return previewImageFromFile(small);
  }
  return previewImageFromFile(photo['big'] as TdObject | undefined);
}

function previewImageFromThumbnail(thumbnail: TdObject | undefined): LinkPreviewImage {
  if (thumbnail === undefined) {
    return EMPTY_LINK_PREVIEW_IMAGE;
  }
  return previewImageFromFile(
    thumbnail['file'] as TdObject | undefined,
    (thumbnail['width'] as number | undefined) ?? 0,
    (thumbnail['height'] as number | undefined) ?? 0
  );
}

function previewImageFromMedia(media: TdObject | undefined): LinkPreviewImage {
  if (media === undefined) {
    return EMPTY_LINK_PREVIEW_IMAGE;
  }
  let image: LinkPreviewImage = previewImageFromPhoto(media['photo'] as TdObject | undefined);
  if (image.fileId !== 0) {
    return image;
  }
  image = previewImageFromThumbnail(media['thumbnail'] as TdObject | undefined);
  if (image.fileId !== 0) {
    return image;
  }
  image = previewImageFromThumbnail(media['album_cover_thumbnail'] as TdObject | undefined);
  if (image.fileId !== 0) {
    return image;
  }
  const nested: TdObject | undefined = media['media'] as TdObject | undefined;
  return nested !== undefined ? previewImageFromMedia(nested) : EMPTY_LINK_PREVIEW_IMAGE;
}

function previewImageOfType(previewType: TdObject | undefined): LinkPreviewImage {
  if (previewType === undefined) {
    return EMPTY_LINK_PREVIEW_IMAGE;
  }
  let image: LinkPreviewImage = previewImageFromPhoto(previewType['photo'] as TdObject | undefined);
  if (image.fileId !== 0) {
    return image;
  }
  const mediaKeys: string[] = [
    'video', 'animation', 'audio', 'document', 'sticker', 'video_note', 'voice_note'
  ];
  for (const key of mediaKeys) {
    image = previewImageFromMedia(previewType[key] as TdObject | undefined);
    if (image.fileId !== 0) {
      return image;
    }
  }
  image = previewImageFromThumbnail(previewType['thumbnail'] as TdObject | undefined);
  if (image.fileId !== 0) {
    return image;
  }
  const albumMedia: TdObject[] = (previewType['media'] as TdObject[] | undefined) ?? [];
  for (const item of albumMedia) {
    image = previewImageFromMedia(item);
    if (image.fileId !== 0) {
      return image;
    }
  }
  return EMPTY_LINK_PREVIEW_IMAGE;
}

// A URL/message-link preview attached to a text message (TDLib messageText.link_preview).
function parseLinkPreview(content: TdObject): LinkPreviewInfo {
  const lp = content['link_preview'] as TdObject | undefined;
  if (lp === undefined) {
    return EMPTY_LINK_PREVIEW;
  }
  const descFt = lp['description'] as TdObject | undefined;
  const lpType = lp['type'] as TdObject | undefined;
  const typeName = lpType !== undefined ? ((lpType['@type'] as string | undefined) ?? '') : '';
  const image: LinkPreviewImage = previewImageOfType(lpType);
  return {
    siteName: (lp['site_name'] as string | undefined) ?? '',
    title: (lp['title'] as string | undefined) ?? '',
    description: descFt !== undefined ? ((descFt['text'] as string | undefined) ?? '') : '',
    descriptionEntities: textEntities(descFt),
    photoFileId: image.fileId,
    photoWidth: image.width,
    photoHeight: image.height,
    photoPath: image.path,
    photoProgress: image.progress,
    photoActive: image.active,
    typeName,
    url: (lp['url'] as string | undefined) ?? ''
  };
}

function textEntities(ft: TdObject | undefined): TdObject[] {
  if (ft === undefined) {
    return [];
  }
  return (ft['entities'] as TdObject[] | undefined) ?? [];
}

function largestPhotoSize(photo: TdObject | undefined): PhotoSize {
  if (photo === undefined) {
    return { fileId: 0, width: 0, height: 0 };
  }
  const sizes = photo['sizes'] as TdObject[] | undefined;
  if (sizes === undefined || sizes.length === 0) {
    return { fileId: 0, width: 0, height: 0 };
  }
  const last = sizes[sizes.length - 1];
  const file = last['photo'] as TdObject | undefined;
  return {
    fileId: file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0,
    width: (last['width'] as number | undefined) ?? 0,
    height: (last['height'] as number | undefined) ?? 0
  };
}

// A smaller size for inline bubble display (fast to download); the largest
// size is downloaded separately, on demand, when the viewer is opened.
function inlinePhotoSize(photo: TdObject | undefined): PhotoSize {
  if (photo === undefined) {
    return { fileId: 0, width: 0, height: 0 };
  }
  const sizes = photo['sizes'] as TdObject[] | undefined;
  if (sizes === undefined || sizes.length === 0) {
    return { fileId: 0, width: 0, height: 0 };
  }
  const idx = Math.min(1, sizes.length - 1);
  const s = sizes[idx];
  const file = s['photo'] as TdObject | undefined;
  return {
    fileId: file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0,
    width: (s['width'] as number | undefined) ?? 0,
    height: (s['height'] as number | undefined) ?? 0
  };
}

// Caption of a media message (photo/video/etc.) — the text shown below the media.
function captionText(content: TdObject): string {
  const cap = content['caption'] as TdObject | undefined;
  if (cap === undefined) {
    return '';
  }
  return (cap['text'] as string | undefined) ?? '';
}

// A video's thumbnail image, used as its "photo" for grid/album/single display
// (actual playback is out of scope — the thumbnail + a play overlay stands in).
function videoThumbnail(video: TdObject | undefined): PhotoSize {
  if (video === undefined) {
    return { fileId: 0, width: 0, height: 0 };
  }
  const sourceWidth = (video['width'] as number | undefined) ?? 0;
  const sourceHeight = (video['height'] as number | undefined) ?? 0;
  const thumb = video['thumbnail'] as TdObject | undefined;
  if (thumb === undefined) {
    return { fileId: 0, width: sourceWidth, height: sourceHeight };
  }
  const file = thumb['file'] as TdObject | undefined;
  const thumbWidth = (thumb['width'] as number | undefined) ?? 0;
  const thumbHeight = (thumb['height'] as number | undefined) ?? 0;
  return {
    fileId: file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0,
    // Some TDLib messages contain a valid thumbnail file but report 0×0 for
    // its dimensions. Keep the video's source geometry so the chat bubble
    // doesn't flash square and then jump to 16:9 when playback starts.
    width: thumbWidth > 0 ? thumbWidth : sourceWidth,
    height: thumbHeight > 0 ? thumbHeight : sourceHeight
  };
}

function formattedTextValue(value: TdObject | undefined): string {
  return value !== undefined ? ((value['text'] as string | undefined) ?? '') : '';
}

function formatTonAmount(value: number): string {
  if (value <= 0) {
    return 'TON 数量未知';
  }
  const ton = value / 1_000_000_000;
  const fixed = ton.toFixed(3);
  const trimmed = fixed.replace(/\.?0+$/, '');
  return `${trimmed} TON`;
}

function stickerPreview(sticker: TdObject | undefined): MsgContent | null {
  return stickerMsgContent(sticker);
}

function giftBase(kind: string, title: string, value: string, status: string,
  text: string, sticker: TdObject | undefined): MsgContent {
  const media = stickerPreview(sticker);
  return {
    contentType: 'gift',
    text,
    photoFileId: media !== null ? media.photoFileId : 0,
    photoWidth: media !== null ? media.photoWidth : 0,
    photoHeight: media !== null ? media.photoHeight : 0,
    photoLocalPath: media !== null ? media.photoLocalPath : '',
    photoInitialProgress: media !== null ? media.photoInitialProgress : 0,
    photoInitialActive: media !== null ? media.photoInitialActive : false,
    placeholderLabel: '',
    entities: [],
    linkSiteName: '', linkTitle: '', linkDescription: '', linkDescriptionEntities: [],
    linkPhotoFileId: 0, linkUrl: '',
    videoDuration: 0, videoFileId: 0, videoFileSize: 0, videoMimeType: '',
    videoFileName: '', photoFullFileId: 0,
    giftKind: kind, giftTitle: title, giftValue: value, giftStatus: status
  };
}

function giveawayPrizeText(prize: TdObject | undefined): string {
  if (prize === undefined) {
    return '奖品信息暂不可用';
  }
  const type = (prize['@type'] as string | undefined) ?? '';
  if (type === 'giveawayPrizePremium') {
    const months = Math.max(0, (prize['month_count'] as number | undefined) ?? 0);
    return months > 0 ? `${months} 个月 Telegram Premium` : 'Telegram Premium';
  }
  if (type === 'giveawayPrizeStars') {
    const stars = Math.max(0, (prize['star_count'] as number | undefined) ?? 0);
    return stars > 0 ? `${stars} 颗 Telegram 星星` : 'Telegram 星星';
  }
  return 'Telegram 抽奖奖品';
}

function giveawayBase(state: string, winnerCount: number, prize: string,
  description: string, selectionDate: number, unclaimedCount: number,
  giveawayMessageId: number, boostedChatId: number, refunded: boolean,
  onlyNewMembers: boolean, sticker: TdObject | undefined): MsgContent {
  const media = stickerPreview(sticker);
  return {
    contentType: 'giveaway', text: '',
    photoFileId: media !== null ? media.photoFileId : 0,
    photoWidth: media !== null ? media.photoWidth : 0,
    photoHeight: media !== null ? media.photoHeight : 0,
    photoLocalPath: media !== null ? media.photoLocalPath : '',
    photoInitialProgress: media !== null ? media.photoInitialProgress : 0,
    photoInitialActive: media !== null ? media.photoInitialActive : false,
    placeholderLabel: '', entities: [],
    linkSiteName: '', linkTitle: '', linkDescription: '', linkDescriptionEntities: [],
    linkPhotoFileId: 0, linkUrl: '',
    videoDuration: 0, videoFileId: 0, videoFileSize: 0, videoMimeType: '',
    videoFileName: '', photoFullFileId: 0,
    giveawayState: state,
    giveawayWinnerCount: Math.max(0, winnerCount),
    giveawayPrize: prize,
    giveawayDescription: description,
    giveawaySelectionDate: Math.max(0, selectionDate),
    giveawayUnclaimedCount: Math.max(0, unclaimedCount),
    giveawayMessageId: Math.max(0, giveawayMessageId),
    giveawayBoostedChatId: boostedChatId,
    giveawayRefunded: refunded,
    giveawayOnlyNewMembers: onlyNewMembers
  };
}

export function formatMsgContent(message: TdObject): MsgContent {
  const content = message['content'] as TdObject | undefined;
  const type = content !== undefined ? (content['@type'] as string | undefined) : undefined;
  if (type === 'messageText') {
    const ft = content!['text'] as TdObject | undefined;
    const text = ft !== undefined ? ((ft['text'] as string | undefined) ?? '') : '';
    const lp: LinkPreviewInfo = parseLinkPreview(content!);
    // A message that is exactly one custom emoji renders as an animated
    // sticker (like the official client), not as its fallback character.
    const ents = textEntities(ft);
    if (ents.length === 1) {
      const et = ents[0]['type'] as TdObject | undefined;
      const etName = et !== undefined ? ((et['@type'] as string | undefined) ?? '') : '';
      const off = (ents[0]['offset'] as number | undefined) ?? -1;
      const len = (ents[0]['length'] as number | undefined) ?? 0;
      if (etName === 'textEntityTypeCustomEmoji') {
        console.info(`formatMsgContent customEmoji cand: off=${off} len=${len} textLen=${text.length}`);
      }
      const customEmojiId = et !== undefined ? `${et['custom_emoji_id'] ?? ''}` : '';
      if (etName === 'textEntityTypeCustomEmoji' && customEmojiId !== '' &&
        off === 0 && len >= text.length - 1 && len <= text.length) {
        return {
          contentType: 'customEmoji', text, photoFileId: 0, photoWidth: 0, photoHeight: 0,
          placeholderLabel: '', entities: [],
          customEmojiId,
          linkSiteName: '', linkTitle: '', linkDescription: '', linkDescriptionEntities: [],
          linkPhotoFileId: 0, linkUrl: '',
          videoDuration: 0, videoFileId: 0, videoFileSize: 0, videoMimeType: '', videoFileName: '', photoFullFileId: 0
        };
      }
    }
    return {
      contentType: 'text', text, photoFileId: 0, photoWidth: 0, photoHeight: 0, placeholderLabel: '', entities: textEntities(ft),
      linkSiteName: lp.siteName, linkTitle: lp.title, linkDescription: lp.description,
      linkDescriptionEntities: lp.descriptionEntities, linkPhotoFileId: lp.photoFileId, linkUrl: lp.url,
      linkPreviewType: lp.typeName,
      linkPhotoWidth: lp.photoWidth, linkPhotoHeight: lp.photoHeight,
      linkPhotoLocalPath: lp.photoPath, linkPhotoInitialProgress: lp.photoProgress,
      linkPhotoInitialActive: lp.photoActive,
      videoDuration: 0, videoFileId: 0, videoFileSize: 0, videoMimeType: '', videoFileName: '', photoFullFileId: 0
    };
  }
  if (type === 'messagePhoto') {
    const photo = content!['photo'] as TdObject | undefined;
    const size: PhotoSize = inlinePhotoSize(photo);
    const full: PhotoSize = largestPhotoSize(photo);
    return {
      contentType: 'photo',
      text: captionText(content!),
      photoFileId: size.fileId,
      photoWidth: size.width,
      photoHeight: size.height,
      placeholderLabel: '',
      entities: textEntities(content!['caption'] as TdObject | undefined),
      linkSiteName: '', linkTitle: '', linkDescription: '', linkDescriptionEntities: [], linkPhotoFileId: 0, linkUrl: '',
      videoDuration: 0, videoFileId: 0, videoFileSize: 0, videoMimeType: '', videoFileName: '', photoFullFileId: full.fileId !== size.fileId ? full.fileId : 0
    };
  }
  if (type === 'messageVideo') {
    const video = content!['video'] as TdObject | undefined;
    const size: PhotoSize = videoThumbnail(video);
    const videoFile = video !== undefined ? (video['video'] as TdObject | undefined) : undefined;
    const videoSize = videoFile !== undefined ? (((videoFile['size'] as number | undefined) ?? 0) || ((videoFile['expected_size'] as number | undefined) ?? 0)) : 0;
    return {
      contentType: 'video',
      text: captionText(content!),
      photoFileId: size.fileId,
      photoWidth: size.width,
      photoHeight: size.height,
      placeholderLabel: '',
      entities: textEntities(content!['caption'] as TdObject | undefined),
      linkSiteName: '', linkTitle: '', linkDescription: '', linkDescriptionEntities: [], linkPhotoFileId: 0, linkUrl: '',
      videoDuration: video !== undefined ? ((video['duration'] as number | undefined) ?? 0) : 0,
      videoFileId: videoFile !== undefined ? ((videoFile['id'] as number | undefined) ?? 0) : 0,
      videoFileSize: videoSize,
      videoMimeType: video !== undefined ? ((video['mime_type'] as string | undefined) ?? '') : '',
      videoFileName: video !== undefined ? ((video['file_name'] as string | undefined) ?? '') : '',
      photoFullFileId: 0
    };
  }
  // GIFs (messageAnimation) are MP4 loops — render through the video pipeline
  // (thumbnail + tap to play fullscreen).
  if (type === 'messageAnimation') {
    const anim = content!['animation'] as TdObject | undefined;
    const size: PhotoSize = videoThumbnail(anim);
    const animFile = anim !== undefined ? (anim['animation'] as TdObject | undefined) : undefined;
    const animSize = animFile !== undefined
      ? (((animFile['size'] as number | undefined) ?? 0) || ((animFile['expected_size'] as number | undefined) ?? 0)) : 0;
    return {
      contentType: 'video',
      isAnimation: true,
      text: captionText(content!),
      photoFileId: size.fileId,
      photoWidth: size.width,
      photoHeight: size.height,
      placeholderLabel: '',
      entities: textEntities(content!['caption'] as TdObject | undefined),
      linkSiteName: '', linkTitle: '', linkDescription: '', linkDescriptionEntities: [], linkPhotoFileId: 0, linkUrl: '',
      videoDuration: anim !== undefined ? ((anim['duration'] as number | undefined) ?? 0) : 0,
      videoFileId: animFile !== undefined ? ((animFile['id'] as number | undefined) ?? 0) : 0,
      videoFileSize: animSize,
      videoMimeType: anim !== undefined ? ((anim['mime_type'] as string | undefined) ?? '') : '',
      videoFileName: anim !== undefined ? ((anim['file_name'] as string | undefined) ?? '') : '',
      photoFullFileId: 0
    };
  }
  // Voice notes also reuse the video* slots (duration / file id / size / mime
  // / local path once downloaded).
  if (type === 'messageVoiceNote') {
    const vn = content!['voice_note'] as TdObject | undefined;
    const voiceFile = vn !== undefined ? (vn['voice'] as TdObject | undefined) : undefined;
    const voiceSize = voiceFile !== undefined
      ? (((voiceFile['size'] as number | undefined) ?? 0) || ((voiceFile['expected_size'] as number | undefined) ?? 0)) : 0;
    return {
      contentType: 'voice',
      text: captionText(content!),
      photoFileId: 0, photoWidth: 0, photoHeight: 0,
      placeholderLabel: '',
      entities: textEntities(content!['caption'] as TdObject | undefined),
      linkSiteName: '', linkTitle: '', linkDescription: '', linkDescriptionEntities: [], linkPhotoFileId: 0, linkUrl: '',
      videoDuration: vn !== undefined ? ((vn['duration'] as number | undefined) ?? 0) : 0,
      videoFileId: voiceFile !== undefined ? ((voiceFile['id'] as number | undefined) ?? 0) : 0,
      videoFileSize: voiceSize,
      videoMimeType: vn !== undefined ? ((vn['mime_type'] as string | undefined) ?? '') : '',
      videoFileName: '',
      photoFullFileId: 0,
      voiceWaveform: vn !== undefined ? ((vn['waveform'] as string | undefined) ?? '') : '',
      voiceListened: (content!['is_listened'] as boolean | undefined) ?? false
    };
  }
  if (type === 'messageAudio') {
    const audio = content!['audio'] as TdObject | undefined;
    const audioFile = audio !== undefined ? (audio['audio'] as TdObject | undefined) : undefined;
    const cover = audio !== undefined
      ? (audio['album_cover_thumbnail'] as TdObject | undefined) : undefined;
    const coverFile = cover !== undefined ? (cover['file'] as TdObject | undefined) : undefined;
    const audioSize = audioFile !== undefined
      ? (((audioFile['size'] as number | undefined) ?? 0) ||
        ((audioFile['expected_size'] as number | undefined) ?? 0)) : 0;
    return {
      contentType: 'audio',
      text: captionText(content!),
      photoFileId: coverFile !== undefined ? ((coverFile['id'] as number | undefined) ?? 0) : 0,
      photoWidth: cover !== undefined ? ((cover['width'] as number | undefined) ?? 0) : 0,
      photoHeight: cover !== undefined ? ((cover['height'] as number | undefined) ?? 0) : 0,
      placeholderLabel: '',
      entities: textEntities(content!['caption'] as TdObject | undefined),
      linkSiteName: '', linkTitle: '', linkDescription: '', linkDescriptionEntities: [],
      linkPhotoFileId: 0, linkUrl: '',
      videoDuration: audio !== undefined ? ((audio['duration'] as number | undefined) ?? 0) : 0,
      videoFileId: audioFile !== undefined ? ((audioFile['id'] as number | undefined) ?? 0) : 0,
      videoFileSize: audioSize,
      videoMimeType: audio !== undefined ? ((audio['mime_type'] as string | undefined) ?? '') : '',
      videoFileName: audio !== undefined ? ((audio['file_name'] as string | undefined) ?? '') : '',
      photoFullFileId: 0,
      audioTitle: audio !== undefined ? ((audio['title'] as string | undefined) ?? '') : '',
      audioPerformer: audio !== undefined ? ((audio['performer'] as string | undefined) ?? '') : ''
    };
  }
  // Documents reuse the video* slots (same semantics: a named, sized,
  // downloadable file with progress + local path once fetched).
  if (type === 'messageDocument') {
    const doc = content!['document'] as TdObject | undefined;
    const docFile = doc !== undefined ? (doc['document'] as TdObject | undefined) : undefined;
    const docSize = docFile !== undefined
      ? (((docFile['size'] as number | undefined) ?? 0) || ((docFile['expected_size'] as number | undefined) ?? 0)) : 0;
    const localState: LocalFileState = localFileState(docFile);
    return {
      contentType: 'file',
      text: captionText(content!),
      photoFileId: 0, photoWidth: 0, photoHeight: 0,
      placeholderLabel: '',
      entities: textEntities(content!['caption'] as TdObject | undefined),
      linkSiteName: '', linkTitle: '', linkDescription: '', linkDescriptionEntities: [], linkPhotoFileId: 0, linkUrl: '',
      videoDuration: 0,
      videoFileId: docFile !== undefined ? ((docFile['id'] as number | undefined) ?? 0) : 0,
      videoFileSize: docSize,
      videoMimeType: doc !== undefined ? ((doc['mime_type'] as string | undefined) ?? '') : '',
      videoFileName: doc !== undefined ? ((doc['file_name'] as string | undefined) ?? '') : '',
      photoFullFileId: 0,
      videoLocalPath: localState.path,
      videoInitialProgress: localState.progress,
      videoInitialActive: localState.active
    };
  }
  if (type === 'messagePaidMedia') {
    const media = (content!['media'] as TdObject[] | undefined) ?? [];
    const first = media.length > 0 ? media[0] : undefined;
    const firstType = first !== undefined
      ? ((first['@type'] as string | undefined) ?? '') : '';
    const locked = media.length === 0 ||
      media.some((item: TdObject): boolean => item['@type'] === 'paidMediaPreview');
    let size: PhotoSize = { fileId: 0, width: 0, height: 0 };
    let full: PhotoSize = { fileId: 0, width: 0, height: 0 };
    let videoFileId = 0;
    let videoFileSize = 0;
    let videoDuration = 0;
    let videoMimeType = '';
    let videoFileName = '';
    let kind = 'preview';
    if (firstType === 'paidMediaPhoto') {
      const photo = first!['photo'] as TdObject | undefined;
      size = inlinePhotoSize(photo);
      full = largestPhotoSize(photo);
      kind = 'photo';
    } else if (firstType === 'paidMediaVideo') {
      const video = first!['video'] as TdObject | undefined;
      const file = video !== undefined ? (video['video'] as TdObject | undefined) : undefined;
      size = videoThumbnail(video);
      videoFileId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
      videoFileSize = file !== undefined
        ? (((file['size'] as number | undefined) ?? 0) ||
          ((file['expected_size'] as number | undefined) ?? 0)) : 0;
      videoDuration = video !== undefined
        ? ((video['duration'] as number | undefined) ?? 0) : 0;
      videoMimeType = video !== undefined
        ? ((video['mime_type'] as string | undefined) ?? '') : '';
      videoFileName = video !== undefined
        ? ((video['file_name'] as string | undefined) ?? '') : '';
      kind = 'video';
    } else if (firstType === 'paidMediaPreview') {
      size = {
        fileId: 0,
        width: Math.max(0, (first!['width'] as number | undefined) ?? 0),
        height: Math.max(0, (first!['height'] as number | undefined) ?? 0)
      };
      videoDuration = Math.max(0, (first!['duration'] as number | undefined) ?? 0);
    }
    return {
      contentType: 'paidMedia',
      text: captionText(content!),
      photoFileId: size.fileId,
      photoWidth: size.width,
      photoHeight: size.height,
      placeholderLabel: '',
      entities: textEntities(content!['caption'] as TdObject | undefined),
      linkSiteName: '', linkTitle: '', linkDescription: '', linkDescriptionEntities: [],
      linkPhotoFileId: 0, linkUrl: '',
      videoDuration,
      videoFileId,
      videoFileSize,
      videoMimeType,
      videoFileName,
      photoFullFileId: full.fileId !== size.fileId ? full.fileId : 0,
      paidMediaLocked: locked,
      paidMediaStarCount: Math.max(0,
        (content!['star_count'] as number | undefined) ?? 0),
      paidMediaCount: media.length,
      paidMediaKind: kind
    };
  }
  if (type === 'messageGiftedPremium') {
    const months = Math.max(0, (content!['month_count'] as number | undefined) ?? 0);
    const days = Math.max(0, (content!['day_count'] as number | undefined) ?? 0);
    const duration = months > 0 ? `${months} 个月`
      : (days > 0 ? `${days} 天` : 'Telegram Premium');
    return giftBase(
      'premium', 'Telegram Premium 礼物', duration, '已赠送',
      formattedTextValue(content!['text'] as TdObject | undefined),
      content!['sticker'] as TdObject | undefined
    );
  }
  if (type === 'messageGiftedStars') {
    const stars = Math.max(0, (content!['star_count'] as number | undefined) ?? 0);
    return giftBase(
      'stars', 'Telegram 星星礼物',
      stars > 0 ? `${stars} 颗星星` : '星星数量未知',
      '已到账', '', content!['sticker'] as TdObject | undefined
    );
  }
  if (type === 'messageGiftedTon') {
    const amount = Math.max(0, (content!['ton_amount'] as number | undefined) ?? 0);
    return giftBase(
      'ton', 'TON 礼物', formatTonAmount(amount),
      '已到账', '', content!['sticker'] as TdObject | undefined
    );
  }
  if (type === 'messagePremiumGiftCode') {
    const months = Math.max(0, (content!['month_count'] as number | undefined) ?? 0);
    const days = Math.max(0, (content!['day_count'] as number | undefined) ?? 0);
    const duration = months > 0 ? `${months} 个月 Premium`
      : (days > 0 ? `${days} 天 Premium` : 'Telegram Premium');
    const unclaimed = (content!['is_unclaimed'] as boolean | undefined) ?? false;
    const result = giftBase(
      'code', 'Premium 兑换码', duration,
      unclaimed ? '尚未领取' : '可查看兑换码',
      formattedTextValue(content!['text'] as TdObject | undefined),
      content!['sticker'] as TdObject | undefined
    );
    result.giftCode = (content!['code'] as string | undefined) ?? '';
    return result;
  }
  if (type === 'messageGift') {
    const gift = content!['gift'] as TdObject | undefined;
    const refunded = (content!['was_refunded'] as boolean | undefined) ?? false;
    const upgraded = (content!['was_upgraded'] as boolean | undefined) ?? false;
    const converted = (content!['was_converted'] as boolean | undefined) ?? false;
    const saved = (content!['is_saved'] as boolean | undefined) ?? false;
    const uniqueNumber = Math.max(0,
      (content!['unique_gift_number'] as number | undefined) ?? 0);
    const starCount = gift !== undefined
      ? Math.max(0, (gift['star_count'] as number | undefined) ?? 0) : 0;
    let status = saved ? '已展示在个人资料' : '已收到';
    if (uniqueNumber > 0 || upgraded) {
      status = uniqueNumber > 0 ? `珍藏编号 #${uniqueNumber}` : '已升级为珍藏礼物';
    }
    if (converted) {
      status = '已兑换为星星';
    }
    if (refunded) {
      status = '已退款，不再可用';
    }
    const result = giftBase(
      'regular',
      gift !== undefined && ((gift['is_for_birthday'] as boolean | undefined) ?? false)
        ? '生日礼物' : 'Telegram 礼物',
      starCount > 0 ? `价值 ${starCount} 颗星星` : '一份特别礼物',
      status,
      formattedTextValue(content!['text'] as TdObject | undefined),
      gift !== undefined ? (gift['sticker'] as TdObject | undefined) : undefined
    );
    result.giftRefunded = refunded;
    return result;
  }
  if (type === 'messageUpgradedGift') {
    const gift = content!['gift'] as TdObject | undefined;
    const model = gift !== undefined ? (gift['model'] as TdObject | undefined) : undefined;
    const number = gift !== undefined
      ? Math.max(0, (gift['number'] as number | undefined) ?? 0) : 0;
    const usdCents = gift !== undefined
      ? Math.max(0, (gift['value_usd_amount'] as number | undefined) ?? 0) : 0;
    const burned = gift !== undefined
      ? ((gift['is_burned'] as boolean | undefined) ?? false) : false;
    const transferred = (content!['was_transferred'] as boolean | undefined) ?? false;
    const saved = (content!['is_saved'] as boolean | undefined) ?? false;
    let status = saved ? '已展示在个人资料' : '珍藏礼物';
    if ((content!['can_be_transferred'] as boolean | undefined) ?? false) {
      status = '可转让的珍藏礼物';
    }
    if (transferred) {
      status = '已转让给其他用户';
    }
    if (burned) {
      status = '已用于合成其他礼物';
    }
    return giftBase(
      'collectible',
      gift !== undefined && ((gift['title'] as string | undefined) ?? '') !== ''
        ? ((gift['title'] as string | undefined) ?? '珍藏礼物') : '珍藏礼物',
      usdCents > 0 ? `估值 $${(usdCents / 100).toFixed(2)}`
        : (number > 0 ? `珍藏编号 #${number}` : '独一无二的 Telegram 礼物'),
      status,
      model !== undefined && ((model['name'] as string | undefined) ?? '') !== ''
        ? `款式：${(model['name'] as string | undefined) ?? ''}` : '',
      model !== undefined ? (model['sticker'] as TdObject | undefined) : undefined
    );
  }
  if (type === 'messageGiveaway') {
    const parameters = content!['parameters'] as TdObject | undefined;
    return giveawayBase(
      'active',
      (content!['winner_count'] as number | undefined) ?? 0,
      giveawayPrizeText(content!['prize'] as TdObject | undefined),
      parameters !== undefined
        ? ((parameters['prize_description'] as string | undefined) ?? '') : '',
      parameters !== undefined
        ? ((parameters['winners_selection_date'] as number | undefined) ?? 0) : 0,
      0, 0,
      parameters !== undefined
        ? ((parameters['boosted_chat_id'] as number | undefined) ?? 0) : 0,
      false,
      parameters !== undefined
        ? ((parameters['only_new_members'] as boolean | undefined) ?? false) : false,
      content!['sticker'] as TdObject | undefined
    );
  }
  if (type === 'messageGiveawayWinners') {
    return giveawayBase(
      'winners',
      (content!['winner_count'] as number | undefined) ?? 0,
      giveawayPrizeText(content!['prize'] as TdObject | undefined),
      (content!['prize_description'] as string | undefined) ?? '',
      (content!['actual_winners_selection_date'] as number | undefined) ?? 0,
      (content!['unclaimed_prize_count'] as number | undefined) ?? 0,
      (content!['giveaway_message_id'] as number | undefined) ?? 0,
      (content!['boosted_chat_id'] as number | undefined) ?? 0,
      (content!['was_refunded'] as boolean | undefined) ?? false,
      (content!['only_new_members'] as boolean | undefined) ?? false,
      undefined
    );
  }
  if (type === 'messageGiveawayCompleted') {
    return giveawayBase(
      'completed',
      (content!['winner_count'] as number | undefined) ?? 0,
      ((content!['is_star_giveaway'] as boolean | undefined) ?? false)
        ? 'Telegram 星星' : 'Telegram Premium',
      '', 0,
      (content!['unclaimed_prize_count'] as number | undefined) ?? 0,
      (content!['giveaway_message_id'] as number | undefined) ?? 0,
      0, false, false, undefined
    );
  }
  if (type === 'messageGiveawayPrizeStars') {
    const stars = Math.max(0, (content!['star_count'] as number | undefined) ?? 0);
    return giveawayBase(
      'prize', 1,
      stars > 0 ? `${stars} 颗 Telegram 星星` : 'Telegram 星星',
      (content!['is_unclaimed'] as boolean | undefined) ?? false
        ? '奖品未被领取，已退回频道' : '恭喜，你获得了抽奖奖品',
      0, 0,
      (content!['giveaway_message_id'] as number | undefined) ?? 0,
      (content!['boosted_chat_id'] as number | undefined) ?? 0,
      false, false,
      content!['sticker'] as TdObject | undefined
    );
  }
  if (type === 'messageContact') {
    const contact = content!['contact'] as TdObject | undefined;
    return {
      contentType: 'contact', text: '', photoFileId: 0, photoWidth: 0, photoHeight: 0,
      placeholderLabel: '', entities: [],
      linkSiteName: '', linkTitle: '', linkDescription: '', linkDescriptionEntities: [],
      linkPhotoFileId: 0, linkUrl: '',
      videoDuration: 0, videoFileId: 0, videoFileSize: 0, videoMimeType: '',
      videoFileName: '', photoFullFileId: 0,
      contactPhone: contact !== undefined
        ? ((contact['phone_number'] as string | undefined) ?? '') : '',
      contactFirstName: contact !== undefined
        ? ((contact['first_name'] as string | undefined) ?? '') : '',
      contactLastName: contact !== undefined
        ? ((contact['last_name'] as string | undefined) ?? '') : '',
      contactVcard: contact !== undefined ? ((contact['vcard'] as string | undefined) ?? '') : '',
      contactUserId: contact !== undefined ? ((contact['user_id'] as number | undefined) ?? 0) : 0
    };
  }
  if (type === 'messageLocation' || type === 'messageVenue') {
    const venue = type === 'messageVenue'
      ? (content!['venue'] as TdObject | undefined) : undefined;
    const location = type === 'messageVenue'
      ? (venue !== undefined ? (venue['location'] as TdObject | undefined) : undefined)
      : (content!['location'] as TdObject | undefined);
    const latitude = location !== undefined
      ? ((location['latitude'] as number | undefined) ?? 0) : 0;
    const longitude = location !== undefined
      ? ((location['longitude'] as number | undefined) ?? 0) : 0;
    const valid = location !== undefined && Number.isFinite(latitude) && Number.isFinite(longitude)
      && latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180;
    return {
      contentType: type === 'messageVenue' ? 'venue' : 'location',
      text: '', photoFileId: 0, photoWidth: 0, photoHeight: 0,
      placeholderLabel: '', entities: [],
      linkSiteName: '', linkTitle: '', linkDescription: '', linkDescriptionEntities: [],
      linkPhotoFileId: 0, linkUrl: '',
      videoDuration: 0, videoFileId: 0, videoFileSize: 0, videoMimeType: '',
      videoFileName: '', photoFullFileId: 0,
      locationLatitude: latitude,
      locationLongitude: longitude,
      locationAccuracy: location !== undefined
        ? ((location['horizontal_accuracy'] as number | undefined) ?? 0) : 0,
      locationValid: valid,
      locationLivePeriod: type === 'messageLocation'
        ? ((content!['live_period'] as number | undefined) ?? 0) : 0,
      locationExpiresIn: type === 'messageLocation'
        ? ((content!['expires_in'] as number | undefined) ?? 0) : 0,
      locationHeading: type === 'messageLocation'
        ? ((content!['heading'] as number | undefined) ?? 0) : 0,
      locationProximityRadius: type === 'messageLocation'
        ? ((content!['proximity_alert_radius'] as number | undefined) ?? 0) : 0,
      venueTitle: venue !== undefined ? ((venue['title'] as string | undefined) ?? '') : '',
      venueAddress: venue !== undefined ? ((venue['address'] as string | undefined) ?? '') : '',
      venueProvider: venue !== undefined ? ((venue['provider'] as string | undefined) ?? '') : '',
      venueId: venue !== undefined ? ((venue['id'] as string | undefined) ?? '') : '',
      venueType: venue !== undefined ? ((venue['type'] as string | undefined) ?? '') : ''
    };
  }
  if (type === 'messagePoll') {
    const poll = content!['poll'] as TdObject | undefined;
    const question = poll !== undefined ? (poll['question'] as TdObject | undefined) : undefined;
    const rawOptions = poll !== undefined
      ? ((poll['options'] as TdObject[] | undefined) ?? []) : [];
    const options: PollOptionInfo[] = rawOptions.map((option: TdObject): PollOptionInfo => {
      const optionText = option['text'] as TdObject | undefined;
      return {
        text: optionText !== undefined ? ((optionText['text'] as string | undefined) ?? '') : '',
        voterCount: Math.max(0, (option['voter_count'] as number | undefined) ?? 0),
        votePercentage: Math.max(0, Math.min(100,
          (option['vote_percentage'] as number | undefined) ?? 0)),
        isChosen: (option['is_chosen'] as boolean | undefined) ?? false,
        isBeingChosen: (option['is_being_chosen'] as boolean | undefined) ?? false
      };
    });
    const pollType = poll !== undefined ? (poll['type'] as TdObject | undefined) : undefined;
    const typeName = pollType !== undefined
      ? ((pollType['@type'] as string | undefined) ?? '') : '';
    const explanation = pollType !== undefined
      ? (pollType['explanation'] as TdObject | undefined) : undefined;
    return {
      contentType: 'poll', text: '', photoFileId: 0, photoWidth: 0, photoHeight: 0,
      placeholderLabel: '', entities: [],
      linkSiteName: '', linkTitle: '', linkDescription: '', linkDescriptionEntities: [],
      linkPhotoFileId: 0, linkUrl: '',
      videoDuration: 0, videoFileId: 0, videoFileSize: 0, videoMimeType: '',
      videoFileName: '', photoFullFileId: 0,
      pollId: poll !== undefined ? `${poll['id'] ?? ''}` : '',
      pollQuestion: question !== undefined ? ((question['text'] as string | undefined) ?? '') : '',
      pollOptions: options,
      pollTotalVoterCount: poll !== undefined
        ? Math.max(0, (poll['total_voter_count'] as number | undefined) ?? 0) : 0,
      pollIsAnonymous: poll !== undefined
        ? ((poll['is_anonymous'] as boolean | undefined) ?? true) : true,
      pollIsQuiz: typeName === 'pollTypeQuiz',
      pollAllowMultiple: typeName === 'pollTypeRegular'
        && ((pollType!['allow_multiple_answers'] as boolean | undefined) ?? false),
      pollCorrectOptionId: typeName === 'pollTypeQuiz'
        ? ((pollType!['correct_option_id'] as number | undefined) ?? -1) : -1,
      pollExplanation: explanation !== undefined
        ? ((explanation['text'] as string | undefined) ?? '') : '',
      pollOpenPeriod: poll !== undefined
        ? Math.max(0, (poll['open_period'] as number | undefined) ?? 0) : 0,
      pollCloseDate: poll !== undefined
        ? Math.max(0, (poll['close_date'] as number | undefined) ?? 0) : 0,
      pollIsClosed: poll !== undefined
        ? ((poll['is_closed'] as boolean | undefined) ?? false) : true
    };
  }
  if (type === 'messageDice') {
    const emoji = (content!['emoji'] as string | undefined) ?? '';
    const value = Math.max(0, (content!['value'] as number | undefined) ?? 0);
    // final_state 是官方 TGS 动画（播完定格在结果上）——走既有贴纸下载/
    // 渲染管线；未生成结果前退回 initial_state（滚动中动画）。
    const pickDiceSticker = (state: TdObject | undefined): TdObject | undefined => {
      if (state === undefined ||
        ((state['@type'] as string | undefined) ?? '') !== 'diceStickersRegular') {
        return undefined;
      }
      return state['sticker'] as TdObject | undefined;
    };
    const diceSticker = pickDiceSticker(content!['final_state'] as TdObject | undefined) ??
      pickDiceSticker(content!['initial_state'] as TdObject | undefined);
    const diceStickerFile = diceSticker !== undefined
      ? diceSticker['sticker'] as TdObject | undefined : undefined;
    const diceStickerFileId: number = diceStickerFile !== undefined
      ? ((diceStickerFile['id'] as number | undefined) ?? 0) : 0;
    const diceLocal: LocalFileState = localFileState(diceStickerFile);
    // 🎰 老虎机（diceStickersSlotMachine）：5 层 TGS。渲染 z 序 =
    // 背景 → 左/中/右转轮 → 拉杆（拉杆最上层）。
    const pickSlotLayers = (state: TdObject | undefined): TdObject[] => {
      if (state === undefined ||
        ((state['@type'] as string | undefined) ?? '') !== 'diceStickersSlotMachine') {
        return [];
      }
      const fields: string[] = ['background', 'left_reel', 'center_reel', 'right_reel', 'lever'];
      const layers: TdObject[] = [];
      for (const field of fields) {
        const layer = state[field] as TdObject | undefined;
        if (layer !== undefined) {
          layers.push(layer);
        }
      }
      return layers.length === fields.length ? layers : [];
    };
    const slotLayers = ((): TdObject[] => {
      const fromFinal = pickSlotLayers(content!['final_state'] as TdObject | undefined);
      return fromFinal.length > 0
        ? fromFinal : pickSlotLayers(content!['initial_state'] as TdObject | undefined);
    })();
    const diceLayerFileIds: number[] = [];
    const diceLayerPaths: string[] = [];
    for (const layer of slotLayers) {
      const layerFile = layer['sticker'] as TdObject | undefined;
      diceLayerFileIds.push(layerFile !== undefined
        ? ((layerFile['id'] as number | undefined) ?? 0) : 0);
      diceLayerPaths.push(localFileState(layerFile).path);
    }
    return {
      contentType: 'dice', text: '', photoFileId: 0, photoWidth: 0, photoHeight: 0,
      placeholderLabel: '', entities: [],
      linkSiteName: '', linkTitle: '', linkDescription: '', linkDescriptionEntities: [],
      linkPhotoFileId: 0, linkUrl: '',
      videoDuration: 0, videoFileId: 0, videoFileSize: 0, videoMimeType: '',
      videoFileName: '', photoFullFileId: 0,
      stickerFileId: diceStickerFileId,
      stickerFormat: 'tgs',
      stickerLocalPath: diceLocal.path,
      diceLayerFileIds: diceLayerFileIds,
      diceLayerPaths: diceLayerPaths,
      diceEmoji: emoji !== '' ? emoji : '🎲',
      diceValue: value,
      diceSuccessFrame: Math.max(0,
        (content!['success_animation_frame_number'] as number | undefined) ?? 0),
      diceHasFinalState: content!['final_state'] !== undefined || value > 0
    };
  }
  if (type === 'messageGame') {
    const game = content!['game'] as TdObject | undefined;
    const gameText = game !== undefined ? (game['text'] as TdObject | undefined) : undefined;
    const size = inlinePhotoSize(game !== undefined
      ? (game['photo'] as TdObject | undefined) : undefined);
    return {
      contentType: 'game',
      text: '',
      photoFileId: size.fileId,
      photoWidth: size.width,
      photoHeight: size.height,
      placeholderLabel: '',
      entities: [],
      linkSiteName: '', linkTitle: '', linkDescription: '', linkDescriptionEntities: [],
      linkPhotoFileId: 0, linkUrl: '',
      videoDuration: 0, videoFileId: 0, videoFileSize: 0, videoMimeType: '',
      videoFileName: '', photoFullFileId: 0,
      gameId: game !== undefined ? `${game['id'] ?? ''}` : '',
      gameShortName: game !== undefined ? ((game['short_name'] as string | undefined) ?? '') : '',
      gameTitle: game !== undefined ? ((game['title'] as string | undefined) ?? '') : '',
      gameDescription: game !== undefined
        ? ((game['description'] as string | undefined) ?? '') : '',
      gameText: gameText !== undefined ? ((gameText['text'] as string | undefined) ?? '') : ''
    };
  }
  if (type === 'messageSticker') {
    const parsed = stickerMsgContent(content!['sticker'] as TdObject | undefined);
    if (parsed !== null) {
      return parsed;
    }
    return {
      contentType: 'sticker', text: '', photoFileId: 0, photoWidth: 0, photoHeight: 0,
      placeholderLabel: '', entities: [],
      linkSiteName: '', linkTitle: '', linkDescription: '', linkDescriptionEntities: [],
      linkPhotoFileId: 0, linkUrl: '',
      videoDuration: 0, videoFileId: 0, videoFileSize: 0, videoMimeType: '',
      videoFileName: '', photoFullFileId: 0, stickerFileId: 0, stickerFormat: ''
    };
  }
  // Single-emoji messages arrive as messageAnimatedEmoji; TDLib pre-resolves
  // the sticker (standard AND premium custom emoji) into animated_emoji.sticker.
  if (type === 'messageAnimatedEmoji') {
    const ae = content!['animated_emoji'] as TdObject | undefined;
    const parsed = stickerMsgContent(ae !== undefined ? (ae['sticker'] as TdObject | undefined) : undefined);
    if (parsed !== null) {
      parsed.isEmojiSticker = true;
      return parsed;
    }
    const emoji = (content!['emoji'] as string | undefined) ?? '';
    if (emoji !== '') {
      return {
        contentType: 'emoji', text: emoji, photoFileId: 0, photoWidth: 0, photoHeight: 0, placeholderLabel: '', entities: [],
        linkSiteName: '', linkTitle: '', linkDescription: '', linkDescriptionEntities: [], linkPhotoFileId: 0, linkUrl: '',
        videoDuration: 0, videoFileId: 0, videoFileSize: 0, videoMimeType: '', videoFileName: '', photoFullFileId: 0
      };
    }
    return {
      contentType: 'emoji', text: '', photoFileId: 0, photoWidth: 0, photoHeight: 0,
      placeholderLabel: '', entities: [],
      linkSiteName: '', linkTitle: '', linkDescription: '', linkDescriptionEntities: [],
      linkPhotoFileId: 0, linkUrl: '',
      videoDuration: 0, videoFileId: 0, videoFileSize: 0, videoMimeType: '',
      videoFileName: '', photoFullFileId: 0, isEmojiSticker: true
    };
  }
  if (type === '__never__') {
    // (folded into stickerMsgContent below)
  }
  // Diagnostics for the "bare 'Message' bubble" reports — identifies which
  // TDLib content type still lacks a renderer.
  console.info(`formatMsgContent: unhandled content type ${type ?? 'undefined'} (msg ${message['id']})`);
  return {
    contentType: 'other', text: '', photoFileId: 0, photoWidth: 0, photoHeight: 0, placeholderLabel: formatPreview(message), entities: [],
    linkSiteName: '', linkTitle: '', linkDescription: '', linkDescriptionEntities: [], linkPhotoFileId: 0, linkUrl: '',
    videoDuration: 0, videoFileId: 0, videoFileSize: 0, videoMimeType: '', videoFileName: '', photoFullFileId: 0
  };
}

// Shared sticker → MsgContent parser (messageSticker and animated-emoji
// stickers): WEBP renders directly, TGS/WEBM animate from the source file
// with the raster thumbnail as placeholder. null when nothing is renderable.
function stickerMsgContent(sticker: TdObject | undefined): MsgContent | null {
  {
    const format = sticker !== undefined ? (sticker['format'] as TdObject | undefined) : undefined;
    const formatName = format !== undefined ? ((format['@type'] as string | undefined) ?? '') : '';
    // Keep Telegram's Unicode alternative even when an animated sticker file
    // is available. Embedded consumers (for example the livestream overlay)
    // can show this immediately without having to host another media player.
    const fallbackEmoji = sticker !== undefined ? ((sticker['emoji'] as string | undefined) ?? '') : '';
    const stickerFile = sticker !== undefined ? (sticker['sticker'] as TdObject | undefined) : undefined;
    const thumb = sticker !== undefined ? (sticker['thumbnail'] as TdObject | undefined) : undefined;
    // Only raster thumbnails are Image-decodable — a thumbnail can itself be
    // TGS/WEBM (ExtDecoder "Failed to match desc" otherwise).
    const thumbFormat = thumb !== undefined ? (thumb['format'] as TdObject | undefined) : undefined;
    const thumbFormatName = thumbFormat !== undefined ? ((thumbFormat['@type'] as string | undefined) ?? '') : '';
    const thumbIsRaster = thumbFormatName === 'thumbnailFormatWebp' || thumbFormatName === 'thumbnailFormatJpeg'
      || thumbFormatName === 'thumbnailFormatPng' || thumbFormatName === 'thumbnailFormatGif';
    const thumbFile = thumb !== undefined && thumbIsRaster ? (thumb['file'] as TdObject | undefined) : undefined;
    // Static WEBP renders directly. TGS (Lottie) and WEBM (looping ijkplayer)
    // animate once the source file downloads — the raster thumbnail is the
    // placeholder until then.
    const stickerFileId = stickerFile !== undefined ? ((stickerFile['id'] as number | undefined) ?? 0) : 0;
    const thumbFileId = thumbFile !== undefined ? ((thumbFile['id'] as number | undefined) ?? 0) : 0;
    const isWebp = formatName === 'stickerFormatWebp';
    const isTgs = formatName === 'stickerFormatTgs';
    const isWebm = formatName === 'stickerFormatWebm';
    const knownAnimated = isTgs || isWebm;
    const sourceState: LocalFileState = localFileState(stickerFile);
    const thumbState: LocalFileState = localFileState(thumbFile);
    // Unknown future formats must not be handed to the WEBM decoder. A raster
    // thumbnail is still a valid, stable fallback.
    const fileId = isWebp ? stickerFileId : thumbFileId;
    if (fileId !== 0 || (knownAnimated && stickerFileId !== 0)) {
      return {
        contentType: 'sticker', text: fallbackEmoji,
        photoFileId: fileId,
        photoWidth: sticker !== undefined ? ((sticker['width'] as number | undefined) ?? 0) : 0,
        photoHeight: sticker !== undefined ? ((sticker['height'] as number | undefined) ?? 0) : 0,
        placeholderLabel: '', entities: [],
        linkSiteName: '', linkTitle: '', linkDescription: '', linkDescriptionEntities: [], linkPhotoFileId: 0, linkUrl: '',
        videoDuration: 0, videoFileId: 0, videoFileSize: 0, videoMimeType: '', videoFileName: '', photoFullFileId: 0,
        stickerFileId: knownAnimated ? stickerFileId : 0,
        stickerFormat: isWebp || !knownAnimated ? 'webp' : (isTgs ? 'tgs' : 'webm'),
        photoLocalPath: isWebp ? sourceState.path : thumbState.path,
        photoInitialProgress: isWebp ? sourceState.progress : thumbState.progress,
        photoInitialActive: isWebp ? sourceState.active : thumbState.active,
        stickerLocalPath: knownAnimated ? sourceState.path : '',
        stickerInitialProgress: knownAnimated ? sourceState.progress : 0,
        stickerInitialActive: knownAnimated ? sourceState.active : false
      };
    }
    // No renderable file at all → the sticker's emoji, big and bare.
    if (fallbackEmoji !== '') {
      return {
        contentType: 'emoji', text: fallbackEmoji, photoFileId: 0, photoWidth: 0, photoHeight: 0, placeholderLabel: '', entities: [],
        linkSiteName: '', linkTitle: '', linkDescription: '', linkDescriptionEntities: [], linkPhotoFileId: 0, linkUrl: '',
        videoDuration: 0, videoFileId: 0, videoFileSize: 0, videoMimeType: '', videoFileName: '', photoFullFileId: 0
      };
    }
    return null;
  }
}
