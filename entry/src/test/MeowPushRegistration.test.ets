import { describe, it, expect } from '@ohos/hypium';
import {
  buildMeowConfirmBody, buildMeowDeleteBody, buildMeowRegisterStartBody,
  parseMeowConfirmResponse, parseMeowStartResponse, validateMeowCode, validateMeowNickname
} from '../main/ets/services/MeowPushRegistration';

const GOOD_ENDPOINT: string = 'https://push.example.com/webpush/abc123';
const GOOD_P256DH: string = 'BEl62iUYgUivxIkv69yViEuiBIa-Ib9-SkQ';
const GOOD_AUTH: string = 'tBHItJI5svbpez7KI4CC';
const GOOD_SECRET: string = 'sekret-token-xyz';
const GOOD_SUBKEY: string = 'abcdef0123456789';
const GOOD_PENDING_ID: string = 'pending-987';

export default function meowPushRegistrationTest() {
  describe('MeowPushRegistration', () => {
    it('accepts_a_nonblank_nickname', 0, () => {
      const v = validateMeowNickname('cat-lover');
      expect(v.valid).assertTrue();
      expect(v.error).assertEqual('');
    });

    it('rejects_blank_or_whitespace_nickname', 0, () => {
      expect(validateMeowNickname('').valid).assertFalse();
      expect(validateMeowNickname('   ').valid).assertFalse();
    });

    it('accepts_a_nonblank_code', 0, () => {
      expect(validateMeowCode('123456').valid).assertTrue();
    });

    it('rejects_blank_or_whitespace_code', 0, () => {
      expect(validateMeowCode('').valid).assertFalse();
      expect(validateMeowCode('   ').valid).assertFalse();
    });

    it('builds_register_start_body_with_subkey_and_trimmed_nickname', 0, () => {
      const body = buildMeowRegisterStartBody(GOOD_SUBKEY, '  cat-lover  ');
      expect(body.subKey).assertEqual(GOOD_SUBKEY);
      expect(body.meow).assertEqual('cat-lover');
    });

    it('builds_confirm_body_with_subkey_pendingid_and_trimmed_code', 0, () => {
      const body = buildMeowConfirmBody(GOOD_SUBKEY, GOOD_PENDING_ID, ' 123456 ');
      expect(body.subKey).assertEqual(GOOD_SUBKEY);
      expect(body.pendingId).assertEqual(GOOD_PENDING_ID);
      expect(body.code).assertEqual('123456');
    });

    it('builds_delete_body_with_subkey_and_secret', 0, () => {
      const body = buildMeowDeleteBody(GOOD_SUBKEY, GOOD_SECRET);
      expect(body.subKey).assertEqual(GOOD_SUBKEY);
      expect(body.secret).assertEqual(GOOD_SECRET);
    });

    // 第一步只返回 pendingId，不带任何密钥。
    it('parses_register_start_response', 0, () => {
      const r = parseMeowStartResponse(JSON.stringify({ pendingId: GOOD_PENDING_ID }));
      expect(r.error).assertEqual('');
      expect(r.pendingId).assertEqual(GOOD_PENDING_ID);
    });

    it('reports_error_when_start_response_missing_pendingid', 0, () => {
      const r = parseMeowStartResponse(JSON.stringify({}));
      expect(r.error.length > 0).assertTrue();
      expect(r.pendingId).assertEqual('');
    });

    it('reports_error_on_malformed_start_json_without_throwing', 0, () => {
      const r = parseMeowStartResponse('{ not json');
      expect(r.error.length > 0).assertTrue();
    });

    // 第二步：验证码确认成功后返回三个 Web Push 字段 + secret。
    it('parses_confirm_response', 0, () => {
      const r = parseMeowConfirmResponse(JSON.stringify({
        endpoint: GOOD_ENDPOINT, p256dh: GOOD_P256DH, auth: GOOD_AUTH, secret: GOOD_SECRET
      }));
      expect(r.error).assertEqual('');
      expect(r.config.endpoint).assertEqual(GOOD_ENDPOINT);
      expect(r.config.p256dh).assertEqual(GOOD_P256DH);
      expect(r.config.auth).assertEqual(GOOD_AUTH);
      expect(r.secret).assertEqual(GOOD_SECRET);
    });

    it('reports_error_when_confirm_response_missing_secret', 0, () => {
      const r = parseMeowConfirmResponse(JSON.stringify({
        endpoint: GOOD_ENDPOINT, p256dh: GOOD_P256DH, auth: GOOD_AUTH
      }));
      expect(r.error.length > 0).assertTrue();
    });

    it('reports_error_when_confirm_response_missing_webpush_fields', 0, () => {
      const r = parseMeowConfirmResponse(JSON.stringify({ secret: GOOD_SECRET }));
      expect(r.error.length > 0).assertTrue();
    });

    it('reports_error_on_malformed_confirm_json_without_throwing', 0, () => {
      const r = parseMeowConfirmResponse('{ not json');
      expect(r.error.length > 0).assertTrue();
      expect(r.config.endpoint).assertEqual('');
    });

    it('reports_error_on_non_object_confirm_json', 0, () => {
      const r = parseMeowConfirmResponse('"just a string"');
      expect(r.error.length > 0).assertTrue();
    });

    // 复制粘贴/服务端拼装 JSON 时常见前后空白，字段值不该带上。
    it('trims_whitespace_in_parsed_confirm_fields', 0, () => {
      const r = parseMeowConfirmResponse(JSON.stringify({
        endpoint: `  ${GOOD_ENDPOINT}  `, p256dh: GOOD_P256DH, auth: GOOD_AUTH, secret: ` ${GOOD_SECRET} `
      }));
      expect(r.config.endpoint).assertEqual(GOOD_ENDPOINT);
      expect(r.secret).assertEqual(GOOD_SECRET);
    });
  });
}
