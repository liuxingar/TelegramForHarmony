import { describe, it, expect } from '@ohos/hypium';
import { appendMention, mentionToken } from '../main/ets/util/mentionDraft';

export default function mentionDraftTest() {
  describe('mentionDraft', () => {
    it('prefers the public username', 0, () => {
      expect(mentionToken('Alice Smith', 'alice')).assertEqual('@alice');
    });

    it('falls back to the display name when there is no username', 0, () => {
      expect(mentionToken('Alice Smith', '')).assertEqual('Alice Smith');
    });

    it('yields nothing when neither name nor username is known', 0, () => {
      expect(mentionToken('', '')).assertEqual('');
      expect(mentionToken('   ', '')).assertEqual('');
    });

    it('appends to an empty draft with a trailing space', 0, () => {
      expect(appendMention('', '@alice')).assertEqual('@alice ');
    });

    it('inserts a separating space when the draft has none', 0, () => {
      expect(appendMention('hi', '@alice')).assertEqual('hi @alice ');
    });

    it('reuses the draft\'s existing trailing space', 0, () => {
      expect(appendMention('hi ', '@alice')).assertEqual('hi @alice ');
    });

    it('keeps a trailing newline as the separator', 0, () => {
      expect(appendMention('hi\n', '@alice')).assertEqual('hi\n@alice ');
    });

    it('is a no-op when the same mention already trails the draft', 0, () => {
      expect(appendMention('hi @alice ', '@alice')).assertEqual('hi @alice ');
      expect(appendMention('hi @alice', '@alice')).assertEqual('hi @alice ');
    });

    it('still appends when the trailing token only shares a prefix', 0, () => {
      expect(appendMention('hi @alicia ', '@alice')).assertEqual('hi @alicia @alice ');
    });

    it('appends the same mention again once other text follows it', 0, () => {
      expect(appendMention('@alice hey', '@alice')).assertEqual('@alice hey @alice ');
    });

    it('handles display names containing spaces', 0, () => {
      expect(appendMention('hi', 'Alice Smith')).assertEqual('hi Alice Smith ');
      expect(appendMention('hi Alice Smith ', 'Alice Smith')).assertEqual('hi Alice Smith ');
    });

    it('leaves the draft untouched for an empty token', 0, () => {
      expect(appendMention('hi', '')).assertEqual('hi');
      expect(appendMention('', '')).assertEqual('');
    });
  });
}
