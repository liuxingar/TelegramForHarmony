import { router, promptAction } from '@kit.ArkUI';
import { getTdClient } from '../../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { formatPreview } from '../../util/formatPreview';
import {
  COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';

const CARD_RADIUS: number = 14;
// forumTopicIcon.color 的取值集合（TDLib 固定的六色）。
const TOPIC_COLORS: Map<number, string> = new Map([
  [0x6FB9F0, '#6FB9F0'], [0xFFD67E, '#FFD67E'], [0xCB86DB, '#CB86DB'],
  [0x8EEE98, '#8EEE98'], [0xFF93B2, '#FF93B2'], [0xFB6F5F, '#FB6F5F']
]);

interface TopicRow {
  threadId: number;
  name: string;
  iconColor: string;
  isGeneral: boolean;
  isClosed: boolean;
  unreadCount: number;
  lastMessageText: string;
}

// 话题群（forum）的话题列表页。点话题 → ChatPage(threadRootId)。
@Entry
@Component
struct ForumTopicsPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State title: string = '话题';
  @State rows: TopicRow[] = [];
  @State loadState: string = 'loading'; // loading | ready | error
  @State creating: boolean = false;
  private chatId: number = 0;
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    const params = router.getParams() as Record<string, Object> | undefined;
    this.chatId = params !== undefined ? ((params['chatId'] as number | undefined) ?? 0) : 0;
    const title = params !== undefined ? ((params['title'] as string | undefined) ?? '') : '';
    if (title !== '') {
      this.title = title;
    }
    this.load();
  }

  aboutToDisappear(): void {
    this.active = false;
  }

  onPageShow(): void {
    // 从话题内返回时刷新未读数/最后消息。
    if (this.loadState === 'ready') {
      this.load();
    }
  }

  private load(): void {
    if (this.chatId === 0) {
      this.loadState = 'error';
      return;
    }
    const req: TdRequest = { '@type': 'getForumTopics' };
    req['chat_id'] = this.chatId;
    req['query'] = '';
    req['offset_date'] = 0;
    req['offset_message_id'] = 0;
    req['offset_forum_topic_id'] = 0;
    req['limit'] = 100;
    getTdClient().send(req).then((res: TdObject): void => {
      if (!this.active) {
        return;
      }
      const topics: TdObject[] = (res['topics'] as TdObject[] | undefined) ?? [];
      this.rows = topics.map((topic: TdObject): TopicRow => this.parseTopic(topic))
        .filter((row: TopicRow): boolean => row.threadId > 0);
      this.loadState = 'ready';
    }).catch((e: TdError): void => {
      if (!this.active) {
        return;
      }
      console.error(`ForumTopicsPage.getForumTopics failed: ${e.message}`);
      this.loadState = 'error';
    });
  }

  private parseTopic(topic: TdObject): TopicRow {
    const info = topic['info'] as TdObject | undefined;
    const threadId: number = info !== undefined
      ? ((info['forum_topic_id'] as number | undefined) ?? 0) : 0;
    const name: string = info !== undefined
      ? ((info['name'] as string | undefined) ?? '') : '';
    const icon = info !== undefined ? info['icon'] as TdObject | undefined : undefined;
    const colorValue: number = icon !== undefined
      ? ((icon['color'] as number | undefined) ?? 0) : 0;
    const lastMessage = topic['last_message'] as TdObject | undefined;
    return {
      threadId: threadId,
      name: name !== '' ? name : '话题',
      iconColor: TOPIC_COLORS.get(colorValue) ?? '#6FB9F0',
      isGeneral: info !== undefined
        ? ((info['is_general'] as boolean | undefined) ?? false) : false,
      isClosed: info !== undefined
        ? ((info['is_closed'] as boolean | undefined) ?? false) : false,
      unreadCount: (topic['unread_count'] as number | undefined) ?? 0,
      lastMessageText: formatPreview(lastMessage ?? null)
    };
  }

  private openTopic(row: TopicRow): void {
    const params: Record<string, Object> = {
      'chatId': this.chatId,
      'forumTopicId': row.threadId,
      'topicName': row.name
    };
    router.pushUrl({ url: 'pages/chat/ChatPage', params }).catch((error: Error): void => {
      console.error(`ForumTopicsPage.openTopic failed: ${error.message}`);
    });
  }

  private createTopic(name: string): void {
    if (this.creating || name.trim() === '') {
      return;
    }
    this.creating = true;
    const req: TdRequest = { '@type': 'createForumTopic' };
    req['chat_id'] = this.chatId;
    req['name'] = name.trim();
    getTdClient().send(req).then((info: TdObject): void => {
      this.creating = false;
      const threadId: number = (info['forum_topic_id'] as number | undefined) ?? 0;
      if (threadId > 0) {
        this.load();
        this.openTopic({
          threadId: threadId, name: name.trim(), iconColor: '#6FB9F0',
          isGeneral: false, isClosed: false, unreadCount: 0, lastMessageText: ''
        });
      }
    }).catch((e: TdError): void => {
      this.creating = false;
      console.error(`ForumTopicsPage.createForumTopic failed: ${e.message}`);
      promptAction.showToast({ message: '创建话题失败（需要管理话题权限）', duration: 2000 });
    });
  }

  @State showNameInput: boolean = false;
  @State pendingTopicName: string = '';

  @Builder
  topicRowView(row: TopicRow) {
    Row({ space: 12 }) {
      Row() {
        Text(row.isGeneral ? '#' : row.name.substring(0, 1).toUpperCase())
          .fontSize(17).fontWeight(FontWeight.Bold).fontColor(Color.White);
      }
      .width(44).height(44).borderRadius(12)
      .backgroundColor(row.iconColor)
      .justifyContent(FlexAlign.Center);
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text(row.name).fontSize(16).fontWeight(FontWeight.Medium)
            .fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1);
          if (row.isClosed) {
            SymbolGlyph($r('sys.symbol.lock_fill')).fontSize(13).fontColor([COLOR_TEXT_SECONDARY]);
          }
        }
        .width('100%');
        Text(row.lastMessageText !== '' ? row.lastMessageText : '暂无消息')
          .fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%');
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1);
      if (row.unreadCount > 0) {
        Text(row.unreadCount > 99 ? '99+' : `${row.unreadCount}`)
          .fontSize(12).fontColor(Color.White)
          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
          .borderRadius(10).backgroundColor(COLOR_PRIMARY);
      }
    }
    .width('100%').padding({ left: 14, right: 12, top: 10, bottom: 10 })
    .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
    .onClick((): void => this.openTopic(row));
  }

  build() {
    Column() {
      Row({ space: 6 }) {
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(25).fontColor([COLOR_TEXT_PRIMARY]);
        }
        .width(44).height(44).borderRadius(22).justifyContent(FlexAlign.Center)
        .onClick((): void => router.back());
        Column({ space: 1 }) {
          Text(this.title).fontSize(19).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
          Text(`${this.rows.length} 个话题`).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
        }
        .alignItems(HorizontalAlign.Start).layoutWeight(1);
        Row() {
          SymbolGlyph($r('sys.symbol.plus')).fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
        }
        .width(44).height(44).borderRadius(22).justifyContent(FlexAlign.Center)
        .onClick((): void => {
          this.showNameInput = true;
        });
      }
      .width('100%').padding({ left: 8, right: 8, top: this.topSafe + 6, bottom: 6 });
      if (this.loadState === 'loading') {
        Column() {
          LoadingProgress().width(34).height(34);
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center);
      } else if (this.loadState === 'error') {
        Column({ space: 10 }) {
          Text('话题加载失败').fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
          Button('重试').onClick((): void => {
            this.loadState = 'loading';
            this.load();
          });
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center);
      } else {
        List({ space: 8 }) {
          ForEach(this.rows, (row: TopicRow) => {
            ListItem() {
              this.topicRowView(row);
            }
          }, (row: TopicRow): string =>
            `topic_${row.threadId}_${row.unreadCount}_${row.lastMessageText}`);
        }
        .width('100%').layoutWeight(1)
        .padding({ left: 12, right: 12, bottom: this.bottomSafe + 12 });
      }
      if (this.showNameInput) {
        Column({ space: 10 }) {
          Text('新建话题').fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
          TextInput({ placeholder: '话题名称', text: this.pendingTopicName })
            .fontSize(15).height(42)
            .onChange((value: string): void => {
              this.pendingTopicName = value;
            });
          Row({ space: 12 }) {
            Button('取消').buttonStyle(ButtonStyleMode.NORMAL).layoutWeight(1)
              .onClick((): void => {
                this.showNameInput = false;
                this.pendingTopicName = '';
              });
            Button(this.creating ? '创建中…' : '创建')
              .backgroundColor(COLOR_PRIMARY).layoutWeight(1)
              .enabled(!this.creating && this.pendingTopicName.trim() !== '')
              .onClick((): void => {
                const name: string = this.pendingTopicName;
                this.showNameInput = false;
                this.pendingTopicName = '';
                this.createTopic(name);
              });
          }
          .width('100%');
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: this.bottomSafe + 16 })
        .backgroundColor(COLOR_SURFACE)
        .borderRadius({ topLeft: 16, topRight: 16 });
      }
    }
    .width('100%').height('100%').backgroundColor(COLOR_PAGE_BG);
  }
}
