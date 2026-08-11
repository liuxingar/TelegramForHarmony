import { describe, it, expect } from '@ohos/hypium';
import { TdObject } from '../main/ets/tdkit/TdTypes';
import {
  PROXY_HTTP, PROXY_MTPROTO, PROXY_SOCKS5, ProxyEntry,
  proxyEntryFromAddedObject, proxyObjectOf
} from '../main/ets/store/ProxyApi';
import {
  parseProxyPort, proxyActionErrorText, proxyConnectionText,
  proxyFormError, sameProxyConfiguration
} from '../main/ets/util/proxyLogic';

function entry(type: string): ProxyEntry {
  return {
    id: 7, server: 'proxy.example.com', port: 443, type: type,
    username: 'user', password: 'pass', secret: 'secret', httpOnly: false,
    lastUsedDate: 100, isEnabled: false
  };
}

export default function proxyLogicTest() {
  describe('ProxyLogic', (): void => {
    it('accepts_only_strict_valid_ports', 0, (): void => {
      expect(parseProxyPort('443')).assertEqual(443);
      expect(parseProxyPort(' 1080 ')).assertEqual(1080);
      expect(parseProxyPort('80abc')).assertEqual(0);
      expect(parseProxyPort('0')).assertEqual(0);
      expect(parseProxyPort('65536')).assertEqual(0);
    });

    it('validates_required_proxy_fields', 0, (): void => {
      expect(proxyFormError('', '443', PROXY_SOCKS5, '')).assertEqual('请填写服务器地址');
      expect(proxyFormError('host', 'abc', PROXY_SOCKS5, ''))
        .assertEqual('端口需为 1–65535 的整数');
      expect(proxyFormError('host', '443', PROXY_MTPROTO, ''))
        .assertEqual('MTProto 代理需要填写密钥');
      expect(proxyFormError('host', '443', PROXY_MTPROTO, 'secret')).assertEqual('');
    });

    it('preserves_http_only_and_added_proxy_metadata', 0, (): void => {
      const httpType: TdObject = {
        '@type': PROXY_HTTP, 'username': 'u', 'password': 'p', 'http_only': true
      };
      const proxy: TdObject = {
        '@type': 'proxy', 'server': 'http.example.com', 'port': 8080, 'type': httpType
      };
      const added: TdObject = {
        '@type': 'addedProxy', 'id': 12, 'last_used_date': 99,
        'is_enabled': true, 'proxy': proxy
      };
      const parsed = proxyEntryFromAddedObject(added);
      expect(parsed.id).assertEqual(12);
      expect(parsed.httpOnly).assertTrue();
      expect(parsed.lastUsedDate).assertEqual(99);
      expect(parsed.isEnabled).assertTrue();

      const encoded = proxyObjectOf(parsed);
      const encodedType = encoded['type'] as TdObject;
      expect(encodedType['http_only'] as boolean).assertTrue();
      expect(encodedType['username'] as string).assertEqual('u');
    });

    it('detects_duplicates_without_mixing_proxy_types', 0, (): void => {
      const first = entry(PROXY_SOCKS5);
      const duplicate = entry(PROXY_SOCKS5);
      duplicate.id = 8;
      duplicate.server = 'PROXY.EXAMPLE.COM';
      expect(sameProxyConfiguration(first, duplicate)).assertTrue();
      duplicate.type = PROXY_HTTP;
      expect(sameProxyConfiguration(first, duplicate)).assertFalse();
    });

    it('maps_connection_and_action_states', 0, (): void => {
      expect(proxyConnectionText('connectionStateReady', true)).assertEqual('代理已连接');
      expect(proxyConnectionText('connectionStateReady', false)).assertEqual('当前为直连');
      expect(proxyConnectionText('connectionStateConnectingToProxy', true))
        .assertEqual('正在连接代理');
      expect(proxyActionErrorText('request timeout', '启用代理'))
        .assertEqual('启用代理超时，请刷新状态后重试');
    });
  });
}
