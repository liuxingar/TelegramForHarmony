import { describe, it, expect } from '@ohos/hypium';
import {
  buildCacheTrimRequest, shouldTrimCache, CACHE_LIMIT_UNLIMITED,
  CACHE_LIMIT_DEFAULT, CACHE_LIMIT_OPTIONS
} from '../main/ets/store/CacheLimit';

export default function cacheLimitTest() {
  describe('CacheLimit', () => {
    it('默认上限是 4GB 且在候选列表里', 0, () => {
      expect(CACHE_LIMIT_DEFAULT).assertEqual(4 * 1024 * 1024 * 1024);
      expect(CACHE_LIMIT_OPTIONS.indexOf(CACHE_LIMIT_DEFAULT) >= 0).assertTrue();
    });

    it('候选列表含"不限"且升序', 0, () => {
      expect(CACHE_LIMIT_OPTIONS.indexOf(CACHE_LIMIT_UNLIMITED) >= 0).assertTrue();
      const sized = CACHE_LIMIT_OPTIONS.filter((v: number): boolean => v !== CACHE_LIMIT_UNLIMITED);
      for (let i = 1; i < sized.length; i++) {
        expect(sized[i] > sized[i - 1]).assertTrue();
      }
    });

    it('不限时不触发收缩', 0, () => {
      expect(shouldTrimCache(CACHE_LIMIT_UNLIMITED)).assertFalse();
      expect(shouldTrimCache(-1)).assertFalse();
      expect(shouldTrimCache(CACHE_LIMIT_DEFAULT)).assertTrue();
    });

    it('收缩请求把上限写进 size，其余参数交给 TDLib 默认值', 0, () => {
      const req = buildCacheTrimRequest(CACHE_LIMIT_DEFAULT);
      expect(req['@type']).assertEqual('optimizeStorage');
      expect(req['size']).assertEqual(CACHE_LIMIT_DEFAULT);
      expect(req['ttl']).assertEqual(-1);
      expect(req['count']).assertEqual(-1);
      expect(req['immunity_delay']).assertEqual(-1);
      expect(req['return_deleted_file_statistics']).assertEqual(false);
      expect(req['chat_limit']).assertEqual(0);
    });

    it('收缩不限定文件类型与会话（全局 LRU）', 0, () => {
      const req = buildCacheTrimRequest(CACHE_LIMIT_DEFAULT);
      expect((req['file_types'] as Object[]).length).assertEqual(0);
      expect((req['chat_ids'] as Object[]).length).assertEqual(0);
      expect((req['exclude_chat_ids'] as Object[]).length).assertEqual(0);
    });
  });
}
