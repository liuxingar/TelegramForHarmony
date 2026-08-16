import { fileIo } from '@kit.CoreFileKit';
import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { ChatStore } from './ChatStore';
import { ChatThemeStore } from './ChatThemeStore';
import { fillColorsOf, objectOrNull } from '../util/backgroundPresentation';
import { gunzipTgs } from '../util/gunzipTgs';

// Everything the chat surface needs to paint its background. One immutable
// snapshot instead of the nine separate page state variables this replaces.
export interface ChatBackgroundState {
  custom: boolean;        // false = fall back to the app's chat_bg resource
  colors: string[];       // gradient fill, empty when the background is an image
  angle: number;          // gradient rotation, degrees
  path: string;           // local file once downloaded, '' while pending
  imageOpacity: number;   // pattern intensity, 1 for plain wallpapers
  dimming: number;        // 0..1, applied over the image in dark mode
  blurred: boolean;
  bubbleOutColor: string; // outgoing bubble tint carried by a chat theme
  // A pattern is a small tileable motif drawn over the fill; a photo wallpaper
  // is a single image that covers the surface. They need different fits, so the
  // renderer has to be able to tell them apart.
  isPattern: boolean;
}

export function emptyChatBackground(): ChatBackgroundState {
  return {
    custom: false, colors: [], angle: 180, path: '',
    imageOpacity: 1, dimming: 0, blurred: false, bubbleOutColor: '', isPattern: false
  };
}

type Listener = (state: ChatBackgroundState) => void;

// Inflated .tgv → .svg, remembered for the process.
//
// A fresh ChatBackgroundStore is constructed for every chat that opens, so
// without this each open pays a fileIo.access at best, and a gunzip plus a full
// file write whenever the cached .svg is gone. Both sat on the path between the
// tap and the first frame of the chat.
const inflatedPatterns: Map<string, string> = new Map();

// Resolves the background for one open chat, following the same precedence the
// official client uses: the chat's own background → its theme's background →
// the account default → the installed default for the current light/dark mode.
//
// Extracted from ChatPage, where this logic sat as nine @State variables, four
// TDLib subscriptions wired into aboutToAppear, and a dozen private methods.
// `isDarkMode` is injected rather than read here because determining it needs a
// UI resource context, which a store has no business holding.
export class ChatBackgroundStore {
  private client: TdClient;
  private chats: ChatStore;
  private themes: ChatThemeStore;
  private isDarkMode: () => boolean;

  private chatId: number = 0;
  private state: ChatBackgroundState = emptyChatBackground();
  private listeners: Listener[] = [];
  private unsubs: Array<() => void> = [];

  // Guards async resolution against a newer one having started meanwhile.
  private resolveSeq: number = 0;
  // Last applied background, serialized — avoids re-running identical updates.
  private signature: string = '';
  private fileId: number = 0;

  constructor(client: TdClient, chats: ChatStore, themes: ChatThemeStore,
    isDarkMode: () => boolean) {
    this.client = client;
    this.chats = chats;
    this.themes = themes;
    this.isDarkMode = isDarkMode;
  }

  current(): ChatBackgroundState {
    return this.state;
  }

  subscribe(listener: Listener): () => void {
    this.listeners = [...this.listeners, listener];
    listener(this.state);
    return (): void => {
      this.listeners = this.listeners.filter((l: Listener): boolean => l !== listener);
    };
  }

  private emit(): void {
    for (const listener of this.listeners) {
      listener(this.state);
    }
  }

  private patch(next: ChatBackgroundState): void {
    this.state = next;
    this.emit();
  }

  // ArkTS forbids object spread (arkts-no-spread), so field-wise copy it is.
  private cloned(): ChatBackgroundState {
    return {
      custom: this.state.custom,
      colors: this.state.colors,
      angle: this.state.angle,
      path: this.state.path,
      imageOpacity: this.state.imageOpacity,
      dimming: this.state.dimming,
      blurred: this.state.blurred,
      bubbleOutColor: this.state.bubbleOutColor,
      isPattern: this.state.isPattern
    };
  }

  private patchBubbleColor(color: string): void {
    const next: ChatBackgroundState = this.cloned();
    next.bubbleOutColor = color;
    this.patch(next);
  }

  private patchPath(path: string): void {
    const next: ChatBackgroundState = this.cloned();
    next.path = path;
    this.patch(next);
  }

