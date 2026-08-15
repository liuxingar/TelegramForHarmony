import { describe, it, expect } from '@ohos/hypium';
import {
  chatHeaderPresentation, chatHeaderTitle, ChatHeaderInput
} from '../main/ets/util/chatHeaderPresentation';

function input(title: string, subtitle: string, state: string,
  loadError: string, kind: string): ChatHeaderInput {
  return { title, subtitle, state, loadError, kind };
}

export default function chatHeaderPresentationTest() {
  describe('chatHeaderPresentation', () => {
    it('shows the title once known', 0, () => {
      const p = chatHeaderPresentation(input('Ann', '', 'ready', '', 'private'));
      expect(p.titleText).assertEqual('Ann');
    });

    it('a cached title wins even while still loading', 0, () => {
      // Entering from the chat list must not flash "正在加载" over a title the
      // list already had.
      const p = chatHeaderPresentation(input('Ann', '', 'loading', '', ''));
      expect(p.titleText).assertEqual('Ann');
    });

    it('a cached title wins even after the request failed', 0, () => {
      const p = chatHeaderPresentation(input('Ann', '', 'error', '加载失败', 'private'));
      expect(p.titleText).assertEqual('Ann');
    });

    it('falls back to a loading title', 0, () => {
      expect(chatHeaderPresentation(input('', '', 'loading', '', '')).titleText)
        .assertEqual('正在加载');
    });

    it('falls back to an error title', 0, () => {
      expect(chatHeaderPresentation(input('', '', 'error', 'x', '')).titleText)
        .assertEqual('无法读取聊天');
    });

    it('a derived subtitle outranks everything else', 0, () => {
      const p = chatHeaderPresentation(input('G', '128 名成员', 'ready', '', 'group'));
      expect(p.subtitleText).assertEqual('128 名成员');
    });

    it('a derived subtitle shows even while loading', 0, () => {
      const p = chatHeaderPresentation(input('G', '最后上线于昨天', 'loading', '', ''));
      expect(p.subtitleText).assertEqual('最后上线于昨天');
    });

    it('loading without a subtitle explains itself', 0, () => {
      expect(chatHeaderPresentation(input('', '', 'loading', '', '')).subtitleText)
        .assertEqual('正在获取会话信息…');
    });

    it('an error surfaces its reason', 0, () => {
      expect(chatHeaderPresentation(input('', '', 'error', '会话参数无效', '')).subtitleText)
        .assertEqual('会话参数无效');
    });

    it('an error without a reason invites a retry', 0, () => {
      expect(chatHeaderPresentation(input('', '', 'error', '', '')).subtitleText)
        .assertEqual('点击重试');
    });

    it('labels each chat kind when nothing better is known', 0, () => {
      expect(chatHeaderPresentation(input('C', '', 'ready', '', 'channel')).subtitleText)
        .assertEqual('频道');
      expect(chatHeaderPresentation(input('G', '', 'ready', '', 'group')).subtitleText)
        .assertEqual('群组');
      expect(chatHeaderPresentation(input('S', '', 'ready', '', 'secret')).subtitleText)
        .assertEqual('加密聊天');
      expect(chatHeaderPresentation(input('U', '', 'ready', '', 'private')).subtitleText)
        .assertEqual('Telegram 用户');
    });

    it('an unresolved kind still reads as a user', 0, () => {
      expect(chatHeaderPresentation(input('U', '', 'ready', '', '')).subtitleText)
        .assertEqual('Telegram 用户');
    });

    it('an ordinary chat is titled after the chat', 0, () => {
      expect(chatHeaderTitle({
        chatTitle: 'Ann', topicName: '', forumTopicId: 0, threadRootId: 0
      })).assertEqual('Ann');
    });

    it('a forum topic is titled after the topic', 0, () => {
      expect(chatHeaderTitle({
        chatTitle: 'Group', topicName: '公告', forumTopicId: 5, threadRootId: 0
      })).assertEqual('公告');
    });

    it('an unnamed forum topic falls back', 0, () => {
      expect(chatHeaderTitle({
        chatTitle: 'Group', topicName: '', forumTopicId: 5, threadRootId: 0
      })).assertEqual('话题');
    });

    it('a named comment thread keeps its name', 0, () => {
      // The bug this rule fixes: the per-update refresh used to overwrite this
      // with a bare '评论' moments after the chat opened.
      expect(chatHeaderTitle({
        chatTitle: 'Channel', topicName: '第 3 集讨论', forumTopicId: 0, threadRootId: 9
      })).assertEqual('第 3 集讨论');
    });

    it('an unnamed comment thread falls back', 0, () => {
      expect(chatHeaderTitle({
        chatTitle: 'Channel', topicName: '', forumTopicId: 0, threadRootId: 9
      })).assertEqual('评论');
    });

    it('a forum topic outranks a thread id', 0, () => {
      expect(chatHeaderTitle({
        chatTitle: 'Group', topicName: '公告', forumTopicId: 5, threadRootId: 9
      })).assertEqual('公告');
    });
  });
}
