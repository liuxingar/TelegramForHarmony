import { MessageEntry } from '../store/MessageEntry';
import { VoiceState } from './VoicePlayback';
import { str } from '../util/strings';

// --- Pure queue maths over a loaded message list -----------------------------
//
// The "queue" is just the audio messages of the open chat, in list order. These
// are free functions with no dependencies so they can be exercised directly.

// Neighbouring audio message in list order. `direction` < 0 walks backwards.
// Returns null at either end, or when `messageId` is not an audio message.
export function adjacentAudioEntry(
  messages: MessageEntry[], messageId: number, direction: number
): MessageEntry | null {
  const music: MessageEntry[] =
    messages.filter((entry: MessageEntry): boolean => entry.contentType === 'audio');
  const index: number = music.findIndex((entry: MessageEntry): boolean => entry.id === messageId);
  const nextIndex: number = index + (direction < 0 ? -1 : 1);
  return index >= 0 && nextIndex >= 0 && nextIndex < music.length ? music[nextIndex] : null;
}

export function audioQueueLength(messages: MessageEntry[]): number {
  let count: number = 0;
  for (const entry of messages) {
    if (entry.contentType === 'audio') {
      count++;
    }
  }
  return count;
}

// 1-based position of `messageId` among the audio messages; 0 when absent.
export function audioQueuePosition(messages: MessageEntry[], messageId: number): number {
  let position: number = 0;
  for (const entry of messages) {
    if (entry.contentType !== 'audio') {
      continue;
    }
    position++;
    if (entry.id === messageId) {
      return position;
    }
  }
  return 0;
}

// --- Stateful controller -----------------------------------------------------

// Everything MusicQueue reaches outside itself, passed in rather than imported,
// so tests can drive it without a real player, TDLib or a UI context.
export interface MusicQueueDeps {
  currentState: () => VoiceState;
  toggleMusic: (messageId: number, path: string, fallbackDurationSec: number) => void;
  startMusic: (messageId: number, path: string, fallbackDurationSec: number) => void;
  seek: (messageId: number, fraction: number) => void;
  // Ask the store for the full audio file; `failed` retries a failed download.
  requestDownload: (messageId: number, failed: boolean) => void;
  toast: (message: string, durationMs: number) => void;
}

// Play/skip/seek over the chat's audio messages, plus the "tapped before the
// file finished downloading" hand-off: the tap records a pending id, and the
// next message-list update that carries a local path starts playback.
export class MusicQueue {
  private deps: MusicQueueDeps;
  private pendingPlayId: number = 0;

  constructor(deps: MusicQueueDeps) {
    this.deps = deps;
  }

  // Exposed for the "还在下载" indicator and for tests.
  getPendingPlayId(): number {
    return this.pendingPlayId;
  }

  reset(): void {
    this.pendingPlayId = 0;
  }

  hasNext(messages: MessageEntry[], messageId: number): boolean {
    return adjacentAudioEntry(messages, messageId, 1) !== null;
  }

  hasPrevious(messages: MessageEntry[], messageId: number): boolean {
    return adjacentAudioEntry(messages, messageId, -1) !== null;
  }

  queueLength(messages: MessageEntry[]): number {
    return audioQueueLength(messages);
  }

  queuePosition(messages: MessageEntry[], messageId: number): number {
    return audioQueuePosition(messages, messageId);
  }

  // `forceStart` distinguishes "skip to this track" (always restart) from a tap
  // on the track itself (toggle play/pause).
  play(messages: MessageEntry[], messageId: number, forceStart: boolean): void {
    let entry: MessageEntry | null = null;
    for (const item of messages) {
      if (item.id === messageId) {
        entry = item;
        break;
      }
    }
    if (entry === null || entry.contentType !== 'audio') {
      return;
    }
    if (entry.videoFileId === 0 && entry.videoPath === '') {
      this.pendingPlayId = 0;
      this.deps.toast(str('mq_audio_unavailable'), 1600);
      return;
    }
    if (entry.videoPath === '') {
      this.pendingPlayId = messageId;
      this.deps.requestDownload(messageId, entry.videoFailed);
      this.deps.toast(
        entry.videoFailed ? str('mq_redownloading')
          : (entry.mediaDownloadActive ? str('mq_downloading') : str('mq_download_started')),
        1400
      );
      return;
    }
    this.pendingPlayId = 0;
    if (forceStart) {
      this.deps.startMusic(messageId, entry.videoPath, entry.videoDuration);
    } else {
      this.deps.toggleMusic(messageId, entry.videoPath, entry.videoDuration);
    }
  }

  // Called on every message-list update: starts the track whose download the
  // user was waiting on, or gives up if it failed / vanished.
  settlePending(list: MessageEntry[]): void {
    if (this.pendingPlayId === 0) {
      return;
    }
    const pendingId: number = this.pendingPlayId;
    const entry: MessageEntry | undefined =
      list.find((item: MessageEntry): boolean => item.id === pendingId);
    if (entry === undefined || entry.contentType !== 'audio') {
      this.pendingPlayId = 0;
      return;
    }
    if (entry.videoFailed) {
      this.pendingPlayId = 0;
      this.deps.toast(str('mq_download_failed'), 1800);
      return;
    }
    if (entry.videoPath !== '') {
      this.pendingPlayId = 0;
      this.deps.startMusic(entry.id, entry.videoPath, entry.videoDuration);
    }
  }

  onCompleted(messages: MessageEntry[], messageId: number): void {
    this.next(messages, messageId);
  }

  next(messages: MessageEntry[], messageId: number): void {
    const following: MessageEntry | null = adjacentAudioEntry(messages, messageId, 1);
    if (following !== null) {
      this.play(messages, following.id, true);
    }
  }

  // Mirrors the usual media-player rule: past the first few seconds, "previous"
  // restarts the current track instead of skipping back.
  previous(messages: MessageEntry[], messageId: number): void {
    const current: VoiceState = this.deps.currentState();
    if (current.mode === 'music' && current.playingId === messageId && current.positionMs > 3000) {
      this.deps.seek(messageId, 0);
      return;
    }
    const preceding: MessageEntry | null = adjacentAudioEntry(messages, messageId, -1);
    if (preceding !== null) {
      this.play(messages, preceding.id, true);
    } else if (current.mode === 'music' && current.playingId === messageId) {
      this.deps.seek(messageId, 0);
    }
  }

  seek(messageId: number, fraction: number): void {
    this.deps.seek(messageId, fraction);
  }
}
