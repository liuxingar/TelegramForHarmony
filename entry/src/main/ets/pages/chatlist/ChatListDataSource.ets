import { ChatEntry } from '../../store/ChatEntry';
import { keyTableReload, newKeyTableId } from '../../util/keyGuard';

// LazyForEach data source for the chat list.
//
// The list was a plain ForEach, and ForEach builds every child up front: a
// device log showed `Ids.size[424]`, i.e. 424 ChatRow components alive for a
// list that shows about eight. That is paid on the list's first layout, again
// in memory for as long as the screen exists, and again on every update that
// marks the ForEach dirty.
//
// The diff mirrors AlbumGroupDataSource: compare keys, notify only the rows
// that actually differ. Chat lists reorder constantly (a new message moves a
// chat to the top), so a blanket reload on every update would rebuild the
// visible rows several times a second.
export class ChatListDataSource implements IDataSource {
  private items: ChatEntry[] = [];
  private keys: string[] = [];
  private listeners: DataChangeListener[] = [];
  // Diagnostic only: one key table per instance, since each list body has its
  // own LazyForEach. See AlbumGroupDataSource.keyTableId.
  readonly keyTableId: string = newKeyTableId('chatlist');

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): ChatEntry {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((l: DataChangeListener) => l !== listener);
  }

  // See AlbumGroupDataSource.reload: the row key embeds the language epoch, so
  // a bump renames every row without the data changing at all.
  reload(): void {
    this.notify([{ type: DataOperationType.RELOAD } as DataReloadOperation]);
  }

  // `keys` is supplied by the caller because the row key depends on state the
  // data source has no business knowing — which list it is (pinning is
  // per-list) and the language epoch.
  update(next: ChatEntry[], nextKeys: string[]): void {
    // One snapshot, so a hit is a genuine data-level duplicate.
    const seen: Map<string, number> = new Map();
    for (let i = 0; i < nextKeys.length; i++) {
      const at = seen.get(nextKeys[i]);
      if (at !== undefined) {
        console.error(`[CL] duplicate row key in snapshot at ${i} and ${at} -> ${nextKeys[i]}`);
      } else {
        seen.set(nextKeys[i], i);
      }
    }
    const prevKeys = this.keys;
    const prevIds = this.items.map((item: ChatEntry): number => item.id);
    this.items = next;
    this.keys = nextKeys;

    if (prevKeys.length !== nextKeys.length) {
      this.notify([{ type: DataOperationType.RELOAD } as DataReloadOperation]);
      return;
    }
    // CHANGE means "the item at this index is the same one, with new content".
    // A chat list reorders constantly — any new message pulls its chat to the
    // top — and after a reorder every index holds a DIFFERENT chat. Reporting
    // that as CHANGE tells the list the identity is unchanged while the row's
    // key is one already registered at another index, which is the "Use repeat
    // key" warning and rows rendering the wrong chat.
    for (let i = 0; i < next.length; i++) {
      if (prevIds[i] !== next[i].id) {
        this.notify([{ type: DataOperationType.RELOAD } as DataReloadOperation]);
        return;
      }
    }
    const ops: DataOperation[] = [];
    for (let i = 0; i < nextKeys.length; i++) {
      if (prevKeys[i] !== nextKeys[i]) {
        ops.push({ type: DataOperationType.CHANGE, index: i } as DataChangeOperation);
      }
    }
    if (ops.length === 0) {
      return;
    }
    this.notify(ops);
  }

  private notify(ops: DataOperation[]): void {
    console.info(`[CL] ops=${ops.map((o: DataOperation): string => `${o.type}`).join(',')}`);
    // This list only ever emits RELOAD or CHANGE; CHANGE keeps the row's
    // identity, so only RELOAD invalidates the diagnostic key table.
    for (const op of ops) {
      if (op.type === DataOperationType.RELOAD) {
        keyTableReload(this.keyTableId);
      }
    }
    for (const l of this.listeners) {
      l.onDatasetChange(ops);
    }
  }
}
