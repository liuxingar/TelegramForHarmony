import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction, router } from '@kit.ArkUI';
import { TdError } from '../../tdkit/TdTypes';
import {
  FolderChatSummary, FolderInviteLinkData, createFolderInviteLink,
  deleteFolderInviteLink, editFolderInviteLink, getChatsForFolderInviteLink,
  getFolderChatSummaries, getFolderInviteLinks, getFolderNewChats,
  processFolderNewChats
} from '../../store/FolderApi';
import {
  COLOR_DIVIDER, COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE,
  COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { AvatarView } from '../chatlist/AvatarView';

interface FolderInviteParams {
  folderId: number;
  title: string;
}

const CARD_RADIUS: number = 14;
const DANGER: string = '#E64646';

@Entry
@Component
struct FolderInviteLinksPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State folderId: number = 0;
  @State title: string = '';
  @State loadState: string = 'loading';
  @State warning: string = '';
  @State links: FolderInviteLinkData[] = [];
  @State eligibleChats: FolderChatSummary[] = [];
  @State newChats: FolderChatSummary[] = [];
  @State operationKey: string = '';
  @State editorOpen: boolean = false;
  @State editingLink: string = '';
  @State linkName: string = '';
  @State selectedChatIds: number[] = [];
  @State newChatsOpen: boolean = false;
  @State selectedNewChatIds: number[] = [];
  private active: boolean = false;
  private loadSequence: number = 0;

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
    const params = router.getParams() as FolderInviteParams | undefined;
    this.folderId = params?.folderId ?? 0;
    this.title = params?.title ?? '';
    this.load();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.loadSequence++;
  }

  private load(): void {
    const sequence = ++this.loadSequence;
    this.loadState = 'loading';
    this.warning = '';
    if (this.folderId <= 0) { this.loadState = 'error'; return; }
    Promise.all([
      getFolderInviteLinks(this.folderId),
      getChatsForFolderInviteLink(this.folderId),
      getFolderNewChats(this.folderId).catch((): number[] => [])
    ]).then((values: [FolderInviteLinkData[], number[], number[]]): Promise<FolderChatSummary[][]> => {
      if (!this.active || sequence !== this.loadSequence) { return Promise.resolve([[], []]); }
      this.links = values[0];
      return Promise.all([
        getFolderChatSummaries(values[1]), getFolderChatSummaries(values[2])
      ]);
    }).then((summaries: FolderChatSummary[][]): void => {
      if (!this.active || sequence !== this.loadSequence) { return; }
      this.eligibleChats = summaries[0];
      this.newChats = summaries[1];
      this.selectedNewChatIds = summaries[1].map((chat: FolderChatSummary): number => chat.id);
      this.loadState = 'ready';
    }).catch((error: TdError): void => {
      if (!this.active || sequence !== this.loadSequence) { return; }
      this.loadState = 'error';
      this.warning = '共享链接暂时无法加载';
      console.error(`FolderInviteLinksPage.load failed: ${error.message}`);
    });
  }

  private copy(link: string): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, link);
    pasteboard.getSystemPasteboard().setData(data).then((): void => {
      promptAction.showToast({ message: '链接已复制', duration: 1400 });
    }).catch((): void => {
      promptAction.showToast({ message: '复制失败', duration: 1500 });
    });
  }

  private openCreate(): void {
    if (this.operationKey !== '') { return; }
    if (this.eligibleChats.length === 0) {
      this.warning = '只有明确添加到文件夹且允许分享的群组或频道才能创建链接';
      return;
    }
    this.editingLink = '';
    this.linkName = '';
    this.selectedChatIds = this.eligibleChats.map((chat: FolderChatSummary): number => chat.id);
    this.editorOpen = true;
  }

  private openEdit(link: FolderInviteLinkData): void {
    if (this.operationKey !== '') { return; }
    this.editingLink = link.inviteLink;
    this.linkName = link.name;
    this.selectedChatIds = link.chatIds.slice();
    this.editorOpen = true;
  }

  private toggleChat(id: number): void {
    this.selectedChatIds = this.selectedChatIds.indexOf(id) >= 0
      ? this.selectedChatIds.filter((value: number): boolean => value !== id)
      : [...this.selectedChatIds, id];
  }

  private saveLink(): void {
    if (this.operationKey !== '' || this.selectedChatIds.length === 0) {
      if (this.selectedChatIds.length === 0) { this.warning = '至少选择一个可分享的聊天'; }
      return;
    }
    const key = this.editingLink === '' ? 'create' : 'edit';
    this.operationKey = key;
    const task: Promise<FolderInviteLinkData> = this.editingLink === ''
      ? createFolderInviteLink(this.folderId, this.linkName.trim(), this.selectedChatIds)
      : editFolderInviteLink(this.folderId, this.editingLink, this.linkName.trim(), this.selectedChatIds);
    task.then((saved: FolderInviteLinkData): void => {
      if (!this.active) { return; }
      const index = this.links.findIndex((link: FolderInviteLinkData): boolean =>
        link.inviteLink === (this.editingLink === '' ? saved.inviteLink : this.editingLink));
      if (index < 0) { this.links = [...this.links, saved]; }
      else { const next = this.links.slice(); next[index] = saved; this.links = next; }
      this.operationKey = '';
      this.editorOpen = false;
      this.warning = '';
      promptAction.showToast({ message: key === 'create' ? '共享链接已创建' : '共享链接已更新', duration: 1500 });
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.operationKey = '';
      this.warning = error.message.indexOf('PREMIUM') >= 0
        ? '共享链接数量已达到当前账号上限' : '保存共享链接失败，请稍后重试';
      promptAction.showToast({ message: this.warning, duration: 1900 });
      console.error(`FolderInviteLinksPage.saveLink failed: ${error.message}`);
    });
  }

  private confirmDelete(link: FolderInviteLinkData): void {
    promptAction.showDialog({
      title: '删除共享链接', message: '删除后，已获得此链接的人将无法再通过它添加文件夹。',
      buttons: [
        { text: '取消', color: COLOR_TEXT_SECONDARY as string },
        { text: '删除', color: DANGER }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (result.index !== 1 || this.operationKey !== '') { return; }
      this.operationKey = `delete_${link.inviteLink}`;
      deleteFolderInviteLink(this.folderId, link.inviteLink).then((): void => {
        if (!this.active) { return; }
        this.links = this.links.filter((item: FolderInviteLinkData): boolean => item.inviteLink !== link.inviteLink);
        this.operationKey = '';
        promptAction.showToast({ message: '共享链接已删除', duration: 1500 });
      }).catch((error: TdError): void => {
        if (!this.active) { return; }
        this.operationKey = '';
        this.warning = '删除链接失败，请重试';
        console.error(`FolderInviteLinksPage.delete failed: ${error.message}`);
      });
    }).catch((): void => {});
  }

  private toggleNewChat(id: number): void {
    this.selectedNewChatIds = this.selectedNewChatIds.indexOf(id) >= 0
      ? this.selectedNewChatIds.filter((value: number): boolean => value !== id)
      : [...this.selectedNewChatIds, id];
  }

  private addNewChats(): void {
    if (this.operationKey !== '' || this.selectedNewChatIds.length === 0) { return; }
    this.operationKey = 'new_chats';
    processFolderNewChats(this.folderId, this.selectedNewChatIds).then((): void => {
      if (!this.active) { return; }
      const selected = this.selectedNewChatIds.slice();
      this.newChats = this.newChats.filter((chat: FolderChatSummary): boolean => selected.indexOf(chat.id) < 0);
      this.selectedNewChatIds = [];
      this.newChatsOpen = false;
      this.operationKey = '';
      promptAction.showToast({ message: '已添加共享文件夹的新聊天', duration: 1700 });
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.operationKey = '';
      this.warning = '部分聊天无法加入，请确认账号权限后重试';
      console.error(`FolderInviteLinksPage.newChats failed: ${error.message}`);
    });
  }

  @Builder
  header() {
    Row({ space: 6 }) {
      Row() { SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(25).fontColor([COLOR_TEXT_PRIMARY]); }
        .width(44).height(44).borderRadius(22).justifyContent(FlexAlign.Center)
        .stateStyles({ normal: this.pressNormal, pressed: this.pressDown }).onClick((): void => router.back());
      Column({ space: 1 }) {
        Text('共享文件夹').fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
        Text(this.title).fontSize(11).fontColor(COLOR_TEXT_SECONDARY).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      if (this.operationKey !== '') { LoadingProgress().width(19).height(19).color(COLOR_PRIMARY).margin({ right: 13 }); }
    }.width('100%').height(56).padding({ left: 8, right: 8 });
  }

  @Builder
  linkMenu(link: FolderInviteLinkData) {
    Menu() {
      MenuItem({ content: '编辑链接' }).onClick((): void => this.openEdit(link));
      MenuItem({ content: '复制链接' }).onClick((): void => this.copy(link.inviteLink));
      MenuItem({ content: '删除链接' }).onClick((): void => this.confirmDelete(link));
    }
  }

  @Builder
  linkRow(link: FolderInviteLinkData) {
    Row({ space: 12 }) {
      Row() { Text('🔗').fontSize(20); }.width(42).height(42).borderRadius(14)
        .justifyContent(FlexAlign.Center).backgroundColor('#165B8FF9');
      Column({ space: 3 }) {
        Text(link.name !== '' ? link.name : '共享链接').fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(`${link.chatIds.length} 个聊天 · ${link.inviteLink}`)
          .fontSize(11).fontColor(COLOR_TEXT_SECONDARY).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }.layoutWeight(1).alignItems(HorizontalAlign.Start).onClick((): void => this.copy(link.inviteLink));
      Row() { SymbolGlyph($r('sys.symbol.more')).fontSize(19).fontColor([COLOR_TEXT_SECONDARY]); }
        .width(40).height(40).borderRadius(20).justifyContent(FlexAlign.Center)
        .stateStyles({ normal: this.pressNormal, pressed: this.pressDown }).bindMenu(this.linkMenu(link));
    }.width('100%').padding(14).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  @Builder
  readyContent() {
    Scroll() {
      Column({ space: 14 }) {
        if (this.warning !== '') {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(17).fontColor(['#E68A00']);
            Text(this.warning).fontSize(12).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
          }.width('100%').padding(12).backgroundColor('#16E68A00').borderRadius(12);
        }
        if (this.newChats.length > 0) {
          Row({ space: 12 }) {
            Text('✨').fontSize(22);
            Column({ space: 2 }) {
              Text(`${this.newChats.length} 个新聊天`).fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
              Text('共享文件夹创建者添加了新的群组或频道').fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
            }.layoutWeight(1).alignItems(HorizontalAlign.Start);
            Text('查看').fontSize(14).fontColor(COLOR_PRIMARY).onClick((): void => { this.newChatsOpen = true; });
          }.width('100%').padding(14).backgroundColor('#125B8FF9').borderRadius(CARD_RADIUS);
        }
        Text('链接').fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_SECONDARY)
          .width('100%').padding({ left: 4 });
        if (this.links.length === 0) {
          Column({ space: 7 }) {
            Text('🔗').fontSize(38);
            Text('还没有共享链接').fontSize(17).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
            Text('创建后，其他人可以一次添加链接中的群组和频道。')
              .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center);
          }.width('100%').padding({ top: 28, bottom: 28 }).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
        } else {
          ForEach(this.links, (link: FolderInviteLinkData) => { this.linkRow(link); },
            (link: FolderInviteLinkData): string => link.inviteLink);
        }
        Row({ space: 9 }) {
          SymbolGlyph($r('sys.symbol.plus_circle')).fontSize(20).fontColor([COLOR_PRIMARY]);
          Text('创建共享链接').fontSize(16).fontColor(COLOR_PRIMARY).layoutWeight(1);
        }.width('100%').padding(14).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
          .stateStyles({ normal: this.pressNormal, pressed: this.pressDown }).onClick((): void => this.openCreate());
        Text('共享链接只能包含明确添加到文件夹、并允许当前账号分享的群组和频道。')
          .fontSize(11).fontColor(COLOR_TEXT_SECONDARY).padding({ left: 8, right: 8 });
      }.width('100%').padding({ left: 12, right: 12, top: 6, bottom: this.bottomSafe + 24 });
    }.layoutWeight(1).width('100%').scrollBar(BarState.Off).align(Alignment.Top);
  }

  @Builder
  linkEditorSheet() {
    Column() {
      Row() {
        Column({ space: 2 }) {
          Text(this.editingLink === '' ? '创建共享链接' : '编辑共享链接')
            .fontSize(19).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
          Text(`已选择 ${this.selectedChatIds.length} 个聊天`).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).alignItems(HorizontalAlign.Start);
        Text('保存').fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
          .width(52).height(38).textAlign(TextAlign.Center).onClick((): void => this.saveLink());
      }.width('100%').padding({ left: 16, right: 10, top: 12, bottom: 8 });
      TextInput({ placeholder: '链接名称（可选）', text: this.linkName })
        .fontSize(15).maxLength(32).height(44).margin({ left: 16, right: 16, bottom: 8 })
        .padding({ left: 12, right: 12 }).backgroundColor(COLOR_PAGE_BG).borderRadius(12)
        .onChange((value: string): void => { this.linkName = value; });
      List() {
        ForEach(this.eligibleChats, (chat: FolderChatSummary) => {
          ListItem() {
            Row({ space: 12 }) {
              Row({ space: 12 }) {
                AvatarView({ avatarPath: chat.avatarPath, initials: chat.initials, colorSeed: chat.id, avatarSize: 38 });
                Text(chat.title).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
              }.layoutWeight(1);
              // Display-only: onChange plus the row click would re-enter the
              // toggle during render and freeze the app (same bug as the
              // folder-edit picker).
              Toggle({ type: ToggleType.Checkbox, isOn: this.selectedChatIds.indexOf(chat.id) >= 0 })
                .selectedColor(COLOR_PRIMARY).hitTestBehavior(HitTestMode.None);
            }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .onClick((): void => this.toggleChat(chat.id));
          }
        }, (chat: FolderChatSummary): string => `eligible_${chat.id}`);
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
      Text('只有被选中的聊天会出现在这个链接中').fontSize(11).fontColor(COLOR_TEXT_SECONDARY)
        .padding({ top: 8, bottom: this.bottomSafe + 10 });
    }.width('100%').height('100%');
  }

  @Builder
  newChatsSheet() {
    Column() {
      Text('共享文件夹的新聊天').fontSize(19).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .padding({ top: 14, bottom: 6 });
      Text('选择要加入并添加到文件夹的聊天').fontSize(12).fontColor(COLOR_TEXT_SECONDARY).padding({ bottom: 8 });
      List() {
        ForEach(this.newChats, (chat: FolderChatSummary) => {
          ListItem() {
            Row({ space: 12 }) {
              AvatarView({ avatarPath: chat.avatarPath, initials: chat.initials, colorSeed: chat.id, avatarSize: 38 });
              Text(chat.title).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
              Toggle({ type: ToggleType.Checkbox, isOn: this.selectedNewChatIds.indexOf(chat.id) >= 0 })
                .selectedColor(COLOR_PRIMARY).onChange((): void => this.toggleNewChat(chat.id));
            }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 8 });
          }
        }, (chat: FolderChatSummary): string => `new_${chat.id}`);
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
      Text(`添加 ${this.selectedNewChatIds.length} 个聊天`).fontSize(16).fontWeight(FontWeight.Medium)
        .fontColor(Color.White).textAlign(TextAlign.Center).width('100%')
        .padding({ top: 12, bottom: 12 }).backgroundColor(COLOR_PRIMARY).borderRadius(12)
        .margin({ left: 16, right: 16, top: 8, bottom: this.bottomSafe + 10 })
        .enabled(this.selectedNewChatIds.length > 0).onClick((): void => this.addNewChats());
    }.width('100%').height('100%');
  }

  build() {
    Column() {
      this.header();
      if (this.loadState === 'loading') {
        Column() { LoadingProgress().width(34).height(34).color(COLOR_PRIMARY); }
          .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.loadState === 'error') {
        Column({ space: 10 }) {
          Text('共享链接加载失败').fontSize(17).fontColor(COLOR_TEXT_PRIMARY);
          Text('重新加载').fontSize(14).fontColor(COLOR_PRIMARY).onClick((): void => this.load());
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else { this.readyContent(); }
    }.width('100%').height('100%').backgroundColor(COLOR_PAGE_BG)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .padding({ top: this.topSafe })
      .bindSheet($$this.editorOpen, this.linkEditorSheet(), {
        height: '82%', backgroundColor: COLOR_SURFACE, dragBar: true
      })
      .bindSheet($$this.newChatsOpen, this.newChatsSheet(), {
        height: '72%', backgroundColor: COLOR_SURFACE, dragBar: true
      });
  }
}
