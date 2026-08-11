export interface FolderIconOption {
  name: string;
  label: string;
  emoji: string;
  symbol: Resource;
}

// Telegram folder icons are predefined server-side names; every client renders
// its own local artwork for them. Tintable system symbols keep the look flat
// and consistent with the rest of the UI (color emoji can't be tinted).
export const FOLDER_ICON_OPTIONS: FolderIconOption[] = [
  { name: 'Custom', label: '文件夹', emoji: '📁', symbol: $r('sys.symbol.folder') },
  { name: 'Unread', label: '未读', emoji: '📨', symbol: $r('sys.symbol.envelope') },
  { name: 'Unmuted', label: '提醒', emoji: '🔔', symbol: $r('sys.symbol.bell') },
  { name: 'Private', label: '私聊', emoji: '👤', symbol: $r('sys.symbol.person') },
  { name: 'Groups', label: '群组', emoji: '👥', symbol: $r('sys.symbol.person_2') },
  { name: 'Channels', label: '频道', emoji: '📢', symbol: $r('sys.symbol.speaker') },
  { name: 'Bots', label: '机器人', emoji: '🤖', symbol: $r('sys.symbol.robot') },
  { name: 'Favorite', label: '收藏', emoji: '⭐', symbol: $r('sys.symbol.star') },
  { name: 'Work', label: '工作', emoji: '💼', symbol: $r('sys.symbol.briefcase') },
  { name: 'Study', label: '学习', emoji: '📚', symbol: $r('sys.symbol.graduationcap') },
  { name: 'Home', label: '家庭', emoji: '🏠', symbol: $r('sys.symbol.house') },
  { name: 'Travel', label: '旅行', emoji: '✈️', symbol: $r('sys.symbol.airplane') },
  { name: 'Game', label: '游戏', emoji: '🎮', symbol: $r('sys.symbol.game') },
  { name: 'Sport', label: '运动', emoji: '⚽', symbol: $r('sys.symbol.basketball') },
  { name: 'Trade', label: '交易', emoji: '📈', symbol: $r('sys.symbol.coins') },
  { name: 'Money', label: '财务', emoji: '💰', symbol: $r('sys.symbol.moneybag') },
  { name: 'Love', label: '喜欢', emoji: '❤️', symbol: $r('sys.symbol.heart') },
  { name: 'Party', label: '聚会', emoji: '🎉', symbol: $r('sys.symbol.balloon_2') },
  { name: 'Book', label: '阅读', emoji: '📖', symbol: $r('sys.symbol.book') },
  { name: 'Palette', label: '创作', emoji: '🎨', symbol: $r('sys.symbol.paintpalette') }
];

export const FOLDER_COLORS: string[] = [
  '#5B8FF9', '#61CDBB', '#F6BD16', '#E8684A', '#9270CA', '#6DC8EC', '#FF7A9A'
];

function optionOf(name: string): FolderIconOption | undefined {
  return FOLDER_ICON_OPTIONS.find((item: FolderIconOption): boolean => item.name === name);
}

export function folderEmoji(name: string): string {
  return optionOf(name)?.emoji ?? '📁';
}

export function folderSymbol(name: string): Resource {
  return optionOf(name)?.symbol ?? $r('sys.symbol.folder');
}

export function folderColor(colorId: number): string {
  return colorId >= 0 && colorId < FOLDER_COLORS.length ? FOLDER_COLORS[colorId] : '#5B8FF9';
}
