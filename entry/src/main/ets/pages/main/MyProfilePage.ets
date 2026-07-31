import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { cameraPicker } from '@kit.CameraKit';
import { camera } from '@kit.CameraKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { StickerPicker, StickerItem } from '../chat/StickerPicker';
import { getTdClient } from '../../tdkit/Globals';
import { ProfileStore, StoryItem } from '../../store/ProfileStore';
import { AvatarView } from '../chatlist/AvatarView';
import { QrDialog } from '../common/QrDialog';
import { TgsStickerView } from '../chat/TgsStickerView';
import { WebmStickerView } from '../chat/WebmStickerView';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { publicLink } from '../../util/telegramLink';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';

const CARD_BG: ResourceColor = $r('app.color.surface');
const CARD_RADIUS: number = 14;
const PAGE_BG: ResourceColor = $r('app.color.page_bg');
const TOP_ACTION_SIZE: number = 44;
const PROFILE_LOAD_TIMEOUT_MS: number = 8000;

// The current user's own profile tab (Telegram-style "my profile"): avatar
// header, 设置照片/编辑信息/设置 quick actions, an info card (phone/username/
// birthday) and the 动态 posts section. Mirrors ProfileStore snapshot into
// @State so every card re-renders on updates.
@Preview
@Component
export struct MyProfilePage {
  @Prop active: boolean = false;
  onOpenSettings: () => void = (): void => {};
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageProp('screenWidthVp') screenW: number = 360;
  @StorageProp('appIsForeground') appIsForeground: boolean = false;
  @State myId: number = 0;
  @State name: string = '';
  @State initials: string = '?';
  @State avatarPath: string = '';
  @State avatarAnimPath: string = '';
  @State statusEmojiPath: string = '';
  @State statusEmojiFormat: string = '';
  @State statusText: string = '';
  @State phone: string = '';
  @State usernames: string[] = [];
  @State birthday: string = '';
  @State postTab: number = 0; // 0 动态 / 1 已归档的动态
  @State stories: StoryItem[] = [];
  @State storiesLoading: boolean = true;
  @State storiesError: string = '';
  @State archivedStories: StoryItem[] = [];
  @State archivedStoriesLoading: boolean = false;
  @State archivedStoriesLoaded: boolean = false;
  @State archivedStoriesError: string = '';
  @State profileLoading: boolean = true;
  @State profileError: string = '';
  @State headerVisible: boolean = false;
  @State avatarPressed: boolean = false;
  @State photoUploading: boolean = false;
  @State openingEditor: boolean = false;
  @State topMenuOpen: boolean = false;
  @State photoMenuOpen: boolean = false;
  @State switchingToSettings: boolean = false;
  @State pressedQuickAction: string = '';
  @State pressedInfoKey: string = '';
  @State copyingInfoKey: string = '';
  @State copiedInfoKey: string = '';
  @State pressedPostTab: number = -1;
  @State postTabsWidth: number = 0;
  @State pressedPostStateAction: string = '';
  @State storyPickerOpen: boolean = false;
  @State storyPosting: boolean = false;
  private store: ProfileStore | null = null;
  private unsub: (() => void) | null = null;
  private profileLoadSequence: number = 0;
  private profileLoadTimer: number = -1;
  private headerRevealTimer: number = -1;
  private editorNavigationTimer: number = -1;
  private settingsNavigationTimer: number = -1;
  private copiedInfoTimer: number = -1;
  private photoUploadSequence: number = 0;
  private storyUploadSequence: number = 0;
  private storyChatId: number = 0;

  aboutToAppear(): void {
    this.loadProfile();
  }