  open(chatId: number): void {
    this.close();
    this.chatId = chatId;
    this.unsubs = [
      this.client.onUpdate('updateChatBackground', (u: TdObject): void => {
        if ((u['chat_id'] as number | undefined) !== this.chatId) {
          return;
        }
        const seq: number = ++this.resolveSeq;
        const background = objectOrNull(u['background']);
        if (background !== null) {
          this.applyBackground(background);
        } else {
          this.applyDefault(seq);
        }
      }),
      this.client.onUpdate('updateChatTheme', (u: TdObject): void => {
        if ((u['chat_id'] as number | undefined) !== this.chatId) {
          return;
        }
        const seq: number = ++this.resolveSeq;
        const themeName: string = (u['theme_name'] as string | undefined) ?? '';
        if (themeName === '') {
          const specific = this.chats.entryOf(this.chatId)?.background ?? null;
          if (specific !== null) {
            this.applyBackground(specific);
          } else {
            this.applyDefault(seq);
          }
        } else {
          this.applyTheme(themeName, seq);
        }
      }),
      this.client.onUpdate('updateDefaultBackground', (u: TdObject): void => {
        const forDarkTheme: boolean = (u['for_dark_theme'] as boolean | undefined) ?? false;
        if (forDarkTheme !== this.isDarkMode() || this.hasSpecificBackground()) {
          return;
        }
        const seq: number = ++this.resolveSeq;
        const background = objectOrNull(u['background']);
        if (background !== null) {
          this.applyBackground(background);
        } else {
          this.loadInstalledDefault(forDarkTheme, seq);
        }
      }),
      this.client.onUpdate('updateFile', (u: TdObject): void => {
        const file = u['file'] as TdObject | undefined;
        if (file !== undefined) {
          this.applyFile(file);
        }
      })
    ];
    this.refresh();
  }

  close(): void {
    for (const unsub of this.unsubs) {
      unsub();
    }
    this.unsubs = [];
    this.resolveSeq++;
    this.signature = '';
    this.fileId = 0;
    this.chatId = 0;
  }

  refresh(): void {
    // Reset the theme bubble tint; the theme path re-derives it in the same
    // tick when this chat still carries a theme.
    this.patchBubbleColor('');
    const cached = this.chats.entryOf(this.chatId);
    if (cached?.background !== null && cached?.background !== undefined) {
      this.applyBackground(cached.background);
    }
    const seq: number = ++this.resolveSeq;
    const request: TdRequest = { '@type': 'getChat' };
    request['chat_id'] = this.chatId;
    this.client.send(request).then((chat: TdObject): void => {
      if (seq !== this.resolveSeq) {
        return;
      }
      const background = objectOrNull(chat['background']);
      const themeName: string = (chat['theme_name'] as string | undefined) ?? '';
      if (background !== null || themeName === '') {
        if (background !== null) {
          this.applyBackground(background);
        } else {
          this.applyDefault(seq);
        }
      } else {
        this.applyTheme(themeName, seq);
      }
    }).catch((error: TdError): void => {
      console.error(`ChatBackgroundStore getChat failed: ${error.message}`);
    });
  }

  // A background already carried by a cached ChatEntry — the page hands this in
  // when it refreshes header identity, saving a round trip.
  applyKnownBackground(background: TdObject | null): void {
    this.applyBackground(background);
  }

  private hasSpecificBackground(): boolean {
    const entry = this.chats.entryOf(this.chatId);
    return entry !== undefined && (entry.background !== null || entry.themeName !== '');
  }

  // The image for a background is always the full document.
  //
  // Patterns used to take the thumbnail instead, and that is what made them
  // render at the wrong scale: the thumbnail is a picker-sized raster of the
  // whole motif sheet, so stretching it across the screen scales the motif up by
  // whatever the viewport/thumbnail ratio happens to be. No objectFit fixes a
  // source that is already the wrong thing. The real document is a .tgv —
  // gzipped SVG — which inflateIfPattern() unpacks below; being a vector it
  // scales exactly.
  private documentFile(background: TdObject): TdObject | null {
    const document = objectOrNull(background['document']);
    if (document === null) {
      return null;
    }
    return objectOrNull(document['document']);
  }

