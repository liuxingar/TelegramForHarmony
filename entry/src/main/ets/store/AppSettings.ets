import { preferences } from '@kit.ArkData';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { batteryInfo, commonEventManager } from '@kit.BasicServicesKit';

// User settings that outlive the process. Each one is mirrored into AppStorage
// so any component can bind it with @StorageProp and re-render on change, while
// Preferences keeps the value across restarts.
//
// Only settings the app actually honours live here — a switch that changes
// nothing is worse than no switch at all.

const STORE_NAME: string = 'app_settings';

// AppStorage keys (also the Preferences keys — one name per setting).
export const KEY_TEXT_SIZE: string = 'msgTextSize';        // message font size, vp
export const KEY_BUBBLE_RADIUS: string = 'bubbleRadius';   // message corner radius, vp
export const KEY_THREE_LINES: string = 'chatListThreeLines'; // chat list row shows 2 or 3 lines
export const KEY_NIGHT_MODE: string = 'nightMode';         // 'system' | 'dark' | 'light'
export const KEY_REDUCE_ANIM: string = 'reduceAnimations'; // stop autoplaying animated stickers
export const KEY_SEND_BY_ENTER: string = 'sendByEnter';    // Enter sends instead of newline
// Power saving. Threshold: 0 = off, 10..100 = activate at/below this SOC,
// 101 = always on. User choices are kept separately from the derived active
// flag, so leaving low-power mode restores the exact previous behaviour.
export const KEY_POWER_THRESHOLD: string = 'powerSavingThreshold';
export const KEY_POWER_ACTIVE: string = 'powerSavingActive';
export const KEY_BATTERY_PERCENT: string = 'deviceBatteryPercent';
export const KEY_POWER_STICKERS: string = 'powerAnimatedStickers';
export const KEY_POWER_EMOJI: string = 'powerAnimatedEmoji';
export const KEY_POWER_CHAT_EFFECTS: string = 'powerChatEffects';
export const KEY_POWER_CALL_ANIMATIONS: string = 'powerCallAnimations';
export const KEY_POWER_AUTOPLAY_VIDEO: string = 'powerAutoplayVideo';
export const KEY_POWER_AUTOPLAY_GIF: string = 'powerAutoplayGif';
export const KEY_POWER_PARTICLES: string = 'powerParticles';
export const KEY_POWER_SMOOTH_TRANSITIONS: string = 'powerSmoothTransitions';
export const KEY_POWER_STICKER_AUTOPLAY: string = 'powerStickerAutoplay';
export const KEY_POWER_STICKER_LOOP: string = 'powerStickerLoop';
export const KEY_POWER_EMOJI_CHAT: string = 'powerEmojiChat';
export const KEY_POWER_EMOJI_REACTIONS: string = 'powerEmojiReactions';
export const KEY_POWER_EMOJI_STATUS: string = 'powerEmojiStatus';
export const KEY_POWER_EFFECT_MESSAGE: string = 'powerEffectMessage';
export const KEY_POWER_EFFECT_REACTION: string = 'powerEffectReaction';
export const KEY_POWER_EFFECT_REPLY: string = 'powerEffectReply';
export const KEY_POWER_EFFECT_MENU: string = 'powerEffectMenu';
export const KEY_POWER_EFFECT_BLUR: string = 'powerEffectBlur';
export const KEY_POWER_EFFECT_BACKGROUND: string = 'powerEffectBackground';
// Data & storage. The current network is supplied by NetworkStateService and
// is intentionally kept in AppStorage only; user choices below are persisted.
export const KEY_CURRENT_NETWORK_TYPE: string = 'currentNetworkType'; // none | wifi | mobile | roaming | other
export const KEY_AUTO_WIFI_PHOTO: string = 'autoWifiPhoto';
export const KEY_AUTO_WIFI_VIDEO: string = 'autoWifiVideo';
export const KEY_AUTO_WIFI_FILE: string = 'autoWifiFile';
export const KEY_AUTO_WIFI_VIDEO_LIMIT: string = 'autoWifiVideoLimit';
export const KEY_AUTO_WIFI_FILE_LIMIT: string = 'autoWifiFileLimit';
export const KEY_AUTO_WIFI_PRELOAD_VIDEO: string = 'autoWifiPreloadVideo';
export const KEY_AUTO_WIFI_NEXT_AUDIO: string = 'autoWifiNextAudio';
export const KEY_AUTO_WIFI_STORIES: string = 'autoWifiStories';
export const KEY_AUTO_MOBILE_PHOTO: string = 'autoMobilePhoto';
export const KEY_AUTO_MOBILE_VIDEO: string = 'autoMobileVideo';
export const KEY_AUTO_MOBILE_FILE: string = 'autoMobileFile';
export const KEY_AUTO_MOBILE_VIDEO_LIMIT: string = 'autoMobileVideoLimit';
export const KEY_AUTO_MOBILE_FILE_LIMIT: string = 'autoMobileFileLimit';
export const KEY_AUTO_MOBILE_PRELOAD_VIDEO: string = 'autoMobilePreloadVideo';
export const KEY_AUTO_MOBILE_NEXT_AUDIO: string = 'autoMobileNextAudio';
export const KEY_AUTO_MOBILE_STORIES: string = 'autoMobileStories';
export const KEY_AUTO_ROAMING_PHOTO: string = 'autoRoamingPhoto';
export const KEY_AUTO_ROAMING_VIDEO: string = 'autoRoamingVideo';
export const KEY_AUTO_ROAMING_FILE: string = 'autoRoamingFile';
export const KEY_AUTO_ROAMING_VIDEO_LIMIT: string = 'autoRoamingVideoLimit';
export const KEY_AUTO_ROAMING_FILE_LIMIT: string = 'autoRoamingFileLimit';
export const KEY_AUTO_ROAMING_PRELOAD_VIDEO: string = 'autoRoamingPreloadVideo';
export const KEY_AUTO_ROAMING_NEXT_AUDIO: string = 'autoRoamingNextAudio';
export const KEY_AUTO_ROAMING_STORIES: string = 'autoRoamingStories';
export const KEY_AUTO_LESS_DATA_CALLS: string = 'autoLessDataCalls';
export const KEY_AUTOSAVE_PRIVATE: string = 'autosavePrivate';
export const KEY_AUTOSAVE_GROUP: string = 'autosaveGroup';
export const KEY_AUTOSAVE_CHANNEL: string = 'autosaveChannel';
export const POWER_THRESHOLD_DEFAULT: number = 10;

