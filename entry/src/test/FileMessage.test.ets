import { describe, it, expect } from '@ohos/hypium';
import {
  displayFileName, fileExtension, fileOpenMimeType, fileStatusText, fileTypeVisual
} from '../main/ets/util/fileMessage';

export default function fileMessageTest() {
  describe('fileMessage', () => {
    it('classifies_common_document_types', 0, () => {
      expect(fileTypeVisual('manual.pdf', '').label).assertEqual('PDF');
      expect(fileTypeVisual('brief.docx', '').label).assertEqual('DOC');
      expect(fileTypeVisual('budget.xlsx', '').label).assertEqual('XLS');
      expect(fileTypeVisual('slides.pptx', '').label).assertEqual('PPT');
      expect(fileTypeVisual('source.zip', '').label).assertEqual('ZIP');
      expect(fileTypeVisual('main.ets', '').label).assertEqual('CODE');
    });
    it('falls_back_to_mime_and_safe_generic_labels', 0, () => {
      expect(fileExtension('', 'application/pdf')).assertEqual('pdf');
      expect(fileTypeVisual('', 'audio/ogg').label).assertEqual('AUDIO');
      expect(fileTypeVisual('backup.xyz', '').label).assertEqual('XYZ');
      expect(fileTypeVisual('', '').label).assertEqual('FILE');
      expect(displayFileName('')).assertEqual('未命名文件');
      expect(fileOpenMimeType('manual.pdf', '')).assertEqual('application/pdf');
      expect(fileOpenMimeType('voice.mp3', 'application/octet-stream')).assertEqual('audio/mpeg');
      expect(fileOpenMimeType('anything.bin', 'application/x-custom'))
        .assertEqual('application/x-custom');
    });
    it('describes_every_download_state', 0, () => {
      expect(fileStatusText(0, '', 0, false, 0, false)).assertEqual('文件不可用');
      expect(fileStatusText(7, '', 0, false, 0, false))
        .assertEqual('未知大小 · 点击下载');
      expect(fileStatusText(7, '', 1024, true, 0, false))
        .assertEqual('1.0 KB · 正在下载');
      expect(fileStatusText(7, '', 1024, true, 53, false))
        .assertEqual('1.0 KB · 正在下载 53%');
      expect(fileStatusText(7, '', 1024, false, 0, true))
        .assertEqual('下载失败 · 点按重试');
      expect(fileStatusText(7, '/data/a.bin', 1024, false, 100, false))
        .assertEqual('1.0 KB · 点击打开');
    });
  });
}
