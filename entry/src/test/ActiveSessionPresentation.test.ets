import { describe, it, expect } from '@ohos/hypium';
import { TdObject } from '../main/ets/tdkit/TdTypes';
import {
  activeSessionError, freshSessionSeconds, inactiveSessionTtlLabel,
  sessionDeviceType, sessionWaitText
} from '../main/ets/util/ActiveSessionPresentation';

export default function activeSessionPresentationTest() {
  describe('ActiveSessionPresentation', () => {
    it('reads_official_device_type_and_legacy_fallback', 0, () => {
      const official: TdObject = {
        '@type': 'session',
        'device_type': { '@type': 'sessionDeviceTypeAndroid' } as TdObject
      };
      const legacy: TdObject = {
        '@type': 'session',
        'type': { '@type': 'sessionDeviceTypeDesktop' } as TdObject
      };
      expect(sessionDeviceType(official)).assertEqual('sessionDeviceTypeAndroid');
      expect(sessionDeviceType(legacy)).assertEqual('sessionDeviceTypeDesktop');
    });

    it('calculates_fresh_session_protection_and_wait_text', 0, () => {
      expect(freshSessionSeconds(100, 100)).assertEqual(86400);
      expect(freshSessionSeconds(100, 86500)).assertEqual(0);
      expect(sessionWaitText(3660)).assertEqual('1 小时 1 分钟后');
      expect(sessionWaitText(60)).assertEqual('1 分钟后');
    });

    it('maps_server_errors_without_leaking_raw_text', 0, () => {
      expect(activeSessionError('FRESH_RESET_AUTHORISATION_FORBIDDEN').kind)
        .assertEqual('fresh');
      expect(activeSessionError('SESSION_NOT_FOUND').shouldRefresh).assertTrue();
      expect(activeSessionError('FLOOD_WAIT_65').text)
        .assertEqual('操作过于频繁，请在 2 分钟后重试');
      expect(activeSessionError('AUTH_TOKEN_EXPIRED').kind).assertEqual('qr');
    });

    it('keeps_nonstandard_server_ttl_visible', 0, () => {
      expect(inactiveSessionTtlLabel(30)).assertEqual('1 个月');
      expect(inactiveSessionTtlLabel(60)).assertEqual('60 天');
      expect(inactiveSessionTtlLabel(366)).assertEqual('1 年');
    });
  });
}