  private loadProfile(): void {
    const sequence = ++this.profileLoadSequence;
    this.closeProfileStore();
    this.clearProfileLoadTimer();
    this.profileLoading = true;
    this.profileError = '';
    this.stories = [];
    this.storiesLoading = true;
    this.storiesError = '';
    this.archivedStories = [];
    this.archivedStoriesLoading = false;
    this.archivedStoriesLoaded = false;
    this.archivedStoriesError = '';
    this.headerVisible = false;
    this.headerRevealTimer = setTimeout((): void => {
      this.headerRevealTimer = -1;
      this.headerVisible = true;
    }, powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 40));
    const req: TdRequest = { '@type': 'getMe' };
    getTdClient().send(req, PROFILE_LOAD_TIMEOUT_MS).then((me: TdObject) => {
      if (sequence !== this.profileLoadSequence) {
        return;
      }
      this.myId = (me['id'] as number | undefined) ?? 0;
      if (this.myId === 0) {
        this.profileLoading = false;
        this.profileError = '暂时无法读取个人资料';
        return;
      }
      const store = new ProfileStore(getTdClient(), this.myId);
      this.store = store;
      this.unsub = store.subscribe(() => { this.refresh(); });
      store.open();
      if (this.postTab === 1) {
        store.loadArchivedStories();
      }
      this.profileLoadTimer = setTimeout((): void => {
        this.profileLoadTimer = -1;
        if (sequence === this.profileLoadSequence && this.profileLoading) {
          this.profileLoading = false;
          this.profileError = '个人资料加载超时';
        }
      }, PROFILE_LOAD_TIMEOUT_MS);
    }).catch((e: TdError) => {
      if (sequence !== this.profileLoadSequence) {
        return;
      }
      this.clearProfileLoadTimer();
      this.profileLoading = false;
      this.profileError = '个人资料加载失败';
      console.error(`MyProfilePage.getMe failed: ${e.message}`);
    });
  }

  aboutToDisappear(): void {
    this.profileLoadSequence++;
    this.photoUploadSequence++;
    this.storyUploadSequence++;
    this.clearProfileLoadTimer();
    this.closeProfileStore();
    if (this.headerRevealTimer !== -1) {
      clearTimeout(this.headerRevealTimer);
      this.headerRevealTimer = -1;
    }
    if (this.editorNavigationTimer !== -1) {
      clearTimeout(this.editorNavigationTimer);
      this.editorNavigationTimer = -1;
    }
    if (this.settingsNavigationTimer !== -1) {
      clearTimeout(this.settingsNavigationTimer);
      this.settingsNavigationTimer = -1;
    }
    if (this.copiedInfoTimer !== -1) {
      clearTimeout(this.copiedInfoTimer);
      this.copiedInfoTimer = -1;
    }
    this.headerVisible = false;
    this.avatarPressed = false;
    this.openingEditor = false;
    this.topMenuOpen = false;
    this.photoMenuOpen = false;
    this.switchingToSettings = false;
    this.pressedQuickAction = '';
    this.pressedInfoKey = '';
    this.copyingInfoKey = '';
    this.copiedInfoKey = '';
    this.pressedPostTab = -1;
    this.pressedPostStateAction = '';
    this.storyPickerOpen = false;
    this.storyPosting = false;
  }

  private closeProfileStore(): void {
    if (this.unsub !== null) { this.unsub(); this.unsub = null; }
    if (this.store !== null) { this.store.close(); this.store = null; }
  }

  private clearProfileLoadTimer(): void {
    if (this.profileLoadTimer !== -1) {
      clearTimeout(this.profileLoadTimer);
      this.profileLoadTimer = -1;
    }
  }

  private retryProfile(): void {
    if (this.profileLoading || this.photoUploading || this.openingEditor) {
      return;
    }
    this.loadProfile();
  }

  @State qrLink: string = '';
  private qrCtrl: CustomDialogController = new CustomDialogController({
    builder: QrDialog({ link: this.qrLink, title: this.name }),
    alignment: DialogAlignment.Center,
    autoCancel: true
  });

  private openQr(): void {
    if (this.profileLoading || this.profileError !== '' ||
      this.photoUploading || this.photoMenuOpen || this.openingEditor ||
      this.switchingToSettings || this.topMenuOpen) {
      return;
    }
    if (this.usernames.length === 0) {
      promptAction.showToast({ message: '未设置用户名，无法生成二维码', duration: 1800 });
      return;
    }
    this.qrLink = publicLink(this.usernames[0]);
    this.qrCtrl.open();
  }

  private openEditor(): void {
    if (this.profileLoading || this.profileError !== '' ||
      this.photoUploading || this.photoMenuOpen || this.openingEditor ||
      this.switchingToSettings || this.topMenuOpen) {
      return;
    }
    this.openingEditor = true;
    this.editorNavigationTimer = setTimeout((): void => {
      this.editorNavigationTimer = -1;
      this.openingEditor = false;
    }, 700);
    router.pushUrl({ url: 'pages/main/AccountEditPage' }).catch((error: Error): void => {
      console.error(`MyProfilePage.openEditor failed: ${error.message}`);
      promptAction.showToast({ message: '无法打开账号资料，请稍后重试', duration: 1800 });
      if (this.editorNavigationTimer !== -1) {
        clearTimeout(this.editorNavigationTimer);
        this.editorNavigationTimer = -1;
      }
      this.openingEditor = false;
    });
  }

  private openSettings(): void {
    if (this.photoUploading || this.photoMenuOpen || this.openingEditor ||
      this.switchingToSettings || this.topMenuOpen) {
      return;
    }
    this.switchingToSettings = true;
    this.pressedQuickAction = '';
    this.settingsNavigationTimer = setTimeout((): void => {
      this.settingsNavigationTimer = -1;
      this.switchingToSettings = false;
    }, 520);
    this.onOpenSettings();
  }

  private showTopMenu(): void {
    if (this.profileLoading || this.profileError !== '' ||
      this.photoUploading || this.photoMenuOpen || this.openingEditor ||
      this.switchingToSettings || this.topMenuOpen) {
      return;
    }
    this.topMenuOpen = true;
    promptAction.showActionMenu({
      title: this.name !== '' ? this.name : '个人资料',
      buttons: [
        { text: '编辑个人资料', color: '#3390EC' },
        { text: '设置头像', color: '#3390EC' },
        { text: '显示二维码', color: '#3390EC' }
      ]
    }).then((result): void => {
      this.topMenuOpen = false;
      if (result.index === 0) {
        this.openEditor();
      } else if (result.index === 1) {
        this.setPhotoMenu();
      } else if (result.index === 2) {
        this.openQr();
      }
    }).catch((): void => {
      this.topMenuOpen = false;
    });
  }

  private stickerCtrl: CustomDialogController = new CustomDialogController({
    builder: StickerAvatarDialog({ onPick: (st: StickerItem): void => { this.onStickerPicked(st); } }),
    alignment: DialogAlignment.Bottom,
    autoCancel: true,
    customStyle: true
  });

  // 设置照片: camera / gallery / sticker.
  private setPhotoMenu(): void {
    if (this.profileLoading || this.profileError !== '' ||
      this.photoUploading || this.photoMenuOpen || this.openingEditor ||
      this.switchingToSettings || this.topMenuOpen) {
      return;
    }
    this.photoMenuOpen = true;
    promptAction.showActionMenu({
      title: '设置照片',
      buttons: [
        { text: '拍照', color: '#3390EC' },
        { text: '从相册选择', color: '#3390EC' },
        { text: '表情贴纸', color: '#3390EC' }
      ]
    }).then((r) => {
      this.photoMenuOpen = false;
      if (r.index === 0) {
        this.photoFromCamera();
      } else if (r.index === 1) {
        this.photoFromGallery();
      } else if (r.index === 2) {
        this.stickerCtrl.open();
      }
    }).catch((e: Object) => {
      this.photoMenuOpen = false;
      console.error(`MyProfilePage.setPhotoMenu failed: ${JSON.stringify(e)}`);
    });
  }

  private async photoFromCamera(): Promise<void> {
    try {
      const profile: cameraPicker.PickerProfile = {
        cameraPosition: camera.CameraPosition.CAMERA_POSITION_FRONT
      };
      const res = await cameraPicker.pick(getContext(this) as common.Context,
        [cameraPicker.PickerMediaType.PHOTO], profile);
      if (res.resultCode === 0 && res.resultUri !== '') {
        const path = this.copyUriToCache(res.resultUri);
        if (path !== '') {
          this.uploadPhoto(path);
        }
      }
    } catch (e) {
      console.error(`MyProfilePage.photoFromCamera failed: ${e}`);
    }
  }

  private photoFromGallery(): void {
    const picker = new photoAccessHelper.PhotoViewPicker();
    const opts = new photoAccessHelper.PhotoSelectOptions();
    opts.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    opts.maxSelectNumber = 1;
    picker.select(opts).then((res: photoAccessHelper.PhotoSelectResult) => {
      const uris = res.photoUris;
      if (uris.length > 0) {
        const path = this.copyUriToCache(uris[0]);
        if (path !== '') {
          this.uploadPhoto(path);
        }
      }
    }).catch((e: Object) => {
      console.error(`MyProfilePage.photoFromGallery failed: ${JSON.stringify(e)}`);
    });
  }

  // Emoji/sticker avatar: static raster of the picked sticker (webp source
  // directly; animated formats fall back to their raster thumbnail).
  private onStickerPicked(st: StickerItem): void {
    this.stickerCtrl.close();
    if (st.format === 'webp') {
      const req: TdRequest = { '@type': 'downloadFile' };
      req['file_id'] = st.fileId;
      req['priority'] = 1;
      req['synchronous'] = true;
      getTdClient().send(req).then((f: TdObject) => {
        const local = f['local'] as TdObject | undefined;
        const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
        if (path !== '') {
          this.uploadPhotoScaled(path);
        }
      }).catch((e: TdError) => {
        console.error(`MyProfilePage sticker download failed: ${e.message}`);
      });
    } else if (st.thumbPath !== '') {
      this.uploadPhotoScaled(st.thumbPath);
    } else if (st.thumbFileId > 0) {
      // Thumbnail wasn't downloaded yet (cell showed the fallback character).
      const req: TdRequest = { '@type': 'downloadFile' };
      req['file_id'] = st.thumbFileId;
      req['priority'] = 1;
      req['synchronous'] = true;
      getTdClient().send(req).then((f: TdObject) => {
        const local = f['local'] as TdObject | undefined;
        const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
        if (path !== '') {
          this.uploadPhotoScaled(path);
        }
      }).catch((e: TdError) => {
        console.error(`MyProfilePage thumb download failed: ${e.message}`);
      });
    } else {
      promptAction.showToast({ message: '该表情暂不可用作头像（unicode 表情请截图或用贴纸）', duration: 2000 });
    }
  }

  // Telegram rejects avatars smaller than 512px (PHOTO_CROP_SIZE_SMALL) —
  // sticker thumbnails are ~128px, so upscale and re-encode before upload.
  private async upscaleForAvatar(path: string): Promise<string> {
    try {
      const src = image.createImageSource(path);
      const info = await src.getImageInfo();
      const w = info.size.width;
      const h = info.size.height;
      if (Math.min(w, h) >= 512) {
        src.release();
        return path;
      }
      const scale = 640 / Math.min(w, h);
      const pm = await src.createPixelMap({
        desiredSize: { width: Math.round(w * scale), height: Math.round(h * scale) }
      });
      const packer = image.createImagePacker();
      const buf = await packer.packing(pm, { format: 'image/jpeg', quality: 92 });
      packer.release();
      pm.release();
      src.release();
      const dest = `${(getContext(this) as common.UIAbilityContext).cacheDir}/avatar_up_${Date.now()}.jpg`;
      const f = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      fs.writeSync(f.fd, buf);
      fs.closeSync(f);
      return dest;
    } catch (e) {
      console.error(`MyProfilePage.upscaleForAvatar failed: ${e}`);
      return path;
    }
  }

  private async uploadPhotoScaled(path: string): Promise<void> {
    this.uploadPhoto(await this.upscaleForAvatar(path));
  }

  private uploadPhoto(path: string): void {
    if (path === '' || this.photoUploading) {
      return;
    }
    const sequence = ++this.photoUploadSequence;
    this.photoUploading = true;
    const inputFile: TdObject = { '@type': 'inputFileLocal' };
    inputFile['path'] = path;
    const photo: TdObject = { '@type': 'inputChatPhotoStatic' };
    photo['photo'] = inputFile;
    const req: TdRequest = { '@type': 'setProfilePhoto' };
    req['photo'] = photo;
    req['is_public'] = false;
    getTdClient().send(req).then(() => {
      if (sequence !== this.photoUploadSequence) {
        return;
      }
      this.photoUploading = false;
      promptAction.showToast({ message: '头像已更新', duration: 1500 });
      if (this.store !== null) {
        this.store.reload();
      }
    }).catch((e: TdError) => {
      if (sequence !== this.photoUploadSequence) {
        return;
      }
      this.photoUploading = false;
      console.error(`MyProfilePage.setProfilePhoto failed: ${e.message}`);
      promptAction.showToast({ message: '头像设置失败，请稍后重试', duration: 2000 });
    });
  }

  private copyUriToCache(uri: string): string {
    try {
      const name = decodeURIComponent(uri.substring(uri.lastIndexOf('/') + 1));
      const dest = `${(getContext(this) as common.UIAbilityContext).cacheDir}/avatar_${Date.now()}_${name}`;
      const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      fs.copyFileSync(src.fd, dest);
      fs.closeSync(src);
      return dest;
    } catch (e) {
      console.error(`MyProfilePage.copyUriToCache failed: ${e}`);
      return '';
    }
  }

  private refresh(): void {
    const s = this.store;
    if (s === null) {
      return;
    }
    this.name = s.name;
    this.initials = s.initials;
    this.avatarPath = s.avatarPath;
    this.avatarAnimPath = s.avatarAnimPath;
    this.statusEmojiPath = s.statusEmojiPath;
    this.statusEmojiFormat = s.statusEmojiFormat;
    this.statusText = s.statusText;
    this.phone = s.phone;
    this.usernames = s.usernames;
    this.birthday = s.birthday;
    const postStateChanged = this.storyItemsChanged(this.stories, s.stories) ||
      this.storyItemsChanged(this.archivedStories, s.archivedStories) ||
      this.storiesLoading !== s.storiesLoading ||
      this.storiesError !== s.storiesError ||
      this.archivedStoriesLoading !== s.archivedStoriesLoading ||
      this.archivedStoriesLoaded !== s.archivedStoriesLoaded ||
      this.archivedStoriesError !== s.archivedStoriesError;
    if (postStateChanged && this.active) {
      animateTo({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }, (): void => {
        this.applyPostSnapshot(s);
      });
    } else {
      this.applyPostSnapshot(s);
    }
    if (this.name !== '') {
      this.clearProfileLoadTimer();
      this.profileLoading = false;
      this.profileError = '';
    }
  }

  private storyItemsChanged(current: StoryItem[], next: StoryItem[]): boolean {
    return current.length !== next.length ||
      current.some((item: StoryItem, index: number): boolean => {
        const candidate = next[index];
        return candidate === undefined || item.id !== candidate.id ||
          item.thumbPath !== candidate.thumbPath;
      });
  }

  private applyPostSnapshot(store: ProfileStore): void {
    this.stories = store.stories;
    this.storiesLoading = store.storiesLoading;
    this.storiesError = store.storiesError;
    this.archivedStories = store.archivedStories;
    this.archivedStoriesLoading = store.archivedStoriesLoading;
    this.archivedStoriesLoaded = store.archivedStoriesLoaded;
    this.archivedStoriesError = store.archivedStoriesError;
  }

  private displayedStatusText(): string {
    if (this.appIsForeground) {
      return '在线';
    }
    return this.statusText !== '' ? this.statusText : 'Telegram 账号';
  }

  private quickActionBusy(key: string): boolean {
    if (key === 'photo') {
      return this.photoUploading || this.photoMenuOpen;
    }
    if (key === 'edit') {
      return this.openingEditor;
    }
    return key === 'settings' && this.switchingToSettings;
  }

  private quickActionEnabled(key: string): boolean {
    if (this.photoUploading || this.photoMenuOpen || this.openingEditor ||
      this.switchingToSettings || this.topMenuOpen) {
      return false;
    }
    if (key === 'settings') {
      return true;
    }
    return !this.profileLoading && this.profileError === '';
  }

  private quickActionLabel(key: string, label: string): string {
    if (key === 'photo') {
      return this.photoUploading ? '上传中' : (this.photoMenuOpen ? '选择中' : label);
    }
    if (key === 'edit' && this.openingEditor) {
      return '打开中';
    }
    if (key === 'settings' && this.switchingToSettings) {
      return '切换中';
    }
    return label;
  }

  private infoValue(key: string): string {
    if (key === 'phone') {
      return this.phone !== '' ? `+${this.phone}` : '';
    }
    if (key === 'username') {
      return this.usernames.length > 0 ? `@${this.usernames[0]}` : '';
    }
    return key === 'birthday' ? this.birthday : '';
  }

  private infoTitle(key: string): string {
    if (key === 'phone') {
      return '手机号码';
    }
    if (key === 'username') {
      return '用户名';
    }
    return '生日';
  }

  private infoHint(key: string): string {
    if (key === 'phone') {
      return '用于登录和账号安全';
    }
    if (key === 'username') {
      return '他人可通过用户名找到你';
    }
    return '你的个人生日信息';
  }

  private infoIcon(key: string): string {
    if (key === 'phone') {
      return 'sys.symbol.phone_fill';
    }
    if (key === 'username') {
      return 'sys.symbol.at';
    }
    return 'sys.symbol.cake';
  }

  private infoColor(key: string): string {
    if (key === 'phone') {
      return '#34C759';
    }
    if (key === 'username') {
      return '#FF9500';
    }
    return '#3478F6';
  }

  private infoTint(key: string): string {
    if (key === 'phone') {
      return '#1834C759';
    }
    if (key === 'username') {
      return '#18FF9500';
    }
    return '#183478F6';
  }

  private infoItemCount(): number {
    let count = 0;
    if (this.phone !== '') { count++; }
    if (this.usernames.length > 0) { count++; }
    if (this.birthday !== '') { count++; }
    return count;
  }

  private copyInfo(key: string): void {
    const value = this.infoValue(key);
    if (value === '' || this.copyingInfoKey !== '' || this.openingEditor) {
      return;
    }
    this.pressedInfoKey = '';
    this.copyingInfoKey = key;
    this.copiedInfoKey = '';
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value);
    pasteboard.getSystemPasteboard().setData(data).then((): void => {
      this.copyingInfoKey = '';
      this.copiedInfoKey = key;
      promptAction.showToast({
        message: `已复制${this.infoTitle(key)}`,
        duration: 1200
      });
      if (this.copiedInfoTimer !== -1) {
        clearTimeout(this.copiedInfoTimer);
      }
      this.copiedInfoTimer = setTimeout((): void => {
        this.copiedInfoTimer = -1;
        if (this.copiedInfoKey === key) {
          this.copiedInfoKey = '';
        }
      }, 1000);
    }).catch((caught: Object): void => {
      this.copyingInfoKey = '';
      console.error(`MyProfilePage.copyInfo(${key}) failed: ${JSON.stringify(caught)}`);
      promptAction.showToast({ message: '复制失败，请稍后重试', duration: 1500 });
    });
  }

  private selectPostTab(index: number): void {
    this.pressedPostTab = -1;
    if (index < 0 || index > 1 || this.postTab === index) {
      return;
    }
    if (index === 1 && this.store !== null &&
      !this.archivedStoriesLoaded && !this.archivedStoriesLoading) {
      this.store.loadArchivedStories();
    }
    animateTo({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 220),
      curve: Curve.EaseOut
    }, (): void => {
      this.postTab = index;
    });
  }

  private handlePostSwipe(angle: number): void {
    const normalized = ((angle % 360) + 360) % 360;
    if (normalized > 135 && normalized < 225) {
      this.selectPostTab(1);
    } else if (normalized < 45 || normalized > 315) {
      this.selectPostTab(0);
    }
  }

  private postTabIcon(index: number): string {
    return index === 0 ? 'sys.symbol.camera' : 'sys.symbol.archivebox';
  }

  private postIndicatorWidth(): number {
    return Math.max(0, (this.postTabsWidth - 6) / 2);
  }

  private storyCell(): number {
    return (this.screenW - 4) / 3;
  }

  private formatStoryDuration(totalSeconds: number): string {
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return `${minutes}:${`${seconds}`.padStart(2, '0')}`;
  }

  private storyPostUnavailableText(result: TdObject): string {
    const type = (result['@type'] as string | undefined) ?? '';
    if (type === 'canPostStoryResultPremiumNeeded') {
      return '当前账号需要 Telegram Premium 才能发布动态';
    }
    if (type === 'canPostStoryResultActiveStoryLimitExceeded') {
      return '当前动态数量已达到上限';
    }
    if (type === 'canPostStoryResultWeeklyLimitExceeded' ||
      type === 'canPostStoryResultMonthlyLimitExceeded') {
      return '动态发布次数已达到限制，请稍后再试';
    }
    return '当前暂时无法发布动态';
  }

  private openStoryComposer(): void {
    if (this.profileLoading || this.profileError !== '' || this.myId === 0 ||
      this.storyPickerOpen || this.storyPosting || this.photoMenuOpen) {
      return;
    }
    this.storyPickerOpen = true;
    const continueWithChat = (chatId: number): void => {
      const canPost: TdRequest = { '@type': 'canPostStory' };
      canPost['chat_id'] = chatId;
      getTdClient().send(canPost).then((result: TdObject): void => {
        if (!this.storyPickerOpen) {
          return;
        }
        if (result['@type'] !== 'canPostStoryResultOk') {
          this.storyPickerOpen = false;
          promptAction.showToast({
            message: this.storyPostUnavailableText(result),
            duration: 2200
          });
          return;
        }
        promptAction.showActionMenu({
          title: '添加动态',
          buttons: [
            { text: '拍摄照片', color: '#3390EC' },
            { text: '从相册选择', color: '#3390EC' }
          ]
        }).then((choice): void => {
          this.storyPickerOpen = false;
          if (choice.index === 0) {
            this.storyFromCamera();
          } else if (choice.index === 1) {
            this.storyFromGallery();
          }
        }).catch((): void => {
          this.storyPickerOpen = false;
        });
      }).catch((error: TdError): void => {
        this.storyPickerOpen = false;
        console.error(`MyProfilePage.canPostStory failed: ${error.message}`);
        promptAction.showToast({ message: '暂时无法添加动态，请稍后重试', duration: 1800 });
      });
    };
    if (this.storyChatId > 0) {
      continueWithChat(this.storyChatId);
      return;
    }
    const create: TdRequest = { '@type': 'createPrivateChat' };
    create['user_id'] = this.myId;
    create['force'] = false;
    getTdClient().send(create).then((chat: TdObject): void => {
      if (!this.storyPickerOpen) {
        return;
      }
      this.storyChatId = (chat['id'] as number | undefined) ?? this.myId;
      continueWithChat(this.storyChatId);
    }).catch((error: TdError): void => {
      this.storyPickerOpen = false;
      console.error(`MyProfilePage.createStoryChat failed: ${error.message}`);
      promptAction.showToast({ message: '暂时无法添加动态，请稍后重试', duration: 1800 });
    });
  }

  private async storyFromCamera(): Promise<void> {
    try {
      const profile: cameraPicker.PickerProfile = {
        cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK
      };
      const result = await cameraPicker.pick(getContext(this) as common.Context,
        [cameraPicker.PickerMediaType.PHOTO], profile);
      if (result.resultCode === 0 && result.resultUri !== '') {
        const path = this.copyUriToCache(result.resultUri);
        if (path !== '') {
          this.confirmStoryPrivacy(path);
        }
      }
    } catch (error) {
      console.error(`MyProfilePage.storyFromCamera failed: ${error}`);
      promptAction.showToast({ message: '无法打开相机，请稍后重试', duration: 1800 });
    }
  }

  private storyFromGallery(): void {
    const picker = new photoAccessHelper.PhotoViewPicker();
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;
    picker.select(options).then((result: photoAccessHelper.PhotoSelectResult): void => {
      if (result.photoUris.length === 0) {
        return;
      }
      const path = this.copyUriToCache(result.photoUris[0]);
      if (path !== '') {
        this.confirmStoryPrivacy(path);
      }
    }).catch((error: Object): void => {
      console.error(`MyProfilePage.storyFromGallery failed: ${JSON.stringify(error)}`);
      promptAction.showToast({ message: '无法打开相册，请稍后重试', duration: 1800 });
    });
  }

  private confirmStoryPrivacy(sourcePath: string): void {
    if (this.storyPosting || this.storyPickerOpen) {
      return;
    }
    this.storyPickerOpen = true;
    promptAction.showActionMenu({
      title: '谁可以查看这条动态？',
      buttons: [
        { text: '所有人', color: '#3390EC' },
        { text: '我的联系人', color: '#3390EC' },
        { text: '亲密好友', color: '#3390EC' }
      ]
    }).then((choice): void => {
      this.storyPickerOpen = false;
      if (choice.index === 0) {
        this.postPhotoStory(sourcePath, 'storyPrivacySettingsEveryone');
      } else if (choice.index === 1) {
        this.postPhotoStory(sourcePath, 'storyPrivacySettingsContacts');
      } else if (choice.index === 2) {
        this.postPhotoStory(sourcePath, 'storyPrivacySettingsCloseFriends');
      }
    }).catch((): void => {
      this.storyPickerOpen = false;
    });
  }

  private async prepareStoryPhoto(path: string): Promise<string> {
    try {
      const source = image.createImageSource(path);
      const info = await source.getImageInfo();
      const width = info.size.width;
      const height = info.size.height;
      if (width <= 0 || height <= 0) {
        source.release();
        return '';
      }
      const storyRatio = 9 / 16;
      let cropWidth = width;
      let cropHeight = height;
      let cropX = 0;
      let cropY = 0;
      if (width / height > storyRatio) {
        cropWidth = Math.max(1, Math.round(height * storyRatio));
        cropX = Math.max(0, Math.floor((width - cropWidth) / 2));
      } else {
        cropHeight = Math.max(1, Math.round(width / storyRatio));
        cropY = Math.max(0, Math.floor((height - cropHeight) / 2));
      }
      const pixelMap = await source.createPixelMap({
        desiredRegion: {
          x: cropX,
          y: cropY,
          size: { width: cropWidth, height: cropHeight }
        },
        desiredSize: { width: 1080, height: 1920 }
      });
      const packer = image.createImagePacker();
      const buffer = await packer.packing(pixelMap, { format: 'image/jpeg', quality: 92 });
      const destination =
        `${(getContext(this) as common.UIAbilityContext).cacheDir}/story_${Date.now()}.jpg`;
      const file = fs.openSync(destination, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      fs.writeSync(file.fd, buffer);
      fs.closeSync(file);
      packer.release();
      pixelMap.release();
      source.release();
      return destination;
    } catch (error) {
      console.error(`MyProfilePage.prepareStoryPhoto failed: ${error}`);
      return '';
    }
  }

  private async postPhotoStory(sourcePath: string, privacyType: string): Promise<void> {
    if (this.storyPosting || this.storyChatId <= 0) {
      return;
    }
    const sequence = ++this.storyUploadSequence;
    this.storyPosting = true;
    const path = await this.prepareStoryPhoto(sourcePath);
    if (sequence !== this.storyUploadSequence) {
      return;
    }
    if (path === '') {
      this.storyPosting = false;
      promptAction.showToast({ message: '照片处理失败，请重新选择', duration: 1800 });
      return;
    }
    const inputFile: TdObject = { '@type': 'inputFileLocal' };
    inputFile['path'] = path;
    const content: TdObject = { '@type': 'inputStoryContentPhoto' };
    content['photo'] = inputFile;
    content['added_sticker_file_ids'] = [];
    const caption: TdObject = { '@type': 'formattedText' };
    caption['text'] = '';
    caption['entities'] = [];
    const request: TdRequest = { '@type': 'postStory' };
    request['chat_id'] = this.storyChatId;
    request['content'] = content;
    request['caption'] = caption;
    const privacy: TdObject = { '@type': privacyType };
    if (privacyType === 'storyPrivacySettingsEveryone' ||
      privacyType === 'storyPrivacySettingsContacts') {
      privacy['except_user_ids'] = [];
    }
    request['privacy_settings'] = privacy;
    request['album_ids'] = [];
    request['active_period'] = 24 * 60 * 60;
    request['is_posted_to_chat_page'] = true;
    request['protect_content'] = false;
    getTdClient().send(request).then((): void => {
      if (sequence !== this.storyUploadSequence) {
        return;
      }
      this.storyPosting = false;
      promptAction.showToast({ message: '动态已发布', duration: 1500 });
      this.store?.reloadStories();
    }).catch((error: TdError): void => {
      if (sequence !== this.storyUploadSequence) {
        return;
      }
      this.storyPosting = false;
      console.error(`MyProfilePage.postStory failed: ${error.message}`);
      promptAction.showToast({ message: '动态发布失败，请稍后重试', duration: 2000 });
    });
  }

  private retryPostState(key: string): void {
    this.pressedPostStateAction = '';
    if (key === 'profile') {
      this.retryProfile();
      return;
    }
    const s = this.store;
    if (s === null) {
      this.retryProfile();
      return;
    }
    if (key === 'archive') {
      s.loadArchivedStories(true);
    } else {
      s.reloadStories();
    }
  }

  @Styles
  topActionNormalStyle() {
    .backgroundColor(CARD_BG)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  topActionPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.72)
    .scale({ x: 0.92, y: 0.92 })
  }

  @Builder
  circleButton(symbol: string, label: string, onTap: () => void) {
    Row() {
      SymbolGlyph($r(symbol)).fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
    }
    .width(TOP_ACTION_SIZE).height(TOP_ACTION_SIZE).borderRadius(TOP_ACTION_SIZE / 2)
    .justifyContent(FlexAlign.Center)
    .shadow({ radius: 4, color: '#12000000', offsetX: 0, offsetY: 1 })
    .stateStyles({
      normal: this.topActionNormalStyle,
      pressed: this.topActionPressedStyle
    })
    .enabled(!this.profileLoading && this.profileError === '' &&
      !this.photoUploading && !this.photoMenuOpen && !this.openingEditor &&
      !this.switchingToSettings && !this.topMenuOpen)
    .opacity(this.profileLoading || this.profileError !== '' ? 0.46 : 1)
    .accessibilityText(label)
    .onClick(onTap);
  }

  @Builder
  actionButton(symbol: string, label: string, key: string, accent: string, onTap: () => void) {
    Column({ space: 5 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: 36, height: 36 })
          .fill(key === 'settings' ? '#147D69D9' : '#143478F6');
        if (this.quickActionBusy(key)) {
          LoadingProgress()
            .width(21)
            .height(21)
            .color(accent)
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.scale({ x: 0.7, y: 0.7 }))
              .animation({
                duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 140),
                curve: Curve.EaseOut
              }));
        } else {
          SymbolGlyph($r(symbol))
            .fontSize(20)
            .fontColor([accent])
            .scale({
              x: this.pressedQuickAction === key ? 0.84 : 1,
              y: this.pressedQuickAction === key ? 0.84 : 1
            })
            .animation({
              duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
              curve: Curve.EaseOut
            });
        }
      }
      .width(36)
      .height(36);
      Text(this.quickActionLabel(key, label))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(accent);
    }
    .layoutWeight(1)
    .height(76)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.pressedQuickAction === key
      ? $r('app.color.surface_alt') : CARD_BG)
    .borderRadius(CARD_RADIUS)
    .border({ width: 0.5, color: $r('app.color.divider') })
    .shadow({
      radius: this.pressedQuickAction === key ? 1 : 5,
      color: this.pressedQuickAction === key ? '#0A000000' : '#14000000',
      offsetX: 0,
      offsetY: this.pressedQuickAction === key ? 0 : 2
    })
    .scale({
      x: this.pressedQuickAction === key ? 0.96 : 1,
      y: this.pressedQuickAction === key ? 0.96 : 1
    })
    .opacity(this.quickActionEnabled(key) || this.quickActionBusy(key) ? 1 : 0.46)
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120),
      curve: Curve.EaseOut
    })
    .enabled(this.quickActionEnabled(key))
    .accessibilityText(this.quickActionBusy(key)
      ? this.quickActionLabel(key, label) : label)
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down && this.quickActionEnabled(key)) {
        this.pressedQuickAction = key;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        if (this.pressedQuickAction === key) {
          this.pressedQuickAction = '';
        }
      }
    })
    .onClick((): void => {
      this.pressedQuickAction = '';
      if (this.quickActionEnabled(key)) {
        onTap();
      }
    });
  }

  @Builder
  infoRow(key: string) {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: 38, height: 38 })
          .fill(this.infoTint(key));
        SymbolGlyph($r(this.infoIcon(key)))
          .fontSize(18)
          .fontColor([this.infoColor(key)])
          .scale({
            x: this.pressedInfoKey === key ? 0.86 : 1,
            y: this.pressedInfoKey === key ? 0.86 : 1
          })
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
            curve: Curve.EaseOut
          });
      }
      .width(38)
      .height(38);
      Column({ space: 3 }) {
        Text(this.infoValue(key))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(`${this.infoTitle(key)} · ${this.infoHint(key)}`)
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
      Stack({ alignContent: Alignment.Center }) {
        if (this.copyingInfoKey === key) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color(COLOR_PRIMARY);
        } else if (this.copiedInfoKey === key) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(17)
            .fontColor(['#34C759'])
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.scale({ x: 0.7, y: 0.7 }))
              .animation({
                duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 150),
                curve: Curve.EaseOut
              }));
        } else {
          SymbolGlyph($r('sys.symbol.plus_square_on_square'))
            .fontSize(17)
            .fontColor([COLOR_TEXT_SECONDARY]);
        }
      }
      .width(34)
      .height(34)
      .borderRadius(17)
      .backgroundColor($r('app.color.surface_alt'));
    }
    .width('100%')
    .height(66)
    .padding({ left: 12, right: 10 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.pressedInfoKey === key
      ? $r('app.color.surface_alt') : Color.Transparent)
    .scale({
      x: this.pressedInfoKey === key ? 0.986 : 1,
      y: this.pressedInfoKey === key ? 0.98 : 1
    })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
      curve: Curve.EaseOut
    })
    .enabled(this.copyingInfoKey === '' && !this.openingEditor && !this.switchingToSettings)
    .accessibilityText(`${this.infoTitle(key)}，${this.infoValue(key)}，点击复制`)
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down && this.copyingInfoKey === '') {
        this.pressedInfoKey = key;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        if (this.pressedInfoKey === key) {
          this.pressedInfoKey = '';
        }
      }
    })
    .onClick((): void => {
      this.pressedInfoKey = '';
      this.copyInfo(key);
    })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: 5 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 170),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  header() {
    Column({ space: 8 }) {
      Row() {
        this.circleButton('sys.symbol.qrcode', '显示个人资料二维码', () => { this.openQr(); });
        Blank().layoutWeight(1);
        this.circleButton('sys.symbol.more', '个人资料更多操作', () => { this.showTopMenu(); });
      }.width('100%').padding({ left: 12, right: 12 });

      Stack({ alignContent: Alignment.BottomEnd }) {
        Stack({ alignContent: Alignment.Center }) {
          if (this.profileLoading) {
            Circle({ width: 100, height: 100 })
              .fill($r('app.color.surface_alt'));
            LoadingProgress()
              .width(28)
              .height(28)
              .color(COLOR_PRIMARY);
          } else {
            AvatarView({
              avatarPath: this.avatarPath, initials: this.initials,
              colorSeed: this.myId, avatarSize: 100,
              animPath: this.avatarAnimPath
            });
          }
          if (this.photoUploading) {
            Circle({ width: 100, height: 100 })
              .fill('#66000000');
            LoadingProgress()
              .width(30)
              .height(30)
              .color(Color.White);
          }
        }
        .width(108)
        .height(108)
        .padding(4)
        .backgroundColor(CARD_BG)
        .borderRadius(54)
        .shadow({
          radius: this.avatarPressed ? 5 : 12,
          color: this.avatarPressed ? '#1C000000' : '#28000000',
          offsetX: 0,
          offsetY: this.avatarPressed ? 1 : 4
        });

        if (!this.profileLoading && !this.photoUploading) {
          Row() {
            SymbolGlyph(this.profileError !== ''
              ? $r('sys.symbol.exclamationmark_circle')
              : $r('sys.symbol.camera'))
              .fontSize(this.profileError !== '' ? 16 : 15)
              .fontColor([Color.White]);
          }
          .width(31)
          .height(31)
          .borderRadius(15.5)
          .backgroundColor(this.profileError !== '' ? '#E64646' : COLOR_PRIMARY)
          .border({ width: 2.5, color: PAGE_BG })
          .justifyContent(FlexAlign.Center)
          .hitTestBehavior(HitTestMode.None)
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.scale({ x: 0.7, y: 0.7 }))
            .animation({
              duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
              curve: Curve.EaseOut
            }));
        }
      }
      .width(112)
      .height(112)
      .scale({
        x: this.avatarPressed ? 0.95 : 1,
        y: this.avatarPressed ? 0.95 : 1
      })
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120),
        curve: Curve.EaseOut
      })
      .enabled(!this.profileLoading && !this.photoUploading && !this.photoMenuOpen &&
        !this.openingEditor && !this.switchingToSettings)
      .accessibilityText(this.profileError !== ''
        ? '个人资料加载失败，点击重新加载'
        : '当前头像，点击设置头像')
      .onTouch((event: TouchEvent): void => {
        if (event.type === TouchType.Down) {
          this.avatarPressed = true;
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.avatarPressed = false;
        }
      })
      .onClick((): void => {
        this.avatarPressed = false;
        if (this.profileError !== '') {
          this.retryProfile();
        } else {
          this.setPhotoMenu();
        }
      });

      Row({ space: 5 }) {
        Text(this.profileLoading
          ? '正在加载个人资料…'
          : (this.profileError !== '' ? '个人资料' : (this.name !== '' ? this.name : 'Telegram 账号')))
          .fontSize(20).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .flexShrink(1);
        if (!this.profileLoading && this.profileError === '' && this.statusEmojiPath !== '') {
          this.statusEmoji();
        }
      }
      .alignItems(VerticalAlign.Center)
      .constraintSize({ maxWidth: '86%' });

      Row({ space: 6 }) {
        if (this.profileLoading) {
          LoadingProgress().width(13).height(13).color(COLOR_PRIMARY);
        } else {
          Circle({ width: 7, height: 7 })
            .fill(this.profileError !== ''
              ? '#E64646'
              : (this.displayedStatusText() === '在线' ? '#34C759' : COLOR_TEXT_SECONDARY));
        }
        Text(this.profileLoading
          ? '正在同步头像和状态'
          : (this.profileError !== ''
            ? '点击头像重新加载'
            : this.displayedStatusText()))
          .fontSize(13)
          .fontColor(this.profileError !== '' ? '#E64646' : COLOR_TEXT_SECONDARY);
      }
      .height(22)
      .alignItems(VerticalAlign.Center);
    }
    .width('100%')
    .padding({ top: this.topSafe + 8 })
    .opacity(this.headerVisible && this.active ? 1 : 0)
    .translate({ y: this.headerVisible && this.active ? 0 : -8 })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 220),
      curve: Curve.EaseOut
    });
  }

  @Builder
  actionsRow() {
    Row({ space: 8 }) {
      this.actionButton(
        'sys.symbol.camera', '设置照片', 'photo', '#3478F6',
        (): void => { this.setPhotoMenu(); }
      );
      this.actionButton(
        'sys.symbol.pencil_line', '编辑信息', 'edit', '#3478F6',
        (): void => { this.openEditor(); }
      );
      this.actionButton(
        'sys.symbol.gearshape', '设置', 'settings', '#7D69D9',
        (): void => { this.openSettings(); }
      );
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 14 })
    .opacity(this.active ? 1 : 0)
    .translate({ y: this.active ? 0 : 8 })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 240),
      curve: Curve.EaseOut
    });
  }

  @Builder
  infoCard() {
    Column({ space: 5 }) {
      Row() {
        Text('账号资料')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_SECONDARY)
          .layoutWeight(1);
        Text(this.profileLoading
          ? '同步中'
          : (this.profileError !== '' ? '不可用' : `${this.infoItemCount()} 项`))
          .fontSize(12)
          .fontColor(this.profileError !== '' ? '#E64646' : COLOR_TEXT_SECONDARY);
      }
      .width('100%')
      .height(26)
      .padding({ left: 4, right: 4 });

      Column() {
        if (this.profileLoading) {
          Row({ space: 12 }) {
            Circle({ width: 38, height: 38 }).fill($r('app.color.surface_alt'));
            Column({ space: 8 }) {
              Rect({ width: 132, height: 12, radius: 6 })
                .fill($r('app.color.surface_alt'));
              Rect({ width: 196, height: 9, radius: 4.5 })
                .fill($r('app.color.surface_alt'));
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1);
            LoadingProgress().width(20).height(20).color(COLOR_PRIMARY);
          }
          .width('100%')
          .height(76)
          .padding({ left: 12, right: 14 })
          .alignItems(VerticalAlign.Center);
        } else if (this.profileError !== '') {
          Row({ space: 12 }) {
            Stack({ alignContent: Alignment.Center }) {
              Circle({ width: 38, height: 38 }).fill('#18E64646');
              SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
                .fontSize(19)
                .fontColor(['#E64646']);
            }
            Column({ space: 3 }) {
              Text('账号资料暂不可用')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(COLOR_TEXT_PRIMARY);
              Text('点击重新加载')
                .fontSize(12)
                .fontColor(COLOR_PRIMARY);
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1);
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(17)
              .fontColor([COLOR_PRIMARY]);
          }
          .width('100%')
          .height(76)
          .padding({ left: 12, right: 14 })
          .alignItems(VerticalAlign.Center)
          .accessibilityText('账号资料加载失败，重新加载')
          .onClick((): void => { this.retryProfile(); });
        } else if (this.infoItemCount() === 0) {
          Row({ space: 12 }) {
            Stack({ alignContent: Alignment.Center }) {
              Circle({ width: 38, height: 38 }).fill('#143478F6');
              SymbolGlyph($r('sys.symbol.person_fill'))
                .fontSize(18)
                .fontColor([COLOR_PRIMARY]);
            }
            Column({ space: 3 }) {
              Text('尚未填写账号资料')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(COLOR_TEXT_PRIMARY);
              Text('点击前往编辑姓名、用户名和生日')
                .fontSize(12)
                .fontColor(COLOR_TEXT_SECONDARY);
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1);
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([COLOR_TEXT_SECONDARY]);
          }
          .width('100%')
          .height(76)
          .padding({ left: 12, right: 14 })
          .alignItems(VerticalAlign.Center)
          .accessibilityText('尚未填写账号资料，前往编辑')
          .onClick((): void => { this.openEditor(); });
        } else {
          if (this.phone !== '') {
            this.infoRow('phone');
          }
          if (this.usernames.length > 0) {
            if (this.phone !== '') {
              Divider()
                .color($r('app.color.divider'))
                .strokeWidth(0.7)
                .margin({ left: 62, right: 10 });
            }
            this.infoRow('username');
          }
          if (this.birthday !== '') {
            if (this.phone !== '' || this.usernames.length > 0) {
              Divider()
                .color($r('app.color.divider'))
                .strokeWidth(0.7)
                .margin({ left: 62, right: 10 });
            }
            this.infoRow('birthday');
          }
        }
      }
      .width('100%')
      .backgroundColor(CARD_BG)
      .borderRadius(CARD_RADIUS)
      .border({ width: 0.5, color: $r('app.color.divider') })
      .shadow({ radius: 5, color: '#12000000', offsetX: 0, offsetY: 2 })
      .clip(true);
    }
    .margin({ left: 12, right: 12, top: 12 })
    .opacity(this.active ? 1 : 0)
    .translate({ y: this.active ? 0 : 10 })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 280),
      curve: Curve.EaseOut
    });
  }

  @Builder
  postTabPill(label: string, index: number) {
    Row({ space: 6 }) {
      if (index === 0 && (this.storyPickerOpen || this.storyPosting)) {
        LoadingProgress()
          .width(16)
          .height(16)
          .color(COLOR_PRIMARY);
      } else {
        SymbolGlyph($r(this.postTabIcon(index)))
          .fontSize(16)
          .fontColor([this.postTab === index ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY])
          .scale({
            x: this.pressedPostTab === index ? 0.9 : 1,
            y: this.pressedPostTab === index ? 0.9 : 1
          })
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
            curve: Curve.EaseOut
          });
      }
      Text(label)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.postTab === index ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
        .maxLines(1);
    }
    .layoutWeight(1)
    .height(40)
    .justifyContent(FlexAlign.Center)
    .borderRadius(13)
    .backgroundColor(this.pressedPostTab === index
      ? $r('app.color.selected_pill') : Color.Transparent)
    .scale({
      x: this.pressedPostTab === index ? 0.975 : 1,
      y: this.pressedPostTab === index ? 0.96 : 1
    })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120),
      curve: Curve.EaseOut
    })
    .accessibilityText(`${label}${this.postTab === index ? '，已选中' : ''}`)
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) {
        this.pressedPostTab = index;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        if (this.pressedPostTab === index) {
          this.pressedPostTab = -1;
        }
      }
    })
    .onClick((): void => {
      if (index === 0 && this.postTab === 0) {
        this.openStoryComposer();
      } else {
        this.selectPostTab(index);
      }
    });
  }

  @Builder
  postsTabs() {
    Column() {
      Stack({ alignContent: Alignment.Start }) {
        Row()
          .width(this.postIndicatorWidth())
          .height(40)
          .borderRadius(13)
          .backgroundColor(CARD_BG)
          .border({ width: 0.5, color: $r('app.color.divider') })
          .shadow({ radius: 4, color: '#16000000', offsetX: 0, offsetY: 2 })
          .position({ x: 3, y: 3 })
          .translate({
            x: this.postTab === 0 ? 0 : this.postIndicatorWidth()
          })
          .opacity(this.postTabsWidth > 0 ? 1 : 0)
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 220),
            curve: Curve.EaseOut
          });

        Row() {
          this.postTabPill('动态', 0);
          this.postTabPill('已归档的动态', 1);
        }
        .width('100%')
        .height(46)
        .padding(3)
        .alignItems(VerticalAlign.Center);
      }
      .width('100%')
      .height(46)
      .backgroundColor($r('app.color.surface_alt'))
      .borderRadius(16)
      .border({ width: 0.5, color: $r('app.color.divider') })
      .onAreaChange((_old: Area, area: Area): void => {
        const width = area.width as number;
        if (width > 0 && width !== this.postTabsWidth) {
          this.postTabsWidth = width;
        }
      });
    }
    .width('100%')
    .padding({ left: 12, right: 12 })
    .margin({ top: 16, bottom: 8 })
    .opacity(this.active ? 1 : 0)
    .translate({ y: this.active ? 0 : 8 })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 300),
      curve: Curve.EaseOut
    });
  }

  @Builder
  postLoadingState(enterX: number) {
    Column({ space: 12 }) {
      Row({ space: 3 }) {
        Rect({ height: 128, radius: 10 })
          .fill($r('app.color.surface_alt'))
          .layoutWeight(1);
        Rect({ height: 128, radius: 10 })
          .fill($r('app.color.surface_alt'))
          .layoutWeight(1);
        Rect({ height: 128, radius: 10 })
          .fill($r('app.color.surface_alt'))
          .layoutWeight(1);
      }
      .width('100%')
      .padding({ left: 2, right: 2 });
      Row({ space: 7 }) {
        LoadingProgress()
          .width(16)
          .height(16)
          .color(COLOR_PRIMARY);
        Text(this.postTab === 0 ? '正在同步动态…' : '正在读取归档动态…')
          .fontSize(13)
          .fontColor(COLOR_TEXT_SECONDARY);
      }
      .height(26)
      .alignItems(VerticalAlign.Center);
    }
    .width('100%')
    .padding({ top: 8, bottom: 30 })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ x: enterX }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  postErrorState(title: string, detail: string, key: string, enterX: number) {
    Column({ space: 10 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: 58, height: 58 })
          .fill('#18E64646');
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(27)
          .fontColor(['#E64646']);
      }
      Text(title)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLOR_TEXT_PRIMARY);
      Text(detail)
        .fontSize(13)
        .fontColor(COLOR_TEXT_SECONDARY)
        .textAlign(TextAlign.Center)
        .constraintSize({ maxWidth: '78%' })
        .maxLines(2);
      Row({ space: 7 }) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(17)
          .fontColor([COLOR_PRIMARY]);
        Text('重新加载')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_PRIMARY);
      }
      .height(40)
      .padding({ left: 18, right: 18 })
      .borderRadius(20)
      .backgroundColor(this.pressedPostStateAction === key
        ? $r('app.color.selected_pill') : $r('app.color.surface_alt'))
      .scale({
        x: this.pressedPostStateAction === key ? 0.96 : 1,
        y: this.pressedPostStateAction === key ? 0.96 : 1
      })
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
        curve: Curve.EaseOut
      })
      .accessibilityText(`${title}，重新加载`)
      .onTouch((event: TouchEvent): void => {
        if (event.type === TouchType.Down) {
          this.pressedPostStateAction = key;
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          if (this.pressedPostStateAction === key) {
            this.pressedPostStateAction = '';
          }
        }
      })
      .onClick((): void => {
        this.retryPostState(key);
      });
    }
    .width('100%')
    .padding({ top: 30, bottom: 38 })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ x: enterX }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  emptyPosts(title: string, detail: string, archived: boolean, enterX: number) {
    Column({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: 62, height: 62 })
          .fill(archived ? '#167D69D9' : '#163478F6');
        SymbolGlyph(archived
          ? $r('sys.symbol.archivebox')
          : $r('sys.symbol.camera'))
          .fontSize(28)
          .fontColor([archived ? '#7D69D9' : COLOR_PRIMARY]);
      }
      .transition(TransitionEffect.OPACITY
        .combine(TransitionEffect.scale({ x: 0.78, y: 0.78 }))
        .animation({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 220),
          curve: Curve.EaseOut
        }));
      Text(title).fontSize(17).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
      Text(detail)
        .fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
        .textAlign(TextAlign.Center).constraintSize({ maxWidth: '80%' });
      if (!archived) {
        Row({ space: 7 }) {
          if (this.storyPickerOpen || this.storyPosting) {
            LoadingProgress().width(17).height(17).color(COLOR_PRIMARY);
          } else {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(17)
              .fontColor([COLOR_PRIMARY]);
          }
          Text(this.storyPosting ? '正在发布' : '添加动态')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_PRIMARY);
        }
        .height(40)
        .padding({ left: 18, right: 18 })
        .borderRadius(20)
        .backgroundColor($r('app.color.selected_pill'))
        .accessibilityText('添加动态')
        .onClick((): void => {
          this.openStoryComposer();
        });
      }
    }
    .width('100%')
    .padding({ top: 30, bottom: 38 })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ x: enterX }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  storyGrid(items: StoryItem[], enterX: number) {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(items, (item: StoryItem) => {
        Stack({ alignContent: Alignment.BottomStart }) {
          if (item.thumbPath !== '') {
            Image(item.thumbPath.startsWith('/') ? `file://${item.thumbPath}` : item.thumbPath)
              .width(this.storyCell())
              .height(this.storyCell() * 1.33)
              .objectFit(ImageFit.Cover)
              .transition(TransitionEffect.OPACITY.animation({
                duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160),
                curve: Curve.EaseOut
              }));
          } else {
            Stack({ alignContent: Alignment.Center }) {
              Column()
                .width(this.storyCell())
                .height(this.storyCell() * 1.33)
                .backgroundColor($r('app.color.surface_alt'));
              SymbolGlyph(item.isVideo
                ? $r('sys.symbol.video')
                : $r('sys.symbol.camera'))
                .fontSize(23)
                .fontColor([COLOR_TEXT_SECONDARY])
                .opacity(0.55);
            }
          }
          if (item.isVideo) {
            Text(`▶ ${this.formatStoryDuration(item.duration)}`)
              .fontSize(11)
              .fontColor(Color.White)
              .backgroundColor('#80000000')
              .borderRadius(5)
              .padding({ left: 5, right: 5, top: 2, bottom: 2 })
              .margin({ left: 6, bottom: 6 });
          }
        }
        .width(this.storyCell())
        .height(this.storyCell() * 1.33)
        .margin({ right: 1, bottom: 1 })
        .clip(true);
      }, (item: StoryItem): string => `my_story_${this.postTab}_${item.id}_${item.thumbPath}`);
    }
    .width('100%')
    .padding({ top: 2, bottom: 28 })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ x: enterX }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 190),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  postsContent() {
    Stack() {
      if (this.profileLoading) {
        this.postLoadingState(this.postTab === 0 ? -12 : 12);
      } else if (this.profileError !== '') {
        this.postErrorState(
          '个人资料加载失败',
          this.profileError,
          'profile',
          this.postTab === 0 ? -12 : 12
        );
      } else if (this.postTab === 0) {
        if (this.storiesLoading) {
          this.postLoadingState(-12);
        } else if (this.storiesError !== '') {
          this.postErrorState('动态加载失败', this.storiesError, 'stories', -12);
        } else if (this.stories.length === 0) {
          this.emptyPosts(
            '暂无动态',
            '发布的照片和视频会显示在您的个人资料页上',
            false,
            -12
          );
        } else {
          this.storyGrid(this.stories, -12);
        }
      } else {
        if (this.archivedStoriesError !== '') {
          this.postErrorState('归档动态加载失败', this.archivedStoriesError, 'archive', 12);
        } else if (this.archivedStoriesLoading || !this.archivedStoriesLoaded) {
          this.postLoadingState(12);
        } else if (this.archivedStories.length === 0) {
          this.emptyPosts(
            '暂无已归档动态',
            '您归档的动态会安全保存在这里，仅自己可见',
            true,
            12
          );
        } else {
          this.storyGrid(this.archivedStories, 12);
        }
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 210 });
  }

  @Builder
  postsSection() {
    Column() {
      this.postsTabs();
      this.postsContent();
    }
    .width('100%')
    .gesture(
      SwipeGesture({ fingers: 1, direction: SwipeDirection.Horizontal, speed: 120 })
        .onAction((event: GestureEvent): void => {
          this.handlePostSwipe(event.angle);
        })
    );
  }

  // Premium emoji status beside the name (animated custom emoji).
  @Builder
  statusEmoji() {
    if (this.statusEmojiFormat === 'tgs') {
      TgsStickerView({
        tgsPath: this.statusEmojiPath, boxWidth: 24, boxHeight: 24, powerCategory: 'emojiStatus'
      });
    } else if (this.statusEmojiFormat === 'webm') {
      WebmStickerView({
        webmPath: this.statusEmojiPath, boxWidth: 24, boxHeight: 24, powerCategory: 'emojiStatus'
      });
    } else {
      Image(`file://${this.statusEmojiPath}`).width(24).height(24).objectFit(ImageFit.Contain);
    }
  }

  build() {
    Scroll() {
      Column() {
        this.header();
        this.actionsRow();
        this.infoCard();
        this.postsSection();
      }
      .width('100%')
      .padding({ bottom: this.bottomSafe + 88 });
    }
    .width('100%').height('100%')
    .backgroundColor(PAGE_BG)
    .align(Alignment.Top)
    .edgeEffect(EdgeEffect.Spring)
    .scrollBar(BarState.Off);
  }
}


// Bottom sheet holding the sticker picker for the emoji-avatar option.
@CustomDialog
struct StickerAvatarDialog {
  controller?: CustomDialogController;
  onPick: (s: StickerItem) => void = (): void => {};

  build() {
    Column() {
      // Avatar builder mode: custom-emoji library + trending packs (official-style).
      StickerPicker({
        stickerType: 'custom_emoji',
        includeTrending: true,
        onPick: (s: StickerItem): void => { this.onPick(s); }
      });
    }
    .width('100%').height(400)
    .backgroundColor($r('app.color.surface'))
    .borderRadius({ topLeft: 16, topRight: 16 })
    .clip(true);
  }
}
