import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { TranslationService, looksLikeTargetLanguage } from '../main/ets/services/TranslationService';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}

function setup(): Array<Object> {
  const b = new FakeBridge();
  const c = new TdClient(b);
  c.start();
  return [b, new TranslationService(c)];
}

function pendingTranslateRequests(b: FakeBridge): string[] {
  const extras: string[] = [];
  for (const json of b.sent) {
    const o = JSON.parse(json) as TdObject;
    if (o['@type'] === 'translateMessageText') {
      extras.push((o['@extra'] as string | undefined) ?? '');
    }
  }
  return extras;
}

function answer(b: FakeBridge, extra: string, text: string): void {
  const res: TdObject = { '@type': 'formattedText' };
  res['text'] = text;
  res['@extra'] = extra;
  b.onReceive(JSON.stringify(res));
}

export default function translationServiceTest() {
  describe('TranslationService', () => {
    it('translates_and_caches_per_content_version', 0, async () => {
      const arr = setup(); const b = arr[0] as FakeBridge; const svc = arr[1] as TranslationService;
      let got: string | null = null;
      svc.request(5, 100, 0, 'zh', (text: string | null): void => { got = text; });
      answer(b, pendingTranslateRequests(b)[0], '你好');
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      expect(got).assertEqual('你好');
      expect(svc.cached(5, 100, 0, 'zh')).assertEqual('你好');
      // Same content version again: served from cache, no second TDLib call.
      let again: string | null = null;
      svc.request(5, 100, 0, 'zh', (text: string | null): void => { again = text; });
      expect(again).assertEqual('你好');
      expect(pendingTranslateRequests(b).length).assertEqual(1);
      // An edit (new editDate) is a different version and asks again.
      svc.request(5, 100, 7, 'zh', (): void => {});
      expect(pendingTranslateRequests(b).length).assertEqual(2);
    });
    // Opening a busy chat queues dozens of rows; only a couple may be on the
    // wire at once, and the rest must drain as answers come back.
    it('caps_inflight_requests_at_two', 0, async () => {
      const arr = setup(); const b = arr[0] as FakeBridge; const svc = arr[1] as TranslationService;
      svc.request(5, 1, 0, 'zh', (): void => {});
      svc.request(5, 2, 0, 'zh', (): void => {});
      svc.request(5, 3, 0, 'zh', (): void => {});
      expect(pendingTranslateRequests(b).length).assertEqual(2);
      answer(b, pendingTranslateRequests(b)[0], 'a');
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      expect(pendingTranslateRequests(b).length).assertEqual(3);
    });
    // Messages already in the target language must not cost a round trip.
    // Script-based: decisive for zh/ja/ko/ru/..., deliberately undecidable
    // between Latin-script languages (those return false and go to the server).
    it('skips_text_already_in_target_language', 0, () => {
      expect(looksLikeTargetLanguage('你好，今天怎么样', 'zh')).assertTrue();
      expect(looksLikeTargetLanguage('Hello there', 'zh')).assertFalse();
      // Japanese is han + kana — the kana veto keeps it translatable for zh.
      expect(looksLikeTargetLanguage('日本語のテキスト', 'zh')).assertFalse();
      expect(looksLikeTargetLanguage('日本語のテキスト', 'ja')).assertTrue();
      expect(looksLikeTargetLanguage('안녕하세요', 'ko')).assertTrue();
      expect(looksLikeTargetLanguage('Привет, как дела', 'ru')).assertTrue();
      // Latin targets stay undecidable: French text is not detectably English.
      expect(looksLikeTargetLanguage('Bonjour tout le monde', 'en')).assertFalse();
      // Nothing translatable at all — pure emoji/digits never go out.
      expect(looksLikeTargetLanguage('👍👍 123', 'en')).assertTrue();
    });
  });
}
