import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { UserStore } from '../main/ets/store/UserStore';
import { buildMessageEntry, MessageEntry } from '../main/ets/store/MessageEntry';
import { collapseAlbums, AlbumGroup } from '../main/ets/util/collapseAlbums';
import { AlbumGroupDataSource } from '../main/ets/pages/chat/AlbumGroupDataSource';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}

function usersOf(): UserStore {
  const b = new FakeBridge(); const c = new TdClient(b); const u = new UserStore(c); c.start();
  const user: TdObject = { '@type': 'user' }; user['id'] = 7; user['first_name'] = 'Ann';
  const upd: TdObject = { '@type': 'updateUser' }; upd['user'] = user;
  b.onReceive(JSON.stringify(upd));
  return u;
}

function entry(id: number, date: number, users: UserStore): MessageEntry {
  const ft: TdObject = { '@type': 'formattedText' }; ft['text'] = `t${id}`;
  const c: TdObject = { '@type': 'messageText' }; c['text'] = ft;
  const sender: TdObject = { '@type': 'messageSenderUser' }; sender['user_id'] = 7;
  const m: TdObject = { '@type': 'message' };
  m['id'] = id; m['is_outgoing'] = false; m['sender_id'] = sender;
  m['date'] = date; m['content'] = c;
  return buildMessageEntry(m, users);
}

function groupsOf(idsAndDates: number[][], users: UserStore): AlbumGroup[] {
  const entries: MessageEntry[] = [];
  for (const pair of idsAndDates) {
    entries.push(entry(pair[0], pair[1], users));
  }
  return collapseAlbums(entries);
}

export default function albumGroupDataSourceTest() {
  describe('AlbumGroupDataSource', () => {
    it('identical_update_reports_none', 0, () => {
      const users = usersOf();
      const ds = new AlbumGroupDataSource();
      const groups = groupsOf([[10, 100], [20, 5000]], users);
      ds.update(groups);
      expect(ds.update(groupsOf([[10, 100], [20, 5000]], users))).assertEqual('none');
    });
    it('older_page_prepend_reports_incremental', 0, () => {
      const users = usersOf();
      const ds = new AlbumGroupDataSource();
      // Dates far apart so each message is its own visual run and a prepend
      // still mutates the old first row's key (date pill/run flags), the
      // normal mixed CHANGE+ADD page case.
      ds.update(groupsOf([[30, 90000], [40, 180000]], users));
      const next = groupsOf([[10, 100], [20, 5000], [30, 90000], [40, 180000]], users);
      expect(ds.update(next)).assertEqual('incremental');
    });
    it('window_replacement_reports_reload', 0, () => {
      const users = usersOf();
      const ds = new AlbumGroupDataSource();
      ds.update(groupsOf([[10, 100], [20, 5000], [30, 90000], [40, 180000]], users));
      // A loadAround jump replaces the window with unrelated rows (different
      // row count, no shared prefix/suffix) — the only case that reloads.
      expect(ds.update(groupsOf([[50, 100], [60, 5000], [70, 90000]], users)))
        .assertEqual('reload');
    });
  });
}
