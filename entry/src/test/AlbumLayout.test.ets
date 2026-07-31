import { describe, it, expect } from '@ohos/hypium';
import { packAlbumRows, AlbumCell } from '../main/ets/util/packAlbumRows';

function rowWidth(row: AlbumCell[]): number {
  let width = 0;
  for (const cell of row) {
    width += cell.width;
  }
  return width + Math.max(0, row.length - 1) * 2;
}

export default function albumLayoutTest() {
  describe('AlbumLayout', () => {
    it('four_items_form_two_balanced_rows', 0, () => {
      const rows = packAlbumRows([1, 1, 1, 1], 280);
      expect(rows.length).assertEqual(2);
      expect(rows[0].length).assertEqual(2);
      expect(rows[1].length).assertEqual(2);
      expect(rowWidth(rows[0])).assertEqual(280);
      expect(rowWidth(rows[1])).assertEqual(280);
    });
    it('extreme_portrait_is_height_bounded', 0, () => {
      const rows = packAlbumRows([0.1], 280);
      expect(rows[0][0].height <= 188).assertTrue();
      expect(rows[0][0].width).assertEqual(280);
    });
    it('extreme_panorama_is_not_paper_thin', 0, () => {
      const rows = packAlbumRows([10], 280);
      expect(rows[0][0].height >= 132).assertTrue();
    });
    it('nine_items_have_no_orphan_row', 0, () => {
      const rows = packAlbumRows([1, 1, 1, 1, 1, 1, 1, 1, 1], 280);
      expect(rows.length).assertEqual(3);
      expect(rows[2].length).assertEqual(3);
    });
  });
}