export const AUTO_WIFI_VIDEO_LIMIT_DEFAULT: number = 64 * 1024 * 1024;
export const AUTO_WIFI_FILE_LIMIT_DEFAULT: number = 32 * 1024 * 1024;
export const AUTO_MOBILE_VIDEO_LIMIT_DEFAULT: number = 10 * 1024 * 1024;
export const AUTO_MOBILE_FILE_LIMIT_DEFAULT: number = 2 * 1024 * 1024;
export const AUTO_ROAMING_VIDEO_LIMIT_DEFAULT: number = 2 * 1024 * 1024;
export const AUTO_ROAMING_FILE_LIMIT_DEFAULT: number = 1024 * 1024;

export const TEXT_SIZE_MIN: number = 12;
export const TEXT_SIZE_MAX: number = 24;
export const TEXT_SIZE_DEFAULT: number = 16;
export const RADIUS_MIN: number = 0;
export const RADIUS_MAX: number = 20;
export const RADIUS_DEFAULT: number = 17;

export const NIGHT_SYSTEM: string = 'system';
export const NIGHT_DARK: string = 'dark';
export const NIGHT_LIGHT: string = 'light';

let store: preferences.Preferences | null = null;
let appContext: common.Context | null = null;
let batterySubscriber: commonEventManager.CommonEventSubscriber | null = null;

