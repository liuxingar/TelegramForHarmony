import { promptAction, router } from '@kit.ArkUI';
import { TdError } from '../../tdkit/TdTypes';
import { getFolderStore } from '../../tdkit/Globals';
import {
  FolderChatSummary, FolderData, FolderLimits, chatIdsNotInChatList, defaultFolderIconName,
  emptyFolder, folderChatCount, getFolder, getFolderChatSummaries, getFolderLimits,
  saveFolder, searchFolderChats
} from '../../store/FolderApi';
import {
  KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration
} from '../../store/AppSettings';
import {
  FOLDER_COLORS, FOLDER_ICON_OPTIONS, FolderIconOption, folderColor, folderSymbol
} from '../../util/FolderVisuals';
import { AvatarView } from '../chatlist/AvatarView';
import {
  COLOR_DIVIDER, COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE,
  COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';

const CARD_RADIUS: number = 14;
const PICK_INCLUDE: string = 'include';
const PICK_EXCLUDE: string = 'exclude';
const NAME_MAX: number = 12;

export interface FolderEditParams {
  folderId: number;
}

@Entry
@Component
struct FolderEditPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State folderId: number = 0;
  @State loadState: string = 'loading';
  @State saving: boolean = false;
  @State warning: string = '';
  @State name: string = '';
  @State included: number[] = [];
  @State excluded: number[] = [];
  @State includeContacts: boolean = false;
  @State includeNonContacts: boolean = false;
  @State includeBots: boolean = false;
  @State includeGroups: boolean = false;
  @State includeChannels: boolean = false;
  @State excludeMuted: boolean = false;
  @State excludeRead: boolean = false;
  @State excludeArchived: boolean = false;
  @State iconName: string = '';
  @State defaultIconName: string = 'Custom';
  @State colorId: number = -1;
  @State pickerOpen: boolean = false;
  @State pickerMode: string = PICK_INCLUDE;
  @State pickerQuery: string = '';
  @State pickerRows: FolderChatSummary[] = [];
  @State pickerState: string = 'idle';
  @State chatSummaries: Map<number, FolderChatSummary> = new Map();
  @State previewCount: number = 0;
  @State previewState: string = 'idle';
  @State limits: FolderLimits = { folderCount: 10, chosenChatCount: 100 };
  private base: FolderData = emptyFolder();
  private originalSignature: string = '';
  private active: boolean = false;
  private loadSequence: number = 0;
  private pickerSequence: number = 0;
  private pickerTimer: number = -1;
  private previewSequence: number = 0;
  private iconSequence: number = 0;
  private previewTimer: number = -1;

  @Styles
  pressNormal() {
    .opacity(1).scale({ x: 1, y: 1 }).backgroundColor(Color.Transparent)
  }

  @Styles
  pressDown() {
    .opacity(0.7).scale({ x: 0.97, y: 0.97 }).backgroundColor($r('app.color.surface_alt'))
  }

  aboutToAppear(): void {
    this.active = true;
    const params = router.getParams() as FolderEditParams | undefined;
    this.folderId = params?.folderId ?? 0;
    getFolderLimits().then((limits: FolderLimits): void => {
      if (this.active) { this.limits = limits; }
    });
    this.loadFolder();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.loadSequence++;
    this.pickerSequence++;
    this.previewSequence++;
    this.iconSequence++;
    if (this.pickerTimer !== -1) { clearTimeout(this.pickerTimer); this.pickerTimer = -1; }
    if (this.previewTimer !== -1) { clearTimeout(this.previewTimer); this.previewTimer = -1; }
  }

  onBackPress(): boolean {
    if (this.pickerOpen) { this.pickerOpen = false; return true; }
    if (this.saving) { return true; }
    if (this.isDirty()) { this.confirmDiscard(); return true; }
    return false;
  }

  private loadFolder(): void {
    const sequence = ++this.loadSequence;
    this.loadState = 'loading';
    this.warning = '';
    const task: Promise<FolderData> = this.folderId === 0
      ? Promise.resolve(emptyFolder()) : getFolder(this.folderId);
    task.then((folder: FolderData): Promise<FolderChatSummary[]> => {
      if (!this.active || sequence !== this.loadSequence) { return Promise.resolve([]); }
      this.base = folder;
      this.applyFolder(folder);
      const ids = [...folder.includedChatIds, ...folder.excludedChatIds, ...folder.pinnedChatIds];
      return getFolderChatSummaries(ids);
    }).then((summaries: FolderChatSummary[]): void => {
      if (!this.active || sequence !== this.loadSequence) { return; }
      const map = new Map<number, FolderChatSummary>();
      for (const summary of summaries) { map.set(summary.id, summary); }
      this.chatSummaries = map;
      this.loadState = 'ready';
      this.originalSignature = this.signature();
      this.refreshDefaultIcon();
      this.schedulePreview();
    }).catch((error: TdError): void => {
      if (!this.active || sequence !== this.loadSequence) { return; }
      this.loadState = 'error';
      this.warning = '读取文件夹失败，未加载成功前不会覆盖原设置';
      console.error(`FolderEditPage.load failed: ${error.message}`);
    });
  }

  private applyFolder(folder: FolderData): void {
    this.name = folder.name;
    this.included = folder.includedChatIds.slice();
    this.excluded = folder.excludedChatIds.slice();
    this.includeContacts = folder.includeContacts;
    this.includeNonContacts = folder.includeNonContacts;
    this.includeBots = folder.includeBots;
    this.includeGroups = folder.includeGroups;
    this.includeChannels = folder.includeChannels;
    this.excludeMuted = folder.excludeMuted;
    this.excludeRead = folder.excludeRead;
    this.excludeArchived = folder.excludeArchived;
    this.iconName = folder.iconName;
    this.defaultIconName = folder.iconName !== '' ? folder.iconName : 'Custom';
    this.colorId = folder.colorId;
  }

  private unique(ids: number[]): number[] {
    const result: number[] = [];
    for (const id of ids) { if (id !== 0 && result.indexOf(id) < 0) { result.push(id); } }
    return result;
  }

  private draft(): FolderData {
    const includeIds = this.unique(this.included);
    const excludeIds = this.unique(this.excluded)
      .filter((id: number): boolean => includeIds.indexOf(id) < 0);
    const sameName = this.name.trim() === this.base.name;
    return {
      id: this.folderId,
      name: this.name.trim(),
      nameEntities: sameName ? this.base.nameEntities : [],
      animateCustomEmoji: sameName ? this.base.animateCustomEmoji : false,
      iconName: this.iconName,
      colorId: this.colorId,
      isShareable: this.base.isShareable,
      // Pinned chats aren't necessarily duplicated in included_chat_ids. The
      // editor doesn't expose pin order, so preserve it unless the user
      // explicitly excludes that chat.
      pinnedChatIds: this.base.pinnedChatIds.filter((id: number): boolean => excludeIds.indexOf(id) < 0),
      includedChatIds: includeIds,
      excludedChatIds: excludeIds,
      excludeMuted: this.excludeMuted,
      excludeRead: this.excludeRead,
      excludeArchived: this.excludeArchived,
      includeContacts: this.includeContacts,
      includeNonContacts: this.includeNonContacts,
      includeBots: this.includeBots,
      includeGroups: this.includeGroups,
      includeChannels: this.includeChannels
    };
  }

  private signature(): string {
    const folder = this.draft();
    return [folder.name, folder.iconName, `${folder.colorId}`,
      folder.includedChatIds.join(','), folder.excludedChatIds.join(','),
      `${folder.excludeMuted}`, `${folder.excludeRead}`, `${folder.excludeArchived}`,
      `${folder.includeContacts}`, `${folder.includeNonContacts}`, `${folder.includeBots}`,
      `${folder.includeGroups}`, `${folder.includeChannels}`].join('|');
  }

  private isDirty(): boolean {
    return this.loadState === 'ready' && this.signature() !== this.originalSignature;
  }

  private hasAnyFilter(): boolean {
    return this.base.pinnedChatIds.length > 0 || this.included.length > 0 || this.includeContacts || this.includeNonContacts ||
      this.includeBots || this.includeGroups || this.includeChannels;
  }

  private chosenChatCount(): number {
    return this.unique([...this.base.pinnedChatIds, ...this.included, ...this.excluded]).length;
  }

  private validate(): string {
    const title = this.name.trim();
    if (title.length === 0) { return '请填写文件夹名称'; }
    if (title.length > NAME_MAX || title.indexOf('\n') >= 0) { return '文件夹名称最多 12 个字符且不能换行'; }
    if (!this.hasAnyFilter()) { return '至少要包含一个聊天或一类聊天'; }
    if (this.chosenChatCount() > this.limits.chosenChatCount) {
      return `单独选择的聊天不能超过 ${this.limits.chosenChatCount} 个`;
    }
    if (this.base.isShareable && (this.excluded.length > 0 || this.excludeMuted || this.excludeRead ||
      this.excludeArchived || this.includeContacts || this.includeNonContacts || this.includeBots ||
      this.includeGroups || this.includeChannels)) {
      return '共享文件夹只能包含明确添加的聊天，请先删除共享链接再使用类型规则';
    }
    return '';
  }

  private save(): void {
    if (this.saving || this.loadState !== 'ready') { return; }
    const issue = this.validate();
    if (issue !== '') { this.warning = issue; promptAction.showToast({ message: issue, duration: 2200 }); return; }
    this.saving = true;
    this.warning = '';
    const folder = this.draft();
    const chosen = this.unique(
      [...folder.pinnedChatIds, ...folder.includedChatIds, ...folder.excludedChatIds]
    );
    chatIdsNotInChatList(chosen).then((invalid: number[]): Promise<number> => {
      if (invalid.length > 0) {
        // A chat picked earlier can have left the chat list since (left
        // channel, deleted chat, pre-fix search results). TDLib rejects the
        // whole save for it, so drop it up front and tell the user.
        const keep = (id: number): boolean => invalid.indexOf(id) < 0;
        folder.pinnedChatIds = folder.pinnedChatIds.filter(keep);
        folder.includedChatIds = folder.includedChatIds.filter(keep);
        folder.excludedChatIds = folder.excludedChatIds.filter(keep);
        this.included = this.included.filter(keep);
        this.excluded = this.excluded.filter(keep);
        promptAction.showToast({
          message: `已移除 ${invalid.length} 个不在会话列表中的聊天`, duration: 2200
        });
        if (folder.pinnedChatIds.length === 0 && folder.includedChatIds.length === 0 &&
          !folder.includeContacts && !folder.includeNonContacts && !folder.includeBots &&
          !folder.includeGroups && !folder.includeChannels) {
          return Promise.reject(new TdError(400, 'FOLDER_EMPTY_AFTER_CLEANUP'));
        }
      }
      return saveFolder(folder);
    }).then((id: number): void => {
      if (!this.active) { return; }
      this.saving = false;
      this.folderId = id;
      this.base = {
        id, name: folder.name, nameEntities: folder.nameEntities.slice(),
        animateCustomEmoji: folder.animateCustomEmoji, iconName: folder.iconName,
        colorId: folder.colorId, isShareable: folder.isShareable,
        pinnedChatIds: folder.pinnedChatIds.slice(), includedChatIds: folder.includedChatIds.slice(),
        excludedChatIds: folder.excludedChatIds.slice(), excludeMuted: folder.excludeMuted,
        excludeRead: folder.excludeRead, excludeArchived: folder.excludeArchived,
        includeContacts: folder.includeContacts, includeNonContacts: folder.includeNonContacts,
        includeBots: folder.includeBots, includeGroups: folder.includeGroups,
        includeChannels: folder.includeChannels
      };
      this.originalSignature = this.signature();
      promptAction.showToast({ message: folder.id === 0 ? '文件夹已创建' : '已保存', duration: 1500 });
      router.back();
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.saving = false;
      this.warning = this.folderErrorMessage(error);
      console.error(`FolderEditPage.save failed: ${error.message}`);
    });
  }

  private folderErrorMessage(error: TdError): string {
    if (error.message === 'FOLDER_EMPTY_AFTER_CLEANUP') {
      return '移除无效聊天后文件夹为空，请重新选择聊天或规则';
    }
    if (error.message.indexOf('CHATLISTS_TOO_MUCH') >= 0 || error.message.indexOf('FOLDER') >= 0 &&
      error.message.indexOf('TOO_MUCH') >= 0) { return '已达到当前账号的文件夹数量上限'; }
    if (error.message.indexOf('CHATLISTS_CHATS_TOO_MUCH') >= 0) { return '文件夹中单独选择的聊天过多'; }
    if (error.message.indexOf('PREMIUM') >= 0) { return '该颜色或标签能力需要 Telegram Premium'; }
    if (error.message.indexOf('not in the chat list') >= 0) {
      return '有所选聊天不在会话列表中（例如未加入的频道或群组），请从文件夹中移除后再保存';
    }
    return '保存失败，输入内容已保留，请稍后重试';
  }

  private confirmDiscard(): void {
    promptAction.showDialog({
      title: '放弃修改？', message: '尚未保存的文件夹设置会丢失。',
      buttons: [
        { text: '继续编辑', color: COLOR_TEXT_SECONDARY as string },
        { text: '放弃', color: '#E64646' }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (result.index === 1) { this.originalSignature = this.signature(); router.back(); }
    }).catch((): void => {});
  }

  private requestBack(): void {
    if (this.saving) { return; }
    if (this.isDirty()) { this.confirmDiscard(); } else { router.back(); }
  }

  private schedulePreview(): void {
    if (this.previewTimer !== -1) { clearTimeout(this.previewTimer); }
    this.previewState = 'loading';
    const sequence = ++this.previewSequence;
    this.previewTimer = setTimeout((): void => {
      this.previewTimer = -1;
      folderChatCount(this.draft()).then((count: number): void => {
        if (this.active && sequence === this.previewSequence) {
          this.previewCount = count; this.previewState = 'ready';
        }
      }).catch((): void => {
        if (this.active && sequence === this.previewSequence) { this.previewState = 'error'; }
      });
    }, 320);
  }

  private refreshDefaultIcon(): void {
    if (this.iconName !== '') { return; }
    const sequence = ++this.iconSequence;
    defaultFolderIconName(this.draft()).then((name: string): void => {
      if (this.active && sequence === this.iconSequence && this.iconName === '') {
        this.defaultIconName = name;
      }
    }).catch((): void => {});
  }

  private fieldChanged(): void {
    this.warning = '';
    this.schedulePreview();
    this.refreshDefaultIcon();
  }

  private setType(kind: string, value: boolean): void {
    if (this.base.isShareable) { return; }
    if (kind === 'contacts') { this.includeContacts = value; }
    else if (kind === 'nonContacts') { this.includeNonContacts = value; }
    else if (kind === 'bots') { this.includeBots = value; }
    else if (kind === 'groups') { this.includeGroups = value; }
    else if (kind === 'channels') { this.includeChannels = value; }
    else if (kind === 'muted') { this.excludeMuted = value; }
    else if (kind === 'read') { this.excludeRead = value; }
    else { this.excludeArchived = value; }
    this.fieldChanged();
  }

  private summary(id: number): FolderChatSummary {
    return this.chatSummaries.get(id) ?? {
      id, title: `聊天 ${id}`, initials: '?', avatarPath: '', kind: 'private'
    };
  }

  private selectedForPicker(id: number): boolean {
    return (this.pickerMode === PICK_INCLUDE ? this.included : this.excluded).indexOf(id) >= 0;
  }

  private openPicker(mode: string): void {
    if (this.base.isShareable && mode === PICK_EXCLUDE) { return; }
    this.pickerMode = mode;
    this.pickerQuery = '';
    this.pickerOpen = true;
    this.runPickerSearch('');
  }

  private schedulePickerSearch(query: string): void {
    this.pickerQuery = query;
    if (this.pickerTimer !== -1) { clearTimeout(this.pickerTimer); }
    this.pickerTimer = setTimeout((): void => {
      this.pickerTimer = -1;
      this.runPickerSearch(this.pickerQuery);
    }, 280);
  }

  private runPickerSearch(query: string): void {
    const sequence = ++this.pickerSequence;
    this.pickerState = 'loading';
    searchFolderChats(query).then((rows: FolderChatSummary[]): void => {
      if (!this.active || sequence !== this.pickerSequence) { return; }
      const selected = this.pickerMode === PICK_INCLUDE ? this.included : this.excluded;
      const merged: FolderChatSummary[] = [];
      for (const id of selected) {
        const row = this.summary(id);
        if (merged.findIndex((item: FolderChatSummary): boolean => item.id === id) < 0) { merged.push(row); }
      }
      for (const row of rows) {
        if (merged.findIndex((item: FolderChatSummary): boolean => item.id === row.id) < 0) { merged.push(row); }
      }
      const map = new Map(this.chatSummaries);
      for (const row of merged) { map.set(row.id, row); }
      this.chatSummaries = map;
      this.pickerRows = merged;
      this.pickerState = merged.length > 0 ? 'ready' : 'empty';
    }).catch((error: TdError): void => {
      if (!this.active || sequence !== this.pickerSequence) { return; }
      this.pickerState = 'error';
      console.error(`FolderEditPage.search failed: ${error.message}`);
    });
  }

  private togglePickerChat(id: number): void {
    if (this.selectedForPicker(id)) {
      if (this.pickerMode === PICK_INCLUDE) {
        this.included = this.included.filter((value: number): boolean => value !== id);
      } else {
        this.excluded = this.excluded.filter((value: number): boolean => value !== id);
      }
    } else if (this.pickerMode === PICK_INCLUDE) {
      if (this.excluded.indexOf(id) < 0 && this.chosenChatCount() >= this.limits.chosenChatCount) {
        promptAction.showToast({ message: `最多选择 ${this.limits.chosenChatCount} 个聊天`, duration: 1800 });
        return;
      }
      this.included = [...this.included, id];
      this.excluded = this.excluded.filter((value: number): boolean => value !== id);
    } else {
      if (this.included.indexOf(id) < 0 && this.chosenChatCount() >= this.limits.chosenChatCount) {
        promptAction.showToast({ message: `最多选择 ${this.limits.chosenChatCount} 个聊天`, duration: 1800 });
        return;
      }
      this.excluded = [...this.excluded, id];
      this.included = this.included.filter((value: number): boolean => value !== id);
    }
    this.fieldChanged();
  }

  private removeChat(id: number, included: boolean): void {
    if (included) { this.included = this.included.filter((value: number): boolean => value !== id); }
    else { this.excluded = this.excluded.filter((value: number): boolean => value !== id); }
    this.fieldChanged();
  }

  private kindLabel(kind: string): string {
    if (kind === 'channel') { return '频道'; }
    if (kind === 'basicGroup' || kind === 'supergroup') { return '群组'; }
    if (kind === 'secret') { return '秘密聊天'; }
    return '私聊';
  }

  private openShareLinks(): void {
    if (this.saving) { return; }
    if (this.isDirty()) {
      promptAction.showToast({ message: '请先保存文件夹修改，再管理共享链接', duration: 1900 });
      return;
    }
    const params: Record<string, Object> = { 'folderId': this.folderId, 'title': this.name.trim() };
    router.pushUrl({ url: 'pages/main/FolderInviteLinksPage', params });
  }

  @Builder
  header() {
    Row({ space: 6 }) {
      Row() { SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(25).fontColor([COLOR_TEXT_PRIMARY]); }
        .width(44).height(44).borderRadius(22).justifyContent(FlexAlign.Center)
        .stateStyles({ normal: this.pressNormal, pressed: this.pressDown })
        .onClick((): void => this.requestBack());
      Column({ space: 1 }) {
        Text(this.folderId === 0 ? '新建文件夹' : '编辑文件夹')
          .fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
        Text(this.previewState === 'ready' ? `预计约 ${this.previewCount} 个聊天` :
          (this.previewState === 'loading' ? '正在计算范围…' : '设置包含与排除规则'))
          .fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      if (this.saving) {
        LoadingProgress().width(19).height(19).color(COLOR_PRIMARY).margin({ right: 12 });
      } else {
        Text('保存').fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor(this.loadState === 'ready' && this.isDirty() ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
          .width(52).height(40).textAlign(TextAlign.Center)
          .stateStyles({ normal: this.pressNormal, pressed: this.pressDown })
          .enabled(this.loadState === 'ready' && this.isDirty())
          .onClick((): void => this.save());
      }
    }.width('100%').height(56).padding({ left: 8, right: 8 }).alignItems(VerticalAlign.Center);
  }

  @Builder
  loadSkeleton() {
    Column({ space: 14 }) {
      Row().width('100%').height(92).borderRadius(CARD_RADIUS).backgroundColor(COLOR_SURFACE);
      Row().width('100%').height(220).borderRadius(CARD_RADIUS).backgroundColor(COLOR_SURFACE);
      Row().width('100%').height(160).borderRadius(CARD_RADIUS).backgroundColor(COLOR_SURFACE);
    }.padding({ left: 12, right: 12, top: 8 });
  }

  @Builder
  loadError() {
    Column({ space: 12 }) {
      Text('📁').fontSize(44);
      Text('无法读取这个文件夹').fontSize(18).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
      Text('原设置不会被覆盖，可以重新加载或返回。').fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      Text('重新加载').fontSize(15).fontColor(Color.White).fontWeight(FontWeight.Medium)
        .padding({ left: 22, right: 22, top: 10, bottom: 10 }).backgroundColor(COLOR_PRIMARY).borderRadius(18)
        .stateStyles({ normal: this.pressNormal, pressed: this.pressDown }).onClick((): void => this.loadFolder());
    }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
  }

  @Builder
  sectionTitle(title: string, subtitle: string = '') {
    Column({ space: 2 }) {
      Text(title).fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_SECONDARY).width('100%');
      if (subtitle !== '') { Text(subtitle).fontSize(11).fontColor(COLOR_TEXT_SECONDARY).width('100%'); }
    }.alignItems(HorizontalAlign.Start).padding({ left: 4, top: 2 });
  }

  @Builder
  identityCard() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Row() {
          SymbolGlyph(folderSymbol(this.iconName !== '' ? this.iconName : this.defaultIconName))
            .fontSize(25).fontColor([folderColor(this.colorId)]);
        }
          .width(50).height(50).borderRadius(16).justifyContent(FlexAlign.Center)
          .backgroundColor(`${folderColor(this.colorId)}20`);
        Column({ space: 4 }) {
          TextInput({ placeholder: '文件夹名称', text: this.name })
            .fontSize(17).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
            .backgroundColor(Color.Transparent).padding(0).maxLength(NAME_MAX)
            .onChange((value: string): void => { this.name = value.replace(/\n/g, ''); this.warning = ''; });
          Text(`${this.name.length}/${NAME_MAX}`).fontSize(11)
            .fontColor(this.name.length >= NAME_MAX ? '#E64646' : COLOR_TEXT_SECONDARY).width('100%');
        }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      }.width('100%');
      Divider().strokeWidth(0.5).color(COLOR_DIVIDER);
      Text('图标').fontSize(12).fontColor(COLOR_TEXT_SECONDARY).width('100%');
      Scroll() {
        Row({ space: 9 }) {
          Column({ space: 3 }) {
            Row() {
              SymbolGlyph(folderSymbol(this.defaultIconName)).fontSize(20)
                .fontColor([this.iconName === '' ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY]);
            }.width(42).height(42).borderRadius(14)
              .justifyContent(FlexAlign.Center).backgroundColor(this.iconName === '' ? '#225B8FF9' : COLOR_PAGE_BG)
              .border({ width: this.iconName === '' ? 1.5 : 0, color: COLOR_PRIMARY });
            Text('自动').fontSize(10).fontColor(this.iconName === '' ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY);
          }.onClick((): void => { this.iconName = ''; this.refreshDefaultIcon(); });
          ForEach(FOLDER_ICON_OPTIONS, (option: FolderIconOption) => {
            Column({ space: 3 }) {
              Row() {
                SymbolGlyph(option.symbol).fontSize(20)
                  .fontColor([this.iconName === option.name ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY]);
              }.width(42).height(42).borderRadius(14)
                .justifyContent(FlexAlign.Center).backgroundColor(this.iconName === option.name ? '#225B8FF9' : COLOR_PAGE_BG)
                .border({ width: this.iconName === option.name ? 1.5 : 0, color: COLOR_PRIMARY });
              Text(option.label).fontSize(10).fontColor(this.iconName === option.name ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY);
            }.onClick((): void => { this.iconName = option.name; this.warning = ''; });
          }, (option: FolderIconOption): string => option.name);
        }.padding({ bottom: 2 });
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%');
      if (getFolderStore().areTagsEnabled()) {
        Divider().strokeWidth(0.5).color(COLOR_DIVIDER);
        Text('标签颜色').fontSize(12).fontColor(COLOR_TEXT_SECONDARY).width('100%');
        Row({ space: 12 }) {
          Row() { SymbolGlyph($r('sys.symbol.xmark')).fontSize(14).fontColor([COLOR_TEXT_SECONDARY]); }
            .width(30).height(30).borderRadius(15).justifyContent(FlexAlign.Center)
            .border({ width: this.colorId === -1 ? 2 : 1, color: this.colorId === -1 ? COLOR_PRIMARY : COLOR_DIVIDER })
            .onClick((): void => { this.colorId = -1; });
          ForEach(FOLDER_COLORS, (color: string, index: number) => {
            Circle({ width: 30, height: 30 }).fill(color)
              .border({ width: this.colorId === index ? 3 : 0, color: Color.White })
              .outline({ width: this.colorId === index ? 2 : 0, color: color })
              .onClick((): void => { this.colorId = index; });
          }, (_color: string, index: number): string => `color_${index}`);
        }.width('100%');
      }
    }.width('100%').padding(14).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  @Builder
  toggleRow(title: string, subtitle: string, value: boolean, kind: string) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(title).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
        Text(subtitle).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      Toggle({ type: ToggleType.Switch, isOn: value }).selectedColor(COLOR_PRIMARY)
        .enabled(!this.base.isShareable).onChange((next: boolean): void => this.setType(kind, next));
    }.width('100%').padding({ left: 14, right: 14, top: 9, bottom: 9 });
  }

  @Builder
  selectedChatRow(id: number, included: boolean) {
    Row({ space: 11 }) {
      AvatarView({
        avatarPath: this.summary(id).avatarPath,
        initials: this.summary(id).initials,
        colorSeed: id,
        avatarSize: 34
      });
      Column({ space: 1 }) {
        Text(this.summary(id).title).fontSize(15).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(this.kindLabel(this.summary(id).kind)).fontSize(10).fontColor(COLOR_TEXT_SECONDARY);
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      Row() { SymbolGlyph($r('sys.symbol.xmark')).fontSize(15).fontColor([COLOR_TEXT_SECONDARY]); }
        .width(36).height(36).borderRadius(18).justifyContent(FlexAlign.Center)
        .stateStyles({ normal: this.pressNormal, pressed: this.pressDown })
        .onClick((): void => this.removeChat(id, included));
    }.width('100%').padding({ left: 14, right: 8, top: 7, bottom: 7 })
      .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: 8 }))
        .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 170), curve: Curve.EaseOut }));
  }

  @Builder
  addRow(title: string, mode: string) {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.plus_circle')).fontSize(19).fontColor([COLOR_PRIMARY]);
      Text(title).fontSize(16).fontColor(COLOR_PRIMARY).layoutWeight(1);
      Text(`${mode === PICK_INCLUDE ? this.included.length : this.excluded.length}/${this.limits.chosenChatCount}`)
        .fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
    }.width('100%').padding({ left: 14, right: 14, top: 11, bottom: 11 })
      .stateStyles({ normal: this.pressNormal, pressed: this.pressDown })
      .onClick((): void => this.openPicker(mode));
  }

  @Builder
  includeCard() {
    Column() {
      if (this.base.isShareable) {
        Row({ space: 8 }) {
          Text('🔗').fontSize(16);
          Text('共享文件夹只能使用明确添加的聊天').fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
        }.width('100%').padding(14).backgroundColor('#105B8FF9');
      } else {
        this.toggleRow('联系人', '所有联系人私聊', this.includeContacts, 'contacts');
        Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 });
        this.toggleRow('非联系人', '尚未保存为联系人的私聊', this.includeNonContacts, 'nonContacts');
        Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 });
        this.toggleRow('群组', '基础群组和超级群组', this.includeGroups, 'groups');
        Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 });
        this.toggleRow('频道', '订阅的广播频道', this.includeChannels, 'channels');
        Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 });
        this.toggleRow('机器人', '与机器人的私聊', this.includeBots, 'bots');
      }
      ForEach(this.included, (id: number) => {
        Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 58 });
        this.selectedChatRow(id, true);
      }, (id: number): string => `include_${id}`);
      Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 });
      this.addRow('添加聊天', PICK_INCLUDE);
    }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).clip(true);
  }

  @Builder
  excludeCard() {
    Column() {
      this.toggleRow('已静音', '排除关闭通知的聊天', this.excludeMuted, 'muted');
      Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 });
      this.toggleRow('已读', '只保留仍有未读消息的聊天', this.excludeRead, 'read');
      Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 });
      this.toggleRow('已归档', '排除归档列表中的聊天', this.excludeArchived, 'archived');
      ForEach(this.excluded, (id: number) => {
        Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 58 });
        this.selectedChatRow(id, false);
      }, (id: number): string => `exclude_${id}`);
      Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 });
      this.addRow('添加要排除的聊天', PICK_EXCLUDE);
    }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).clip(true)
      .opacity(this.base.isShareable ? 0.48 : 1).enabled(!this.base.isShareable);
  }

  @Builder
  shareCard() {
    Row({ space: 12 }) {
      Row() { Text('🔗').fontSize(20); }.width(42).height(42).borderRadius(14)
        .justifyContent(FlexAlign.Center).backgroundColor('#165B8FF9');
      Column({ space: 3 }) {
        Text('共享文件夹').fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
        Text(this.base.isShareable ? '管理共享链接和新增聊天' : '为明确添加的群组或频道创建链接')
          .fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([COLOR_TEXT_SECONDARY]);
    }.width('100%').padding(14).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
      .stateStyles({ normal: this.pressNormal, pressed: this.pressDown })
      .onClick((): void => this.openShareLinks());
  }

  @Builder
  warningBar() {
    if (this.warning !== '') {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(17).fontColor(['#E68A00']);
        Text(this.warning).fontSize(12).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
      }.width('100%').padding(12).backgroundColor('#16E68A00').borderRadius(12)
        .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut }));
    }
  }

  @Builder
  editor() {
    Scroll() {
      Column({ space: 14 }) {
        this.warningBar();
        this.sectionTitle('名称和外观');
        this.identityCard();
        this.sectionTitle('包含的聊天', this.base.isShareable ? '共享文件夹仅支持明确添加' : '类型规则和单独聊天可以同时使用');
        this.includeCard();
        this.sectionTitle('排除的聊天', '单独排除优先于包含规则');
        this.excludeCard();
        if (this.folderId > 0) {
          this.sectionTitle('共享');
          this.shareCard();
        }
      }.width('100%').padding({ left: 12, right: 12, top: 4, bottom: this.bottomSafe + 28 });
    }.layoutWeight(1).width('100%').scrollBar(BarState.Off).align(Alignment.Top);
  }

  @Builder
  pickerSheet() {
    Column() {
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text(this.pickerMode === PICK_INCLUDE ? '添加聊天' : '排除聊天')
            .fontSize(19).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
          Text(`已选择 ${this.pickerMode === PICK_INCLUDE ? this.included.length : this.excluded.length} 个`)
            .fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).alignItems(HorizontalAlign.Start);
        Text('完成').fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
          .width(52).height(38).textAlign(TextAlign.Center)
          .stateStyles({ normal: this.pressNormal, pressed: this.pressDown })
          .onClick((): void => { this.pickerOpen = false; this.pickerQuery = ''; });
      }.width('100%').padding({ left: 16, right: 10, top: 12, bottom: 8 });
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(17).fontColor([COLOR_TEXT_SECONDARY]);
        TextInput({ placeholder: '搜索聊天、群组或频道', text: this.pickerQuery })
          .fontSize(15).layoutWeight(1).backgroundColor(Color.Transparent).padding(0)
          .onChange((value: string): void => this.schedulePickerSearch(value));
        if (this.pickerState === 'loading') { LoadingProgress().width(17).height(17).color(COLOR_PRIMARY); }
      }.height(44).margin({ left: 16, right: 16, bottom: 8 }).padding({ left: 12, right: 12 })
        .backgroundColor(COLOR_PAGE_BG).borderRadius(14);
      if (this.pickerState === 'error') {
        Column({ space: 10 }) {
          Text('搜索暂时失败').fontSize(15).fontColor(COLOR_TEXT_PRIMARY);
          Text('重新搜索').fontSize(14).fontColor(COLOR_PRIMARY)
            .onClick((): void => this.runPickerSearch(this.pickerQuery));
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.pickerState === 'empty') {
        Column({ space: 7 }) {
          Text('🔍').fontSize(36);
          Text('没有找到聊天').fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
          Text('可以尝试群组名称或公开用户名').fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else {
        List() {
          ForEach(this.pickerRows, (chat: FolderChatSummary) => {
            ListItem() {
              Row({ space: 12 }) {
                Row({ space: 12 }) {
                  AvatarView({ avatarPath: chat.avatarPath, initials: chat.initials, colorSeed: chat.id, avatarSize: 40 });
                  Column({ space: 2 }) {
                    Text(chat.title).fontSize(16).fontColor(COLOR_TEXT_PRIMARY)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                    Text(this.kindLabel(chat.kind)).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start);
                }.layoutWeight(1);
                // Display-only: a live onChange here re-fires while the row
                // click's state update re-renders isOn, which mutates state
                // mid-render and loops until the input watchdog kills the app.
                Toggle({ type: ToggleType.Checkbox, isOn: this.selectedForPicker(chat.id) })
                  .selectedColor(COLOR_PRIMARY).hitTestBehavior(HitTestMode.None);
              }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 8 })
                .stateStyles({ normal: this.pressNormal, pressed: this.pressDown })
                .onClick((): void => this.togglePickerChat(chat.id));
            }
          }, (chat: FolderChatSummary): string => `picker_${chat.id}`);
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
      }
      Text('选择会立即保留，点击完成返回编辑页').fontSize(11).fontColor(COLOR_TEXT_SECONDARY)
        .padding({ top: 8, bottom: this.bottomSafe + 10 });
    }.width('100%').height('100%');
  }

  build() {
    Column() {
      this.header();
      if (this.loadState === 'loading') { this.loadSkeleton(); }
      else if (this.loadState === 'error') { this.loadError(); }
      else { this.editor(); }
    }.width('100%').height('100%').backgroundColor(COLOR_PAGE_BG)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .padding({ top: this.topSafe })
      .bindSheet($$this.pickerOpen, this.pickerSheet(), {
        // The sheet's own top-right 完成 button replaces the system close icon,
        // which would otherwise overlap it.
        height: '82%', backgroundColor: COLOR_SURFACE, dragBar: true, showClose: false
      });
  }
}
