import { router, promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { getTdClient, getUserStore } from '../../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../../tdkit/TdTypes';
import {
  AdminRow, GroupPermissions, InviteLinkRow, JoinRequestRow, banMember, createInviteLink,
  defaultPermissions, deleteMessagesFromSender, getAdministrators, getInviteLinks,
  checkUsernameAvailable, deleteMessagesByDate, getJoinRequests, permissionsFromTd,
  processJoinRequest, revokeInviteLink, setAdmin, setChatDescription, setChatPermissions,
  setChatTitle, setPublicUsername, setSlowMode
} from '../../store/ChatAdminApi';
import {
  COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';

const CARD_RADIUS: number = 14;
const SLOW_MODE_VALUES: number[] = [0, 10, 30, 60, 300, 900, 3600];
const SLOW_MODE_LABELS: string[] = ['关闭', '10 秒', '30 秒', '1 分钟', '5 分钟', '15 分钟', '1 小时'];

interface AdminPageParams {
  chatId?: number;
}

@Entry
@Component
struct GroupAdminPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State title: string = '';
  @State description: string = '';
  @State permissions: GroupPermissions = defaultPermissions();
  @State slowModeIndex: number = 0;
  @State admins: AdminRow[] = [];
  @State links: InviteLinkRow[] = [];
  @State requests: JoinRequestRow[] = [];
  @State loadState: string = 'loading';
  @State busy: boolean = false;
  @State publicUsername: string = '';
  private supergroupId: number = 0;
  private chatId: number = 0;
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    const params = router.getParams() as AdminPageParams | undefined;
    this.chatId = params?.chatId ?? 0;
    this.load();
  }

  aboutToDisappear(): void {
    this.active = false;
  }

  private load(): void {
    if (this.chatId === 0) { this.loadState = 'error'; return; }
    this.loadState = 'loading';
    const chatReq: TdRequest = { '@type': 'getChat' };
    chatReq['chat_id'] = this.chatId;
    getTdClient().send(chatReq).then((chat: TdObject): void => {
      if (!this.active) { return; }
      this.title = (chat['title'] as string | undefined) ?? '';
      this.permissions = permissionsFromTd(chat['permissions'] as TdObject | undefined);
      const type = chat['type'] as TdObject | undefined;
      this.supergroupId = type !== undefined
        ? ((type['supergroup_id'] as number | undefined) ?? 0) : 0;
      this.loadState = 'ready';
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      console.error(`GroupAdminPage.load failed: ${error.message}`);
      this.loadState = 'error';
    });
    getAdministrators(this.chatId).then((rows: AdminRow[]): void => {
      if (this.active) {
        this.admins = rows;
        for (const row of rows) { getUserStore().ensure(row.userId); }
      }
    }).catch((): void => {});
    getInviteLinks(this.chatId, 0).then((rows: InviteLinkRow[]): void => {
      if (this.active) { this.links = rows; }
    }).catch((): void => {});
    getJoinRequests(this.chatId).then((rows: JoinRequestRow[]): void => {
      if (this.active) {
        this.requests = rows;
        for (const row of rows) { getUserStore().ensure(row.userId); }
      }
    }).catch((): void => {});
  }

  private nameOf(userId: number): string {
    const name = getUserStore().displayName(userId);
    return name !== '' ? name : `用户 ${userId}`;
  }

  private fail(error: TdError, fallback: string): void {
    this.busy = false;
    console.error(`GroupAdminPage: ${error.message}`);
    promptAction.showToast({
      message: error.message.indexOf('rights') >= 0 || error.message.indexOf('ADMIN') >= 0
        ? '权限不足' : fallback,
      duration: 1700
    });
  }

  private saveTitle(): void {
    const value = this.title.trim();
    if (value === '' || this.busy) { return; }
    this.busy = true;
    setChatTitle(this.chatId, value).then((): void => {
      this.busy = false;
      promptAction.showToast({ message: '名称已更新', duration: 1400 });
    }).catch((e: TdError): void => this.fail(e, '修改名称失败'));
  }

  private saveDescription(): void {
    if (this.busy) { return; }
    this.busy = true;
    setChatDescription(this.chatId, this.description.trim()).then((): void => {
      this.busy = false;
      promptAction.showToast({ message: '简介已更新', duration: 1400 });
    }).catch((e: TdError): void => this.fail(e, '修改简介失败'));
  }

  // Permission switches write the whole set — TDLib has no partial update.
  private togglePermission(key: string, value: boolean): void {
    const next: GroupPermissions = {
      sendMessages: key === 'sendMessages' ? value : this.permissions.sendMessages,
      sendMedia: key === 'sendMedia' ? value : this.permissions.sendMedia,
      sendPolls: key === 'sendPolls' ? value : this.permissions.sendPolls,
      sendOther: key === 'sendOther' ? value : this.permissions.sendOther,
      addLinkPreviews: key === 'addLinkPreviews' ? value : this.permissions.addLinkPreviews,
      changeInfo: key === 'changeInfo' ? value : this.permissions.changeInfo,
      inviteUsers: key === 'inviteUsers' ? value : this.permissions.inviteUsers,
      pinMessages: key === 'pinMessages' ? value : this.permissions.pinMessages
    };
    const previous = this.permissions;
    this.permissions = next;
    setChatPermissions(this.chatId, next).catch((e: TdError): void => {
      this.permissions = previous;
      this.fail(e, '权限修改失败');
    });
  }

  private chooseSlowMode(): void {
    promptAction.showActionMenu({
      title: '慢速模式',
      buttons: SLOW_MODE_LABELS.slice(0, 6).map((text: string): promptAction.Button =>
        ({ text, color: '#3390EC' } as promptAction.Button)) as
        [promptAction.Button, promptAction.Button?, promptAction.Button?,
          promptAction.Button?, promptAction.Button?, promptAction.Button?]
    }).then((chosen): void => {
      const seconds = SLOW_MODE_VALUES[chosen.index];
      if (seconds === undefined) { return; }
      setSlowMode(this.chatId, seconds).then((): void => {
        this.slowModeIndex = chosen.index;
        promptAction.showToast({
          message: seconds === 0 ? '已关闭慢速模式' : `发言间隔 ${SLOW_MODE_LABELS[chosen.index]}`,
          duration: 1600
        });
      }).catch((e: TdError): void => this.fail(e, '慢速模式设置失败'));
    }).catch((): void => {});
  }

  private memberActions(userId: number, isAdmin: boolean): void {
    const labels: string[] = isAdmin ? ['撤销管理员'] : ['设为管理员', '移出并封禁', '删除其全部消息'];
    promptAction.showActionMenu({
      title: this.nameOf(userId),
      buttons: labels.map((text: string): promptAction.Button =>
        ({ text, color: text.indexOf('封禁') >= 0 || text.indexOf('删除') >= 0
          ? '#E5484D' : '#3390EC' } as promptAction.Button)) as
        [promptAction.Button, promptAction.Button?, promptAction.Button?,
          promptAction.Button?, promptAction.Button?, promptAction.Button?]
    }).then((chosen): void => {
      const label = labels[chosen.index];
      if (label === undefined) { return; }
      let task: Promise<void> | null = null;
      if (label === '撤销管理员') { task = setAdmin(this.chatId, userId, false); }
      else if (label === '设为管理员') { task = setAdmin(this.chatId, userId, true); }
      else if (label === '移出并封禁') { task = banMember(this.chatId, userId, false); }
      else { task = deleteMessagesFromSender(this.chatId, userId); }
      task.then((): void => {
        promptAction.showToast({ message: '操作成功', duration: 1400 });
        this.load();
      }).catch((e: TdError): void => this.fail(e, '操作失败'));
    }).catch((): void => {});
  }

  // Public username: '' turns the group private. Availability is checked
  // before writing so the user gets a precise reason.
  private savePublicUsername(): void {
    if (this.busy) { return; }
    const value = this.publicUsername.trim();
    this.busy = true;
    const check: Promise<string> = value === ''
      ? Promise.resolve('') : checkUsernameAvailable(this.chatId, value);
    check.then((issue: string): Promise<void> => {
      if (issue !== '') { return Promise.reject(new TdError(400, issue)); }
      if (this.supergroupId === 0) {
        return Promise.reject(new TdError(400, '仅超级群/频道支持公开用户名'));
      }
      return setPublicUsername(this.supergroupId, value);
    }).then((): void => {
      this.busy = false;
      promptAction.showToast({
        message: value === '' ? '已设为私有群组' : `公开链接 t.me/${value} 已生效`, duration: 1900
      });
    }).catch((e: TdError): void => {
      this.busy = false;
      promptAction.showToast({ message: e.message, duration: 1900 });
    });
  }

  private deleteTodayMessages(): void {
    promptAction.showDialog({
      title: '删除今天的消息',
      message: '将删除本会话今天的全部消息，所有人可见，且无法恢复。',
      buttons: [
        { text: '取消', color: '#8E8E93' },
        { text: '删除', color: '#E5484D' }
      ]
    }).then((result): void => {
      if (result.index !== 1) { return; }
      const now = Math.floor(Date.now() / 1000);
      const start = new Date();
      start.setHours(0, 0, 0, 0);
      deleteMessagesByDate(this.chatId, Math.floor(start.getTime() / 1000), now).then((): void => {
        promptAction.showToast({ message: '已删除', duration: 1500 });
      }).catch((e: TdError): void => this.fail(e, '删除失败'));
    }).catch((): void => {});
  }

  private newInviteLink(): void {
    if (this.busy) { return; }
    this.busy = true;
    createInviteLink(this.chatId, '', 0, false).then((link: string): void => {
      this.busy = false;
      if (link !== '') {
        const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, link);
        pasteboard.getSystemPasteboard().setData(data).catch((): void => {});
        promptAction.showToast({ message: '新链接已创建并复制', duration: 1700 });
      }
      this.load();
    }).catch((e: TdError): void => this.fail(e, '创建邀请链接失败'));
  }

  private handleRequest(userId: number, approve: boolean): void {
    processJoinRequest(this.chatId, userId, approve).then((): void => {
      this.requests = this.requests.filter((r: JoinRequestRow): boolean => r.userId !== userId);
      promptAction.showToast({ message: approve ? '已通过' : '已拒绝', duration: 1400 });
    }).catch((e: TdError): void => this.fail(e, '处理失败'));
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([COLOR_TEXT_PRIMARY]);
      }.width(40).height(40).borderRadius(20).backgroundColor(Color.Transparent)
      .onClick((): void => { router.back(); });
      Text('群组管理').fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
      if (this.busy) { LoadingProgress().width(20).height(20).color(COLOR_PRIMARY); }
    }.width('100%').height(52).padding({ left: 8, right: 16 }).alignItems(VerticalAlign.Center);
  }

  @Builder
  permissionRow(label: string, key: string, value: boolean) {
    Row() {
      Text(label).fontSize(15).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
      Toggle({ type: ToggleType.Switch, isOn: value }).selectedColor(COLOR_PRIMARY)
        .onChange((next: boolean): void => this.togglePermission(key, next));
    }.width('100%').height(48).padding({ left: 14, right: 12 });
  }

  build() {
    Column() {
      this.header();
      if (this.loadState === 'loading') {
        Column({ space: 9 }) {
          LoadingProgress().width(32).height(32).color(COLOR_PRIMARY);
          Text('正在加载群组信息…').fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.loadState === 'error') {
        Column({ space: 10 }) {
          Text('加载失败').fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
          Button('重新加载').onClick((): void => this.load());
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else {
        Scroll() {
          Column({ space: 12 }) {
            Column({ space: 10 }) {
              Text('基本信息').fontSize(12).fontColor(COLOR_TEXT_SECONDARY).width('100%');
              TextInput({ placeholder: '群组名称', text: this.title })
                .fontSize(15).backgroundColor(COLOR_PAGE_BG).borderRadius(10)
                .onChange((value: string): void => { this.title = value; })
                .onSubmit((): void => this.saveTitle());
              TextArea({ placeholder: '群组简介', text: this.description })
                .fontSize(14).height(72).backgroundColor(COLOR_PAGE_BG).borderRadius(10)
                .onChange((value: string): void => { this.description = value; });
              Row({ space: 10 }) {
                Button('保存名称').layoutWeight(1).height(38).fontSize(14)
                  .onClick((): void => this.saveTitle());
                Button('保存简介').layoutWeight(1).height(38).fontSize(14)
                  .onClick((): void => this.saveDescription());
              }.width('100%');
              Row({ space: 8 }) {
                Text('t.me/').fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
                TextInput({ placeholder: '公开用户名（留空则私有）', text: this.publicUsername })
                  .fontSize(14).layoutWeight(1).backgroundColor(COLOR_PAGE_BG).borderRadius(10)
                  .onChange((value: string): void => { this.publicUsername = value; });
                Button('保存').height(34).fontSize(13)
                  .onClick((): void => this.savePublicUsername());
              }.width('100%');
            }
            .width('100%').padding(14).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);

            Column() {
              Text('成员权限').fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
                .width('100%').padding({ left: 14, top: 12, bottom: 4 });
              this.permissionRow('发送消息', 'sendMessages', this.permissions.sendMessages);
              this.permissionRow('发送媒体', 'sendMedia', this.permissions.sendMedia);
              this.permissionRow('发起投票', 'sendPolls', this.permissions.sendPolls);
              this.permissionRow('发送贴纸和 GIF', 'sendOther', this.permissions.sendOther);
              this.permissionRow('嵌入链接预览', 'addLinkPreviews', this.permissions.addLinkPreviews);
              this.permissionRow('修改群信息', 'changeInfo', this.permissions.changeInfo);
              this.permissionRow('添加成员', 'inviteUsers', this.permissions.inviteUsers);
              this.permissionRow('置顶消息', 'pinMessages', this.permissions.pinMessages);
              Row() {
                Text('慢速模式').fontSize(15).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
                Text(SLOW_MODE_LABELS[this.slowModeIndex]).fontSize(14).fontColor(COLOR_PRIMARY);
              }.width('100%').height(48).padding({ left: 14, right: 14 })
              .onClick((): void => this.chooseSlowMode());
            }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);

            if (this.requests.length > 0) {
              Column() {
                Text(`入群申请 · ${this.requests.length}`).fontSize(12)
                  .fontColor(COLOR_TEXT_SECONDARY).width('100%')
                  .padding({ left: 14, top: 12, bottom: 4 });
                ForEach(this.requests, (row: JoinRequestRow) => {
                  Row({ space: 8 }) {
                    Text(this.nameOf(row.userId)).fontSize(15).fontColor(COLOR_TEXT_PRIMARY)
                      .layoutWeight(1).maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis });
                    Button('通过').height(32).fontSize(13)
                      .onClick((): void => this.handleRequest(row.userId, true));
                    Button('拒绝').height(32).fontSize(13)
                      .backgroundColor(COLOR_PAGE_BG).fontColor('#E5484D')
                      .onClick((): void => this.handleRequest(row.userId, false));
                  }.width('100%').height(52).padding({ left: 14, right: 12 });
                }, (row: JoinRequestRow): string => `req_${row.userId}`);
              }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
            }

            Column() {
              Text(`管理员 · ${this.admins.length}`).fontSize(12)
                .fontColor(COLOR_TEXT_SECONDARY).width('100%')
                .padding({ left: 14, top: 12, bottom: 4 });
              ForEach(this.admins, (row: AdminRow) => {
                Row({ space: 8 }) {
                  Column({ space: 2 }) {
                    Text(this.nameOf(row.userId)).fontSize(15).fontColor(COLOR_TEXT_PRIMARY)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                    Text(row.isCreator ? '创建者'
                      : (row.customTitle !== '' ? row.customTitle : '管理员'))
                      .fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start);
                  if (!row.isCreator) {
                    SymbolGlyph($r('sys.symbol.more')).fontSize(18)
                      .fontColor([COLOR_TEXT_SECONDARY]);
                  }
                }
                .width('100%').height(54).padding({ left: 14, right: 14 })
                .onClick((): void => {
                  if (!row.isCreator) { this.memberActions(row.userId, true); }
                });
              }, (row: AdminRow): string => `adm_${row.userId}`);
            }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);

            Column() {
              Row() {
                Text(`邀请链接 · ${this.links.length}`).fontSize(12)
                  .fontColor(COLOR_TEXT_SECONDARY).layoutWeight(1);
                Text('新建').fontSize(13).fontColor(COLOR_PRIMARY)
                  .onClick((): void => this.newInviteLink());
              }.width('100%').padding({ left: 14, right: 14, top: 12, bottom: 4 });
              ForEach(this.links, (row: InviteLinkRow) => {
                Row({ space: 8 }) {
                  Column({ space: 2 }) {
                    Text(row.name !== '' ? row.name : (row.isPrimary ? '主链接' : '邀请链接'))
                      .fontSize(14).fontColor(COLOR_TEXT_PRIMARY);
                    Text(row.link).fontSize(11).fontColor(COLOR_TEXT_SECONDARY)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start);
                  SymbolGlyph($r('sys.symbol.doc')).fontSize(16)
                    .fontColor([COLOR_PRIMARY])
                    .onClick((): void => {
                      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, row.link);
                      pasteboard.getSystemPasteboard().setData(data).then((): void => {
                        promptAction.showToast({ message: '已复制', duration: 1300 });
                      }).catch((): void => {});
                    });
                  if (!row.isPrimary) {
                    SymbolGlyph($r('sys.symbol.trash')).fontSize(16).fontColor(['#E5484D'])
                      .onClick((): void => {
                        revokeInviteLink(this.chatId, row.link).then((): void => {
                          promptAction.showToast({ message: '链接已撤销', duration: 1400 });
                          this.load();
                        }).catch((e: TdError): void => this.fail(e, '撤销失败'));
                      });
                  }
                }.width('100%').height(56).padding({ left: 14, right: 14 });
              }, (row: InviteLinkRow): string => `lnk_${row.link}`);
            }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);

            Row({ space: 10 }) {
              SymbolGlyph($r('sys.symbol.trash')).fontSize(17).fontColor(['#E5484D']);
              Text('删除今天的全部消息').fontSize(15).fontColor('#E5484D').layoutWeight(1);
            }
            .width('100%').height(48).padding({ left: 14, right: 14 })
            .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
            .onClick((): void => this.deleteTodayMessages());

            Text('所有操作都会由服务器校验权限；没有相应管理权限时会提示"权限不足"。')
              .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(18).width('100%');
          }.width('100%').padding({ left: 12, right: 12, bottom: this.bottomSafe + 24 });
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
      }
    }
    .width('100%').height('100%').backgroundColor(COLOR_PAGE_BG)
    .padding({ top: this.topSafe });
  }
}
