import { describe, expect, it } from '@ohos/hypium';
import { backgroundBlurRadius } from '../main/ets/util/chatBackgroundRaster';

export default function backgroundBlurTest() {
  describe('BackgroundBlur', (): void => {
    it('blurs_plain_photo_wallpaper_at_baseline_radius', 0, (): void => {
      expect(backgroundBlurRadius('/cache/wall.jpg', false, false)).assertEqual(8);
    });
    it('blurs_officially_blurred_photo_wallpaper_harder', 0, (): void => {
      expect(backgroundBlurRadius('/cache/wall.jpg', false, true)).assertEqual(16);
    });
    it('leaves_pattern_wallpaper_sharp', 0, (): void => {
      expect(backgroundBlurRadius('/cache/pattern.png', true, false)).assertEqual(0);
    });
    it('leaves_pattern_wallpaper_sharp_even_when_blurred_flag_set', 0, (): void => {
      expect(backgroundBlurRadius('/cache/pattern.png', true, true)).assertEqual(0);
    });
    it('leaves_pure_gradient_sharp', 0, (): void => {
      expect(backgroundBlurRadius('', false, false)).assertEqual(0);
    });
    it('leaves_pure_gradient_sharp_even_when_blurred_flag_set', 0, (): void => {
      expect(backgroundBlurRadius('', false, true)).assertEqual(0);
    });
  });
}
