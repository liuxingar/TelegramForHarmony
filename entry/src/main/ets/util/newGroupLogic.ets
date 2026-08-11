import { TdObject } from '../tdkit/TdTypes';

export interface NewBasicGroupResult {
  chatId: number;
  failedUserIds: number[];
}

export function parseNewBasicGroupResult(result: TdObject): NewBasicGroupResult {
  // Current TDLib returns createdBasicGroupChat rather than chat. Keep the
  // legacy `id` fallback for older native bridges that flattened the result.
  const chatId = (result['chat_id'] as number | undefined) ??
    ((result['id'] as number | undefined) ?? 0);
  const failed = result['failed_to_add_members'] as TdObject | undefined;
  const entries = failed !== undefined
    ? ((failed['failed_to_add_members'] as TdObject[] | undefined) ?? []) : [];
  const failedUserIds: number[] = [];
  for (const entry of entries) {
    const userId = (entry['user_id'] as number | undefined) ?? 0;
    if (userId > 0 && failedUserIds.indexOf(userId) < 0) {
      failedUserIds.push(userId);
    }
  }
  return { chatId, failedUserIds };
}

export function newGroupTitleError(rawTitle: string): string {
  const title = rawTitle.trim();
  if (title === '') { return '请输入群组名称'; }
  if (title.length > 128) { return '群组名称不能超过 128 个字符'; }
  return '';
}

export function maxSelectableBasicGroupMembers(groupSizeMax: number): number {
  // The current account is also a group member, while user_ids only contains
  // the other people selected on this page.
  return Math.max(1, groupSizeMax - 1);
}

export function newGroupCreationOutcomeUncertain(rawMessage: string): boolean {
  // TdClient stops waiting after its local timeout, but TDLib may still have
  // accepted the mutating request. Retrying Create in that state can produce
  // a duplicate group.
  return rawMessage.toLowerCase().indexOf('request timeout') >= 0;
}

export function newGroupCreationErrorText(rawMessage: string): string {
  const message = rawMessage.toUpperCase();
  if (message.indexOf('FLOOD_WAIT') >= 0 || message.indexOf('TOO_MANY_REQUESTS') >= 0) {
    return '操作过于频繁，请稍后再试';
  }
  if (message.indexOf('USERS_TOO_MUCH') >= 0 || message.indexOf('GROUP_TOO_LARGE') >= 0) {
    return '选择的成员数量超过当前群组上限';
  }
  if (message.indexOf('USER_PRIVACY_RESTRICTED') >= 0) {
    return '部分成员的隐私设置不允许被直接加入群组';
  }
  if (message.indexOf('CHAT_TITLE_EMPTY') >= 0 || message.indexOf('TITLE_INVALID') >= 0) {
    return '群组名称无效，请修改后重试';
  }
  if (message.indexOf('NETWORK') >= 0 || message.indexOf('TIMEOUT') >= 0 ||
    message.indexOf('CONNECTION') >= 0) {
    return '网络连接失败，请检查网络后重试';
  }
  return '群组创建失败，请稍后重试';
}
