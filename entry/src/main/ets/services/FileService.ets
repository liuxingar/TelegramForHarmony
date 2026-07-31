import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { ChatStore } from '../store/ChatStore';

const AVATAR_PRIORITY: number = 1;

export class FileService {
  private client: TdClient;
  private store: ChatStore;
  // A TDLib file can be reused by more than one chat. Keeping only one chat
  // here makes the last request steal the update, leaving earlier rows on
  // initials until their detail page downloads the same file again.
  private fileToChats: Map<number, Set<number>> = new Map();
  private requested: Set<number> = new Set();
  private completedPaths: Map<number, string> = new Map();

  constructor(client: TdClient, store: ChatStore) {
    this.client = client;
    this.store = store;
    client.onUpdate('updateFile', (u: TdObject) => this.onFile(u));
  }

  requestAvatar(chatId: number, fileId: number): void {
    if (fileId === 0) {
      return;
    }
    let chatIds = this.fileToChats.get(fileId);
    if (chatIds === undefined) {
      chatIds = new Set<number>();
      this.fileToChats.set(fileId, chatIds);
    }
    chatIds.add(chatId);
    const completedPath = this.completedPaths.get(fileId) ?? '';
    if (completedPath !== '') {
      if (this.store.photoFileIdOf(chatId) === fileId) {
        this.store.setAvatarPath(chatId, completedPath);
      }
      return;
    }
    if (this.requested.has(fileId)) {
      return;
    }
    this.requested.add(fileId);
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = fileId;
    req['priority'] = AVATAR_PRIORITY;
    // The response carries the file's current state. Files TDLib already
    // downloaded (e.g. small profile photos fetched during loadChats) come
    // back complete here and emit NO further updateFile, so we must apply the
    // response directly — relying on updateFile alone would miss them.
    this.client.send(req).then((file: TdObject) => {
      this.applyFile(file);
    }).catch((e: TdError) => {
      console.error(`FileService.downloadFile ${fileId} failed: ${e.message}`);
      this.requested.delete(fileId);
    });
  }

  private onFile(update: TdObject): void {
    const file = update['file'] as TdObject | undefined;
    if (file === undefined) {
      return;
    }
    this.applyFile(file);
  }

  private applyFile(file: TdObject): void {
    const id = file['id'] as number | undefined;
    if (id === undefined) {
      return;
    }
    const chatIds = this.fileToChats.get(id);
    if (chatIds === undefined) {
      return;
    }
    const local = file['local'] as TdObject | undefined;
    if (local === undefined) {
      return;
    }
    const done = (local['is_downloading_completed'] as boolean | undefined) ?? false;
    const path = (local['path'] as string | undefined) ?? '';
    if (done && path !== '') {
      this.completedPaths.set(id, path);
      this.requested.delete(id);
      for (const chatId of chatIds) {
        // Ignore a late completion from the chat's previous photo.
        if (this.store.photoFileIdOf(chatId) === id) {
          this.store.setAvatarPath(chatId, path);
        }
      }
    }
  }
}