  // Pattern documents arrive as .tgv (gzipped SVG), which ArkUI's Image cannot
  // read. Inflate once next to the download and hand back the .svg path; the
  // file is regenerated if TDLib's cache ever drops it.
  private async inflateIfPattern(path: string): Promise<string> {
    if (!path.endsWith('.tgv')) {
      return path;
    }
    const memo = inflatedPatterns.get(path);
    if (memo !== undefined) {
      return memo;
    }
    const svgPath = `${path}.svg`;
    try {
      if (await fileIo.access(svgPath)) {
        inflatedPatterns.set(path, svgPath);
        return svgPath;
      }
      const svg = await gunzipTgs(path);
      if (svg === '') {
        return '';
      }
      const file = await fileIo.open(svgPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      await fileIo.write(file.fd, svg);
      await fileIo.close(file);
      inflatedPatterns.set(path, svgPath);
      return svgPath;
    } catch (e) {
      console.error(`ChatBackgroundStore.inflateIfPattern(${path}) failed: ${e}`);
      return '';
    }
  }

  private localPathOf(file: TdObject): string {
    const local = objectOrNull(file['local']);
    if (local === null ||
      !((local['is_downloading_completed'] as boolean | undefined) ?? false)) {
      return '';
    }
    return (local['path'] as string | undefined) ?? '';
  }

  private applyFile(file: TdObject): void {
    const id: number = (file['id'] as number | undefined) ?? 0;
    if (id === 0 || id !== this.fileId) {
      return;
    }
    const path: string = this.localPathOf(file);
    if (path !== '' && path !== this.state.path) {
      this.usePath(path, id);
    }
  }

  // Inflation is async, so a background resolved in the meantime must win:
  // fileId is re-checked before the state is touched.
  private usePath(path: string, id: number): void {
    if (!path.endsWith('.tgv')) {
      this.patchPath(path);
      return;
    }
    this.inflateIfPattern(path).then((usable: string): void => {
      if (usable !== '' && id === this.fileId) {
        this.patchPath(usable);
      }
    });
  }

  private requestFile(file: TdObject): void {
    const id: number = (file['id'] as number | undefined) ?? 0;
    this.fileId = id;
    if (id <= 0) {
      return;
    }
    const localPath: string = this.localPathOf(file);
    if (localPath !== '') {
      console.info(`[ChatBackground] chat=${this.chatId} file=${id} cached=true`);
      this.usePath(localPath, id);
      return;
    }
    console.info(`[ChatBackground] chat=${this.chatId} file=${id} download=true`);
    const request: TdRequest = { '@type': 'downloadFile' };
    request['file_id'] = id;
    request['priority'] = 1;
    request['offset'] = 0;
    request['limit'] = 0;
    request['synchronous'] = false;
    this.client.send(request).then((downloaded: TdObject): void => {
      this.applyFile(downloaded);
    }).catch((error: TdError): void => {
      console.error(`ChatBackgroundStore download ${id} failed: ${error.message}`);
    });
  }

  private applyBackground(chatBackground: TdObject | null): void {
    const signature: string =
      chatBackground !== null ? JSON.stringify(chatBackground) : 'none';
    if (signature === this.signature) {
      return;
    }
    this.signature = signature;
    this.fileId = 0;
    const bubbleOutColor: string = this.state.bubbleOutColor;
    const cleared: ChatBackgroundState = emptyChatBackground();
    cleared.bubbleOutColor = bubbleOutColor;
    this.patch(cleared);
    if (chatBackground === null) {
      return;
    }

    // Chat.background is a chatBackground wrapper around the reusable
    // background object. Accept a bare background too for API compatibility.
    const nested = objectOrNull(chatBackground['background']);
    const background = nested !== null ? nested : chatBackground;
    const type = objectOrNull(background['type']);
    if (type === null) {
      return;
    }
    const typeName: string = (type['@type'] as string | undefined) ?? '';
    if (typeName === 'backgroundTypeChatTheme') {
      const themeName: string = (type['theme_name'] as string | undefined) ?? '';
      if (themeName !== '') {
        this.applyTheme(themeName, ++this.resolveSeq);
      }
      return;
    }
    let fill: TdObject | null = null;
    let pattern: boolean = false;
    if (typeName === 'backgroundTypeFill' || typeName === 'backgroundTypePattern') {
      fill = objectOrNull(type['fill']);
      pattern = typeName === 'backgroundTypePattern';
    }
    const colors: string[] = fillColorsOf(fill);
    const angle: number = fill !== null
      ? ((fill['rotation_angle'] as number | undefined) ?? 180) : 180;
    const file = this.documentFile(background);
    const id: number = file !== null ? ((file['id'] as number | undefined) ?? 0) : 0;
    console.info(
      `[ChatBackground] chat=${this.chatId} type=${typeName} colors=${colors.length} file=${id}`
    );
    if (colors.length === 0 && id === 0) {
      return;
    }

    const dimming: number = Math.max(0, Math.min(
      1, ((chatBackground['dark_theme_dimming'] as number | undefined) ?? 0) / 100
    ));
    const blurred: boolean = typeName === 'backgroundTypeWallpaper' &&
      ((type['is_blurred'] as boolean | undefined) ?? false);
    let imageOpacity: number = 1;
    if (pattern) {
      const intensity: number = Math.abs((type['intensity'] as number | undefined) ?? 50);
      imageOpacity = Math.max(0.08, Math.min(1, intensity / 100));
    }
    this.patch({
      custom: true, colors, angle, path: '',
      imageOpacity, dimming, blurred, bubbleOutColor, isPattern: pattern
    });
    if (file !== null) {
      this.requestFile(file);
    }
  }

  private applyDefault(seq: number): void {
    const forDarkTheme: boolean = this.isDarkMode();
    if (this.chats.defaultBackgroundKnown(forDarkTheme)) {
      const background = this.chats.defaultBackground(forDarkTheme);
      if (background !== null) {
        this.applyBackground(background);
        return;
      }
    }
    this.loadInstalledDefault(forDarkTheme, seq);
  }

  private loadInstalledDefault(forDarkTheme: boolean, seq: number): void {
    const request: TdRequest = { '@type': 'getInstalledBackgrounds' };
    request['for_dark_theme'] = forDarkTheme;
    this.client.send(request).then((result: TdObject): void => {
      if (seq !== this.resolveSeq || this.hasSpecificBackground()) {
        return;
      }
      const backgrounds: TdObject[] = (result['backgrounds'] as TdObject[] | undefined) ?? [];
      const matchingDefaults = backgrounds.filter((item: TdObject): boolean =>
        ((item['is_default'] as boolean | undefined) ?? false) &&
        (((item['is_dark'] as boolean | undefined) ?? false) === forDarkTheme)
      );
      const matchingTheme = backgrounds.filter((item: TdObject): boolean =>
        (((item['is_dark'] as boolean | undefined) ?? false) === forDarkTheme)
      );
      // Never use an arbitrary background from the opposite color scheme. When
      // TDLib has no matching candidate the renderer keeps chat_bg.
      const selected = matchingDefaults.length > 0
        ? matchingDefaults[0] : (matchingTheme.length > 0 ? matchingTheme[0] : null);
      console.info(
        `[ChatBackground] chat=${this.chatId} source=installed dark=${forDarkTheme} ` +
        `count=${backgrounds.length} defaults=${matchingDefaults.length}`
      );
      this.applyBackground(selected);
    }).catch((error: TdError): void => {
      console.error(`ChatBackgroundStore getInstalledBackgrounds failed: ${error.message}`);
      if (seq === this.resolveSeq) {
        this.applyBackground(null);
      }
    });
  }

  // theme_name backgrounds live in TDLib's chat theme catalog rather than on
  // Chat.background. TDLib has no getChatThemes request — the list arrives once
  // per connection via updateChatThemes and is cached by ChatThemeStore.
  private applyTheme(themeName: string, seq: number): void {
    if (seq !== this.resolveSeq) {
      return;
    }
    const theme = this.themes.chatThemes().find((item: TdObject): boolean =>
      ((item['name'] as string | undefined) ?? '') === themeName
    );
    if (theme === undefined) {
      this.patchBubbleColor('');
      this.applyBackground(null);
      return;
    }
    const settingsName: string = this.isDarkMode() ? 'dark_settings' : 'light_settings';
    const settings = objectOrNull(theme[settingsName]);
    const bubbleColors: string[] = fillColorsOf(settings !== null
      ? objectOrNull(settings['outgoing_message_fill']) : null);
    this.patchBubbleColor(bubbleColors.length > 0 ? bubbleColors[0] : '');
    this.applyBackground(settings !== null ? objectOrNull(settings['background']) : null);
  }
}

// Resolve the account-default background once at startup so the first chat that
// opens finds the file downloaded and the pattern already inflated, instead of
// paying for both between the tap and the first frame.
//
// chatId 0 matches no chat, so the per-chat updates this store subscribes to
// never fire for it and it settles on the account default — exactly what most
// chats resolve to anyway. It is closed straight after; the work it warms lives
// in TDLib's file cache and in inflatedPatterns, both process-wide.
export function preloadDefaultChatBackground(
  client: TdClient, chats: ChatStore, themes: ChatThemeStore, isDarkMode: () => boolean,
  onResolved: (state: ChatBackgroundState) => void = (): void => {}
): void {
  const store = new ChatBackgroundStore(client, chats, themes, isDarkMode);
  const unsub = store.subscribe((state: ChatBackgroundState): void => {
    // A pure-gradient background is fully resolved with no file at all, so
    // waiting for a path would leave those unrasterised forever.
    if (state.path !== '' || state.colors.length > 0) {
      unsub();
      store.close();
      onResolved(state);
    }
  });
  store.open(0);
}
