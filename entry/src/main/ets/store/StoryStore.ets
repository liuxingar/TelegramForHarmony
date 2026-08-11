import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';

export interface StoryRingEntry {
  chatId: number;
  order: number;
  storyIds: number[];       // 升序（发布时间序）
  maxReadStoryId: number;
  hasUnread: boolean;
}

type StoryListener = (entries: StoryRingEntry[]) => void;

// 聊天列表顶部故事环的数据源：主故事列表（storyListMain）的活跃故事集合。
// TDLib 通过 updateChatActiveStories 推送每个会话的故事快照，空列表即移除。
export class StoryStore {
  private client: TdClient;
  private entriesById: Map<number, StoryRingEntry> = new Map();
  private subs: StoryListener[] = [];
  private opened: boolean = false;

  constructor(client: TdClient) {
    this.client = client;
    client.onUpdate('updateChatActiveStories', (u: TdObject) => this.onActiveStories(u));
  }

  // 触发 TDLib 拉取主故事列表（结果全部经 update 回流）。
  open(): void {
    if (this.opened) {
      return;
    }
    this.opened = true;
    const req: TdRequest = { '@type': 'loadActiveStories' };
    req['story_list'] = { '@type': 'storyListMain' } as TdObject;
    this.client.send(req).catch((e: TdError): void => {
      // 404 = 列表已到底（无更多会话），是正常终止信号。
      if (e.code !== 404) {
        console.error(`StoryStore.loadActiveStories failed: ${e.message}`);
      }
    });
  }

  subscribe(l: StoryListener): () => void {
    this.subs = [...this.subs, l];
    l(this.entries());
    return (): void => {
      this.subs = this.subs.filter((x: StoryListener) => x !== l);
    };
  }

  entries(): StoryRingEntry[] {
    return Array.from(this.entriesById.values())
      .sort((a: StoryRingEntry, b: StoryRingEntry) => b.order - a.order);
  }

  entryOf(chatId: number): StoryRingEntry | undefined {
    return this.entriesById.get(chatId);
  }

  private onActiveStories(u: TdObject): void {
    const active = u['active_stories'] as TdObject | undefined;
    if (active === undefined) {
      return;
    }
    const chatId: number = (active['chat_id'] as number | undefined) ?? 0;
    if (chatId === 0) {
      return;
    }
    const list = active['list'] as TdObject | undefined;
    const listType: string = list !== undefined
      ? ((list['@type'] as string | undefined) ?? '') : '';
    const infos: TdObject[] = (active['stories'] as TdObject[] | undefined) ?? [];
    // 归档（被隐藏的联系人）不进主环；故事过期清空后同样移除。
    if (infos.length === 0 || listType === 'storyListArchive') {
      if (this.entriesById.delete(chatId)) {
        this.publish();
      }
      return;
    }
    const maxRead: number = (active['max_read_story_id'] as number | undefined) ?? 0;
    const storyIds: number[] = infos
      .map((info: TdObject): number => (info['story_id'] as number | undefined) ?? 0)
      .filter((id: number): boolean => id > 0)
      .sort((a: number, b: number) => a - b);
    this.entriesById.set(chatId, {
      chatId: chatId,
      order: (active['order'] as number | undefined) ?? 0,
      storyIds: storyIds,
      maxReadStoryId: maxRead,
      hasUnread: storyIds.some((id: number): boolean => id > maxRead)
    });
    this.publish();
  }

  private publish(): void {
    const snapshot = this.entries();
    for (const l of this.subs) {
      l(snapshot);
    }
  }
}