const POWER_BOOLEAN_DEFAULTS: string[] = [
  KEY_POWER_STICKERS,
  KEY_POWER_EMOJI,
  KEY_POWER_CHAT_EFFECTS,
  KEY_POWER_CALL_ANIMATIONS,
  KEY_POWER_AUTOPLAY_VIDEO,
  KEY_POWER_AUTOPLAY_GIF,
  KEY_POWER_PARTICLES,
  KEY_POWER_SMOOTH_TRANSITIONS,
  KEY_POWER_STICKER_AUTOPLAY,
  KEY_POWER_STICKER_LOOP,
  KEY_POWER_EMOJI_CHAT,
  KEY_POWER_EMOJI_REACTIONS,
  KEY_POWER_EMOJI_STATUS
];

const POWER_BOOLEAN_FALSE_DEFAULTS: string[] = [
  KEY_POWER_EFFECT_REACTION,
  KEY_POWER_EFFECT_REPLY,
  KEY_POWER_EFFECT_BLUR,
  KEY_POWER_EFFECT_BACKGROUND
];

const POWER_BOOLEAN_TRUE_EFFECT_DEFAULTS: string[] = [
  KEY_POWER_EFFECT_MESSAGE,
  KEY_POWER_EFFECT_MENU
];

// 后台播放：各媒体类别切后台是否继续播放（audioPlayback 长时任务）。
export const KEY_BG_PLAY_MUSIC: string = 'bgPlayMusic';
export const KEY_BG_PLAY_VOICE: string = 'bgPlayVoice';
export const KEY_BG_PLAY_VIDEO: string = 'bgPlayVideo';
export const KEY_BG_PLAY_LIVE: string = 'bgPlayLive';

const DATA_BOOLEAN_TRUE_DEFAULTS: string[] = [
  // 音乐/语音/直播默认续播（符合平台惯例）；视频默认不续播。
  KEY_BG_PLAY_MUSIC,
  KEY_BG_PLAY_VOICE,
  KEY_BG_PLAY_LIVE,
  KEY_AUTO_WIFI_PHOTO,
  KEY_AUTO_WIFI_VIDEO,
  KEY_AUTO_WIFI_FILE,
  KEY_AUTO_WIFI_PRELOAD_VIDEO,
  KEY_AUTO_WIFI_NEXT_AUDIO,
  KEY_AUTO_WIFI_STORIES,
  KEY_AUTO_MOBILE_PHOTO,
  KEY_AUTO_MOBILE_VIDEO,
  KEY_AUTO_MOBILE_NEXT_AUDIO
];

const DATA_BOOLEAN_FALSE_DEFAULTS: string[] = [
  KEY_BG_PLAY_VIDEO,
  KEY_AUTO_MOBILE_FILE,
  KEY_AUTO_MOBILE_PRELOAD_VIDEO,
  KEY_AUTO_MOBILE_STORIES,
  KEY_AUTO_ROAMING_PHOTO,
  KEY_AUTO_ROAMING_VIDEO,
  KEY_AUTO_ROAMING_FILE,
  KEY_AUTO_ROAMING_PRELOAD_VIDEO,
  KEY_AUTO_ROAMING_NEXT_AUDIO,
  KEY_AUTO_ROAMING_STORIES,
  KEY_AUTO_LESS_DATA_CALLS,
  KEY_AUTOSAVE_PRIVATE,
  KEY_AUTOSAVE_GROUP,
  KEY_AUTOSAVE_CHANNEL
];

interface NumberDefault {
  key: string;
  value: number;
}

