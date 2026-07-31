import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { UserStore } from '../main/ets/store/UserStore';
import { MessageStore } from '../main/ets/store/MessageStore';
import { MessageEntry } from '../main/ets/store/MessageEntry';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}
function setup(chatId: number, historyPageSize: number = 30): Array<Object> {
  const b = new FakeBridge(); const c = new TdClient(b); const u = new UserStore(c);
  const store = new MessageStore(c, u, chatId, 0, historyPageSize); c.start();
  return [b, store];
}
function textMessage(id: number, chatId: number, outgoing: boolean, text: string): TdObject {
  const ft: TdObject = { '@type': 'formattedText' }; ft['text'] = text;
  const content: TdObject = { '@type': 'messageText' }; content['text'] = ft;
  const m: TdObject = { '@type': 'message' };
  m['id'] = id; m['chat_id'] = chatId; m['is_outgoing'] = outgoing; m['date'] = 100; m['content'] = content;
  return m;
}
function keyboardMessage(id: number, chatId: number, label: string): TdObject {
  const m = textMessage(id, chatId, false, 'choose');
  const button: TdObject = { '@type': 'keyboardButton' };
  button['text'] = label;
  button['type'] = { '@type': 'keyboardButtonTypeText' } as TdObject;
  const markup: TdObject = { '@type': 'replyMarkupShowKeyboard' };
  markup['rows'] = [[button]];
  markup['is_persistent'] = true;
  m['reply_markup'] = markup;
  return m;
}
function videoMessage(id: number, chatId: number, fileId: number, thumbId: number): TdObject {
  const source: TdObject = { '@type': 'file' };
  source['id'] = fileId;
  source['size'] = 1000;
  const thumbFile: TdObject = { '@type': 'file' };
  thumbFile['id'] = thumbId;
  const thumb: TdObject = { '@type': 'thumbnail' };
  thumb['file'] = thumbFile;
  thumb['width'] = 320;
  thumb['height'] = 180;
  const video: TdObject = { '@type': 'video' };
  video['video'] = source;
  video['thumbnail'] = thumb;
  video['width'] = 320;
  video['height'] = 180;
  const content: TdObject = { '@type': 'messageVideo' };
  content['video'] = video;
  const m: TdObject = { '@type': 'message' };
  m['id'] = id;
  m['chat_id'] = chatId;
  m['is_outgoing'] = false;
  m['date'] = 100;
  m['content'] = content;
  return m;
}
function animationMessage(id: number, chatId: number, fileId: number, thumbId: number): TdObject {
  const source: TdObject = { '@type': 'file' };
  source['id'] = fileId;
  source['size'] = 1000;
  const thumbFile: TdObject = { '@type': 'file' };
  thumbFile['id'] = thumbId;
  const thumb: TdObject = { '@type': 'thumbnail' };
  thumb['file'] = thumbFile;
  thumb['width'] = 320;
  thumb['height'] = 180;
  const animation: TdObject = { '@type': 'animation' };
  animation['animation'] = source;
  animation['thumbnail'] = thumb;
  animation['width'] = 320;
  animation['height'] = 180;
  const content: TdObject = { '@type': 'messageAnimation' };
  content['animation'] = animation;
  const message: TdObject = { '@type': 'message' };
  message['id'] = id;
  message['chat_id'] = chatId;
  message['is_outgoing'] = false;
  message['date'] = 100;
  message['content'] = content;
  return message;
}
function voiceMessage(id: number, chatId: number, fileId: number, listened: boolean): TdObject {
  const source: TdObject = { '@type': 'file' };
  source['id'] = fileId;
  source['size'] = 1000;
  const voice: TdObject = { '@type': 'voiceNote' };
  voice['voice'] = source;
  voice['duration'] = 8;
  voice['mime_type'] = 'audio/ogg';
  voice['waveform'] = '//8=';
  const content: TdObject = { '@type': 'messageVoiceNote' };
  content['voice_note'] = voice;
  content['is_listened'] = listened;
  const message: TdObject = { '@type': 'message' };
  message['id'] = id;
  message['chat_id'] = chatId;
  message['is_outgoing'] = false;
  message['date'] = 100;
  message['content'] = content;
  return message;
}
function audioMessage(id: number, chatId: number, fileId: number, coverId: number): TdObject {
  const source: TdObject = { '@type': 'file' };
  source['id'] = fileId;
  source['size'] = 1000;
  const coverSource: TdObject = { '@type': 'file' };
  coverSource['id'] = coverId;
  const cover: TdObject = { '@type': 'thumbnail' };
  cover['file'] = coverSource;
  cover['width'] = 200;
  cover['height'] = 200;
  const audio: TdObject = { '@type': 'audio' };
  audio['audio'] = source;
  audio['album_cover_thumbnail'] = cover;
  audio['duration'] = 180;
  audio['title'] = 'Track';
  audio['performer'] = 'Artist';
  audio['file_name'] = 'track.mp3';
  audio['mime_type'] = 'audio/mpeg';
  const content: TdObject = { '@type': 'messageAudio' };
  content['audio'] = audio;
  const message: TdObject = { '@type': 'message' };
  message['id'] = id;
  message['chat_id'] = chatId;
  message['is_outgoing'] = false;
  message['date'] = 100;
  message['content'] = content;
  return message;
}
function documentMessage(
  id: number,
  chatId: number,
  fileId: number,
  localPath: string = ''
): TdObject {
  const source: TdObject = { '@type': 'file' };
  source['id'] = fileId;
  source['size'] = 1000;
  const local: TdObject = { '@type': 'localFile' };
  local['is_downloading_completed'] = localPath !== '';
  local['is_downloading_active'] = false;
  local['path'] = localPath;
  local['downloaded_size'] = localPath !== '' ? 1000 : 0;
  source['local'] = local;
  const document: TdObject = { '@type': 'document' };
  document['document'] = source;
  document['file_name'] = 'guide.pdf';
  document['mime_type'] = 'application/pdf';
  const content: TdObject = { '@type': 'messageDocument' };
  content['document'] = document;
  const message: TdObject = { '@type': 'message' };
  message['id'] = id;
  message['chat_id'] = chatId;
  message['is_outgoing'] = false;
  message['date'] = 100;
  message['content'] = content;
  return message;
}
function pollObject(chosenOption: number = -1, total: number = 0): TdObject {
  const question: TdObject = { '@type': 'formattedText' };
  question['text'] = '今天喝什么';
  const tea: TdObject = { '@type': 'pollOption' };
  tea['text'] = { '@type': 'formattedText', 'text': '茶' } as TdObject;
  tea['voter_count'] = chosenOption === 0 ? total : 0;
  tea['vote_percentage'] = chosenOption === 0 ? 100 : 0;
  tea['is_chosen'] = chosenOption === 0;
  tea['is_being_chosen'] = false;
  const coffee: TdObject = { '@type': 'pollOption' };
  coffee['text'] = { '@type': 'formattedText', 'text': '咖啡' } as TdObject;
  coffee['voter_count'] = chosenOption === 1 ? total : 0;
  coffee['vote_percentage'] = chosenOption === 1 ? 100 : 0;
  coffee['is_chosen'] = chosenOption === 1;
  coffee['is_being_chosen'] = false;
  const type: TdObject = { '@type': 'pollTypeRegular' };
  type['allow_multiple_answers'] = false;
  const poll: TdObject = { '@type': 'poll' };
  poll['id'] = 'poll-store-1';
  poll['question'] = question;
  poll['options'] = [tea, coffee];
  poll['total_voter_count'] = total;
  poll['is_anonymous'] = true;
  poll['type'] = type;
  poll['is_closed'] = false;
  return poll;
}
function pollMessage(id: number, chatId: number): TdObject {
  const content: TdObject = { '@type': 'messagePoll' };
  content['poll'] = pollObject();
  const message: TdObject = { '@type': 'message' };
  message['id'] = id;
  message['chat_id'] = chatId;
  message['is_outgoing'] = false;
  message['date'] = 100;
  message['content'] = content;
  return message;
}
function pushNewMessage(b: FakeBridge, m: TdObject): void {
  const u: TdObject = { '@type': 'updateNewMessage' }; u['message'] = m;
  b.onReceive(JSON.stringify(u));
}
function extraOf(json: string): string {
  const o = JSON.parse(json) as TdObject; return (o['@extra'] as string | undefined) ?? '';
}
function feedChat(b: FakeBridge, chatId: number): void {
  // find the getChat request and answer it with a minimal chat (no unread
  // anchor), so startInitialLoad() takes the plain loadHistory(0) path.
  let extra = '';
  for (const s of b.sent) {
    const o = JSON.parse(s) as TdObject;
    if (o['@type'] === 'getChat') { extra = extraOf(s); }
  }
  const chat: TdObject = { '@type': 'chat' };
  chat['id'] = chatId;
  chat['@extra'] = extra;
  b.onReceive(JSON.stringify(chat));
}
function feedHistory(b: FakeBridge, msgs: TdObject[]): void {
  // find the getChatHistory request and answer it with a `messages` response
  let extra = '';
  for (const s of b.sent) {
    const o = JSON.parse(s) as TdObject;
    if (o['@type'] === 'getChatHistory') { extra = extraOf(s); }
  }
  const res: TdObject = { '@type': 'messages' }; res['total_count'] = msgs.length; res['messages'] = msgs; res['@extra'] = extra;
  b.onReceive(JSON.stringify(res));
}
function requestCount(b: FakeBridge, type: string): number {
  return b.sent.filter((json: string): boolean =>
    (JSON.parse(json) as TdObject)['@type'] === type).length;
}
function feedRequestError(b: FakeBridge, type: string, code: number, message: string): void {
  let extra = '';
  for (const json of b.sent) {
    const request = JSON.parse(json) as TdObject;
    if (request['@type'] === type) {
      extra = extraOf(json);
    }
  }
  const error: TdObject = { '@type': 'error' };
  error['code'] = code;
  error['message'] = message;
  error['@extra'] = extra;
  b.onReceive(JSON.stringify(error));
}
function ids(list: MessageEntry[]): number[] { return list.map((m: MessageEntry) => m.id); }

