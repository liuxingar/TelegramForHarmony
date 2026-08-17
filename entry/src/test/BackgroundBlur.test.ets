import { describe, expect, it } from '@ohos/hypium';
import { backgroundBlurRadius } from '../main/ets/util/chatBackgroundRaster';

export default function backgroundBlurTest() {
  describe('BackgroundBlur', (): void => {
    it('always_blurs_a_tiled_pattern_background', 0, (): void => {
      expect(backgroundBlurRadius('/cache/pattern.png', true, false)).assertEqual(8);
    });
    it('blurs_a_tiled_pattern_background_the_same_even_when_blurred_flag_set', 0, (): void => {
      expect(backgroundBlurRadius('/cache/pattern.png', true, true)).assertEqual(8);
    });
    it('leaves_a_plain_photo_wallpaper_sharp_unless_flagged_blurred', 0, (): void => {
      expect(backgroundBlurRadius('/cache/wall.jpg', false, false)).assertEqual(0);
    });
    it('blurs_a_photo_wallpaper_flagged_blurred', 0, (): void => {
      expect(backgroundBlurRadius('/cache/wall.jpg', false, true)).assertEqual(12);
    });
    it('leaves_pure_gradient_sharp', 0, (): void => {
      expect(backgroundBlurRadius('', false, false)).assertEqual(0);
    });
    it('leaves_pure_gradient_sharp_even_when_blurred_flag_set', 0, (): void => {
      expect(backgroundBlurRadius('', false, true)).assertEqual(0);
    });
  });
}