const DATA_NUMBER_DEFAULTS: NumberDefault[] = [
  { key: KEY_AUTO_WIFI_VIDEO_LIMIT, value: AUTO_WIFI_VIDEO_LIMIT_DEFAULT },
  { key: KEY_AUTO_WIFI_FILE_LIMIT, value: AUTO_WIFI_FILE_LIMIT_DEFAULT },
  { key: KEY_AUTO_MOBILE_VIDEO_LIMIT, value: AUTO_MOBILE_VIDEO_LIMIT_DEFAULT },
  { key: KEY_AUTO_MOBILE_FILE_LIMIT, value: AUTO_MOBILE_FILE_LIMIT_DEFAULT },
  { key: KEY_AUTO_ROAMING_VIDEO_LIMIT, value: AUTO_ROAMING_VIDEO_LIMIT_DEFAULT },
  { key: KEY_AUTO_ROAMING_FILE_LIMIT, value: AUTO_ROAMING_FILE_LIMIT_DEFAULT }
];

function applyPowerState(percent: number): void {
  const safePercent = Math.max(0, Math.min(100, Math.round(percent)));
  const threshold = AppStorage.get<number>(KEY_POWER_THRESHOLD) ?? POWER_THRESHOLD_DEFAULT;
  const active = threshold === 101 || (threshold > 0 && safePercent <= threshold);
  AppStorage.setOrCreate(KEY_BATTERY_PERCENT, safePercent);
  AppStorage.setOrCreate(KEY_POWER_ACTIVE, active);
}

// Read the authoritative SOC instead of trusting event payload field names,
// which differ between OpenHarmony releases.
export function refreshPowerSavingState(): void {
  try {
    applyPowerState(batteryInfo.batterySOC);
  } catch (e) {
    console.error(`AppSettings.refreshPowerSavingState failed: ${e}`);
  }
}

function beginBatteryMonitoring(): void {
  if (batterySubscriber !== null) {
    return;
  }
  const info: commonEventManager.CommonEventSubscribeInfo = {
    events: [
      commonEventManager.Support.COMMON_EVENT_BATTERY_CHANGED,
      commonEventManager.Support.COMMON_EVENT_POWER_CONNECTED,
      commonEventManager.Support.COMMON_EVENT_POWER_DISCONNECTED
    ]
  };
  commonEventManager.createSubscriber(info).then(
    (subscriber: commonEventManager.CommonEventSubscriber): void => {
      batterySubscriber = subscriber;
      commonEventManager.subscribe(subscriber, (error, _data): void => {
        // HarmonyOS returns null (rather than undefined) for a successful
        // AsyncCallback error argument on some device releases.
        if (error !== undefined && error !== null && error.code !== 0) {
          console.error(`AppSettings battery event failed: ${error.message}`);
          return;
        }
        refreshPowerSavingState();
      });
    }
  ).catch((e: Object): void => {
    console.error(`AppSettings battery subscribe failed: ${JSON.stringify(e)}`);
  });
}

function colorModeOf(nightMode: string): ConfigurationConstant.ColorMode {
  if (nightMode === NIGHT_DARK) {
    return ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }
  if (nightMode === NIGHT_LIGHT) {
    return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  }
  return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET; // follow the system
}

// Push the stored night mode to the app — NOT_SET means "follow the system".
export function applyNightMode(nightMode: string): void {
  if (appContext === null) {
    return;
  }
  try {
    (appContext as common.Context).getApplicationContext().setColorMode(colorModeOf(nightMode));
  } catch (e) {
    console.error(`AppSettings.applyNightMode failed: ${e}`);
  }
}

