import { describe, expect, it } from '@ohos/hypium';
import { patternTileGrid, PatternTileGrid } from '../main/ets/util/chatBackgroundRaster';

export default function patternTileGridTest() {
  describe('PatternTileGrid', (): void => {
    it('covers_a_phone_screen_with_at_least_one_tile_per_axis', 0, (): void => {
      const grid: PatternTileGrid = patternTileGrid(376, 809, 340);
      expect(grid.cols >= 1).assertTrue();
      expect(grid.rows >= 1).assertTrue();
      expect(grid.cols * grid.tileWidth >= 376).assertTrue();
      expect(grid.rows * grid.tileHeight >= 809).assertTrue();
    });
    it('covers_a_wide_tablet_screen_that_used_to_show_bare_edges', 0, (): void => {
      // A 16:10 tablet in portrait — screenW/screenH ~0.625, wider than the
      // pattern's own ~0.4865 ratio. This is exactly the shape that left
      // Contain-fit padding on the sides before tiling.
      const grid: PatternTileGrid = patternTileGrid(900, 1440, 340);
      expect(grid.cols * grid.tileWidth >= 900).assertTrue();
      expect(grid.rows * grid.tileHeight >= 1440).assertTrue();
    });
    it('keeps_every_tile_at_the_patterns_native_aspect_ratio', 0, (): void => {
      const grid: PatternTileGrid = patternTileGrid(500, 900, 340);
      const ratio: number = grid.tileWidth / grid.tileHeight;
      expect(Math.abs(ratio - (1440 / 2960)) < 0.001).assertTrue();
    });
    it('never_produces_zero_tiles_for_a_degenerate_size', 0, (): void => {
      const grid: PatternTileGrid = patternTileGrid(0, 0, 340);
      expect(grid.cols >= 1).assertTrue();
      expect(grid.rows >= 1).assertTrue();
    });
    it('scales_tile_count_up_as_the_canvas_grows', 0, (): void => {
      const small: PatternTileGrid = patternTileGrid(400, 800, 340);
      const large: PatternTileGrid = patternTileGrid(1600, 3200, 340);
      expect(large.cols >= small.cols).assertTrue();
      expect(large.rows >= small.rows).assertTrue();
    });
  });
}
