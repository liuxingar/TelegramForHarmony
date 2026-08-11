import { describe, expect, it } from '@ohos/hypium';
import { TdObject } from '../main/ets/tdkit/TdTypes';
import {
  accentPreviewOf, builtinAccentColor, profileAccentPreviewOf
} from '../main/ets/util/accentPresentation';

export default function accentPresentationTest() {
  describe('AccentPresentation', (): void => {
    it('exposes_seven_builtin_name_colors', 0, (): void => {
      for (let id = 0; id <= 6; id++) {
        expect(builtinAccentColor(id).startsWith('#')).assertTrue();
      }
      expect(builtinAccentColor(0) === builtinAccentColor(1)).assertFalse();
    });
    it('maps_server_accent_color_to_hex_list', 0, (): void => {
      const value: TdObject = { '@type': 'accentColor' };
      value['id'] = 8;
      value['built_in_accent_color_id'] = 3;
      value['light_theme_colors'] = [0xAA0000, 0x00BB00];
      value['dark_theme_colors'] = [0x110000, 0x001100];
      const light = accentPreviewOf(value, false);
      expect(light !== null).assertTrue();
      expect(light?.id).assertEqual(8);
      expect(light?.colors.join(',')).assertEqual('#AA0000,#00BB00');
      const dark = accentPreviewOf(value, true);
      expect(dark?.colors.join(',')).assertEqual('#110000,#001100');
    });
    it('falls_back_to_builtin_color_when_palette_empty', 0, (): void => {
      const value: TdObject = { '@type': 'accentColor' };
      value['id'] = 2;
      value['built_in_accent_color_id'] = 2;
      const preview = accentPreviewOf(value, false);
      expect(preview?.colors.length).assertEqual(1);
      expect(preview?.colors[0]).assertEqual(builtinAccentColor(2));
    });
    it('maps_profile_accent_palette_colors', 0, (): void => {
      const palette: TdObject = { '@type': 'profileAccentColors' };
      palette['palette_colors'] = [0x123456];
      palette['background_colors'] = [0x654321, 0x111111];
      const value: TdObject = { '@type': 'profileAccentColor' };
      value['id'] = 5;
      value['light_theme_colors'] = palette;
      value['dark_theme_colors'] = palette;
      const preview = profileAccentPreviewOf(value, false);
      expect(preview !== null).assertTrue();
      expect(preview?.id).assertEqual(5);
      expect(preview?.colors.join(',')).assertEqual('#654321,#111111');
    });
    it('rejects_profile_color_without_palette', 0, (): void => {
      const value: TdObject = { '@type': 'profileAccentColor' };
      value['id'] = 5;
      expect(profileAccentPreviewOf(value, false) === null).assertTrue();
    });
  });
}