// Load everything into AppStorage. Call once at startup, before the first page
// renders, so components never flash the default value.
export async function initSettings(context: common.Context): Promise<void> {
  appContext = context;
  try {
    store = await preferences.getPreferences(context, STORE_NAME);
    const s = store as preferences.Preferences;
    AppStorage.setOrCreate(KEY_TEXT_SIZE, await s.get(KEY_TEXT_SIZE, TEXT_SIZE_DEFAULT) as number);
    AppStorage.setOrCreate(KEY_BUBBLE_RADIUS, await s.get(KEY_BUBBLE_RADIUS, RADIUS_DEFAULT) as number);
    AppStorage.setOrCreate(KEY_THREE_LINES, await s.get(KEY_THREE_LINES, false) as boolean);
    AppStorage.setOrCreate(KEY_REDUCE_ANIM, await s.get(KEY_REDUCE_ANIM, false) as boolean);
    AppStorage.setOrCreate(KEY_SEND_BY_ENTER, await s.get(KEY_SEND_BY_ENTER, false) as boolean);
    AppStorage.setOrCreate(
      KEY_POWER_THRESHOLD,
      await s.get(KEY_POWER_THRESHOLD, POWER_THRESHOLD_DEFAULT) as number
    );
    for (const key of POWER_BOOLEAN_DEFAULTS) {
      AppStorage.setOrCreate(key, await s.get(key, true) as boolean);
    }
    for (const key of POWER_BOOLEAN_TRUE_EFFECT_DEFAULTS) {
      AppStorage.setOrCreate(key, await s.get(key, true) as boolean);
    }
    for (const key of POWER_BOOLEAN_FALSE_DEFAULTS) {
      AppStorage.setOrCreate(key, await s.get(key, false) as boolean);
    }
    for (const key of DATA_BOOLEAN_TRUE_DEFAULTS) {
      AppStorage.setOrCreate(key, await s.get(key, true) as boolean);
    }
    for (const key of DATA_BOOLEAN_FALSE_DEFAULTS) {
      AppStorage.setOrCreate(key, await s.get(key, false) as boolean);
    }
    for (const item of DATA_NUMBER_DEFAULTS) {
      AppStorage.setOrCreate(item.key, await s.get(item.key, item.value) as number);
    }
    AppStorage.setOrCreate(KEY_CURRENT_NETWORK_TYPE, 'other');
    AppStorage.setOrCreate(KEY_POWER_ACTIVE, false);
    AppStorage.setOrCreate(KEY_BATTERY_PERCENT, 100);
    const night = await s.get(KEY_NIGHT_MODE, NIGHT_SYSTEM) as string;
    AppStorage.setOrCreate(KEY_NIGHT_MODE, night);
    applyNightMode(night);
    refreshPowerSavingState();
    beginBatteryMonitoring();
  } catch (e) {
    console.error(`AppSettings.initSettings failed: ${e}`);
    // Defaults still populate AppStorage so the UI works without persistence.
    AppStorage.setOrCreate(KEY_TEXT_SIZE, TEXT_SIZE_DEFAULT);
    AppStorage.setOrCreate(KEY_BUBBLE_RADIUS, RADIUS_DEFAULT);
    AppStorage.setOrCreate(KEY_THREE_LINES, false);
    AppStorage.setOrCreate(KEY_NIGHT_MODE, NIGHT_SYSTEM);
    AppStorage.setOrCreate(KEY_REDUCE_ANIM, false);
    AppStorage.setOrCreate(KEY_SEND_BY_ENTER, false);
    AppStorage.setOrCreate(KEY_POWER_THRESHOLD, POWER_THRESHOLD_DEFAULT);
    for (const key of POWER_BOOLEAN_DEFAULTS) {
      AppStorage.setOrCreate(key, true);
    }
    for (const key of POWER_BOOLEAN_TRUE_EFFECT_DEFAULTS) {
      AppStorage.setOrCreate(key, true);
    }
    for (const key of POWER_BOOLEAN_FALSE_DEFAULTS) {
      AppStorage.setOrCreate(key, false);
    }
    for (const key of DATA_BOOLEAN_TRUE_DEFAULTS) {
      AppStorage.setOrCreate(key, true);
    }
    for (const key of DATA_BOOLEAN_FALSE_DEFAULTS) {
      AppStorage.setOrCreate(key, false);
    }
    for (const item of DATA_NUMBER_DEFAULTS) {
      AppStorage.setOrCreate(item.key, item.value);
    }
    AppStorage.setOrCreate(KEY_CURRENT_NETWORK_TYPE, 'other');
    AppStorage.setOrCreate(KEY_POWER_ACTIVE, false);
    AppStorage.setOrCreate(KEY_BATTERY_PERCENT, 100);
    refreshPowerSavingState();
    beginBatteryMonitoring();
  }
}