export default function messageStoreTest() {
  describe('MessageStore', () => {
    it('open_sends_openchat_and_history', 0, async () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      feedChat(b, 5); // history is deferred until getChat resolves (unread anchor)
      // onChat() runs in a .then() microtask, not synchronously after feedChat.
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      const types = b.sent.map((s: string) => (JSON.parse(s) as TdObject)['@type']);
      expect(types.includes('openChat')).assertTrue();
      expect(types.includes('getChatHistory')).assertTrue();
    });
    it('history_loads_ascending', 0, async () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      expect(store.getInitialHistoryState()).assertEqual('loading');
      feedChat(b, 5);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      feedHistory(b, [textMessage(30, 5, false, 'c'), textMessage(20, 5, false, 'b'), textMessage(10, 5, false, 'a')]);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      expect(ids(store.getMessages()).join(',')).assertEqual('10,20,30');
      expect(store.getInitialHistoryState()).assertEqual('ready');
    });
    it('empty_history_is_ready_and_stops_older_paging', 0, async () => {
      const arr = setup(5, 2); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      feedChat(b, 5);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      feedRequestError(b, 'getChatHistory', 404, 'Not Found');
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      expect(store.getInitialHistoryState()).assertEqual('ready');
      expect(store.getInitialHistoryError()).assertEqual('');
      expect(store.getMessages().length).assertEqual(0);
      expect(store.getHasMoreOlder()).assertFalse();
      expect(store.getOlderLoadState()).assertEqual('end');
    });
    it('initial_history_error_can_retry_without_false_empty_state', 0, async () => {
      const arr = setup(5, 2); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      feedChat(b, 5);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      feedRequestError(b, 'getChatHistory', -1, 'request timeout');
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      expect(store.getInitialHistoryState()).assertEqual('error');
      expect(store.getInitialHistoryError()).assertEqual('连接超时，请检查网络后重试');
      const before = requestCount(b, 'getChatHistory');
      store.retryInitialHistory();
      expect(store.getInitialHistoryState()).assertEqual('loading');
      expect(requestCount(b, 'getChatHistory')).assertEqual(before + 1);
      feedHistory(b, []);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      expect(store.getInitialHistoryState()).assertEqual('ready');
      expect(store.getInitialHistoryError()).assertEqual('');
    });
    it('older_page_error_retries_and_404_marks_history_end', 0, async () => {
      const arr = setup(5, 2); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      feedChat(b, 5);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      feedHistory(b, [
        textMessage(20, 5, false, 'b'),
        textMessage(10, 5, false, 'a')
      ]);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      expect(store.getHasMoreOlder()).assertTrue();
      expect(store.loadOlder()).assertTrue();
      feedRequestError(b, 'getChatHistory', 500, 'server error');
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      expect(store.getOlderLoadState()).assertEqual('error');
      expect(store.loadOlder()).assertFalse();
      const beforeRetry = requestCount(b, 'getChatHistory');
      store.retryOlder();
      expect(requestCount(b, 'getChatHistory')).assertEqual(beforeRetry + 1);
      feedRequestError(b, 'getChatHistory', 404, 'Not Found');
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      expect(store.getOlderLoadState()).assertEqual('end');
      expect(store.getHasMoreOlder()).assertFalse();
      const atEnd = requestCount(b, 'getChatHistory');
      expect(store.loadOlder()).assertFalse();
      expect(requestCount(b, 'getChatHistory')).assertEqual(atEnd);
    });
    it('new_message_appends', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, textMessage(40, 5, false, 'new'));
      expect(ids(store.getMessages()).join(',')).assertEqual('40');
    });
    it('new_message_other_chat_ignored', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, textMessage(41, 99, false, 'other'));
      expect(store.getMessages().length).assertEqual(0);
    });
    it('keyboard_probe_recovers_markup_beyond_visible_history', 0, async () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      let label = '';
      store.subscribeReplyKeyboard((kb) => {
        label = kb !== null && kb.rows.length > 0 && kb.rows[0].length > 0
          ? kb.rows[0][0].text : '';
      });
      store.open();
      feedChat(b, 5);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      // The visible latest page has no keyboard marker, so MessageStore starts
      // an independent tail probe rather than depending on rendered history.
      feedHistory(b, []);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      feedHistory(b, [keyboardMessage(10, 5, '快捷操作')]);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      expect(label).assertEqual('快捷操作');
    });
    it('send_succeeded_swaps_id', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, textMessage(1001, 5, true, 'hi')); // optimistic (temp id 1001, pending)
      const newMsg = textMessage(2002, 5, true, 'hi');
      const u: TdObject = { '@type': 'updateMessageSendSucceeded' }; u['message'] = newMsg; u['old_message_id'] = 1001;
      b.onReceive(JSON.stringify(u));
      expect(ids(store.getMessages()).join(',')).assertEqual('2002');
      expect(store.getMessages()[0].sendState).assertEqual('sent');
    });
    it('read_outbox_marks_read', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, textMessage(50, 5, true, 'x')); // outgoing, sent
      const u: TdObject = { '@type': 'updateChatReadOutbox' }; u['chat_id'] = 5; u['last_read_outbox_message_id'] = 50;
      b.onReceive(JSON.stringify(u));
      expect(store.getMessages()[0].sendState).assertEqual('read');
    });
    it('edited_update_refreshes_edit_marker', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, textMessage(51, 5, true, 'x'));
      const u: TdObject = { '@type': 'updateMessageEdited' };
      u['chat_id'] = 5;
      u['message_id'] = 51;
      u['edit_date'] = 345;
      b.onReceive(JSON.stringify(u));
      expect(store.getMessages()[0].editDate).assertEqual(345);
    });
    it('delete_removes', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, textMessage(60, 5, false, 'y'));
      const u: TdObject = { '@type': 'updateDeleteMessages' }; u['chat_id'] = 5; u['message_ids'] = [60]; u['is_permanent'] = true;
      b.onReceive(JSON.stringify(u));
      expect(store.getMessages().length).assertEqual(0);
    });
    it('shared_video_file_updates_all_bubbles', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, videoMessage(80, 5, 900, 901));
      pushNewMessage(b, videoMessage(81, 5, 900, 902));
      store.requestVideoDownload(80);
      const local: TdObject = { '@type': 'localFile' };
      local['is_downloading_completed'] = true;
      local['path'] = '/data/video.mp4';
      local['downloaded_size'] = 1000;
      const file: TdObject = { '@type': 'file' };
      file['id'] = 900;
      file['size'] = 1000;
      file['local'] = local;
      const update: TdObject = { '@type': 'updateFile' };
      update['file'] = file;
      b.onReceive(JSON.stringify(update));
      expect(store.getMessages()[0].videoPath).assertEqual('/data/video.mp4');
      expect(store.getMessages()[1].videoPath).assertEqual('/data/video.mp4');
      expect(store.getMessages()[0].videoProgress).assertEqual(100);
      expect(store.getMessages()[1].videoProgress).assertEqual(100);
    });
    it('new_animation_prefetches_loop_source_when_autoplay_is_enabled', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, animationMessage(82, 5, 920, 921));
      const sourceRequested = b.sent.some((json: string): boolean => {
        const request = JSON.parse(json) as TdObject;
        return request['@type'] === 'downloadFile' && request['file_id'] === 920;
      });
      expect(store.getMessages()[0].isAnimation).assertTrue();
      expect(sourceRequested).assertTrue();
    });
    it('voice_listened_update_preserves_downloaded_file', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, voiceMessage(83, 5, 930, false));
      const local: TdObject = { '@type': 'localFile' };
      local['is_downloading_completed'] = true;
      local['path'] = '/data/voice.ogg';
      local['downloaded_size'] = 1000;
      const file: TdObject = { '@type': 'file' };
      file['id'] = 930;
      file['size'] = 1000;
      file['local'] = local;
      const fileUpdate: TdObject = { '@type': 'updateFile' };
      fileUpdate['file'] = file;
      b.onReceive(JSON.stringify(fileUpdate));
      expect(store.getMessages()[0].videoPath).assertEqual('/data/voice.ogg');

      store.markVoiceListened(83);
      expect(store.getMessages()[0].voiceListened).assertTrue();
      const opened: boolean = b.sent.some((json: string): boolean => {
        const request = JSON.parse(json) as TdObject;
        return request['@type'] === 'openMessageContent' && request['message_id'] === 83;
      });
      expect(opened).assertTrue();

      const updated: TdObject = voiceMessage(83, 5, 930, true)['content'] as TdObject;
      const contentUpdate: TdObject = { '@type': 'updateMessageContent' };
      contentUpdate['chat_id'] = 5;
      contentUpdate['message_id'] = 83;
      contentUpdate['new_content'] = updated;
      b.onReceive(JSON.stringify(contentUpdate));
      expect(store.getMessages()[0].voiceListened).assertTrue();
      expect(store.getMessages()[0].videoPath).assertEqual('/data/voice.ogg');
      expect(store.getMessages()[0].videoProgress).assertEqual(100);
    });
    it('audio_prefetches_cover_and_downloads_source_on_demand', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, audioMessage(84, 5, 940, 941));
      expect(store.getMessages()[0].contentType).assertEqual('audio');
      expect(store.getMessages()[0].audioTitle).assertEqual('Track');
      expect(store.getMessages()[0].audioPerformer).assertEqual('Artist');
      const coverRequested: boolean = b.sent.some((json: string): boolean => {
        const request = JSON.parse(json) as TdObject;
        return request['@type'] === 'downloadFile' && request['file_id'] === 941;
      });
      const sourceRequestedBeforeTap: boolean = b.sent.some((json: string): boolean => {
        const request = JSON.parse(json) as TdObject;
        return request['@type'] === 'downloadFile' && request['file_id'] === 940;
      });
      expect(coverRequested).assertTrue();
      expect(sourceRequestedBeforeTap).assertFalse();

      store.requestVideoDownload(84);
      expect(store.getMessages()[0].mediaDownloadActive).assertTrue();
      const sourceRequestedAfterTap: boolean = b.sent.some((json: string): boolean => {
        const request = JSON.parse(json) as TdObject;
        return request['@type'] === 'downloadFile' && request['file_id'] === 940;
      });
      expect(sourceRequestedAfterTap).assertTrue();

      const progressLocal: TdObject = { '@type': 'localFile' };
      progressLocal['is_downloading_completed'] = false;
      progressLocal['is_downloading_active'] = true;
      progressLocal['downloaded_size'] = 400;
      const progressFile: TdObject = { '@type': 'file' };
      progressFile['id'] = 940;
      progressFile['size'] = 1000;
      progressFile['local'] = progressLocal;
      const progressUpdate: TdObject = { '@type': 'updateFile' };
      progressUpdate['file'] = progressFile;
      b.onReceive(JSON.stringify(progressUpdate));
      expect(store.getMessages()[0].videoProgress).assertEqual(40);
      expect(store.getMessages()[0].mediaDownloadActive).assertTrue();

      const completedLocal: TdObject = { '@type': 'localFile' };
      completedLocal['is_downloading_completed'] = true;
      completedLocal['path'] = '/data/track.mp3';
      completedLocal['downloaded_size'] = 1000;
      const completedFile: TdObject = { '@type': 'file' };
      completedFile['id'] = 940;
      completedFile['size'] = 1000;
      completedFile['local'] = completedLocal;
      const completedUpdate: TdObject = { '@type': 'updateFile' };
      completedUpdate['file'] = completedFile;
      b.onReceive(JSON.stringify(completedUpdate));
      expect(store.getMessages()[0].videoPath).assertEqual('/data/track.mp3');
      expect(store.getMessages()[0].videoProgress).assertEqual(100);
      expect(store.getMessages()[0].mediaDownloadActive).assertFalse();
    });
    it('document_hydrates_cached_file_and_remote_file_stays_on_demand', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, documentMessage(85, 5, 950, '/data/guide.pdf'));
      const cached: MessageEntry = store.getMessages()[0];
      expect(cached.contentType).assertEqual('file');
      expect(cached.videoFileName).assertEqual('guide.pdf');
      expect(cached.videoMimeType).assertEqual('application/pdf');
      expect(cached.videoPath).assertEqual('/data/guide.pdf');
      expect(cached.videoProgress).assertEqual(100);

      pushNewMessage(b, documentMessage(86, 5, 951));
      const downloadedBeforeTap: boolean = b.sent.some((json: string): boolean => {
        const request = JSON.parse(json) as TdObject;
        return (request['@type'] === 'downloadFile' ||
          request['@type'] === 'addFileToDownloads') && request['file_id'] === 951;
      });
      expect(downloadedBeforeTap).assertFalse();
      store.requestVideoDownload(86, true);
      const registeredAfterTap: boolean = b.sent.some((json: string): boolean => {
        const request = JSON.parse(json) as TdObject;
        return request['@type'] === 'addFileToDownloads' &&
          request['file_id'] === 951 &&
          request['message_id'] === 86;
      });
      expect(registeredAfterTap).assertTrue();
      expect(store.getMessages()[1].mediaDownloadActive).assertTrue();
    });
    it('poll_vote_is_deduplicated_and_update_poll_refreshes_results', 0, async () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, pollMessage(87, 5));
      let completed = false;
      store.votePoll(87, [1], (ok: boolean): void => { completed = ok; });
      store.votePoll(87, [0], (): void => {});
      const voteRequests: TdObject[] = b.sent
        .map((json: string): TdObject => JSON.parse(json) as TdObject)
        .filter((request: TdObject): boolean => request['@type'] === 'setPollAnswer');
      expect(voteRequests.length).assertEqual(1);
      expect((voteRequests[0]['option_ids'] as number[])[0]).assertEqual(1);
      expect(store.getMessages()[0].pollVotePending).assertTrue();

      const ok: TdObject = { '@type': 'ok' };
      ok['@extra'] = voteRequests[0]['@extra'];
      b.onReceive(JSON.stringify(ok));
      await new Promise<void>((resolve: (value: undefined) => void) =>
        setTimeout(() => resolve(undefined), 0));
      expect(completed).assertTrue();
      expect(store.getMessages()[0].pollVotePending).assertFalse();
      expect(store.getMessages()[0].pollOptions[1].isChosen).assertTrue();

      const update: TdObject = { '@type': 'updatePoll' };
      update['poll'] = pollObject(1, 4);
      b.onReceive(JSON.stringify(update));
      expect(store.getMessages()[0].pollTotalVoterCount).assertEqual(4);
      expect(store.getMessages()[0].pollOptions[1].votePercentage).assertEqual(100);
      expect(store.getMessages()[0].pollOptions[1].isChosen).assertTrue();
    });
    it('send_optimistically_adds_and_requests', 0, async () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      const before = b.sent.length;
      store.send('hello');
      const sentTypes = b.sent.slice(before).map((s: string) => (JSON.parse(s) as TdObject)['@type']);
      expect(sentTypes.includes('sendMessage')).assertTrue();
    });
    it('close_unsubscribes', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      store.close();
      pushNewMessage(b, textMessage(70, 5, false, 'z'));
      expect(store.getMessages().length).assertEqual(0);
      const types = b.sent.map((s: string) => (JSON.parse(s) as TdObject)['@type']);
      expect(types.includes('closeChat')).assertTrue();
    });
  });
}
