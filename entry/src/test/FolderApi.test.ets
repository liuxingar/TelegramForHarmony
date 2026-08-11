import { describe, expect, it } from '@ohos/hypium';
import { TdObject } from '../main/ets/tdkit/TdTypes';
import {
  chatIsInChatList, emptyFolder, folderDataFromTd, toTdFolder
} from '../main/ets/store/FolderApi';

export default function folderApiTest() {
  describe('FolderApi', () => {
    it('td_folder_roundtrip_preserves_rules', 0, () => {
      const folder = emptyFolder();
      folder.name = '工作';
      folder.iconName = 'Work';
      folder.colorId = 2;
      folder.includedChatIds = [10, 20];
      folder.excludedChatIds = [30];
      folder.includeGroups = true;
      folder.excludeMuted = true;
      const td: TdObject = toTdFolder(folder);
      const parsed = folderDataFromTd(td, 9);
      expect(parsed.id).assertEqual(9);
      expect(parsed.name).assertEqual('工作');
      expect(parsed.iconName).assertEqual('Work');
      expect(parsed.colorId).assertEqual(2);
      expect(parsed.includedChatIds.join(',')).assertEqual('10,20');
      expect(parsed.excludedChatIds.join(',')).assertEqual('30');
      expect(parsed.includeGroups).assertTrue();
      expect(parsed.excludeMuted).assertTrue();
    });
    it('preserves_custom_emoji_name_metadata', 0, () => {
      const folder = emptyFolder();
      folder.name = '朋友';
      const entity: TdObject = { '@type': 'textEntity' };
      entity['offset'] = 0; entity['length'] = 1;
      entity['type'] = { '@type': 'textEntityTypeCustomEmoji', 'custom_emoji_id': '123' } as TdObject;
      folder.nameEntities = [entity];
      folder.animateCustomEmoji = true;
      const parsed = folderDataFromTd(toTdFolder(folder));
      expect(parsed.nameEntities.length).assertEqual(1);
      expect(parsed.animateCustomEmoji).assertTrue();
    });
    it('accepts_only_chats_with_a_chat_list_position', 0, () => {
      const listed: TdObject = { '@type': 'chat' };
      listed['positions'] = [{ '@type': 'chatPosition' } as TdObject];
      expect(chatIsInChatList(listed)).assertTrue();
      const unlisted: TdObject = { '@type': 'chat' };
      unlisted['positions'] = [];
      expect(chatIsInChatList(unlisted)).assertFalse();
      const missing: TdObject = { '@type': 'chat' };
      expect(chatIsInChatList(missing)).assertFalse();
    });
  });
}