// Write-through: AppStorage first (instant UI), Preferences after (durable).
function persist(key: string, value: preferences.ValueType): void {
  if (store === null) {
    return;
  }
  const s = store as preferences.Preferences;
  s.put(key, value).then(() => s.flush()).catch((e: Object) => {
    console.error(`AppSettings.persist(${key}) failed: ${JSON.stringify(e)}`);
  });
}

export function setNumber(key: string, value: number): void {
  AppStorage.setOrCreate(key, value);
  persist(key, value);
  if (key === KEY_POWER_THRESHOLD) {
    refreshPowerSavingState();
  }
}

export function setBoolean(key: string, value: boolean): void {
  AppStorage.setOrCreate(key, value);
  persist(key, value);
}

export function setString(key: string, value: string): void {
  AppStorage.setOrCreate(key, value);
  persist(key, value);
}

export interface AutoDownloadPolicy {
  network: string;
  photos: boolean;
  videos: boolean;
  files: boolean;
  videoLimit: number;
  fileLimit: number;
  preloadLargeVideos: boolean;
  preloadNextAudio: boolean;
  preloadStories: boolean;
  lessDataForCalls: boolean;
}

function boolValue(key: string, fallback: boolean): boolean {
  return AppStorage.get<boolean>(key) ?? fallback;
}

function numberValue(key: string, fallback: number): number {
  const value = AppStorage.get<number>(key) ?? fallback;
  return Number.isFinite(value) && value >= 0 ? value : fallback;
}

// "other" is treated like mobile data: it avoids an unexpectedly large
// download on Ethernet/VPN transports whose metering status is unknown.
export function autoDownloadPolicy(networkOverride: string = ''): AutoDownloadPolicy {
  let network = networkOverride !== '' ? networkOverride
    : (AppStorage.get<string>(KEY_CURRENT_NETWORK_TYPE) ?? 'other');
  if (network === 'none') {
    network = 'none';
  } else if (network !== 'wifi' && network !== 'mobile' && network !== 'roaming') {
    network = 'mobile';
  }
  if (network === 'wifi') {
    return {
      network, photos: boolValue(KEY_AUTO_WIFI_PHOTO, true),
      videos: boolValue(KEY_AUTO_WIFI_VIDEO, true), files: boolValue(KEY_AUTO_WIFI_FILE, true),
      videoLimit: numberValue(KEY_AUTO_WIFI_VIDEO_LIMIT, AUTO_WIFI_VIDEO_LIMIT_DEFAULT),
      fileLimit: numberValue(KEY_AUTO_WIFI_FILE_LIMIT, AUTO_WIFI_FILE_LIMIT_DEFAULT),
      preloadLargeVideos: boolValue(KEY_AUTO_WIFI_PRELOAD_VIDEO, true),
      preloadNextAudio: boolValue(KEY_AUTO_WIFI_NEXT_AUDIO, true),
      preloadStories: boolValue(KEY_AUTO_WIFI_STORIES, true),
      lessDataForCalls: boolValue(KEY_AUTO_LESS_DATA_CALLS, false)
    };
  }
  if (network === 'roaming') {
    return {
      network, photos: boolValue(KEY_AUTO_ROAMING_PHOTO, false),
      videos: boolValue(KEY_AUTO_ROAMING_VIDEO, false), files: boolValue(KEY_AUTO_ROAMING_FILE, false),
      videoLimit: numberValue(KEY_AUTO_ROAMING_VIDEO_LIMIT, AUTO_ROAMING_VIDEO_LIMIT_DEFAULT),
      fileLimit: numberValue(KEY_AUTO_ROAMING_FILE_LIMIT, AUTO_ROAMING_FILE_LIMIT_DEFAULT),
      preloadLargeVideos: boolValue(KEY_AUTO_ROAMING_PRELOAD_VIDEO, false),
      preloadNextAudio: boolValue(KEY_AUTO_ROAMING_NEXT_AUDIO, false),
      preloadStories: boolValue(KEY_AUTO_ROAMING_STORIES, false),
      lessDataForCalls: boolValue(KEY_AUTO_LESS_DATA_CALLS, false)
    };
  }
  if (network === 'none') {
    return {
      network, photos: false, videos: false, files: false, videoLimit: 0, fileLimit: 0,
      preloadLargeVideos: false, preloadNextAudio: false, preloadStories: false,
      lessDataForCalls: boolValue(KEY_AUTO_LESS_DATA_CALLS, false)
    };
  }
  return {
    network, photos: boolValue(KEY_AUTO_MOBILE_PHOTO, true),
    videos: boolValue(KEY_AUTO_MOBILE_VIDEO, true), files: boolValue(KEY_AUTO_MOBILE_FILE, false),
    videoLimit: numberValue(KEY_AUTO_MOBILE_VIDEO_LIMIT, AUTO_MOBILE_VIDEO_LIMIT_DEFAULT),
    fileLimit: numberValue(KEY_AUTO_MOBILE_FILE_LIMIT, AUTO_MOBILE_FILE_LIMIT_DEFAULT),
    preloadLargeVideos: boolValue(KEY_AUTO_MOBILE_PRELOAD_VIDEO, false),
    preloadNextAudio: boolValue(KEY_AUTO_MOBILE_NEXT_AUDIO, true),
    preloadStories: boolValue(KEY_AUTO_MOBILE_STORIES, false),
    lessDataForCalls: boolValue(KEY_AUTO_LESS_DATA_CALLS, false)
  };
}

export function shouldAutoDownload(kind: string, size: number): boolean {
  const policy = autoDownloadPolicy();
  if (kind === 'photo') { return policy.photos; }
  const safeSize = Number.isFinite(size) && size > 0 ? size : Number.MAX_SAFE_INTEGER;
  if (kind === 'video' || kind === 'animation') {
    return policy.videos && safeSize <= policy.videoLimit;
  }
  if (kind === 'file' || kind === 'audio') {
    return policy.files && safeSize <= policy.fileLimit;
  }
  return false;
}

export function autosaveEnabled(scope: string): boolean {
  if (scope === 'channel') { return boolValue(KEY_AUTOSAVE_CHANNEL, false); }
  if (scope === 'group') { return boolValue(KEY_AUTOSAVE_GROUP, false); }
  return boolValue(KEY_AUTOSAVE_PRIVATE, false);
}

export function setNightMode(value: string): void {
  AppStorage.setOrCreate(KEY_NIGHT_MODE, value);
  persist(KEY_NIGHT_MODE, value);
  applyNightMode(value);
}

// Read helpers for non-component code (components use @StorageProp instead).
export function textSize(): number {
  return AppStorage.get<number>(KEY_TEXT_SIZE) ?? TEXT_SIZE_DEFAULT;
}

export function reduceAnimations(): boolean {
  return AppStorage.get<boolean>(KEY_REDUCE_ANIM) ?? false;
}

export function powerSavingActive(): boolean {
  return AppStorage.get<boolean>(KEY_POWER_ACTIVE) ?? false;
}

export function powerFeatureEnabled(key: string): boolean {
  return (AppStorage.get<boolean>(key) ?? true) && !powerSavingActive();
}

export function powerGroupFeatureEnabled(groupKey: string, key: string): boolean {
  return powerFeatureEnabled(groupKey) && powerFeatureEnabled(key);
}

export function powerAnimationDuration(key: string, duration: number): number {
  return powerFeatureEnabled(key) ? duration : 0;
}

export function powerGroupAnimationDuration(groupKey: string, key: string, duration: number): number {
  return powerGroupFeatureEnabled(groupKey, key) ? duration : 0;
}
